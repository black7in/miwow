#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowGames.h"
#include "EventWowProtocol.h"
#include "GameTime.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"

// Cola de minijuegos - PROVISIONAL: solo guarda el estado por jugador para que el panel funcione.
// El emparejamiento y las instancias de verdad llegan en el paso 6 (matchmaking).
//
//   Cliente -> servidor: QUEUE <id juego> | LEAVE
//   Servidor -> cliente: QUEUE_STATUS QUEUED <id juego> <segundos en cola> | QUEUE_STATUS NONE
//                        ERROR QUEUE_UNKNOWN_GAME | QUEUE_NOT_IN_LOBBY
namespace
{
    // En Player::CustomData: se pierde con el logout, igual que la cola
    struct QueueState : public DataMap::Base
    {
        std::string GameId;
        Seconds Since = 0s;
    };

    QueueState* GetState(Player* player)
    {
        return player->CustomData.GetDefault<QueueState>("EventWowQueue");
    }

    void SendStatus(Player* player)
    {
        QueueState const* state = GetState(player);
        if (state->GameId.empty())
        {
            EventWowMessage("QUEUE_STATUS").Add("NONE").Send(player);
            return;
        }

        uint32 const waited = static_cast<uint32>((GameTime::GetGameTime() - state->Since).count());
        EventWowMessage("QUEUE_STATUS").Add("QUEUED").Add(state->GameId).Add(waited).Send(player);
    }

    void HandleQueue(Player* player, EventWowProtocol::Args const& args)
    {
        EventWowGameInfo const* game = args.empty() ? nullptr : sEventWowGames.GetGame(args[0]);
        if (!game)
        {
            EventWowMessage("ERROR").Add("QUEUE_UNKNOWN_GAME").Send(player);
            return;
        }

        if (player->GetMapId() != sEventWowConfig.Lobby.GetMapId())
        {
            EventWowMessage("ERROR").Add("QUEUE_NOT_IN_LOBBY").Send(player);
            return;
        }

        // Una sola cola a la vez: apuntarse a otro juego sustituye la anterior
        QueueState* state = GetState(player);
        if (state->GameId != game->Id)
        {
            state->GameId = game->Id;
            state->Since = GameTime::GetGameTime();
            LOG_DEBUG("module.eventwow", "EventWow: {} entra en cola de '{}'", player->GetName(), game->Id);
        }

        SendStatus(player);
    }

    void HandleLeave(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        QueueState* state = GetState(player);
        if (!state->GameId.empty())
            LOG_DEBUG("module.eventwow", "EventWow: {} sale de la cola de '{}'", player->GetName(), state->GameId);

        state->GameId.clear();
        SendStatus(player);
    }
}

void AddSC_eventwow_queue()
{
    EventWowProtocol::RegisterHandler("QUEUE", HandleQueue);
    EventWowProtocol::RegisterHandler("LEAVE", HandleLeave);
    EventWowProtocol::RegisterConnectListener(SendStatus);
}
