#include "EventWowGames.h"
#include "DBCStores.h"
#include "EventWowConfig.h"
#include "EventWowInventory.h"
#include "EventWowProtocol.h"
#include "Group.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <algorithm>

EventWowGames& EventWowGames::Instance()
{
    static EventWowGames instance;
    return instance;
}

void EventWowGames::Register(EventWowGameInfo info)
{
    if (GetGame(info.Id))
    {
        LOG_ERROR("module.eventwow", "EventWow: minijuego '{}' registrado dos veces, se ignora el segundo", info.Id);
        return;
    }

    _games.push_back(std::move(info));
}

EventWowGameInfo const* EventWowGames::GetGame(std::string_view id) const
{
    auto itr = std::find_if(_games.begin(), _games.end(), [id](EventWowGameInfo const& game) { return game.Id == id; });
    return itr != _games.end() ? &*itr : nullptr;
}

void EventWowGames::Validate()
{
    for (EventWowGameInfo& game : _games)
    {
        game.MaxPartySize = std::clamp<uint8>(game.MaxPartySize, 1, std::max<uint8>(1, std::min<uint8>(game.MaxPlayers, MAXGROUPSIZE)));
        game.InventorySlots = std::min(game.InventorySlots, EventWowInventory::MaxSlots);

        if (!game.IsPlayable())
            continue;

        MapEntry const* entry = sMapStore.LookupEntry(game.MapId);
        char const* error = nullptr;
        if (!entry || !entry->IsDungeon())
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
            LOG_ERROR("module.eventwow", "EventWow: minijuego '{}' (mapa {}) desactivado: {}", game.Id, game.MapId, error);
            game.Factory = nullptr;
        }
    }
}

namespace
{
    // GAMES <n> (<id> <icono> <min> <max> <nombre> <descripcion> <jugable 0/1> <grupo max> <casillas>) x n
    void SendGameList(Player* player)
    {
        auto const& games = sEventWowGames.GetAll();

        EventWowMessage message("GAMES");
        message.Add(static_cast<uint32>(games.size()));
        for (EventWowGameInfo const& game : games)
            message.Add(game.Id).Add(game.Icon).Add(game.MinPlayers).Add(game.MaxPlayers)
                .Add(game.Name).Add(game.Description).Add(game.IsPlayable() ? 1 : 0).Add(game.MaxPartySize)
                .Add(game.InventorySlots);

        message.Send(player);
    }

    // LIST: volver a pedir el catalogo
    void HandleList(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        SendGameList(player);
    }
}

class EventWow_GamesWorldScript : public WorldScript
{
public:
    EventWow_GamesWorldScript() : WorldScript("EventWow_GamesWorldScript", {
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnStartup() override
    {
        if (!sEventWowConfig.Enabled)
            return;

        sEventWowGames.Validate();
        LOG_INFO("module.eventwow", "EventWow: {} minijuego(s) registrado(s), protocolo v{}",
            sEventWowGames.GetAll().size(), EventWowProtocol::Version);
    }
};

void AddSC_eventwow_games()
{
    EventWowProtocol::RegisterHandler("LIST", HandleList);
    EventWowProtocol::RegisterConnectListener(SendGameList);

    // Maquetas para el panel con varios juegos (sin factoria: no se puede buscar partida).
    // Los juegos reales se registran en games/ (AddSC_eventwow_game_*), antes que estos.
    sEventWowGames.Register({
        "race",
        "Carrera",
        "Llega el primero a la meta esquivando los obstáculos del recorrido. (Maqueta: todavía no existe.)",
        "Interface\\Icons\\Ability_Rogue_Sprint",
        2,
        10
    });
    sEventWowGames.Register({
        "invasion",
        "Invasión",
        "Resistid juntos oleada tras oleada de enemigos hasta derrotar al jefe final. (Maqueta: todavía no existe.)",
        "Interface\\Icons\\Spell_Shadow_SummonFelGuard",
        5,
        20,
        5
    });

    new EventWow_GamesWorldScript();
}
