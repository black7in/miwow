#include "EventWowGames.h"
#include "EventWowConfig.h"
#include "EventWowProtocol.h"
#include "Log.h"
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

namespace
{
    // GAMES <n> (<id> <icono> <min> <max> <nombre> <descripcion>) x n
    void SendGameList(Player* player)
    {
        auto const& games = sEventWowGames.GetAll();

        EventWowMessage message("GAMES");
        message.Add(static_cast<uint32>(games.size()));
        for (EventWowGameInfo const& game : games)
            message.Add(game.Id).Add(game.Icon).Add(game.MinPlayers).Add(game.MaxPlayers)
                .Add(game.Name).Add(game.Description);

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

        LOG_INFO("module.eventwow", "EventWow: {} minijuego(s) registrado(s), protocolo v{}",
            sEventWowGames.GetAll().size(), EventWowProtocol::Version);
    }
};

void AddSC_eventwow_games()
{
    EventWowProtocol::RegisterHandler("LIST", HandleList);
    EventWowProtocol::RegisterConnectListener(SendGameList);

    // Provisional (corte vertical): los registrara el framework de minijuegos (paso 7).
    // "race" e "invasion" solo existen para maquetar el panel con varios juegos.
    sEventWowGames.Register({
        "test",
        "Prueba",
        "Minijuego de prueba en solitario.",
        "Interface\\Icons\\INV_Misc_QuestionMark",
        1,
        1
    });
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
        20
    });

    new EventWow_GamesWorldScript();
}
