#include "EventWowDevMode.h"
#include "EventWowGames.h"
#include "EventWowMatch.h"
#include "EventWowMatchMgr.h"
#include "EventWowProtocol.h"
#include "Config.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <sstream>
#include <unordered_map>

// Parkour (juego "parkour", mapa 754 "Ascenso"): sesion SIEMPRE ABIERTA (EventWowGameInfo::OpenSession), cada uno a
// su ritmo. Ruta de saltos por secciones que genera tools/mapgen/parkourgen.py; al empezar cada seccion hay un punto
// de control. El recorrido lo lee el servidor de <DataDir>/maps/<mapa>_parkour.txt al arrancar:
//   checkpoint X Y Z O radio altura_de_caida nombre     (el primero es la salida)
//   finish X Y Z O radio
//  - Caer por debajo de la altura de caida de la seccion (su pieza mas baja - 8 yd) = vuelta al ultimo punto de
//    control alcanzado (los puntos de control estan lejos entre si a proposito: caer cuesta). Sin dano por caida
//    (aura oculta 9503000, data/spells/parkour.toml). Si muere igualmente, reaparece en su punto de control.
//  - Puntos de control: llegar a la plataforma (radio en 2D y altura) de cualquiera posterior al actual (si alguien
//    encuentra un atajo, cuenta).
//  - Cronometro personal: empieza al salir de la plataforma de salida y para en la meta. Mejor tiempo y clasificacion
//    de la SESION (se pierden al cerrarse; el ranking guardado llegara mas adelante).
//  - "Reiniciar" (PARKOUR_RESTART): vuelta a la salida con el cronometro a cero.
// Reglas solo para jugadores: en modo dev no se le recoloca.
//
// Protocolo (docs/protocolo.md, v12):
//   PARKOUR_INFO <n secciones> <nombre 1> ... <nombre n>
//   PARKOUR <seccion 1..n> <caidas> <ms> <estado: 0 en la salida, 1 corriendo, 2 en la meta> <ms mejor, 0 = ninguno>
//   PARKOUR_EVENT CHECKPOINT <seccion> | FALL | FINISH <ms> <record 0/1> | PLAYER_FINISH <nombre> <ms> | RESTART
//   PARKOUR_RANK <n> (<nombre> <ms>) x n          mejores tiempos de la sesion (hasta 10)
//   Cliente -> servidor: PARKOUR_RESTART
namespace
{
    constexpr uint32 SPELL_SAFE_FALL = 9503000;
    constexpr Milliseconds CheckInterval = 200ms;
    // El cliente avanza el reloj solo; el servidor lo corrige cada tanto
    constexpr Milliseconds SyncInterval = 10s;
    constexpr std::size_t RankSize = 10;

    struct ParkourCheckpoint
    {
        Position Pos;
        float Radius = 5.0f;
        float FallZ = 0.0f;
        std::string Name;
    };

    struct ParkourCourse
    {
        std::vector<ParkourCheckpoint> Checkpoints;
        Position Finish;
        float FinishRadius = 5.0f;
    };

    std::unordered_map<uint32, ParkourCourse> Courses;

    bool LoadCourse(uint32 mapId, ParkourCourse& course)
    {
        // DataDir de la config (los scripts se registran antes de que World lea la suya; el valor es el mismo)
        std::string path = sConfigMgr->GetOption<std::string>("DataDir", "./");
        if (!path.empty() && path.back() != '/' && path.back() != '\\')
            path += '/';
        char name[32];
        std::snprintf(name, sizeof(name), "maps/%03u_parkour.txt", mapId);
        path += name;

        std::ifstream file(path);
        if (!file)
        {
            LOG_ERROR("module.eventwow", "EventWow: parkour: no existe {} (lo genera tools/Build-Patch.ps1)", path);
            return false;
        }

        bool finish = false;
        std::string line;
        while (std::getline(file, line))
        {
            if (!line.empty() && line.back() == '\r')
                line.pop_back();

            std::istringstream in(line);
            std::string kind;
            in >> kind;
            float x, y, z, o, radius;
            if (kind == "checkpoint")
            {
                ParkourCheckpoint checkpoint;
                float fallZ;
                if (!(in >> x >> y >> z >> o >> radius >> fallZ))
                    continue;

                std::getline(in >> std::ws, checkpoint.Name);
                checkpoint.Pos.Relocate(x, y, z, o);
                checkpoint.Radius = radius;
                checkpoint.FallZ = fallZ;
                course.Checkpoints.push_back(std::move(checkpoint));
            }
            else if (kind == "finish" && (in >> x >> y >> z >> o >> radius))
            {
                course.Finish.Relocate(x, y, z, o);
                course.FinishRadius = radius;
                finish = true;
            }
        }

        if (course.Checkpoints.empty() || !finish)
        {
            LOG_ERROR("module.eventwow", "EventWow: parkour: {} no tiene salida y meta", path);
            return false;
        }

        LOG_INFO("module.eventwow", "EventWow: parkour: recorrido del mapa {}: {} secciones", mapId,
            course.Checkpoints.size());
        return true;
    }

    // Dentro de una plataforma: radio en 2D y de poco por debajo de su cara a bastante por encima (saltando)
    bool IsOnPlatform(Player const* player, Position const& center, float radius)
    {
        float const dz = player->GetPositionZ() - center.GetPositionZ();
        return dz > -2.5f && dz < 8.0f && player->GetExactDist2d(center.GetPositionX(), center.GetPositionY()) < radius;
    }
}

class EventWowGameParkour : public EventWowMatch
{
public:
    explicit EventWowGameParkour(ParkourCourse const& course) : _course(course) { }

    void HandleRestart(Player* player)
    {
        auto itr = _runners.find(player->GetGUID());
        if (itr == _runners.end())
            return;

        Runner& runner = itr->second;
        runner.Section = 0;
        runner.Falls = 0;
        runner.Elapsed = 0ms;
        runner.State = RunnerState::AtStart;
        TeleportTo(player, _course.Checkpoints.front().Pos);
        EventWowMessage("PARKOUR_EVENT").Add("RESTART").Send(player);
        SendRunner(player, runner);
    }

protected:
    enum class RunnerState : uint8
    {
        AtStart = 0,    // en la plataforma de salida: el reloj no corre
        Running = 1,
        Finished = 2
    };

    struct Runner
    {
        uint32 Section = 0;     // indice del ultimo punto de control alcanzado
        uint32 Falls = 0;
        Milliseconds Elapsed = 0ms;
        Milliseconds Best = 0ms;
        RunnerState State = RunnerState::AtStart;
    };

    Position GetArrivalPosition(Player* /*player*/) override
    {
        return _course.Checkpoints.front().Pos;
    }

    Position const& GetRespawnPosition(Player* player) const override
    {
        auto itr = _runners.find(player->GetGUID());
        uint32 const section = itr != _runners.end() ? itr->second.Section : 0;
        return _course.Checkpoints[section].Pos;
    }

    void OnPlayerArrived(Player* player) override
    {
        Runner& runner = _runners[player->GetGUID()];
        runner = Runner();
        player->AddAura(SPELL_SAFE_FALL, player);

        EventWowMessage info("PARKOUR_INFO");
        info.Add(static_cast<uint32>(_course.Checkpoints.size()));
        for (ParkourCheckpoint const& checkpoint : _course.Checkpoints)
            info.Add(checkpoint.Name);
        info.Send(player);

        SendRunner(player, runner);
        SendRank(player);
    }

    void OnPlayerLeft(ObjectGuid guid) override
    {
        _runners.erase(guid);
        // El aura se va con el jugador: tambien se quita aqui por si sigue en el mundo (modo dev, logout ya lo limpia)
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            player->RemoveAurasDueToSpell(SPELL_SAFE_FALL);
    }

    void OnPlayerDied(Player* player) override
    {
        RespawnPlayer(player, 1s);
    }

    void OnUpdate(Milliseconds diff) override
    {
        for (auto& [guid, runner] : _runners)
            if (runner.State == RunnerState::Running)
                runner.Elapsed += diff;

        _checkTimer += diff;
        if (_checkTimer < CheckInterval)
            return;

        _checkTimer = 0ms;
        _syncTimer += CheckInterval;
        bool const sync = _syncTimer >= SyncInterval;
        if (sync)
            _syncTimer = 0ms;

        ForEachPlayer([this, sync](Player* player)
        {
            auto itr = _runners.find(player->GetGUID());
            if (itr == _runners.end() || player->GetInstanceId() != GetInstanceId())
                return;

            Check(player, itr->second);
            if (sync)
                SendRunner(player, itr->second);
        });
    }

private:
    void Check(Player* player, Runner& runner)
    {
        if (!player->IsAlive() || player->IsBeingTeleported() || EventWowDevMode::IsActive(player))
            return;

        ParkourCheckpoint const& current = _course.Checkpoints[runner.Section];

        // Caida: al ultimo punto de control
        if (player->GetPositionZ() < current.FallZ)
        {
            ++runner.Falls;
            TeleportTo(player, current.Pos);
            EventWowMessage("PARKOUR_EVENT").Add("FALL").Send(player);
            SendRunner(player, runner);
            return;
        }

        if (runner.State == RunnerState::Finished)
            return;

        // Sale de la plataforma de salida: empieza el reloj
        if (runner.State == RunnerState::AtStart)
        {
            if (runner.Section == 0 && IsOnPlatform(player, current.Pos, current.Radius))
                return;

            runner.State = RunnerState::Running;
            SendRunner(player, runner);
        }

        // Cualquier punto de control posterior (atajos incluidos)
        for (uint32 i = static_cast<uint32>(_course.Checkpoints.size()) - 1; i > runner.Section; --i)
        {
            ParkourCheckpoint const& next = _course.Checkpoints[i];
            if (!IsOnPlatform(player, next.Pos, next.Radius))
                continue;

            runner.Section = i;
            EventWowMessage("PARKOUR_EVENT").Add("CHECKPOINT").Add(i + 1).Send(player);
            SendRunner(player, runner);
            break;
        }

        if (IsOnPlatform(player, _course.Finish, _course.FinishRadius))
            Finish(player, runner);
    }

    void Finish(Player* player, Runner& runner)
    {
        runner.State = RunnerState::Finished;
        bool const record = runner.Best == 0ms || runner.Elapsed < runner.Best;
        if (record)
            runner.Best = runner.Elapsed;

        uint32 const ms = static_cast<uint32>(runner.Elapsed.count());
        LOG_INFO("module.eventwow", "EventWow: parkour: {} llega a la meta en {} ms ({} caidas)", player->GetName(), ms,
            runner.Falls);
        EventWowMessage("PARKOUR_EVENT").Add("FINISH").Add(ms).Add(record ? 1 : 0).Send(player);
        SendRunner(player, runner);

        std::string const name = player->GetName();
        ForEachPlayer([&name, ms, player](Player* other)
        {
            if (other != player)
                EventWowMessage("PARKOUR_EVENT").Add("PLAYER_FINISH").Add(name).Add(ms).Send(other);
        });

        // Clasificacion de la sesion: mejor tiempo de cada nombre
        auto itr = std::find_if(_rank.begin(), _rank.end(), [&name](auto const& entry) { return entry.first == name; });
        if (itr == _rank.end())
            _rank.emplace_back(name, ms);
        else if (ms < itr->second)
            itr->second = ms;
        else
            return;

        std::sort(_rank.begin(), _rank.end(), [](auto const& a, auto const& b) { return a.second < b.second; });
        if (_rank.size() > RankSize)
            _rank.resize(RankSize);

        ForEachPlayer([this](Player* other) { SendRank(other); });
    }

    void TeleportTo(Player* player, Position const& pos)
    {
        player->NearTeleportTo(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ(), pos.GetOrientation());
    }

    void SendRunner(Player* player, Runner const& runner) const
    {
        EventWowMessage("PARKOUR")
            .Add(runner.Section + 1)
            .Add(runner.Falls)
            .Add(static_cast<uint32>(runner.Elapsed.count()))
            .Add(static_cast<uint32>(runner.State))
            .Add(static_cast<uint32>(runner.Best.count()))
            .Send(player);
    }

    void SendRank(Player* player) const
    {
        EventWowMessage message("PARKOUR_RANK");
        message.Add(static_cast<uint32>(_rank.size()));
        for (auto const& [name, ms] : _rank)
            message.Add(name).Add(ms);
        message.Send(player);
    }

    ParkourCourse const& _course;
    std::unordered_map<ObjectGuid, Runner> _runners;
    // Mejores tiempos de la sesion: (nombre, ms), de menor a mayor
    std::vector<std::pair<std::string, uint32>> _rank;
    Milliseconds _checkTimer = 0ms;
    Milliseconds _syncTimer = 0ms;
};

namespace
{
    // PARKOUR_RESTART: vuelta a la salida con el cronometro a cero
    void HandleParkourRestart(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        if (EventWowGameParkour* parkour = dynamic_cast<EventWowGameParkour*>(sEventWowMatchMgr.GetMatch(player)))
            if (player->GetInstanceId() == parkour->GetInstanceId())
                parkour->HandleRestart(player);
    }
}

void AddSC_eventwow_game_parkour()
{
    EventWowProtocol::RegisterHandler("PARKOUR_RESTART", HandleParkourRestart);

    // Mapa 754 (tools/mapgen/parkourgen.py, Maps/Planos/parkour_ascenso.json)
    EventWowGameInfo game;
    game.Id = "parkour";
    game.Name = "Parkour: Ascenso";
    game.Description = "Sube saltando por muebles, estanterías, máquinas y ruinas flotando en el cielo de Gelidar. "
        "Cinco secciones con un punto de control al empezar cada una: si caes, vuelves al último. Sesión siempre "
        "abierta: entra y sal cuando quieras.";
    game.Icon = "Interface\\Icons\\Ability_Rogue_Sprint";
    game.MinPlayers = 1;
    game.MaxPlayers = 40;
    game.MaxPartySize = 5;
    game.OpenSession = true;
    game.MapId = 754;

    ParkourCourse course;
    if (LoadCourse(game.MapId, course))
    {
        ParkourCourse const& stored = Courses[game.MapId] = std::move(course);
        game.Start = stored.Checkpoints.front().Pos;
        game.Factory = [&stored]() { return std::make_unique<EventWowGameParkour>(stored); };
    }
    else
        game.Description += " (No disponible: falta el recorrido en el servidor.)";

    sEventWowGames.Register(std::move(game));
}
