#include "EventWowMatch.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDisguise.h"
#include "EventWowGames.h"
#include "EventWowMatchMgr.h"
#include "EventWowProtocol.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include <algorithm>

namespace
{
    char const* GetResultName(EventWowMatchResult result)
    {
        switch (result)
        {
            case EventWowMatchResult::Win:
                return "WIN";
            case EventWowMatchResult::Lose:
                return "LOSE";
            default:
                return "NONE";
        }
    }

    // Segundos enteros hacia arriba (lo que muestra el HUD)
    uint32 CeilSeconds(Milliseconds time)
    {
        return static_cast<uint32>((time.count() + 999) / 1000);
    }
}

uint32 EventWowMatch::GetMapId() const
{
    return _game->MapId;
}

bool EventWowMatch::HasPlayer(ObjectGuid guid) const
{
    return std::find(_players.begin(), _players.end(), guid) != _players.end();
}

void EventWowMatch::Init(uint32 id, EventWowGameInfo const* game, uint32 instanceId, GuidVector players)
{
    _id = id;
    _game = game;
    _instanceId = instanceId;
    _players = std::move(players);
    _state = EventWowMatchState::Loading;
    _stateTimer = sEventWowConfig.MatchLoadTimeout;
    _timerActive = true;
}

bool EventWowMatch::TickTimer(Milliseconds diff)
{
    if (!_timerActive)
        return false;

    if (diff >= _stateTimer)
    {
        _stateTimer = 0ms;
        _timerActive = false;
        return true;
    }

    _stateTimer -= diff;
    return false;
}

void EventWowMatch::Update(Milliseconds diff)
{
    if (_players.empty())
        return;

    bool const expired = TickTimer(diff);
    UpdateRespawns(diff);

    _disguiseTimer += diff;
    if (_disguiseTimer >= 1s)
    {
        _disguiseTimer = 0ms;
        ForEachPlayer([this](Player* player)
        {
            if (player->GetInstanceId() == _instanceId)
                EventWowDisguise::Update(player);
        });
    }
    switch (_state)
    {
        case EventWowMatchState::Loading:
        {
            if (_arrived.size() < _players.size())
            {
                if (!expired)
                    break;

                // Los que no han llegado quedan fuera; la partida sigue con el resto
                GuidVector missing;
                for (ObjectGuid const& guid : _players)
                    if (!_arrived.count(guid))
                        missing.push_back(guid);

                for (ObjectGuid const& guid : missing)
                    sEventWowMatchMgr.RemovePlayer(*this, guid, false);

                if (_players.empty())
                    break;
            }

            SetState(EventWowMatchState::Countdown, GetCountdown());
            break;
        }
        case EventWowMatchState::Countdown:
            if (expired || !_timerActive)
            {
                SetState(EventWowMatchState::Running, 0ms);
                OnStart();
            }
            break;
        case EventWowMatchState::Running:
            if (expired)
            {
                OnTimerExpired();
                if (_state != EventWowMatchState::Running)
                    break;
            }
            OnUpdate(diff);
            break;
        case EventWowMatchState::Ended:
            break;
    }
}

void EventWowMatch::HandlePlayerArrived(Player* player)
{
    if (_state == EventWowMatchState::Loading)
        _arrived.insert(player->GetGUID());

    SendState(player);
    SendHud(player);
    if (uint32 const characterId = GetAssignedCharacter(player))
        SetCharacter(player, characterId);

    OnPlayerArrived(player);
}

// Personajes -------------------------------------------------------------------------------------

uint32 EventWowMatch::GetAssignedCharacter(Player* /*player*/) const
{
    std::vector<uint32> const& characters = sEventWowCharacters.GetForGame(_game->Id);
    return characters.empty() ? 0 : characters.front();
}

bool EventWowMatch::SetCharacter(Player* player, uint32 characterId)
{
    EventWowCharacterInfo const* character = sEventWowCharacters.Get(characterId);
    if (!character || !HasPlayer(player->GetGUID()) || player->GetInstanceId() != _instanceId)
        return false;

    EventWowDisguise::Apply(player, *character);
    return true;
}

void EventWowMatch::HandlePlayerLeft(ObjectGuid guid)
{
    auto itr = std::find(_players.begin(), _players.end(), guid);
    if (itr == _players.end())
        return;

    _players.erase(itr);
    _arrived.erase(guid);
    _results.erase(guid);
    _respawns.erase(guid);
    OnPlayerLeft(guid);
}

bool EventWowMatch::IsReadyToClose() const
{
    return _players.empty() || (_state == EventWowMatchState::Ended && !_timerActive);
}

// MATCH_STATE <LOADING|WAITING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
//   LOADING: en camino (sigue en el lobby / pantalla de carga); WAITING: dentro, esperando al resto.
//   segundos: lo que queda del estado (cuenta atras, temporizador de juego, vuelta al lobby); 0 = sin tiempo
void EventWowMatch::SendState(Player* player) const
{
    char const* state = "LOADING";
    switch (_state)
    {
        case EventWowMatchState::Loading:
            state = _arrived.count(player->GetGUID()) ? "WAITING" : "LOADING";
            break;
        case EventWowMatchState::Countdown:
            state = "COUNTDOWN";
            break;
        case EventWowMatchState::Running:
            state = "RUNNING";
            break;
        case EventWowMatchState::Ended:
            state = "ENDED";
            break;
    }

    uint32 const seconds = _timerActive ? CeilSeconds(_stateTimer) : 0;
    EventWowMessage("MATCH_STATE").Add(state).Add(_game->Id).Add(seconds).Send(player);
}

// MATCH_HUD <texto>
void EventWowMatch::SendHud(Player* player) const
{
    if (!_hud.empty())
        EventWowMessage("MATCH_HUD").Add(_hud).Send(player);
}

void EventWowMatch::End(std::string_view summary)
{
    if (_state != EventWowMatchState::Running)
        return;

    // MATCH_END <WIN|LOSE|NONE> <texto>
    ForEachPlayer([this, summary](Player* player)
    {
        auto itr = _results.find(player->GetGUID());
        EventWowMatchResult const result = itr != _results.end() ? itr->second : EventWowMatchResult::None;
        EventWowMessage("MATCH_END").Add(GetResultName(result)).Add(summary).Send(player);
    });

    SetState(EventWowMatchState::Ended, sEventWowConfig.MatchReturnDelay);
}

// Muerte ----------------------------------------------------------------------------------------

void EventWowMatch::HandlePlayerDied(Player* player)
{
    // Al terminar todos vuelven al lobby (y resucitan alli)
    if (_state == EventWowMatchState::Ended)
        return;

    OnPlayerDied(player);
}

Position const& EventWowMatch::GetRespawnPosition(Player* /*player*/) const
{
    return _game->Start;
}

void EventWowMatch::RespawnPlayer(Player* player, Seconds delay)
{
    if (delay <= 0s)
    {
        _respawns.erase(player->GetGUID());
        DoRespawn(player);
        return;
    }

    _respawns[player->GetGUID()] = delay;
    // MATCH_RESPAWN <segundos>: cuenta atras en el HUD (0 = ya ha reaparecido)
    EventWowMessage("MATCH_RESPAWN").Add(static_cast<uint32>(delay.count())).Send(player);
}

void EventWowMatch::UpdateRespawns(Milliseconds diff)
{
    if (_respawns.empty() || _state == EventWowMatchState::Ended)
        return;

    GuidVector due;
    for (auto& [guid, remaining] : _respawns)
    {
        if (remaining > diff)
            remaining -= diff;
        else
            due.push_back(guid);
    }

    for (ObjectGuid const& guid : due)
    {
        _respawns.erase(guid);
        if (Player* player = ObjectAccessor::FindPlayer(guid))
            DoRespawn(player);
    }
}

void EventWowMatch::DoRespawn(Player* player)
{
    if (player->GetInstanceId() != _instanceId)
        return;

    if (!player->IsAlive())
    {
        player->ResurrectPlayer(1.0f);
        player->SpawnCorpseBones();
    }

    player->CombatStop(true);
    player->SetFullHealth();
    TeleportToRespawn(player);
    EventWowMessage("MATCH_RESPAWN").Add(0).Send(player);
}

void EventWowMatch::TeleportToRespawn(Player* player)
{
    Position const& pos = GetRespawnPosition(player);
    player->NearTeleportTo(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ(), pos.GetOrientation());
}

void EventWowMatch::SetResult(ObjectGuid guid, EventWowMatchResult result)
{
    if (HasPlayer(guid))
        _results[guid] = result;
}

void EventWowMatch::SetResultForAll(EventWowMatchResult result)
{
    for (ObjectGuid const& guid : _players)
        _results[guid] = result;
}

void EventWowMatch::SetTimer(Seconds duration)
{
    if (_state != EventWowMatchState::Running)
        return;

    _stateTimer = duration;
    _timerActive = duration > 0s;
    BroadcastState();
}

void EventWowMatch::SetHud(std::string_view text)
{
    _hud = text;
    ForEachPlayer([this](Player* player)
    {
        if (_hud.empty())
            EventWowMessage("MATCH_HUD").Add("").Send(player);
        else
            SendHud(player);
    });
}

InstanceMap* EventWowMatch::GetMap() const
{
    Map* map = sMapMgr->FindMap(GetMapId(), _instanceId);
    return map ? map->ToInstanceMap() : nullptr;
}

void EventWowMatch::ForEachPlayer(std::function<void(Player* player)> const& func) const
{
    // Copia: func puede sacar jugadores de la partida
    GuidVector const players = _players;
    for (ObjectGuid const& guid : players)
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            func(player);
}

void EventWowMatch::SetState(EventWowMatchState state, Milliseconds duration)
{
    _state = state;
    _stateTimer = duration;
    _timerActive = duration > 0ms;
    BroadcastState();
}

void EventWowMatch::BroadcastState() const
{
    ForEachPlayer([this](Player* player) { SendState(player); });
}
