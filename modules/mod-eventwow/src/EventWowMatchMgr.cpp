#include "EventWowMatchMgr.h"
#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowGames.h"
#include "EventWowLobby.h"
#include "EventWowMatch.h"
#include "EventWowProtocol.h"
#include "GameTime.h"
#include "InstanceSaveMgr.h"
#include "Log.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"
#include <algorithm>

//   Cliente -> servidor: QUEUE <id juego> | LEAVE | ABANDON
//   Servidor -> cliente: QUEUE_STATUS QUEUED <id juego> <segundos en cola> | QUEUE_STATUS NONE
//                        MATCH_STATE ... / MATCH_HUD / MATCH_END (EventWowMatch.cpp) | MATCH_STATE NONE
//                        ERROR QUEUE_UNKNOWN_GAME | QUEUE_GAME_UNAVAILABLE | QUEUE_IN_MATCH | QUEUE_NOT_IN_LOBBY
//                              | MATCH_CREATE_FAILED | MATCH_TELEPORT_FAILED
namespace
{
    // Estado por jugador en Player::CustomData (se pierde con el logout, igual que la cola y la partida)
    std::string const QueueKey = "EventWowQueue";
    std::string const MatchKey = "EventWowMatch";

    struct QueueSlot : public DataMap::Base
    {
        std::string GameId;
        Seconds Since = 0s;
    };

    // Lo leen los hooks de instancia (pueden llegar desde hilos de mapa): solo datos del propio jugador
    struct MatchSlot : public DataMap::Base
    {
        uint32 MatchId = 0;
        uint32 MapId = 0;
        uint32 InstanceId = 0;
        bool Arrived = false;
    };

    QueueSlot* GetQueueSlot(Player const* player)
    {
        return player->CustomData.Get<QueueSlot>(QueueKey);
    }

    MatchSlot* GetMatchSlot(Player const* player)
    {
        return player->CustomData.Get<MatchSlot>(MatchKey);
    }

    void SendNoMatch(Player* player)
    {
        EventWowMessage("MATCH_STATE").Add("NONE").Send(player);
    }
}

EventWowMatchMgr& EventWowMatchMgr::Instance()
{
    static EventWowMatchMgr instance;
    return instance;
}

void EventWowMatchMgr::Update(Milliseconds diff)
{
    _queueTimer += diff;
    if (_queueTimer >= 1s)
    {
        _queueTimer = 0ms;
        UpdateQueues();
    }

    std::vector<uint32> toClose;
    for (auto const& [id, match] : _matches)
    {
        match->Update(diff);
        if (match->IsReadyToClose())
            toClose.push_back(id);
    }

    for (uint32 id : toClose)
        CloseMatch(id);
}

// Cola ------------------------------------------------------------------------------------------

char const* EventWowMatchMgr::Enqueue(Player* player, EventWowGameInfo const& game)
{
    if (!game.IsPlayable())
        return "QUEUE_GAME_UNAVAILABLE";

    if (GetMatchSlot(player))
        return "QUEUE_IN_MATCH";

    if (!EventWowLobby::IsInLobby(player))
        return "QUEUE_NOT_IN_LOBBY";

    // Una sola cola a la vez: apuntarse a otro juego sustituye la anterior
    if (QueueSlot const* current = GetQueueSlot(player))
    {
        if (current->GameId == game.Id)
            return nullptr;

        Dequeue(player);
    }

    QueueSlot* slot = player->CustomData.GetDefault<QueueSlot>(QueueKey);
    slot->GameId = game.Id;
    slot->Since = GameTime::GetGameTime();
    _queues[game.Id].push_back({ player->GetGUID(), slot->Since });

    LOG_DEBUG("module.eventwow", "EventWow: {} entra en cola de '{}'", player->GetName(), game.Id);
    return nullptr;
}

void EventWowMatchMgr::Dequeue(Player* player)
{
    QueueSlot const* slot = GetQueueSlot(player);
    if (!slot)
        return;

    auto itr = _queues.find(slot->GameId);
    if (itr != _queues.end())
    {
        std::vector<QueueEntry>& queue = itr->second;
        ObjectGuid const guid = player->GetGUID();
        queue.erase(std::remove_if(queue.begin(), queue.end(),
            [guid](QueueEntry const& entry) { return entry.Guid == guid; }), queue.end());
    }

    LOG_DEBUG("module.eventwow", "EventWow: {} sale de la cola de '{}'", player->GetName(), slot->GameId);
    player->CustomData.Erase(QueueKey);
}

void EventWowMatchMgr::SendQueueStatus(Player* player) const
{
    QueueSlot const* slot = GetQueueSlot(player);
    if (!slot)
    {
        EventWowMessage("QUEUE_STATUS").Add("NONE").Send(player);
        return;
    }

    uint32 const waited = static_cast<uint32>((GameTime::GetGameTime() - slot->Since).count());
    EventWowMessage("QUEUE_STATUS").Add("QUEUED").Add(slot->GameId).Add(waited).Send(player);
}

void EventWowMatchMgr::UpdateQueues()
{
    Seconds const now = GameTime::GetGameTime();
    for (auto& [gameId, queue] : _queues)
    {

        // Entradas huerfanas (el logout ya las quita; por seguridad)
        queue.erase(std::remove_if(queue.begin(), queue.end(), [&gameId](QueueEntry const& entry)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(entry.Guid);
            QueueSlot const* slot = player ? GetQueueSlot(player) : nullptr;
            return !slot || slot->GameId != gameId;
        }), queue.end());

        EventWowGameInfo const* game = sEventWowGames.GetGame(gameId);
        if (!game || !game->IsPlayable())
            continue;

        // Con MaxPlayers: ya. Con MinPlayers: cuando el primero lleva FillWait esperando.
        while (!queue.empty() && queue.size() >= game->MinPlayers)
        {
            std::size_t const count = std::min<std::size_t>(queue.size(), game->MaxPlayers);
            if (count < game->MaxPlayers && now - queue.front().Since < sEventWowConfig.QueueFillWait)
                break;

            GuidVector players;
            players.reserve(count);
            for (std::size_t i = 0; i < count; ++i)
                players.push_back(queue[i].Guid);

            queue.erase(queue.begin(), queue.begin() + count);
            CreateMatch(*game, std::move(players));
        }
    }
}

// Partidas --------------------------------------------------------------------------------------

void EventWowMatchMgr::CreateMatch(EventWowGameInfo const& game, GuidVector players)
{
    std::unique_ptr<EventWowMatch> match = game.Factory();
    uint32 const instanceId = sMapMgr->GenerateInstanceId();
    if (!match || !sInstanceSaveMgr->AddInstanceSave(game.MapId, instanceId, REGULAR_DIFFICULTY))
    {
        LOG_ERROR("module.eventwow", "EventWow: no se pudo crear la partida de '{}' (mapa {})", game.Id, game.MapId);
        for (ObjectGuid const& guid : players)
        {
            if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            {
                player->CustomData.Erase(QueueKey);
                SendQueueStatus(player);
                EventWowMessage("ERROR").Add("MATCH_CREATE_FAILED").Send(player);
            }
        }
        return;
    }

    uint32 const matchId = _nextMatchId++;
    match->Init(matchId, &game, instanceId, players);
    EventWowMatch& ref = *match;
    _matches.emplace(matchId, std::move(match));
    {
        std::lock_guard<std::mutex> lock(_instancesLock);
        _instances.insert(instanceId);
    }

    LOG_INFO("module.eventwow", "EventWow: partida {} de '{}' (mapa {}, instancia {}) con {} jugador(es)",
        matchId, game.Id, game.MapId, instanceId, players.size());

    for (ObjectGuid const& guid : players)
    {
        Player* player = ObjectAccessor::FindConnectedPlayer(guid);
        if (!player)
        {
            ref.HandlePlayerLeft(guid);
            continue;
        }

        player->CustomData.Erase(QueueKey);
        SendQueueStatus(player);

        MatchSlot* slot = player->CustomData.GetDefault<MatchSlot>(MatchKey);
        slot->MatchId = matchId;
        slot->MapId = game.MapId;
        slot->InstanceId = instanceId;
        slot->Arrived = false;

        // La instancia es de dificultad normal; TELE_TO_GM_MODE salta PlayerCannotEnter (banda sin grupo,
        // requisitos de acceso, limite de instancias por hora). InstanceMap::CannotEnter lo decide nuestro hook.
        player->SetDungeonDifficulty(DUNGEON_DIFFICULTY_NORMAL);
        ref.SendState(player);
        if (!player->TeleportTo(game.MapId, game.Start.GetPositionX(), game.Start.GetPositionY(),
            game.Start.GetPositionZ(), game.Start.GetOrientation(), TELE_TO_GM_MODE))
        {
            LOG_ERROR("module.eventwow", "EventWow: no se pudo teleportar a {} a la partida {}", player->GetName(), matchId);
            RemovePlayer(ref, guid, false);
            EventWowMessage("ERROR").Add("MATCH_TELEPORT_FAILED").Send(player);
        }
    }
}

void EventWowMatchMgr::CloseMatch(uint32 matchId)
{
    auto itr = _matches.find(matchId);
    if (itr == _matches.end())
        return;

    EventWowMatch& match = *itr->second;
    GuidVector const players = match.GetPlayers();
    for (ObjectGuid const& guid : players)
        RemovePlayer(match, guid, true);

    uint32 const instanceId = match.GetInstanceId();
    LOG_INFO("module.eventwow", "EventWow: fin de la partida {} de '{}'", matchId, match.GetGame().Id);
    _matches.erase(itr);
    {
        std::lock_guard<std::mutex> lock(_instancesLock);
        _instances.erase(instanceId);
    }

    // Si la instancia nunca llego a cargarse, nadie mas borraria su InstanceSave
    // (si esta cargada, se borra al descargarse: Instance.UnloadDelay)
    sInstanceSaveMgr->DeleteInstanceSaveIfNeeded(instanceId, false);
}

EventWowMatch* EventWowMatchMgr::GetMatch(Player* player) const
{
    MatchSlot const* slot = GetMatchSlot(player);
    if (!slot)
        return nullptr;

    auto itr = _matches.find(slot->MatchId);
    return itr != _matches.end() ? itr->second.get() : nullptr;
}

void EventWowMatchMgr::RemovePlayer(EventWowMatch& match, ObjectGuid guid, bool teleport)
{
    Player* player = ObjectAccessor::FindConnectedPlayer(guid);
    if (player)
    {
        MatchSlot const* slot = GetMatchSlot(player);
        if (slot && slot->MatchId == match.GetId())
            player->CustomData.Erase(MatchKey);
    }

    // Bind temporal que el core crea al entrar (InstanceMap::AddPlayerToMap)
    if (sInstanceSaveMgr->PlayerGetBoundInstance(guid, match.GetMapId(), REGULAR_DIFFICULTY))
        sInstanceSaveMgr->PlayerUnbindInstance(guid, match.GetMapId(), REGULAR_DIFFICULTY, true, player);

    match.HandlePlayerLeft(guid);

    if (!player || !player->IsInWorld())
        return;

    if (teleport && player->GetInstanceId() == match.GetInstanceId())
        EventWowLobby::ReturnToLobby(player);  // MATCH_STATE NONE al llegar (OnPlayerMapChanged)
    else if (EventWowLobby::IsInLobby(player))
        SendNoMatch(player);
}

bool EventWowMatchMgr::IsMatchInstance(uint32 instanceId) const
{
    std::lock_guard<std::mutex> lock(_instancesLock);
    return _instances.count(instanceId) != 0;
}

// Eventos de jugador ----------------------------------------------------------------------------

void EventWowMatchMgr::OnPlayerMapChanged(Player* player)
{
    MatchSlot* slot = GetMatchSlot(player);
    if (!slot)
    {
        // Vuelta al lobby tras una partida (al hacer login lo manda el ConnectListener)
        if (EventWowLobby::IsInLobby(player) && EventWowProtocol::IsConnected(player->GetGUID()))
            SendNoMatch(player);
        return;
    }

    EventWowMatch* match = GetMatch(player);
    if (!match)
    {
        player->CustomData.Erase(MatchKey);
        return;
    }

    if (player->GetMapId() == slot->MapId && player->GetInstanceId() == slot->InstanceId)
    {
        if (slot->Arrived)
            return;

        slot->Arrived = true;
        EventWowLobby::SetVisibility(player, false);
        EventWowLobby::RestoreBaseState(player);
        match->HandlePlayerArrived(player);
        return;
    }

    // Ha acabado en otro mapa (p. ej. liberar espiritu en una mazmorra, teleport de GM): fuera de la partida
    LOG_DEBUG("module.eventwow", "EventWow: {} salio de la instancia de la partida {} (mapa {})",
        player->GetName(), match->GetId(), player->GetMapId());
    RemovePlayer(*match, player->GetGUID(), false);
    if (!EventWowLobby::IsInLobby(player))
        EventWowLobby::ReturnToLobby(player);
}

void EventWowMatchMgr::OnPlayerLogout(Player* player)
{
    Dequeue(player);
    if (EventWowMatch* match = GetMatch(player))
        RemovePlayer(*match, player->GetGUID(), false);
}

void EventWowMatchMgr::OnPlayerConnected(Player* player)
{
    SendQueueStatus(player);
    if (EventWowMatch* match = GetMatch(player))
    {
        match->SendState(player);
        match->SendHud(player);
    }
    else
        SendNoMatch(player);
}

bool EventWowMatchMgr::GetDestinationInstance(Player* player, uint32 mapId, uint32& instanceId) const
{
    MatchSlot const* slot = GetMatchSlot(player);
    if (!slot || slot->MapId != mapId)
        return false;

    // Sin InstanceSave el core crearia una instancia nueva (0): OnPlayerMapChanged lo devolvera al lobby
    if (!sInstanceSaveMgr->GetInstanceSave(slot->InstanceId))
    {
        LOG_ERROR("module.eventwow", "EventWow: la instancia {} de la partida {} ya no existe", slot->InstanceId, slot->MatchId);
        instanceId = 0;
        return true;
    }

    instanceId = slot->InstanceId;
    return true;
}

bool EventWowMatchMgr::CanEnterInstance(Player* player, uint32 mapId, uint32 instanceId, bool& allow) const
{
    MatchSlot const* slot = GetMatchSlot(player);
    if (slot && slot->InstanceId == instanceId)
    {
        // Sin limite de jugadores del mapa ni comprobaciones de grupo/bind
        allow = true;
        return true;
    }

    if (!IsMatchInstance(instanceId))
        return false;

    // Instancia de otra partida: solo GMs
    allow = player->GetSession()->GetSecurity() > SEC_PLAYER;
    if (!allow)
        player->SendTransferAborted(mapId, TRANSFER_ABORT_MAP_NOT_ALLOWED);

    return true;
}

// Scripts ---------------------------------------------------------------------------------------

namespace
{
    // QUEUE <id juego>
    void HandleQueue(Player* player, EventWowProtocol::Args const& args)
    {
        EventWowGameInfo const* game = args.empty() ? nullptr : sEventWowGames.GetGame(args[0]);
        if (!game)
        {
            EventWowMessage("ERROR").Add("QUEUE_UNKNOWN_GAME").Send(player);
            return;
        }

        if (char const* error = sEventWowMatchMgr.Enqueue(player, *game))
        {
            EventWowMessage("ERROR").Add(error).Send(player);
            return;
        }

        sEventWowMatchMgr.SendQueueStatus(player);
    }

    // LEAVE: salir de la cola
    void HandleLeave(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        sEventWowMatchMgr.Dequeue(player);
        sEventWowMatchMgr.SendQueueStatus(player);
    }

    // ABANDON: salir de la partida (vuelve al lobby)
    void HandleAbandon(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        EventWowMatch* match = sEventWowMatchMgr.GetMatch(player);
        if (!match)
        {
            SendNoMatch(player);
            return;
        }

        LOG_DEBUG("module.eventwow", "EventWow: {} abandona la partida {}", player->GetName(), match->GetId());
        sEventWowMatchMgr.RemovePlayer(*match, player->GetGUID(), true);
    }
}

class EventWow_MatchPlayerScript : public PlayerScript
{
public:
    EventWow_MatchPlayerScript() : PlayerScript("EventWow_MatchPlayerScript", {
        PLAYERHOOK_ON_OVERRIDE_INSTANCE_DESTINATION,
        PLAYERHOOK_ON_OVERRIDE_INSTANCE_ENTER,
        PLAYERHOOK_ON_MAP_CHANGED,
        PLAYERHOOK_ON_LOGOUT
    }) { }

    bool OnPlayerOverrideInstanceDestination(Player* player, uint32 mapId, Difficulty /*difficulty*/,
        uint32& instanceId) override
    {
        return sEventWowConfig.Enabled && sEventWowMatchMgr.GetDestinationInstance(player, mapId, instanceId);
    }

    bool OnPlayerOverrideInstanceEnter(Player* player, InstanceMap* map, bool /*loginCheck*/, bool& allow) override
    {
        return sEventWowConfig.Enabled
            && sEventWowMatchMgr.CanEnterInstance(player, map->GetId(), map->GetInstanceId(), allow);
    }

    void OnPlayerMapChanged(Player* player) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnPlayerMapChanged(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnPlayerLogout(player);
    }
};

class EventWow_MatchWorldScript : public WorldScript
{
public:
    EventWow_MatchWorldScript() : WorldScript("EventWow_MatchWorldScript", {
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnUpdate(uint32 diff) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.Update(Milliseconds(diff));
    }
};

void AddSC_eventwow_matches()
{
    EventWowProtocol::RegisterHandler("QUEUE", HandleQueue);
    EventWowProtocol::RegisterHandler("LEAVE", HandleLeave);
    EventWowProtocol::RegisterHandler("ABANDON", HandleAbandon);
    EventWowProtocol::RegisterConnectListener([](Player* player) { sEventWowMatchMgr.OnPlayerConnected(player); });

    new EventWow_MatchPlayerScript();
    new EventWow_MatchWorldScript();
}
