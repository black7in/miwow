#include "EventWowMatchMgr.h"
#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowDisguise.h"
#include "EventWowGames.h"
#include "EventWowLobby.h"
#include "EventWowMatch.h"
#include "EventWowProtocol.h"
#include "EventWowStats.h"
#include "GameTime.h"
#include "Group.h"
#include "InstanceSaveMgr.h"
#include "Log.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "StringConvert.h"
#include "WorldSession.h"
#include <algorithm>

//   Cliente -> servidor: QUEUE <id juego> | LEAVE | ABANDON | ACCEPT <id propuesta> | DECLINE <id propuesta>
//   Servidor -> cliente: QUEUE_STATUS QUEUED <id juego> <segundos en cola> <jugadores en la entrada> | QUEUE_STATUS NONE
//                        MATCH_FOUND <id> <id juego> <segundos para aceptar> <total> <aceptados> <tu: 0/1>
//                        MATCH_FOUND_STATUS <id> <aceptados> <total>
//                        MATCH_FOUND_END <id> ACCEPTED | REQUEUED | REMOVED
//                        ERROR QUEUE_GROUP_DECLINED <nombre> | QUEUE_GROUP_NOT_ACCEPTED
//                        MATCH_STATE ... / MATCH_HUD / MATCH_END (EventWowMatch.cpp) | MATCH_STATE NONE
//                        ERROR QUEUE_UNKNOWN_GAME | QUEUE_GAME_UNAVAILABLE | QUEUE_IN_MATCH | QUEUE_NOT_IN_LOBBY
//                              | QUEUE_NOT_LEADER | QUEUE_SOLO_ONLY <max> | QUEUE_GROUP_TOO_BIG <max>
//                              | QUEUE_GROUP_OFFLINE <nombre> | QUEUE_GROUP_BUSY <nombre>
//                              | QUEUE_GROUP_CANCELLED <nombre> | QUEUE_GROUP_LOGOUT <nombre> | QUEUE_GROUP_CHANGED <nombre>
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
        uint32 EntrySize = 1;   // jugadores de su entrada (el o su grupo)
        uint32 ProposalId = 0;  // != 0: partida encontrada, esperando a que todos acepten
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
        UpdateProposals();
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

bool EventWowMatchMgr::Enqueue(Player* player, EventWowGameInfo const& game)
{
    auto fail = [player](char const* code, std::string const& detail = "")
    {
        EventWowMessage message("ERROR");
        message.Add(code);
        if (!detail.empty())
            message.Add(detail);
        message.Send(player);
        return false;
    };

    if (!game.IsPlayable())
        return fail("QUEUE_GAME_UNAVAILABLE");

    // Con una partida encontrada pendiente de aceptar no se cambia de cola (se responde a la propuesta)
    if (QueueSlot const* current = GetQueueSlot(player))
        if (current->ProposalId)
            return true;

    // Quien se apunta: el jugador solo, o todo su grupo (lo apunta el lider)
    std::vector<Player*> members;
    Group* group = player->GetGroup();
    if (group && group->GetMembersCount() > 1)
    {
        if (!group->IsLeader(player->GetGUID()))
            return fail("QUEUE_NOT_LEADER");

        if (group->GetMembersCount() > game.MaxPartySize)
            return fail(game.MaxPartySize <= 1 ? "QUEUE_SOLO_ONLY" : "QUEUE_GROUP_TOO_BIG",
                std::to_string(game.MaxPartySize));

        for (Group::MemberSlot const& slot : group->GetMemberSlots())
        {
            Player* member = ObjectAccessor::FindConnectedPlayer(slot.guid);
            if (!member || !EventWowProtocol::IsConnected(slot.guid))
                return fail("QUEUE_GROUP_OFFLINE", slot.name);

            members.push_back(member);
        }
    }
    else
        members.push_back(player);

    for (Player* member : members)
    {
        bool const self = member == player;
        if (GetMatchSlot(member))
            return self ? fail("QUEUE_IN_MATCH") : fail("QUEUE_GROUP_BUSY", member->GetName());

        if (!EventWowLobby::IsInLobby(member) && !EventWowDevMode::IsActive(member))
            return self ? fail("QUEUE_NOT_IN_LOBBY") : fail("QUEUE_GROUP_BUSY", member->GetName());

        QueueSlot const* memberSlot = GetQueueSlot(member);
        if (memberSlot && memberSlot->ProposalId)
            return fail("QUEUE_GROUP_BUSY", member->GetName());
    }

    // Ya apuntados juntos a este juego: nada que hacer
    if (QueueSlot const* current = GetQueueSlot(player))
    {
        auto itr = _queues.find(current->GameId);
        if (current->GameId == game.Id && itr != _queues.end())
        {
            for (QueueEntry const& entry : itr->second)
            {
                if (std::find(entry.Players.begin(), entry.Players.end(), player->GetGUID()) == entry.Players.end())
                    continue;

                if (entry.Players.size() == members.size())
                    return true;

                break;
            }
        }
    }

    // Una sola cola a la vez: apuntarse sustituye la anterior de cada miembro
    for (Player* member : members)
        Dequeue(member);

    QueueEntry entry;
    entry.Since = GameTime::GetGameTime();
    for (Player* member : members)
    {
        QueueSlot* slot = member->CustomData.GetDefault<QueueSlot>(QueueKey);
        slot->GameId = game.Id;
        slot->Since = entry.Since;
        slot->EntrySize = static_cast<uint32>(members.size());
        slot->ProposalId = 0;
        entry.Players.push_back(member->GetGUID());
    }
    _queues[game.Id].push_back(std::move(entry));

    for (Player* member : members)
        SendQueueStatus(member);

    LOG_DEBUG("module.eventwow", "EventWow: {} entra en cola de '{}' ({} jugador(es))", player->GetName(), game.Id,
        members.size());
    return true;
}

void EventWowMatchMgr::Dequeue(Player* player, char const* reason)
{
    QueueSlot const* slot = GetQueueSlot(player);
    if (!slot)
        return;

    // Con partida encontrada: es rechazarla (su entrada fuera, el resto vuelve a la cola)
    if (slot->ProposalId)
    {
        FailProposal(slot->ProposalId, { player->GetGUID() }, reason, player->GetName());
        return;
    }

    std::string const gameId = slot->GameId;
    ObjectGuid const guid = player->GetGUID();

    // Toda la entrada del jugador (su grupo)
    GuidVector players = { guid };
    auto itr = _queues.find(gameId);
    if (itr != _queues.end())
    {
        std::vector<QueueEntry>& queue = itr->second;
        auto entry = std::find_if(queue.begin(), queue.end(), [guid](QueueEntry const& queued)
        {
            return std::find(queued.Players.begin(), queued.Players.end(), guid) != queued.Players.end();
        });

        if (entry != queue.end())
        {
            players = std::move(entry->Players);
            queue.erase(entry);
        }
    }

    LOG_DEBUG("module.eventwow", "EventWow: {} sale de la cola de '{}' ({} jugador(es))", player->GetName(), gameId,
        players.size());

    for (ObjectGuid const& memberGuid : players)
    {
        Player* member = memberGuid == guid ? player : ObjectAccessor::FindConnectedPlayer(memberGuid);
        if (!member)
            continue;

        QueueSlot const* memberSlot = GetQueueSlot(member);
        if (!memberSlot || memberSlot->GameId != gameId)
            continue;

        member->CustomData.Erase(QueueKey);
        SendQueueStatus(member);
        if (reason && member != player)
            EventWowMessage("ERROR").Add(reason).Add(player->GetName()).Send(member);
    }
}

void EventWowMatchMgr::OnGroupChanged(Group* group, ObjectGuid guid)
{
    if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
        Dequeue(player, "QUEUE_GROUP_CHANGED");

    if (!group)
        return;

    for (Group::MemberSlot const& slot : group->GetMemberSlots())
        if (Player* member = ObjectAccessor::FindConnectedPlayer(slot.guid))
            Dequeue(member, "QUEUE_GROUP_CHANGED");
}

bool EventWowMatchMgr::IsInMatch(Player const* player) const
{
    return GetMatchSlot(player) != nullptr;
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
    EventWowMessage("QUEUE_STATUS").Add("QUEUED").Add(slot->GameId).Add(waited).Add(slot->EntrySize).Send(player);
}

// Partida encontrada: confirmacion -----------------------------------------------------------------

std::size_t EventWowMatchMgr::Proposal::GetPlayerCount() const
{
    std::size_t count = 0;
    for (QueueEntry const& entry : Entries)
        count += entry.Players.size();
    return count;
}

bool EventWowMatchMgr::Proposal::Contains(ObjectGuid guid) const
{
    for (QueueEntry const& entry : Entries)
        if (std::find(entry.Players.begin(), entry.Players.end(), guid) != entry.Players.end())
            return true;
    return false;
}

EventWowMatchMgr::Proposal* EventWowMatchMgr::GetProposal(Player const* player)
{
    QueueSlot const* slot = GetQueueSlot(player);
    if (!slot || !slot->ProposalId)
        return nullptr;

    auto itr = _proposals.find(slot->ProposalId);
    return itr != _proposals.end() ? &itr->second : nullptr;
}

void EventWowMatchMgr::StartProposal(EventWowGameInfo const& game, std::vector<QueueEntry> entries)
{
    uint32 const id = _nextProposalId++;
    Proposal& proposal = _proposals[id];
    proposal.Id = id;
    proposal.GameId = game.Id;
    proposal.Entries = std::move(entries);
    proposal.Deadline = GameTime::GetGameTime() + sEventWowConfig.QueueAcceptTimeout;

    LOG_DEBUG("module.eventwow", "EventWow: partida encontrada {} de '{}' con {} jugador(es), esperando confirmacion",
        id, game.Id, proposal.GetPlayerCount());

    for (QueueEntry const& entry : proposal.Entries)
    {
        for (ObjectGuid const& guid : entry.Players)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(guid);
            QueueSlot* slot = player ? GetQueueSlot(player) : nullptr;
            if (!slot)
                continue;

            slot->ProposalId = id;
            SendProposal(player, proposal);
        }
    }
}

void EventWowMatchMgr::SendProposal(Player* player, Proposal const& proposal) const
{
    Seconds const now = GameTime::GetGameTime();
    uint32 const left = proposal.Deadline > now ? static_cast<uint32>((proposal.Deadline - now).count()) : 0;
    EventWowMessage("MATCH_FOUND").Add(proposal.Id).Add(proposal.GameId).Add(left)
        .Add(static_cast<uint32>(proposal.GetPlayerCount())).Add(static_cast<uint32>(proposal.Accepted.size()))
        .Add(proposal.Accepted.count(player->GetGUID()) ? 1 : 0).Send(player);
}

void EventWowMatchMgr::AcceptProposal(Player* player, uint32 proposalId)
{
    Proposal* proposal = GetProposal(player);
    if (!proposal || proposal->Id != proposalId)
        return;

    if (!proposal->Accepted.insert(player->GetGUID()).second)
        return;

    uint32 const total = static_cast<uint32>(proposal->GetPlayerCount());
    uint32 const accepted = static_cast<uint32>(proposal->Accepted.size());
    for (QueueEntry const& entry : proposal->Entries)
        for (ObjectGuid const& guid : entry.Players)
            if (Player* member = ObjectAccessor::FindConnectedPlayer(guid))
                EventWowMessage("MATCH_FOUND_STATUS").Add(proposalId).Add(accepted).Add(total).Send(member);

    if (accepted < total)
        return;

    // Todos dentro: a la partida
    GuidVector players;
    for (QueueEntry const& entry : proposal->Entries)
        players.insert(players.end(), entry.Players.begin(), entry.Players.end());

    std::string const gameId = proposal->GameId;
    _proposals.erase(proposalId);

    for (ObjectGuid const& guid : players)
        if (Player* member = ObjectAccessor::FindConnectedPlayer(guid))
            EventWowMessage("MATCH_FOUND_END").Add(proposalId).Add("ACCEPTED").Send(member);

    EventWowGameInfo const* game = sEventWowGames.GetGame(gameId);
    if (!game || !game->IsPlayable())
    {
        for (ObjectGuid const& guid : players)
        {
            if (Player* member = ObjectAccessor::FindConnectedPlayer(guid))
            {
                member->CustomData.Erase(QueueKey);
                SendQueueStatus(member);
                EventWowMessage("ERROR").Add("MATCH_CREATE_FAILED").Send(member);
            }
        }
        return;
    }

    CreateMatch(*game, std::move(players));
}

void EventWowMatchMgr::DeclineProposal(Player* player, uint32 proposalId)
{
    Proposal const* proposal = GetProposal(player);
    if (!proposal || proposal->Id != proposalId)
        return;

    FailProposal(proposalId, { player->GetGUID() }, "QUEUE_GROUP_DECLINED", player->GetName());
}

void EventWowMatchMgr::FailProposal(uint32 proposalId, GuidSet const& failed, char const* reason,
    std::string const& culprit)
{
    auto itr = _proposals.find(proposalId);
    if (itr == _proposals.end())
        return;

    Proposal proposal = std::move(itr->second);
    _proposals.erase(itr);

    LOG_DEBUG("module.eventwow", "EventWow: partida encontrada {} de '{}' cancelada ({} sin aceptar)",
        proposalId, proposal.GameId, failed.size());

    std::vector<QueueEntry>& queue = _queues[proposal.GameId];
    for (QueueEntry& entry : proposal.Entries)
    {
        // Fuera la entrada entera si alguno fallo (o ya no esta)
        bool out = false;
        for (ObjectGuid const& guid : entry.Players)
        {
            Player* member = ObjectAccessor::FindConnectedPlayer(guid);
            QueueSlot const* slot = member ? GetQueueSlot(member) : nullptr;
            if (failed.count(guid) || !slot || slot->ProposalId != proposalId)
            {
                out = true;
                break;
            }
        }

        for (ObjectGuid const& guid : entry.Players)
        {
            Player* member = ObjectAccessor::FindConnectedPlayer(guid);
            QueueSlot* slot = member ? GetQueueSlot(member) : nullptr;
            if (!slot || slot->ProposalId != proposalId)
                continue;

            if (out)
            {
                member->CustomData.Erase(QueueKey);
                EventWowMessage("MATCH_FOUND_END").Add(proposalId).Add("REMOVED").Send(member);
                SendQueueStatus(member);
                if (reason && !failed.count(guid))
                {
                    EventWowMessage message("ERROR");
                    message.Add(reason);
                    if (!culprit.empty())
                        message.Add(culprit);
                    message.Send(member);
                }
            }
            else
            {
                slot->ProposalId = 0;
                EventWowMessage("MATCH_FOUND_END").Add(proposalId).Add("REQUEUED").Send(member);
                SendQueueStatus(member);
            }
        }

        if (!out)
            queue.push_back(std::move(entry));
    }

    // Los que vuelven conservan su antiguedad
    std::stable_sort(queue.begin(), queue.end(), [](QueueEntry const& a, QueueEntry const& b)
    {
        return a.Since < b.Since;
    });
}

void EventWowMatchMgr::UpdateProposals()
{
    Seconds const now = GameTime::GetGameTime();
    std::vector<std::pair<uint32, GuidSet>> expired;
    for (auto const& [id, proposal] : _proposals)
    {
        if (now < proposal.Deadline)
            continue;

        GuidSet notAccepted;
        for (QueueEntry const& entry : proposal.Entries)
            for (ObjectGuid const& guid : entry.Players)
                if (!proposal.Accepted.count(guid))
                    notAccepted.insert(guid);

        expired.emplace_back(id, std::move(notAccepted));
    }

    for (auto const& [id, notAccepted] : expired)
        FailProposal(id, notAccepted, "QUEUE_GROUP_NOT_ACCEPTED", "");
}

void EventWowMatchMgr::UpdateQueues()
{
    Seconds const now = GameTime::GetGameTime();
    for (auto& [gameId, queue] : _queues)
    {
        // Entradas huerfanas (logout y cambios de grupo ya las quitan; por seguridad): si falta alguien, fuera
        // la entrada entera
        for (std::size_t i = 0; i < queue.size();)
        {
            bool valid = true;
            for (ObjectGuid const& guid : queue[i].Players)
            {
                Player* player = ObjectAccessor::FindConnectedPlayer(guid);
                QueueSlot const* slot = player ? GetQueueSlot(player) : nullptr;
                if (!slot || slot->GameId != gameId || slot->ProposalId)
                {
                    valid = false;
                    break;
                }
            }

            if (valid)
            {
                ++i;
                continue;
            }

            GuidVector const players = std::move(queue[i].Players);
            queue.erase(queue.begin() + i);
            for (ObjectGuid const& guid : players)
            {
                Player* player = ObjectAccessor::FindConnectedPlayer(guid);
                QueueSlot const* slot = player ? GetQueueSlot(player) : nullptr;
                if (slot && slot->GameId == gameId && !slot->ProposalId)
                {
                    player->CustomData.Erase(QueueKey);
                    SendQueueStatus(player);
                }
            }
        }

        EventWowGameInfo const* game = sEventWowGames.GetGame(gameId);
        if (!game || !game->IsPlayable())
            continue;

        // Por orden de llegada, entradas enteras que quepan. Con MaxPlayers: ya. Con MinPlayers: cuando la
        // primera (siempre entra) lleva FillWait esperando.
        while (!queue.empty())
        {
            std::vector<std::size_t> picked;
            std::size_t count = 0;
            for (std::size_t i = 0; i < queue.size() && count < game->MaxPlayers; ++i)
            {
                if (count + queue[i].Players.size() > game->MaxPlayers)
                    continue;

                picked.push_back(i);
                count += queue[i].Players.size();
            }

            if (count < game->MinPlayers)
                break;

            if (count < game->MaxPlayers && now - queue.front().Since < sEventWowConfig.QueueFillWait)
                break;

            // Antes de crear la partida, todos deben aceptar (StartProposal)
            std::vector<QueueEntry> entries;
            entries.reserve(picked.size());
            for (std::size_t i : picked)
                entries.push_back(std::move(queue[i]));

            for (auto itr = picked.rbegin(); itr != picked.rend(); ++itr)
                queue.erase(queue.begin() + *itr);

            StartProposal(*game, std::move(entries));
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

    // Binds que quedasen: el core tambien liga al lider del grupo de quien entra aunque no este en la partida
    // (InstanceMap::AddPlayerToMap), y eso impediria borrar el InstanceSave
    if (InstanceSave* save = sInstanceSaveMgr->GetInstanceSave(instanceId))
        sInstanceSaveMgr->UnbindAllFor(save);

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

        // Tambien en modo dev y en el logout: disfraz y bonificaciones son de la partida
        EventWowDisguise::Remove(player);
        EventWowStats::Reset(player);
    }

    // Bind temporal que el core crea al entrar (InstanceMap::AddPlayerToMap)
    if (sInstanceSaveMgr->PlayerGetBoundInstance(guid, match.GetMapId(), REGULAR_DIFFICULTY))
        sInstanceSaveMgr->PlayerUnbindInstance(guid, match.GetMapId(), REGULAR_DIFFICULTY, true, player);

    match.HandlePlayerLeft(guid);

    if (!player || !player->IsInWorld())
        return;

    if (teleport && player->GetInstanceId() == match.GetInstanceId() && !EventWowDevMode::IsActive(player))
        EventWowLobby::ReturnToLobby(player);  // MATCH_STATE NONE al llegar (OnPlayerMapChanged)
    else
        SendNoMatch(player);  // se queda donde esta (modo dev, o aun no habia llegado)
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
        if (!EventWowDevMode::IsActive(player))
            EventWowLobby::RestoreBaseState(player);
        match->HandlePlayerArrived(player);
        return;
    }

    // Ha acabado en otro mapa (p. ej. liberar espiritu en una mazmorra, teleport de GM): fuera de la partida
    LOG_DEBUG("module.eventwow", "EventWow: {} salio de la instancia de la partida {} (mapa {})",
        player->GetName(), match->GetId(), player->GetMapId());
    // Al lobby siempre (resucitado): el cementerio de una mazmorra puede estar en el mismo mapa que el lobby
    RemovePlayer(*match, player->GetGUID(), false);
    if (EventWowDevMode::IsActive(player))
        return;

    if (EventWowLobby::IsInLobby(player))
    {
        EventWowLobby::RestoreBaseState(player);
        EventWowLobby::SetVisibility(player, true);
    }
    else
        EventWowLobby::ReturnToLobby(player);
}

void EventWowMatchMgr::OnPlayerDied(Player* player)
{
    MatchSlot const* slot = GetMatchSlot(player);
    if (!slot || !slot->Arrived || EventWowDevMode::IsActive(player))
        return;

    if (EventWowMatch* match = GetMatch(player))
        match->HandlePlayerDied(player);
}

bool EventWowMatchMgr::CanRepopAtGraveyard(Player* player)
{
    MatchSlot const* slot = GetMatchSlot(player);
    if (!slot || !slot->Arrived || EventWowDevMode::IsActive(player))
        return true;

    // Nunca al cementerio (estaria fuera de la instancia). Vivo = ha caido fuera del mapa: al punto de reaparicion.
    // Muerto = ha liberado el espiritu: se queda como fantasma ahi hasta que el juego lo resucite.
    if (player->IsAlive())
        if (EventWowMatch* match = GetMatch(player))
            match->TeleportToRespawn(player);

    return false;
}

void EventWowMatchMgr::OnPlayerLogout(Player* player)
{
    Dequeue(player, "QUEUE_GROUP_LOGOUT");
    if (EventWowMatch* match = GetMatch(player))
        RemovePlayer(*match, player->GetGUID(), false);
}

void EventWowMatchMgr::OnPlayerConnected(Player* player)
{
    SendQueueStatus(player);
    if (Proposal const* proposal = GetProposal(player))
        SendProposal(player, *proposal);

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

        sEventWowMatchMgr.Enqueue(player, *game);
    }

    // LEAVE: salir de la cola (con todo el grupo con el que se apunto)
    void HandleLeave(Player* player, EventWowProtocol::Args const& /*args*/)
    {
        sEventWowMatchMgr.Dequeue(player, "QUEUE_GROUP_CANCELLED");
        sEventWowMatchMgr.SendQueueStatus(player);
    }

    // ACCEPT <id> / DECLINE <id>: respuesta a una partida encontrada
    uint32 GetProposalArg(EventWowProtocol::Args const& args)
    {
        Optional<uint32> id = args.empty() ? std::nullopt : Acore::StringTo<uint32>(args[0]);
        return id.value_or(0);
    }

    void HandleAccept(Player* player, EventWowProtocol::Args const& args)
    {
        sEventWowMatchMgr.AcceptProposal(player, GetProposalArg(args));
    }

    void HandleDecline(Player* player, EventWowProtocol::Args const& args)
    {
        sEventWowMatchMgr.DeclineProposal(player, GetProposalArg(args));
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
        PLAYERHOOK_ON_PLAYER_JUST_DIED,
        PLAYERHOOK_CAN_REPOP_AT_GRAVEYARD,
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

    void OnPlayerJustDied(Player* player) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnPlayerDied(player);
    }

    bool OnPlayerCanRepopAtGraveyard(Player* player) override
    {
        return !sEventWowConfig.Enabled || sEventWowMatchMgr.CanRepopAtGraveyard(player);
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
    EventWowProtocol::RegisterHandler("ACCEPT", HandleAccept);
    EventWowProtocol::RegisterHandler("DECLINE", HandleDecline);
    EventWowProtocol::RegisterConnectListener([](Player* player) { sEventWowMatchMgr.OnPlayerConnected(player); });

    new EventWow_MatchPlayerScript();
    new EventWow_MatchWorldScript();
}
