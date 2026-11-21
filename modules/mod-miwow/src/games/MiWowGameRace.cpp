#include "MiWowDevMode.h"
#include "MiWowGames.h"
#include "MiWowMatch.h"
#include "MiWowMatchMgr.h"
#include "MiWowProtocol.h"
#include "MiWowVehicle.h"
#include "Config.h"
#include "Creature.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "Random.h"
#include "SpellAuras.h"
#include "SpellInfo.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include "TemporarySummon.h"
#include "Vehicle.h"
#include <array>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <limits>
#include <sstream>
#include <unordered_map>

// Carrera de motos por vueltas (juegos "carrera" y "carrera_estelar").
//
// Pista = linea central que genera tools/mapgen (trackgen.py / platformgen.py) en <DataDir>/maps/<mapa>_pista.json:
// [[s, X, Y, Z, media anchura], ...] cada 2 yardas desde la meta (Z = suelo de la pista). Se lee al arrancar.
//
// El servidor sigue a cada corredor por la pista: busca la muestra mas cercana SOLO en una ventana alrededor de la
// anterior (asi en los cruces del Circuito Estelar no salta al otro tramo, y atajar campo a traves no cuenta: se
// queda "fuera de la pista" y reaparece). El avance acumulado (Progress, yardas desde la meta, negativo en la
// parrilla) da las vueltas, los puntos de control (en orden por construccion) y las posiciones.
//  - Parrilla de 8 detras de la meta: cada piloto llega a la instancia a pie, ya en su puesto (GetArrivalPosition).
//    A los 3 s de la cuenta atras (10 s): "¡Todos a sus motos!" (MountAll; la moto se invoca en su puesto). Montarle
//    al llegar (en Map::AddPlayerToMap, con el cliente aun cargando) hacia saltar "HandleSetActiveMoverOpcode:
//    incorrect mover guid" en la consola. Motos quietas (raiz en el vehiculo) en la cuenta atras y al terminar.
//  - Nunca Vehicle::TeleportVehicle: baja al jugador y lo vuelve a subir por clic (las motos no tienen) y deja el
//    control del vehiculo (mover) descolocado. Para recolocar: se quita la moto, se mueve al jugador y se invoca otra.
//  - Caer (por debajo del suelo de la pista) o salirse demasiado: vuelve al ultimo punto bueno, quieto 2 s.
//  - 2 vueltas. Cuando llega el primero, el resto tiene 30 s. Resultados en pantalla con boton de salir al lobby.
//  - Poderes (tipo Mario Kart; hechizos en data/spells/carrera.toml): filas de cajas por toda la pista. Al pasar por
//    una caja se recibe uno al azar (mas ofensivos/rapidos cuanto mas atras; hasta 5 acumulados, huecos 1-5 de la barra
//    de la moto: Creature::m_spells + VehicleSpellInitialize) y lo lanza la moto. La caja reaparece a los pocos segundos.
//    Las cajas se cogen con el TRAMO recorrido entre dos posiciones (el cliente solo avisa cada ~0,5 s yendo recto: a
//    28 yd/s son ~14 yd de salto y con el punto solo se saltaba cajas).
//    Cohete (al de delante), Turbo, Mancha de aceite (detras), Escudo (para el siguiente golpe), Rayo (frena a todos
//    los de delante). Los golpes los aplica el juego (la moto golpeada se lanza el efecto a si misma): no hace falta que
//    los pilotos sean enemigos y tambien alcanza a los del mismo grupo.
//  - Placas de aceleracion (runas en el suelo): las coloca el juego solo, a la salida de cada curva cerrada y por el
//    lado de dentro (FindBoostPads, lejos de las cajas). Pasar por encima = Acelerón (+40 % 1,5 s), se renueva.
// Reglas solo para jugadores: en modo dev no se le recoloca ni se le inmoviliza.
//
// Protocolo (docs/protocolo.md, v11):
//   RACE_INFO <vueltas>
//   RACE <vuelta> <vueltas> <posicion> <corredores> <ms carrera> <ms vuelta actual> <ms mejor vuelta> <contraria 0/1>
//        <terminado 0/1>                                   (cada 500 ms a cada corredor)
//   RACE_EVENT LAP <vuelta> <ms vuelta> | FINAL_LAP | FELL | FINISH <posicion> <ms> | WINNER <nombre> <segundos>
//              | ITEM <hechizo> <hueco 1-5> | HIT <hechizo> | BLOCK         (v10: poderes)
//              | MOUNT                                                      (v11: "¡Todos a sus motos!")
//   RACE_RESULTS <final 0/1> <n> (<posicion> <nombre> <ms total, 0 = sin terminar> <ms mejor vuelta>) x n
namespace
{
    constexpr uint32 RaceLaps = 2;
    constexpr uint32 GridSlots = 8;
    constexpr Seconds FinishWindow = 30s;          // tras llegar el primero
    constexpr Milliseconds MaxRaceTime = 20min;    // por si nadie termina
    constexpr Milliseconds FallFreeze = 2s;
    constexpr Milliseconds TrackInterval = 100ms;
    constexpr Milliseconds HudInterval = 500ms;
    constexpr Milliseconds RootInterval = 250ms;
    // Moto de carreras (SQL 2026_11_17_02: Salvaged Chopper a 28 yd/s, sin hechizos de vehiculo)
    constexpr uint32 RaceVehicleEntry = 9500001;
    constexpr Milliseconds MountDelay = 3s;        // de la cuenta atras (10 s) hasta "¡Todos a sus motos!"
    constexpr int32 WindowBack = 40;               // muestras (2 yd) hacia atras y hacia delante
    constexpr int32 WindowAhead = 60;

    // Poderes
    enum RacePowerIds : uint32
    {
        NPC_RACE_POWER_BOX = 9500010,
        NPC_RACE_OIL = 9500011,
        NPC_RACE_BOOST_PAD = 9500012,

        // Activadores (barra de la moto)
        SPELL_RACE_ROCKET = 9502000,
        SPELL_RACE_TURBO = 9502001,
        SPELL_RACE_OIL = 9502002,
        SPELL_RACE_SHIELD = 9502003,
        SPELL_RACE_LIGHTNING = 9502004,
        // Efectos
        SPELL_RACE_ROCKET_MISSILE = 9502010,
        SPELL_RACE_SPIN = 9502011,
        SPELL_RACE_SHOCK = 9502012,
        SPELL_RACE_BOOST = 9502013          // placa de aceleracion
    };

    // Probabilidad relativa de cada poder para el primero y para el ultimo (en medio, proporcional a la posicion)
    struct PowerWeight
    {
        uint32 Spell;
        float First;
        float Last;
    };
    constexpr std::array<PowerWeight, 5> PowerWeights = { {
        { SPELL_RACE_ROCKET,    2.0f, 4.0f },
        { SPELL_RACE_TURBO,     1.0f, 4.0f },
        { SPELL_RACE_OIL,       4.0f, 1.0f },
        { SPELL_RACE_SHIELD,    3.0f, 1.0f },
        { SPELL_RACE_LIGHTNING, 0.0f, 2.0f }
    } };

    constexpr float BoxFirstRow = 150.0f;          // yardas desde la meta de la primera fila de cajas
    constexpr float BoxRowSpacing = 180.0f;        // entre filas
    constexpr float BoxLastRowGap = 80.0f;         // sin cajas en las ultimas yardas antes de la meta
    constexpr std::array<float, 4> BoxLaterals = { { -0.6f, -0.2f, 0.2f, 0.6f } }; // fraccion de la media anchura
    constexpr float BoxPickupRadius = 4.0f;
    constexpr Milliseconds BoxRespawn = 4s;
    constexpr float OilRadius = 3.5f;
    constexpr float OilBehind = 7.0f;              // yardas detras de la moto
    constexpr Milliseconds OilLife = 40s;
    constexpr Milliseconds OilOwnerGrace = 2s;     // el que la deja no la pisa al soltarla
    constexpr float PickupHeight = 5.0f;           // diferencia de z maxima (cruces del Circuito Estelar)
    constexpr std::size_t MaxPowers = 5;           // poderes acumulados (huecos 1-5 de la barra de la moto)
    // Tramo maximo entre dos posiciones seguidas para barrerlo (mas = teleport/caida: solo el punto nuevo)
    constexpr float MaxSweep = 60.0f;
    constexpr float WrongWayDistance = 20.0f;      // yardas hacia atras seguidas para avisar

    // Placas de aceleracion: a la salida de cada curva que gire al menos BoostMinTurn, por el lado de dentro
    constexpr int32 BoostTurnWindow = 10;          // muestras a cada lado para medir el giro (40 yd en total)
    constexpr float BoostCurveTurn = 0.26f;        // giro (rad) en esa ventana a partir del que se esta en curva (~15 grados)
    constexpr float BoostMinTurn = 0.87f;          // giro total de la curva (~50 grados)
    constexpr float BoostExitOffset = 12.0f;       // yardas despues del final de la curva
    constexpr float BoostLateral = 0.4f;           // fraccion de la media anchura hacia dentro de la curva
    constexpr float BoostRadius = 5.0f;           // placa a escala 1,8 (SQL 2026_11_18_00)
    constexpr float BoostMinSpacing = 100.0f;      // entre placas
    constexpr float BoostBoxClearance = 25.0f;     // lejos de las filas de cajas
    constexpr float BoostMaxShift = 40.0f;         // lo que se puede adelantar para alejarla de las cajas
    constexpr float BoostStartGap = 60.0f;         // ni en la salida (parrilla)...
    constexpr float BoostEndGap = 40.0f;           // ...ni justo antes de la meta
    constexpr float BoostMaxGap = 500.0f;          // tramo sin placa a partir del que se rellena...
    constexpr float BoostFillSpacing = 400.0f;     // ...con una placa cada tanto
    constexpr Milliseconds BoostRetrigger = 2s;    // la misma placa no vuelve a dar acelerón seguido

    struct RaceSample
    {
        float S, X, Y, Z, Half;
    };

    struct RaceTrack
    {
        std::vector<RaceSample> Samples;
        float Step = 2.0f;
        float Length = 0.0f;

        int32 Count() const { return static_cast<int32>(Samples.size()); }
        int32 Wrap(int32 i) const { return ((i % Count()) + Count()) % Count(); }
        RaceSample const& At(int32 i) const { return Samples[Wrap(i)]; }

        // Rumbo de la pista en la muestra i (orientacion WoW: 0 = +X, pi/2 = +Y)
        float Heading(int32 i) const
        {
            RaceSample const& a = At(i - 1);
            RaceSample const& b = At(i + 1);
            return Position::NormalizeOrientation(std::atan2(b.Y - a.Y, b.X - a.X));
        }

        // Punto en la pista a "back" yardas detras de la muestra i, desplazado lateral yardas a la izquierda
        Position Place(int32 i, float lateral, float zOffset) const
        {
            RaceSample const& p = At(i);
            float const h = Heading(i);
            return Position(p.X - std::sin(h) * lateral, p.Y + std::cos(h) * lateral, p.Z + zOffset, h);
        }
    };

    // Lee [[s, X, Y, Z, h], ...] (sin dependencias de JSON: solo numeros en grupos de 5)
    bool LoadTrack(uint32 mapId, RaceTrack& track)
    {
        // DataDir de la config (los scripts se registran antes de que World lea la suya; el valor es el mismo)
        std::string path = sConfigMgr->GetOption<std::string>("DataDir", "./");
        if (!path.empty() && path.back() != '/' && path.back() != '\\')
            path += '/';
        char name[32];
        std::snprintf(name, sizeof(name), "maps/%03u_pista.json", mapId);
        path += name;

        std::ifstream file(path, std::ios::binary);
        if (!file)
        {
            LOG_ERROR("module.miwow", "MiWow: carrera: no existe {} (lo genera tools/Build-Patch.ps1)", path);
            return false;
        }

        std::stringstream buffer;
        buffer << file.rdbuf();
        std::string const text = buffer.str();

        std::vector<float> numbers;
        char const* cur = text.c_str();
        while (*cur)
        {
            if ((*cur >= '0' && *cur <= '9') || *cur == '-' || *cur == '.')
            {
                char* end = nullptr;
                numbers.push_back(std::strtof(cur, &end));
                cur = end > cur ? end : cur + 1;
            }
            else
                ++cur;
        }

        if (numbers.size() < 5 * 20 || numbers.size() % 5)
        {
            LOG_ERROR("module.miwow", "MiWow: carrera: {} no tiene el formato [[s, X, Y, Z, h], ...]", path);
            return false;
        }

        for (std::size_t i = 0; i < numbers.size(); i += 5)
            track.Samples.push_back({ numbers[i], numbers[i + 1], numbers[i + 2], numbers[i + 3], numbers[i + 4] });

        // Circuito cerrado: si la ultima muestra repite la primera (la meta), sobra
        RaceSample const& first = track.Samples.front();
        RaceSample const& last = track.Samples.back();
        if (std::hypot(last.X - first.X, last.Y - first.Y) < 0.5f && std::fabs(last.Z - first.Z) < 0.5f)
            track.Samples.pop_back();

        track.Step = track.Samples[1].S - track.Samples[0].S;
        track.Length = track.Samples.back().S + track.Step;
        LOG_INFO("module.miwow", "MiWow: carrera: pista del mapa {}: {:.0f} yardas, {} muestras", mapId,
            track.Length, track.Samples.size());
        return true;
    }

    std::unordered_map<uint32, RaceTrack> Tracks;

    // Placa de aceleracion: muestra de la pista y lado (+1 izquierda, -1 derecha)
    struct BoostPadSpot
    {
        int32 Index;
        float Side;
    };

    float AngleDiff(float a, float b)
    {
        float d = a - b;
        while (d > float(M_PI))
            d -= 2.0f * float(M_PI);
        while (d < -float(M_PI))
            d += 2.0f * float(M_PI);
        return d;
    }

    // Busca las curvas (tramos donde el rumbo cambia mas de BoostCurveTurn en la ventana) y pone una placa a la salida
    // de las que giran al menos BoostMinTurn en total, por el lado de dentro: premia trazar cerrado.
    std::vector<BoostPadSpot> FindBoostPads(RaceTrack const& track)
    {
        int32 const n = track.Count();
        auto turnAt = [&track](int32 i)
        {
            return AngleDiff(track.Heading(i + BoostTurnWindow), track.Heading(i - BoostTurnWindow));
        };

        // Empezar en una recta, para que ninguna curva quede partida por el principio del recorrido
        int32 start = 0;
        while (start < n && std::fabs(turnAt(start)) > BoostCurveTurn)
            ++start;
        if (start == n)
            return {};

        std::vector<float> rows;
        for (float s = BoxFirstRow; s < track.Length - BoxLastRowGap; s += BoxRowSpacing)
            rows.push_back(s);
        auto nearBoxes = [&rows](float s)
        {
            return std::any_of(rows.begin(), rows.end(), [s](float r) { return std::fabs(r - s) < BoostBoxClearance; });
        };

        std::vector<BoostPadSpot> pads;
        std::vector<float> placed;      // yardas desde la meta
        // Adelanta s (hasta BoostMaxShift) mientras este junto a una fila de cajas
        auto nudge = [&track, &nearBoxes](float s)
        {
            float const limit = s + BoostMaxShift;
            while (s < limit && nearBoxes(std::fmod(s, track.Length)))
                s += track.Step;
            return std::fmod(s, track.Length);
        };
        auto canPlace = [&track, &nearBoxes, &placed](float s)
        {
            if (nearBoxes(s) || s < BoostStartGap || s > track.Length - BoostEndGap)
                return false;
            return std::none_of(placed.begin(), placed.end(), [&track, s](float p)
            {
                float const d = std::fabs(p - s);
                return std::min(d, track.Length - d) < BoostMinSpacing;
            });
        };
        auto indexOf = [&track](float s) { return track.Wrap(static_cast<int32>(std::lround(s / track.Step))); };

        bool inCurve = false;
        float total = 0.0f;
        for (int32 k = 0; k <= n; ++k)
        {
            int32 const i = start + k;
            bool const curve = k < n && std::fabs(turnAt(i)) > BoostCurveTurn;
            if (curve)
            {
                total = (inCurve ? total : 0.0f) + AngleDiff(track.Heading(i), track.Heading(i - 1));
                inCurve = true;
                continue;
            }
            if (!inCurve)
                continue;

            // Fin de curva en la muestra i
            inCurve = false;
            if (std::fabs(total) < BoostMinTurn)
                continue;

            float const s = nudge(track.At(i).S + BoostExitOffset);
            if (!canPlace(s))
                continue;

            placed.push_back(s);
            pads.push_back({ indexOf(s), total > 0.0f ? 1.0f : -1.0f });
        }

        // Tramos largos sin placa (curvas muy abiertas, rectas): placas repartidas, alternando el lado
        std::vector<float> edges = placed;
        std::sort(edges.begin(), edges.end());
        edges.insert(edges.begin(), BoostStartGap);
        edges.push_back(track.Length - BoostEndGap);
        float side = 1.0f;
        for (std::size_t e = 0; e + 1 < edges.size(); ++e)
        {
            float const gap = edges[e + 1] - edges[e];
            if (gap <= BoostMaxGap)
                continue;

            int32 const count = static_cast<int32>(gap / BoostFillSpacing);
            for (int32 j = 1; j <= count; ++j)
            {
                float const s = nudge(edges[e] + gap * j / (count + 1));
                if (!canPlace(s))
                    continue;

                placed.push_back(s);
                pads.push_back({ indexOf(s), side });
                side = -side;
            }
        }
        return pads;
    }

    // Parametros de cada circuito
    struct RaceSettings
    {
        float OffTrackMargin;   // yardas fuera del borde de la pista a partir de las que se reaparece
        float FallDepth;        // yardas por debajo del suelo de la pista a partir de las que se reaparece
    };
}

class MiWowGameRace : public MiWowMatch
{
public:
    MiWowGameRace(RaceTrack const& track, RaceSettings settings) : _track(track), _settings(settings) { }

    // Desde spell_miwow_race_power: la moto de player ha lanzado el activador spellId
    void OnPowerUsed(Player* player, uint32 spellId)
    {
        auto itr = _racers.find(player->GetGUID());
        if (itr == _racers.end())
            return;

        Racer& racer = itr->second;
        auto power = std::find(racer.Powers.begin(), racer.Powers.end(), spellId);
        if (power == racer.Powers.end())
            return;

        racer.Powers.erase(power);      // los demas suben un hueco
        ApplyPowerToVehicle(player, racer);

        if (GetState() != MiWowMatchState::Running || racer.FinishPosition)
            return;

        switch (spellId)
        {
            case SPELL_RACE_ROCKET:
                FireRocket(player);
                break;
            case SPELL_RACE_OIL:
                DropOil(player);
                break;
            case SPELL_RACE_LIGHTNING:
                Lightning(player);
                break;
            default:                // Turbo y Escudo: el propio hechizo pone el aura
                break;
        }
    }

    // Desde spell_miwow_race_missile: el cohete ha llegado a la moto de victim
    void OnRocketHit(Player* victim)
    {
        Hit(victim, SPELL_RACE_SPIN);
    }

protected:
    // Cada piloto, con su personaje, en la moto de carreras; a pie no puede lanzar nada (ni montura ni forma)
    uint32 GetVehicleEntry() const override { return RaceVehicleEntry; }
    bool BlocksPlayerSpells() const override { return true; }

    struct Racer
    {
        uint32 Slot = 0;
        int32 Index = 0;            // muestra actual (seguimiento en ventana)
        int32 LastGoodIndex = 0;    // ultima muestra en la que iba dentro de la pista
        float Progress = 0.0f;      // yardas desde la meta (negativo en la parrilla)
        uint32 LapsDone = 0;
        Milliseconds LapStart = 0ms;
        Milliseconds BestLap = 0ms;
        Milliseconds FinishTime = 0ms;
        uint32 FinishPosition = 0;  // 0 = corriendo
        Milliseconds Frozen = 0ms;  // quieto (reaparicion)
        Milliseconds Reroot = 0ms;  // reenviar la raiz al subirse a una moto nueva (el cliente aun no la controla)
        ObjectGuid Vehicle;         // moto en la que iba (para detectar una nueva)
        std::vector<uint32> Powers; // activadores en la barra de la moto (huecos 1..MaxPowers)
        Position LastPos;           // posicion de la moto en la comprobacion anterior (cajas/manchas)
        bool HasLastPos = false;
        std::size_t LastBoostPad = std::numeric_limits<std::size_t>::max();
        Milliseconds LastBoostTime = 0ms;
        float Backwards = 0.0f;
        bool WrongWay = false;
    };

    Seconds GetCountdown() const override { return 10s; }
    Seconds GetEndDelay() const override { return 90s; }

    // Puesto de la parrilla (al crear la partida, antes de entrar): llega ahi y la moto se invoca ahi
    Position GetArrivalPosition(Player* player) override
    {
        Racer& racer = _racers[player->GetGUID()];
        if (!racer.Slot)
            racer.Slot = NextFreeSlot();

        return GridPosition(racer);
    }

    void OnPlayerArrived(Player* player) override
    {
        Racer& racer = _racers[player->GetGUID()];
        if (!racer.Slot)
        {
            // No deberia pasar (GetArrivalPosition): al menos un puesto y un seguimiento validos
            racer.Slot = NextFreeSlot();
            GridPosition(racer);
        }

        LOG_INFO("module.miwow", "MiWow: carrera: {} llega al puesto {} (indice {}, moto {})", player->GetName(),
            racer.Slot, racer.Index, player->GetVehicleBase() ? "si" : "no");
        // A pie hasta "¡Todos a sus motos!" (MountAll, en la cuenta atras)
        if (!_mounted)
            MiWowVehicle::HoldVehicle(player);
        SetRooted(player, true);
        MiWowMessage("RACE_INFO").Add(RaceLaps).Send(player);
        SendResults(player, false);
    }

    void OnPlayerLeft(ObjectGuid guid) override
    {
        _racers.erase(guid);
        if (GetState() == MiWowMatchState::Running && !_racers.empty() && AllFinished())
            EndRace();
    }

    void OnStart() override
    {
        SetHud("Completa " + std::to_string(RaceLaps) + " vueltas. ¡Cuidado con las caídas!");
        if (!_mounted)
            MountAll();     // por si la cuenta atras no llego al momento de montar
        _clock = 0ms;
        ForEachPlayer([this](Player* player)
        {
            auto itr = _racers.find(player->GetGUID());
            if (itr == _racers.end())
                return;
            itr->second.LapStart = 0ms;
            SetRooted(player, false);
        });
    }

    void OnUpdate(Milliseconds diff) override
    {
        _clock += diff;
        if (_clock >= MaxRaceTime)
        {
            EndRace();
            return;
        }

        _trackTimer += diff;
        if (_trackTimer >= TrackInterval)
        {
            _trackTimer = 0ms;
            ForEachPlayer([this](Player* player) { Track(player); });
            if (GetState() != MiWowMatchState::Running)
                return;
        }

        _hudTimer += diff;
        if (_hudTimer >= HudInterval)
        {
            _hudTimer = 0ms;
            ForEachPlayer([this](Player* player) { SendRace(player); });
        }
    }

    void OnTimerExpired() override
    {
        EndRace();
    }

    // Siempre (tambien en la carga y la cuenta atras): moto nueva si le falta y motos quietas cuando toca
    void OnTick(Milliseconds diff) override
    {
        _rootTimer += diff;
        if (_rootTimer < RootInterval)
            return;

        Milliseconds const elapsed = _rootTimer;
        _rootTimer = 0ms;
        UpdateItems(elapsed);

        // Llegan a pie a la parrilla; a MountDelay de la cuenta atras, todos a sus motos
        if (!_mounted && GetState() == MiWowMatchState::Countdown)
        {
            _countdownElapsed += elapsed;
            if (_countdownElapsed >= MountDelay)
                MountAll();
        }
        ForEachPlayer([this, elapsed](Player* player)
        {
            auto itr = _racers.find(player->GetGUID());
            if (itr == _racers.end() || MiWowDevMode::IsActive(player))
                return;

            Racer& racer = itr->second;

            // Sin moto (tras recolocarle): la nueva cuanto antes, no al ritmo de MiWowVehicle::Update (1 s)
            Unit* vehicle = player->GetVehicleBase();
            if (!vehicle && player->IsAlive() && !player->IsBeingTeleported())
            {
                MiWowVehicle::Update(player);
                vehicle = player->GetVehicleBase();
            }

            // Moto nueva: la raiz se reenvia cuando el cliente ya la controla
            ObjectGuid const vehicleGuid = vehicle ? vehicle->GetGUID() : ObjectGuid::Empty;
            if (vehicleGuid != racer.Vehicle)
            {
                racer.Vehicle = vehicleGuid;
                if (vehicle)
                {
                    racer.Reroot = 500ms;
                    ApplyPowerToVehicle(player, racer);   // tras una caida la moto es otra
                }
            }

            if (racer.Frozen > 0ms)
                racer.Frozen = racer.Frozen > elapsed ? racer.Frozen - elapsed : 0ms;

            bool const frozen = GetState() != MiWowMatchState::Running || racer.FinishPosition || racer.Frozen > 0ms;
            if (racer.Reroot > 0ms)
            {
                racer.Reroot = racer.Reroot > elapsed ? racer.Reroot - elapsed : 0ms;
                if (racer.Reroot == 0ms && frozen)
                {
                    // La raiz enviada al subirse puede no llegarle al cliente
                    SetRooted(player, false);
                    SetRooted(player, true);
                }
            }
            SetRooted(player, frozen);
        });
    }

    void OnPlayerDied(Player* player) override
    {
        // Reaparece en el ultimo punto bueno (GetRespawnPosition); el seguimiento sigue desde ahi
        auto itr = _racers.find(player->GetGUID());
        if (itr != _racers.end() && !itr->second.FinishPosition)
        {
            MoveTo(itr->second, _track.Wrap(itr->second.LastGoodIndex - 2));
            itr->second.Frozen = FallFreeze + 2s;
        }
        RespawnPlayer(player, 2s);
    }

    Position const& GetRespawnPosition(Player* player) const override
    {
        auto itr = _racers.find(player->GetGUID());
        int32 const index = itr != _racers.end() ? itr->second.LastGoodIndex : _track.Wrap(-5);
        _respawnPosition = _track.Place(index, 0.0f, 2.0f);
        return _respawnPosition;
    }

private:
    uint32 NextFreeSlot() const
    {
        for (uint32 slot = 1; slot <= GridSlots; ++slot)
            if (std::none_of(_racers.begin(), _racers.end(), [slot](auto const& r) { return r.second.Slot == slot; }))
                return slot;
        return GridSlots;
    }

    // Puesto de salida: 2 columnas, filas cada 9 yardas detras de la meta, escalonadas (como tools/mapgen).
    // Deja el seguimiento en ese punto.
    Position GridPosition(Racer& racer) const
    {
        uint32 const k = racer.Slot - 1;
        uint32 const row = k / 2;
        uint32 const col = k % 2;
        float const back = 10.0f + row * 9.0f + col * 4.5f;
        int32 const index = _track.Wrap(-static_cast<int32>(std::lround(back / _track.Step)));
        float const lateral = _track.At(index).Half * 0.45f * (col == 0 ? 1.0f : -1.0f);

        racer.Index = index;
        racer.LastGoodIndex = index;
        racer.Progress = -back;
        return _track.Place(index, lateral, 1.5f);
    }

    // "¡Todos a sus motos!": cada piloto a su moto, invocada en su puesto de la parrilla (si se ha movido a pie, el
    // hechizo de montar le sube desde donde este). Quietas hasta la salida (OnTick).
    void MountAll()
    {
        _mounted = true;
        ForEachPlayer([this](Player* player)
        {
            auto itr = _racers.find(player->GetGUID());
            if (itr == _racers.end())
                return;

            MiWowMessage("RACE_EVENT").Add("MOUNT").Send(player);
            Racer& racer = itr->second;
            Position const spot = GridPosition(racer);
            bool const mounted = MiWowVehicle::MountVehicle(player, &spot);
            LOG_INFO("module.miwow", "MiWow: carrera: {} a su moto (puesto {}): {}", player->GetName(), racer.Slot,
                mounted ? "montado" : "NO montado");
        });
    }

    // --- Poderes ---

    struct PowerBox
    {
        Position Pos;
        ObjectGuid Creature;
        Milliseconds Respawn = 0ms;     // > 0: recogida, reaparece al llegar a 0
    };

    struct BoostPad
    {
        Position Pos;
        ObjectGuid Creature;
    };

    struct OilSlick
    {
        Position Pos;
        ObjectGuid Creature;
        ObjectGuid Owner;
        Milliseconds Age = 0ms;
    };

    // Filas de cajas a lo largo de la pista (una vez, al tener mapa) y su reaparicion; vida de las manchas
    void UpdateItems(Milliseconds elapsed)
    {
        Map* map = GetMap();
        if (!map)
            return;

        if (!_boxesPlaced)
        {
            _boxesPlaced = true;
            for (float s = BoxFirstRow; s < _track.Length - BoxLastRowGap; s += BoxRowSpacing)
            {
                int32 const index = _track.Wrap(static_cast<int32>(std::lround(s / _track.Step)));
                for (float lateral : BoxLaterals)
                {
                    PowerBox box;
                    box.Pos = _track.Place(index, _track.At(index).Half * lateral, 0.0f);
                    // Al suelo real (terreno o plataforma) si esta cerca de la pista
                    float const ground = map->GetHeight(PHASEMASK_NORMAL, box.Pos.GetPositionX(), box.Pos.GetPositionY(),
                        box.Pos.GetPositionZ() + 5.0f, true, 15.0f);
                    if (std::fabs(ground - box.Pos.GetPositionZ()) < 6.0f)
                        box.Pos.m_positionZ = ground;
                    _boxes.push_back(box);
                }
            }
            for (BoostPadSpot const& spot : FindBoostPads(_track))
            {
                BoostPad pad;
                pad.Pos = _track.Place(spot.Index, _track.At(spot.Index).Half * BoostLateral * spot.Side, 0.0f);
                float const ground = map->GetHeight(PHASEMASK_NORMAL, pad.Pos.GetPositionX(), pad.Pos.GetPositionY(),
                    pad.Pos.GetPositionZ() + 5.0f, true, 15.0f);
                if (std::fabs(ground - pad.Pos.GetPositionZ()) < 6.0f)
                    pad.Pos.m_positionZ = ground;
                _pads.push_back(pad);
            }
            LOG_INFO("module.miwow", "MiWow: carrera: {} cajas de poder, {} placas de aceleracion", _boxes.size(),
                _pads.size());
        }

        // Placas: siempre puestas (solo se reinvocan si desaparecen)
        for (BoostPad& pad : _pads)
        {
            if (!pad.Creature || !map->GetCreature(pad.Creature))
            {
                TempSummon* creature = map->SummonCreature(NPC_RACE_BOOST_PAD, pad.Pos);
                pad.Creature = creature ? creature->GetGUID() : ObjectGuid::Empty;
            }
        }

        for (PowerBox& box : _boxes)
        {
            if (box.Respawn > 0ms)
            {
                box.Respawn = box.Respawn > elapsed ? box.Respawn - elapsed : 0ms;
                if (box.Respawn > 0ms)
                    continue;
            }

            if (!box.Creature || !map->GetCreature(box.Creature))
            {
                TempSummon* creature = map->SummonCreature(NPC_RACE_POWER_BOX, box.Pos);
                box.Creature = creature ? creature->GetGUID() : ObjectGuid::Empty;
            }
        }

        for (auto itr = _oil.begin(); itr != _oil.end();)
        {
            itr->Age += elapsed;
            if (itr->Age >= OilLife)
            {
                Despawn(map, itr->Creature);
                itr = _oil.erase(itr);
            }
            else
                ++itr;
        }
    }

    static void Despawn(Map* map, ObjectGuid guid)
    {
        if (Creature* creature = guid ? map->GetCreature(guid) : nullptr)
            creature->DespawnOrUnsummon();
    }

    // El tramo from -> to (lo recorrido desde la comprobacion anterior) pasa a menos de radius de pos
    static bool Touches(Position const& from, Position const& to, Position const& pos, float radius)
    {
        float const dx = to.GetPositionX() - from.GetPositionX();
        float const dy = to.GetPositionY() - from.GetPositionY();
        float const len2 = dx * dx + dy * dy;
        float t = 0.0f;
        if (len2 > 0.0001f)
            t = std::clamp(((pos.GetPositionX() - from.GetPositionX()) * dx + (pos.GetPositionY() - from.GetPositionY()) * dy)
                / len2, 0.0f, 1.0f);

        float const x = from.GetPositionX() + dx * t;
        float const y = from.GetPositionY() + dy * t;
        float const z = from.GetPositionZ() + (to.GetPositionZ() - from.GetPositionZ()) * t;
        float const ex = pos.GetPositionX() - x;
        float const ey = pos.GetPositionY() - y;
        return ex * ex + ey * ey <= radius * radius && std::fabs(z - pos.GetPositionZ()) <= PickupHeight;
    }

    // Cajas y manchas que toca la moto (desde el seguimiento, cada 100 ms)
    void CheckItems(Player* player, Racer& racer, WorldObject const& body)
    {
        Position const to = body.GetPosition();
        Position const from = racer.HasLastPos && racer.LastPos.GetExactDist(&to) <= MaxSweep ? racer.LastPos : to;
        racer.LastPos = to;
        racer.HasLastPos = true;

        Map* map = GetMap();
        if (!map || GetState() != MiWowMatchState::Running)
            return;

        // Con los huecos llenos la caja se queda para otro
        if (racer.Powers.size() < MaxPowers)
        {
            for (PowerBox& box : _boxes)
            {
                if (box.Respawn > 0ms || !Touches(from, to, box.Pos, BoxPickupRadius))
                    continue;

                Despawn(map, box.Creature);
                box.Creature.Clear();
                box.Respawn = BoxRespawn;
                GivePower(player, racer);
                if (racer.Powers.size() >= MaxPowers)
                    break;
            }
        }

        // Placas: acelerón a la moto (la misma placa no repite enseguida; otra si)
        for (std::size_t i = 0; i < _pads.size(); ++i)
        {
            if (!Touches(from, to, _pads[i].Pos, BoostRadius))
                continue;
            if (racer.LastBoostPad == i && _clock - racer.LastBoostTime < BoostRetrigger)
                continue;

            racer.LastBoostPad = i;
            racer.LastBoostTime = _clock;
            if (Unit* vehicle = player->GetVehicleBase())
                vehicle->CastSpell(vehicle, SPELL_RACE_BOOST, true);
        }

        for (auto itr = _oil.begin(); itr != _oil.end(); ++itr)
        {
            if (itr->Owner == player->GetGUID() && itr->Age < OilOwnerGrace)
                continue;
            if (!Touches(from, to, itr->Pos, OilRadius))
                continue;

            Despawn(map, itr->Creature);
            _oil.erase(itr);
            Hit(player, SPELL_RACE_SPIN);
            break;
        }
    }

    // Poder al azar segun la posicion: el primero recibe mas defensa, el ultimo mas ataque y velocidad
    void GivePower(Player* player, Racer& racer)
    {
        std::vector<ObjectGuid> const order = Standings();
        std::size_t const position = std::find(order.begin(), order.end(), player->GetGUID()) - order.begin();
        float const t = order.size() > 1 ? float(position) / float(order.size() - 1) : 0.5f;

        float total = 0.0f;
        for (PowerWeight const& weight : PowerWeights)
            total += weight.First + (weight.Last - weight.First) * t;

        float roll = frand(0.0f, total);
        uint32 spell = PowerWeights.back().Spell;
        for (PowerWeight const& weight : PowerWeights)
        {
            float const w = weight.First + (weight.Last - weight.First) * t;
            if (roll < w)
            {
                spell = weight.Spell;
                break;
            }
            roll -= w;
        }

        racer.Powers.push_back(spell);
        ApplyPowerToVehicle(player, racer);
        MiWowMessage("RACE_EVENT").Add("ITEM").Add(spell).Add(static_cast<uint32>(racer.Powers.size())).Send(player);
    }

    // Los poderes van a los huecos 1..MaxPowers de la barra de la moto (cada moto es una criatura propia)
    static void ApplyPowerToVehicle(Player* player, Racer const& racer)
    {
        Creature* vehicle = player->GetVehicleCreatureBase();
        if (!vehicle)
            return;

        for (std::size_t i = 0; i < MaxPowers; ++i)
            vehicle->m_spells[i] = i < racer.Powers.size() ? racer.Powers[i] : 0;
        player->VehicleSpellInitialize();
    }

    // Golpe a la moto de victim (derrape o frenado); el escudo lo para
    void Hit(Player* victim, uint32 effectSpell)
    {
        auto itr = _racers.find(victim->GetGUID());
        Unit* vehicle = victim->GetVehicleBase();
        if (itr == _racers.end() || itr->second.FinishPosition || !vehicle)
            return;

        if (vehicle->HasAura(SPELL_RACE_SHIELD))
        {
            vehicle->RemoveAurasDueToSpell(SPELL_RACE_SHIELD);
            MiWowMessage("RACE_EVENT").Add("BLOCK").Send(victim);
            return;
        }

        vehicle->CastSpell(vehicle, effectSpell, true);
        MiWowMessage("RACE_EVENT").Add("HIT").Add(effectSpell).Send(victim);
    }

    // Piloto en carrera justo delante (o justo detras si es el primero)
    Player* RocketTarget(Player* shooter) const
    {
        std::vector<ObjectGuid> order = Standings();
        order.erase(std::remove_if(order.begin(), order.end(), [this, shooter](ObjectGuid const& guid)
        {
            return guid != shooter->GetGUID() && _racers.at(guid).FinishPosition;
        }), order.end());

        auto self = std::find(order.begin(), order.end(), shooter->GetGUID());
        if (self == order.end() || order.size() < 2)
            return nullptr;

        ObjectGuid const target = self != order.begin() ? *(self - 1) : *(self + 1);
        Player* player = ObjectAccessor::FindConnectedPlayer(target);
        return player && player->GetInstanceId() == GetInstanceId() && player->GetVehicleBase() ? player : nullptr;
    }

    void FireRocket(Player* shooter)
    {
        Unit* from = shooter->GetVehicleBase();
        Player* target = RocketTarget(shooter);
        if (!from || !target)
            return;

        from->CastSpell(target->GetVehicleBase(), SPELL_RACE_ROCKET_MISSILE, true);
    }

    void DropOil(Player* player)
    {
        Map* map = GetMap();
        Unit* vehicle = player->GetVehicleBase();
        if (!map || !vehicle)
            return;

        float const o = vehicle->GetOrientation();
        Position pos(vehicle->GetPositionX() - std::cos(o) * OilBehind, vehicle->GetPositionY() - std::sin(o) * OilBehind,
            vehicle->GetPositionZ(), o);
        float const ground = map->GetHeight(PHASEMASK_NORMAL, pos.GetPositionX(), pos.GetPositionY(),
            pos.GetPositionZ() + 5.0f, true, 15.0f);
        if (std::fabs(ground - pos.GetPositionZ()) < 6.0f)
            pos.m_positionZ = ground;

        OilSlick oil;
        oil.Pos = pos;
        oil.Owner = player->GetGUID();
        if (TempSummon* creature = map->SummonCreature(NPC_RACE_OIL, pos))
            oil.Creature = creature->GetGUID();
        _oil.push_back(oil);
    }

    // Frena a todos los que van por delante
    void Lightning(Player* caster)
    {
        std::vector<ObjectGuid> const order = Standings();
        for (ObjectGuid const& guid : order)
        {
            if (guid == caster->GetGUID())
                break;
            if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
                if (player->GetInstanceId() == GetInstanceId())
                    Hit(player, SPELL_RACE_SHOCK);
        }
    }

    // Raiz en la moto (el que se mueve es el vehiculo). Nunca en el jugador: montado, el core no deja quitarsela
    // (Unit::SetControlled no la quita con GetVehicle()) y se la llevaria al lobby. Sin moto no hace nada.
    static void SetRooted(Player* player, bool rooted)
    {
        Unit* unit = player->GetVehicleBase();
        if (!unit)
            return;

        if (rooted != unit->HasUnitState(UNIT_STATE_ROOT))
            unit->SetControlled(rooted, UNIT_STATE_ROOT);
    }

    void Track(Player* player)
    {
        auto itr = _racers.find(player->GetGUID());
        if (itr == _racers.end() || !player->IsAlive() || player->GetInstanceId() != GetInstanceId())
            return;

        Racer& racer = itr->second;
        if (racer.FinishPosition || racer.Frozen > 0ms || player->IsBeingTeleported())
            return;

        // Posicion de la moto (la que mueve el cliente); sin moto, la del jugador
        WorldObject const* body = player->GetVehicleBase();
        if (!body)
            body = player;

        // Muestra mas cercana en la ventana (3D: la z separa los tramos que se cruzan)
        float const px = body->GetPositionX();
        float const py = body->GetPositionY();
        float const pz = body->GetPositionZ();
        int32 best = racer.Index;
        float bestDist = std::numeric_limits<float>::max();
        for (int32 i = racer.Index - WindowBack; i <= racer.Index + WindowAhead; ++i)
        {
            RaceSample const& s = _track.At(i);
            float const dz = (pz - s.Z) * 0.5f;
            float const d = (s.X - px) * (s.X - px) + (s.Y - py) * (s.Y - py) + dz * dz;
            if (d < bestDist)
            {
                bestDist = d;
                best = _track.Wrap(i);
            }
        }

        RaceSample const& sample = _track.At(best);
        float const side = std::hypot(sample.X - px, sample.Y - py);
        bool const dev = MiWowDevMode::IsActive(player);
        if (!dev && (pz < sample.Z - _settings.FallDepth || side > sample.Half + _settings.OffTrackMargin))
        {
            Fell(player, racer);
            return;
        }

        // Avance con signo (la pista es cerrada: la diferencia de indices se lleva a [-n/2, n/2))
        int32 delta = best - racer.Index;
        int32 const n = _track.Count();
        if (delta > n / 2)
            delta -= n;
        else if (delta < -n / 2)
            delta += n;

        racer.Index = best;
        float const moved = delta * _track.Step;
        racer.Progress += moved;
        if (side <= sample.Half + 1.0f)
            racer.LastGoodIndex = best;

        // Direccion contraria: varias yardas seguidas hacia atras
        if (moved < 0.0f)
            racer.Backwards -= moved;
        else if (moved > 0.0f)
            racer.Backwards = std::max(0.0f, racer.Backwards - moved * 2.0f);
        racer.WrongWay = racer.Backwards > WrongWayDistance;

        CheckItems(player, racer, *body);

        // Vueltas: cada vez que el avance pasa por la meta (multiplo de la longitud)
        while (racer.LapsDone < RaceLaps && racer.Progress >= (racer.LapsDone + 1) * _track.Length)
        {
            ++racer.LapsDone;
            Milliseconds const lapTime = _clock - racer.LapStart;
            racer.LapStart = _clock;
            if (racer.BestLap == 0ms || lapTime < racer.BestLap)
                racer.BestLap = lapTime;

            if (racer.LapsDone >= RaceLaps)
            {
                Finish(player, racer);
                return;
            }

            MiWowMessage("RACE_EVENT").Add("LAP").Add(racer.LapsDone + 1).Add(static_cast<uint32>(lapTime.count()))
                .Send(player);
            if (racer.LapsDone + 1 == RaceLaps)
                MiWowMessage("RACE_EVENT").Add("FINAL_LAP").Send(player);
        }

    }

    // Lleva el seguimiento a la muestra index (atras) corrigiendo el avance
    void MoveTo(Racer& racer, int32 index) const
    {
        int32 delta = index - racer.Index;
        int32 const n = _track.Count();
        if (delta > n / 2)
            delta -= n;
        else if (delta < -n / 2)
            delta += n;

        racer.Progress += delta * _track.Step;
        racer.Index = index;
        racer.LastGoodIndex = index;
        racer.Backwards = 0.0f;
        racer.WrongWay = false;
    }

    void Fell(Player* player, Racer& racer)
    {
        // Vuelve al ultimo punto bueno (un poco antes)
        int32 const index = _track.Wrap(racer.LastGoodIndex - 2);
        MoveTo(racer, index);
        racer.Frozen = FallFreeze;
        racer.HasLastPos = false;

        // Sin TeleportVehicle: fuera la moto, el jugador al punto y OnTick le da otra alli (ya quieta)
        Position const pos = _track.Place(index, 0.0f, 1.5f);
        MiWowVehicle::DismissVehicle(player);
        player->NearTeleportTo(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ(), pos.GetOrientation());
        MiWowMessage("RACE_EVENT").Add("FELL").Send(player);
    }

    void Finish(Player* player, Racer& racer)
    {
        racer.FinishTime = _clock;
        racer.FinishPosition = ++_finished;
        racer.WrongWay = false;
        SetRooted(player, true);

        MiWowMessage("RACE_EVENT").Add("FINISH").Add(racer.FinishPosition)
            .Add(static_cast<uint32>(racer.FinishTime.count())).Send(player);
        SendRace(player);

        if (racer.FinishPosition == 1)
        {
            SetResult(player->GetGUID(), MiWowMatchResult::Win);
            std::string const name = player->GetName();
            ForEachPlayer([&name](Player* member)
            {
                MiWowMessage("RACE_EVENT").Add("WINNER").Add(name)
                    .Add(static_cast<uint32>(FinishWindow.count())).Send(member);
            });
            SetHud(name + " ha ganado. ¡Termina la carrera!");
            SetTimer(FinishWindow);
        }

        BroadcastResults(false);
        if (AllFinished())
            EndRace();
    }

    bool AllFinished() const
    {
        return std::all_of(_racers.begin(), _racers.end(), [](auto const& r) { return r.second.FinishPosition != 0; });
    }

    void EndRace()
    {
        if (GetState() != MiWowMatchState::Running)
            return;

        std::vector<ObjectGuid> const order = Standings();
        std::string winner;
        if (!order.empty())
            if (Player* first = ObjectAccessor::FindConnectedPlayer(order.front()))
                if (_racers.at(order.front()).FinishPosition == 1)
                    winner = first->GetName();

        ForEachPlayer([](Player* player) { SetRooted(player, true); });
        BroadcastResults(true);
        End(winner.empty() ? std::string("Nadie ha terminado la carrera.") : "Ganador: " + winner);
    }

    // Orden: los que han terminado (por llegada) y despues el resto por avance
    std::vector<ObjectGuid> Standings() const
    {
        std::vector<ObjectGuid> order;
        for (auto const& [guid, racer] : _racers)
            order.push_back(guid);

        std::sort(order.begin(), order.end(), [this](ObjectGuid const& a, ObjectGuid const& b)
        {
            Racer const& ra = _racers.at(a);
            Racer const& rb = _racers.at(b);
            if (ra.FinishPosition && rb.FinishPosition)
                return ra.FinishPosition < rb.FinishPosition;
            if (ra.FinishPosition != rb.FinishPosition)
                return ra.FinishPosition != 0;
            return ra.Progress > rb.Progress;
        });
        return order;
    }

    void SendRace(Player* player) const
    {
        auto itr = _racers.find(player->GetGUID());
        if (itr == _racers.end())
            return;

        Racer const& racer = itr->second;
        std::vector<ObjectGuid> const order = Standings();
        uint32 const position = static_cast<uint32>(std::find(order.begin(), order.end(), player->GetGUID()) - order.begin()) + 1;
        Milliseconds const total = racer.FinishPosition ? racer.FinishTime : _clock;
        Milliseconds const lap = racer.FinishPosition ? 0ms : _clock - racer.LapStart;

        MiWowMessage("RACE").Add(std::min(RaceLaps, racer.LapsDone + 1)).Add(RaceLaps).Add(position)
            .Add(static_cast<uint32>(order.size())).Add(static_cast<uint32>(total.count()))
            .Add(static_cast<uint32>(lap.count())).Add(static_cast<uint32>(racer.BestLap.count()))
            .Add(racer.WrongWay ? 1 : 0).Add(racer.FinishPosition ? 1 : 0).Send(player);
    }

    void SendResults(Player* player, bool final) const
    {
        std::vector<ObjectGuid> const order = Standings();
        MiWowMessage message("RACE_RESULTS");
        message.Add(final ? 1 : 0).Add(static_cast<uint32>(order.size()));
        uint32 position = 0;
        for (ObjectGuid const& guid : order)
        {
            Racer const& racer = _racers.at(guid);
            Player* member = ObjectAccessor::FindConnectedPlayer(guid);
            message.Add(++position).Add(member ? member->GetName() : std::string("?"))
                .Add(static_cast<uint32>(racer.FinishTime.count())).Add(static_cast<uint32>(racer.BestLap.count()));
        }
        message.Send(player);
    }

    void BroadcastResults(bool final) const
    {
        ForEachPlayer([this, final](Player* player) { SendResults(player, final); });
    }

    RaceTrack const& _track;
    RaceSettings _settings;
    std::unordered_map<ObjectGuid, Racer> _racers;
    Milliseconds _clock = 0ms;
    Milliseconds _trackTimer = 0ms;
    Milliseconds _hudTimer = 0ms;
    Milliseconds _rootTimer = 0ms;
    uint32 _finished = 0;
    mutable Position _respawnPosition;
    std::vector<PowerBox> _boxes;
    std::vector<BoostPad> _pads;
    std::vector<OilSlick> _oil;
    bool _boxesPlaced = false;
    bool _mounted = false;
    Milliseconds _countdownElapsed = 0ms;
};

// Activadores de los poderes (los lanza la moto desde su barra): avisan al juego
class spell_miwow_race_power : public SpellScript
{
    PrepareSpellScript(spell_miwow_race_power);

    void HandleAfterCast()
    {
        Unit* caster = GetCaster();
        Player* player = caster ? caster->GetCharmerOrOwnerPlayerOrPlayerItself() : nullptr;
        if (!player)
            return;

        if (MiWowGameRace* race = dynamic_cast<MiWowGameRace*>(sMiWowMatchMgr.GetMatch(player)))
            race->OnPowerUsed(player, GetSpellInfo()->Id);
    }

    void Register() override
    {
        AfterCast += SpellCastFn(spell_miwow_race_power::HandleAfterCast);
    }
};

// Cohete: al llegar a la moto objetivo, el juego aplica el derrape (o lo para el escudo)
class spell_miwow_race_missile : public SpellScript
{
    PrepareSpellScript(spell_miwow_race_missile);

    void HandleDummy(SpellEffIndex /*effIndex*/)
    {
        Unit* target = GetHitUnit();
        Player* victim = target ? target->GetCharmerOrOwnerPlayerOrPlayerItself() : nullptr;
        if (!victim)
            return;

        if (MiWowGameRace* race = dynamic_cast<MiWowGameRace*>(sMiWowMatchMgr.GetMatch(victim)))
            race->OnRocketHit(victim);
    }

    void Register() override
    {
        OnEffectHitTarget += SpellEffectFn(spell_miwow_race_missile::HandleDummy, EFFECT_0, SPELL_EFFECT_DUMMY);
    }
};

namespace
{
    void RegisterRace(MiWowGameInfo game, RaceSettings settings)
    {
        RaceTrack track;
        if (LoadTrack(game.MapId, track))
        {
            RaceTrack const& stored = Tracks[game.MapId] = std::move(track);
            game.Start = stored.Place(stored.Wrap(-5), 0.0f, 2.0f);
            game.Factory = [&stored, settings]() { return std::make_unique<MiWowGameRace>(stored, settings); };
        }
        else
            game.Description += " (No disponible: falta la pista en el servidor.)";

        sMiWowGames.Register(std::move(game));
    }
}

void AddSC_miwow_game_race()
{
    RegisterSpellScript(spell_miwow_race_power);
    RegisterSpellScript(spell_miwow_race_missile);

    MiWowGameInfo game;
    game.MinPlayers = 1;
    game.MaxPlayers = GridSlots;
    game.MaxPartySize = 5;

    // Mapa 752 (tools/mapgen/trackgen.py, Maps/Planos/circuito_cuatro_tierras.json)
    MiWowGameInfo lands = game;
    lands.Id = "carrera";
    lands.Name = "Carrera: Cuatro Tierras";
    lands.Description = "Carrera de motos a 2 vueltas por praderas, bosques, montañas nevadas y cañones. "
        "De 1 a 8 pilotos.";
    lands.Icon = "Interface\\Icons\\Ability_Mount_MechaStrider";
    lands.MapId = 752;
    RegisterRace(lands, { 40.0f, 15.0f });

    // Mapa 753 (tools/mapgen/platformgen.py, Maps/Planos/circuito_estelar.json): sin barandillas, caer es facil
    MiWowGameInfo stars = game;
    stars.Id = "carrera_estelar";
    stars.Name = "Carrera: Circuito Estelar";
    stars.Description = "Carrera de motos a 2 vueltas sobre plataformas flotando en el vacío, sin barandillas y con "
        "un cruce en ocho. De 1 a 8 pilotos.";
    stars.Icon = "Interface\\Icons\\ability_mount_rocketmountblue";
    stars.MapId = 753;
    RegisterRace(stars, { 25.0f, 10.0f });
}
