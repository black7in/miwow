#include "EventWowGames.h"
#include "EventWowConfig.h"
#include "EventWowProtocol.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "StringConvert.h"
#include <algorithm>

EventWowGames& EventWowGames::Instance()
{
    static EventWowGames instance;
    return instance;
}

void EventWowGames::Register(EventWowGameInfo info)
{
    auto itr = std::find_if(_games.begin(), _games.end(),
        [&info](EventWowGameInfo const& game) { return game.Id == info.Id; });
    if (itr != _games.end())
    {
        LOG_ERROR("module.eventwow", "EventWow: minijuego '{}' registrado dos veces, se ignora el segundo", info.Id);
        return;
    }

    _games.push_back(std::move(info));
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

    // HELLO <version>: el cliente entra al mundo (o recarga la UI)
    void HandleHello(Player* player, EventWowProtocol::Args const& args)
    {
        Optional<uint32> version = args.empty() ? std::nullopt : Acore::StringTo<uint32>(args[0]);
        if (version != EventWowProtocol::Version)
        {
            LOG_DEBUG("module.eventwow", "EventWow: {} usa protocolo {}, servidor {}",
                player->GetName(), args.empty() ? "?" : args[0], EventWowProtocol::Version);
            EventWowMessage("ERROR").Add("VERSION").Add(EventWowProtocol::Version).Send(player);
            return;
        }

        EventWowMessage("WELCOME").Add(EventWowProtocol::Version).Send(player);
        SendGameList(player);
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
    EventWowProtocol::RegisterHandler("HELLO", HandleHello);
    EventWowProtocol::RegisterHandler("LIST", HandleList);

    // Provisional (corte vertical): lo registrara el framework de minijuegos (paso 7)
    sEventWowGames.Register({
        "test",
        "Prueba",
        "Minijuego de prueba en solitario.",
        "Interface\\Icons\\INV_Misc_QuestionMark",
        1,
        1
    });

    new EventWow_GamesWorldScript();
}
