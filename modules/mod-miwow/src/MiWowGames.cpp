#include "MiWowGames.h"
#include "DBCStores.h"
#include "MiWowConfig.h"
#include "MiWowProtocol.h"
#include "Group.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <algorithm>

MiWowGames& MiWowGames::Instance()
{
    static MiWowGames instance;
    return instance;
}

void MiWowGames::Register(MiWowGameInfo info)
{
    if (GetGame(info.Id))
    {
        LOG_ERROR("module.miwow", "MiWow: minijuego '{}' registrado dos veces, se ignora el segundo", info.Id);
        return;
    }

    _games.push_back(std::move(info));
}

MiWowGameInfo const* MiWowGames::GetGame(std::string_view id) const
{
    auto itr = std::find_if(_games.begin(), _games.end(), [id](MiWowGameInfo const& game) { return game.Id == id; });
    return itr != _games.end() ? &*itr : nullptr;
}

void MiWowGames::Validate()
{
    for (MiWowGameInfo& game : _games)
    {
        game.MaxPartySize = std::clamp<uint8>(game.MaxPartySize, 1, std::max<uint8>(1, std::min<uint8>(game.MaxPlayers, MAXGROUPSIZE)));

        if (!game.IsPlayable())
            continue;

        MapEntry const* entry = sMapStore.LookupEntry(game.MapId);
        char const* error = nullptr;
        if (game.MapId < MiWowFirstMapId || game.MapId > MiWowLastMapId)
            error = "el mapa no es propio de MiWow (750-799)";
        else if (!entry || !entry->IsDungeon())
            error = "el mapa no es de mazmorra/banda";
        else if (!sObjectMgr->GetInstanceTemplate(game.MapId))
            error = "el mapa no tiene instance_template";
        else if (!GetMapDifficultyData(game.MapId, REGULAR_DIFFICULTY))
            error = "el mapa no tiene dificultad normal";
        else if (!MapMgr::IsValidMapCoord(game.MapId, game.Start))
            error = "punto de aparicion invalido";
        else if (game.MinPlayers < 1 || game.MinPlayers > game.MaxPlayers)
            error = "MinPlayers/MaxPlayers invalidos";

        if (error)
        {
            LOG_ERROR("module.miwow", "MiWow: minijuego '{}' (mapa {}) desactivado: {}", game.Id, game.MapId, error);
            game.Factory = nullptr;
        }
    }
}

namespace
{
    // GAMES <n> (<id> <icono> <min> <max> <nombre> <descripcion> <jugable 0/1> <grupo max> <casillas> <sesion abierta 0/1>)
    //   (casillas: campo de la rama main; aqui siempre 0, el cliente lo ignora)
    //   x n
    void SendGameList(Player* player)
    {
        auto const& games = sMiWowGames.GetAll();

        MiWowMessage message("GAMES");
        message.Add(static_cast<uint32>(games.size()));
        for (MiWowGameInfo const& game : games)
            message.Add(game.Id).Add(game.Icon).Add(game.MinPlayers).Add(game.MaxPlayers)
                .Add(game.Name).Add(game.Description).Add(game.IsPlayable() ? 1 : 0).Add(game.MaxPartySize)
                .Add(0).Add(game.OpenSession ? 1 : 0);

        message.Send(player);
    }

    // LIST: volver a pedir el catalogo
    void HandleList(Player* player, MiWowProtocol::Args const& /*args*/)
    {
        SendGameList(player);
    }
}

class MiWow_GamesWorldScript : public WorldScript
{
public:
    MiWow_GamesWorldScript() : WorldScript("MiWow_GamesWorldScript", {
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnStartup() override
    {
        if (!sMiWowConfig.Enabled)
            return;

        sMiWowGames.Validate();
        LOG_INFO("module.miwow", "MiWow: {} minijuego(s) registrado(s), protocolo v{}",
            sMiWowGames.GetAll().size(), MiWowProtocol::Version);
    }
};

void AddSC_miwow_games()
{
    MiWowProtocol::RegisterHandler("LIST", HandleList);
    MiWowProtocol::RegisterConnectListener(SendGameList);

    // Maquetas para el panel con varios juegos (sin factoria: no se puede buscar partida).
    // Los juegos reales se registran en games/ (AddSC_miwow_game_*), antes que estos.
    sMiWowGames.Register({
        "invasion",
        "Invasión",
        "Resistid juntos oleada tras oleada de enemigos hasta derrotar al jefe final. (Maqueta: todavía no existe.)",
        "Interface\\Icons\\Spell_Shadow_SummonFelGuard",
        5,
        20,
        5
    });

    new MiWow_GamesWorldScript();
}
