#include "MiWowMatch.h"
#include "MiWowConfig.h"
#include "MiWowGames.h"
#include "MiWowLobby.h"
#include "MiWowMatchMgr.h"
#include "MiWowProtocol.h"
#include "MiWowSpellLock.h"
#include "MiWowVehicle.h"
#include "Log.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "GameTime.h"
#include "Player.h"
#include <algorithm>

namespace
{
    char const* GetResultName(MiWowMatchResult result)
    {
        switch (result)
        {
            case MiWowMatchResult::Win:
                return "WIN";
            case MiWowMatchResult::Lose:
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

uint32 MiWowMatch::GetMapId() const
{
    return _game->MapId;
}

bool MiWowMatch::HasPlayer(ObjectGuid guid) const
{
    return std::find(_players.begin(), _players.end(), guid) != _players.end();
}

void MiWowMatch::Init(uint32 id, MiWowGameInfo const* game, uint32 instanceId, GuidVector players)
{
    _id = id;
    _game = game;
    _instanceId = instanceId;
    _players = std::move(players);
    _state = MiWowMatchState::Loading;
    _stateTimer = sMiWowConfig.MatchLoadTimeout;
    _timerActive = true;

    // Sesion abierta: ya en marcha; cada uno tiene su propio plazo para llegar
    if (game->OpenSession)
    {
        _state = MiWowMatchState::Running;
        _stateTimer = 0ms;
        _timerActive = false;
        for (ObjectGuid const& guid : _players)
            _joining[guid] = sMiWowConfig.MatchLoadTimeout;
    }
}

void MiWowMatch::AddPlayer(ObjectGuid guid)
{
    if (HasPlayer(guid))
        return;

    _players.push_back(guid);
    _joining[guid] = sMiWowConfig.MatchLoadTimeout;
}

std::size_t MiWowMatch::GetFreeSlots() const
{
    return _players.size() < _game->MaxPlayers ? _game->MaxPlayers - _players.size() : 0;
}

bool MiWowMatch::TickTimer(Milliseconds diff)
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

void MiWowMatch::Update(Milliseconds diff)
{
    if (_players.empty())
        return;

    bool const expired = TickTimer(diff);
    UpdateRespawns(diff);

    // Sesion abierta: quien no llega a tiempo queda fuera
    if (!_joining.empty())
    {
        GuidVector late;
        for (auto& [guid, remaining] : _joining)
        {
            if (remaining > diff)
                remaining -= diff;
            else
                late.push_back(guid);
        }

        for (ObjectGuid const& guid : late)
        {
            _joining.erase(guid);
            sMiWowMatchMgr.RemovePlayer(*this, guid, false);
        }

        if (_players.empty())
            return;
    }

    _vehicleTimer += diff;
    if (_vehicleTimer >= 1s)
    {
        _vehicleTimer = 0ms;
        ForEachPlayer([this](Player* player)
        {
            if (player->GetInstanceId() == _instanceId)
                MiWowVehicle::Update(player);
        });
    }

    switch (_state)
    {
        case MiWowMatchState::Loading:
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
                    sMiWowMatchMgr.RemovePlayer(*this, guid, false);

                if (_players.empty())
                    break;
            }

            SetState(MiWowMatchState::Countdown, GetCountdown());
            break;
        }
        case MiWowMatchState::Countdown:
            if (expired || !_timerActive)
            {
                SetState(MiWowMatchState::Running, 0ms);
                OnStart();
            }
            break;
        case MiWowMatchState::Running:
            if (expired)
            {
                OnTimerExpired();
                if (_state != MiWowMatchState::Running)
                    break;
            }
            OnUpdate(diff);
            break;
        case MiWowMatchState::Ended:
            break;
    }

    if (!_players.empty())
        OnTick(diff);
}

Seconds MiWowMatch::GetEndDelay() const
{
    return sMiWowConfig.MatchReturnDelay;
}

void MiWowMatch::HandlePlayerArrived(Player* player)
{
    _arrived.insert(player->GetGUID());
    _joining.erase(player->GetGUID());

    SendState(player);
    SendHud(player);
    SendChoice(player);
    if (uint32 const vehicleEntry = GetVehicleEntry())
        MiWowVehicle::Assign(player, vehicleEntry);
    if (BlocksPlayerSpells())
        MiWowSpellLock::Set(player);

    OnPlayerArrived(player);
}

void MiWowMatch::HandlePlayerLeft(ObjectGuid guid)
{
    auto itr = std::find(_players.begin(), _players.end(), guid);
    if (itr == _players.end())
        return;

    _players.erase(itr);
    _arrived.erase(guid);
    _joining.erase(guid);
    _openShops.erase(guid);
    _results.erase(guid);
    _respawns.erase(guid);
    OnPlayerLeft(guid);
}

bool MiWowMatch::IsReadyToClose() const
{
    return _players.empty() || (_state == MiWowMatchState::Ended && !_timerActive);
}

// MATCH_STATE <LOADING|WAITING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
//   LOADING: en camino (pantalla de carga); WAITING: dentro, esperando al resto.
//   segundos: lo que queda del estado (cuenta atras, temporizador de juego, vuelta a donde estaba); 0 = sin tiempo
void MiWowMatch::SendState(Player* player) const
{
    char const* state = "LOADING";
    switch (_state)
    {
        case MiWowMatchState::Loading:
            state = _arrived.count(player->GetGUID()) ? "WAITING" : "LOADING";
            break;
        case MiWowMatchState::Running:
            // Sesion abierta: quien aun no ha llegado esta cargando aunque la partida ya este en marcha
            state = _joining.count(player->GetGUID()) ? "LOADING" : "RUNNING";
            break;
        case MiWowMatchState::Countdown:
            state = "COUNTDOWN";
            break;
        case MiWowMatchState::Ended:
            state = "ENDED";
            break;
    }

    uint32 const seconds = _timerActive ? CeilSeconds(_stateTimer) : 0;
    MiWowMessage("MATCH_STATE").Add(state).Add(_game->Id).Add(seconds).Send(player);
}

// MATCH_HUD <linea> [<linea>...] (una linea por campo; en _hud separadas por '\n')
void MiWowMatch::SendHud(Player* player) const
{
    if (_hud.empty())
        return;

    MiWowMessage message("MATCH_HUD");
    std::string_view rest = _hud;
    while (true)
    {
        std::size_t const end = rest.find('\n');
        message.Add(rest.substr(0, end));
        if (end == std::string_view::npos)
            break;
        rest.remove_prefix(end + 1);
    }
    message.Send(player);
}

void MiWowMatch::End(std::string_view summary)
{
    if (_state != MiWowMatchState::Running)
        return;

    // MATCH_END <WIN|LOSE|NONE> <texto>
    ForEachPlayer([this, summary](Player* player)
    {
        auto itr = _results.find(player->GetGUID());
        MiWowMatchResult const result = itr != _results.end() ? itr->second : MiWowMatchResult::None;
        MiWowMessage("MATCH_END").Add(GetResultName(result)).Add(summary).Send(player);
    });

    SetState(MiWowMatchState::Ended, GetEndDelay());
}

// Muerte ----------------------------------------------------------------------------------------

void MiWowMatch::HandlePlayerDied(Player* player)
{
    // Al terminar todos vuelven a donde estaban (resucitados)
    if (_state == MiWowMatchState::Ended)
        return;

    OnPlayerDied(player);
}

Position const& MiWowMatch::GetRespawnPosition(Player* /*player*/) const
{
    return _game->Start;
}

Position MiWowMatch::GetArrivalPosition(Player* /*player*/)
{
    return _game->Start;
}

void MiWowMatch::RespawnPlayer(Player* player, Seconds delay)
{
    if (delay <= 0s)
    {
        _respawns.erase(player->GetGUID());
        DoRespawn(player);
        return;
    }

    _respawns[player->GetGUID()] = delay;
    // MATCH_RESPAWN <segundos>: cuenta atras en el HUD (0 = ya ha reaparecido)
    MiWowMessage("MATCH_RESPAWN").Add(static_cast<uint32>(delay.count())).Send(player);
}

void MiWowMatch::UpdateRespawns(Milliseconds diff)
{
    if (_respawns.empty() || _state == MiWowMatchState::Ended)
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

void MiWowMatch::DoRespawn(Player* player)
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
    MiWowLobby::RestoreDurability(player);
    TeleportToRespawn(player);
    MiWowMessage("MATCH_RESPAWN").Add(0).Send(player);
}

void MiWowMatch::TeleportToRespawn(Player* player)
{
    Position const& pos = GetRespawnPosition(player);
    player->NearTeleportTo(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ(), pos.GetOrientation());
}

void MiWowMatch::SetResult(ObjectGuid guid, MiWowMatchResult result)
{
    if (HasPlayer(guid))
        _results[guid] = result;
}

void MiWowMatch::SetResultForAll(MiWowMatchResult result)
{
    for (ObjectGuid const& guid : _players)
        _results[guid] = result;
}

void MiWowMatch::SetTimer(Seconds duration)
{
    if (_state != MiWowMatchState::Running)
        return;

    _stateTimer = duration;
    _timerActive = duration > 0s;
    BroadcastState();
}

void MiWowMatch::SetHud(std::string_view text)
{
    _hud = text;
    ForEachPlayer([this](Player* player)
    {
        if (_hud.empty())
            MiWowMessage("MATCH_HUD").Add("").Send(player);
        else
            SendHud(player);
    });
}

// MATCH_CHOICE <id> <titulo> <texto> <segundos> (<nombre> <detalle>)...
void MiWowMatch::SendChoice(Player* player) const
{
    if (_choiceId.empty())
        return;

    uint32 seconds = 0;
    if (_choiceEnd > 0ms)
    {
        Milliseconds const now = GameTime::GetGameTimeMS();
        seconds = _choiceEnd > now ? static_cast<uint32>((_choiceEnd - now).count() + 999) / 1000 : 0;
    }

    MiWowMessage message("MATCH_CHOICE");
    message.Add(_choiceId).Add(_choiceTitle).Add(_choiceText).Add(seconds);
    for (MiWowMatchChoiceOption const& option : _choiceOptions)
        message.Add(option.Name).Add(option.Info);
    message.Send(player);
}

void MiWowMatch::ShowChoice(std::string id, std::string title, std::string text,
    std::vector<MiWowMatchChoiceOption> options, Seconds timeout)
{
    _choiceId = std::move(id);
    _choiceTitle = std::move(title);
    _choiceText = std::move(text);
    _choiceOptions = std::move(options);
    _choiceEnd = timeout > 0s ? GameTime::GetGameTimeMS() + Milliseconds(timeout) : 0ms;
    ForEachPlayer([this](Player* player) { SendChoice(player); });
}

void MiWowMatch::ClearChoice()
{
    if (_choiceId.empty())
        return;

    _choiceId.clear();
    _choiceOptions.clear();
    ForEachPlayer([](Player* player) { MiWowMessage("MATCH_CHOICE_END").Send(player); });
}

void MiWowMatch::HandleChoice(Player* player, std::string_view id, uint32 option)
{
    if (_choiceId.empty() || id != _choiceId || option == 0 || option > _choiceOptions.size())
    {
        // Ventana ya cerrada o vieja: que el cliente la quite
        if (_choiceId.empty())
            MiWowMessage("MATCH_CHOICE_END").Send(player);
        return;
    }

    OnPlayerChoice(player, id, option - 1);
}

// MATCH_SHOP <titulo> <moneda> <cantidad> (<id> <categoria> <icono> <nombre> <detalle> <precio>)...
void MiWowMatch::OpenShop(Player* player)
{
    MiWowShop shop;
    if (!BuildShop(player, shop))
        return;

    _openShops.insert(player->GetGUID());
    MiWowMessage message("MATCH_SHOP");
    message.Add(shop.Title).Add(shop.Currency).Add(shop.Amount);
    for (MiWowShopItem const& item : shop.Items)
        message.Add(item.Id).Add(item.Category).Add(item.Icon).Add(item.Name).Add(item.Detail).Add(item.Price);
    message.Send(player);
}

void MiWowMatch::RefreshShop(Player* player)
{
    if (_openShops.count(player->GetGUID()))
        OpenShop(player);
}

void MiWowMatch::RefreshShops()
{
    if (!_openShops.empty())
        ForEachPlayer([this](Player* player) { RefreshShop(player); });
}

void MiWowMatch::CloseShop(Player* player)
{
    if (_openShops.erase(player->GetGUID()))
        MiWowMessage("MATCH_SHOP_CLOSE").Send(player);
}

void MiWowMatch::CloseShops()
{
    if (!_openShops.empty())
        ForEachPlayer([this](Player* player) { CloseShop(player); });
    _openShops.clear();
}

void MiWowMatch::HandleShopBuy(Player* player, uint32 id)
{
    if (!_openShops.count(player->GetGUID()))
    {
        MiWowMessage("MATCH_SHOP_CLOSE").Send(player);
        return;
    }

    OnShopBuy(player, id);
}

InstanceMap* MiWowMatch::GetMap() const
{
    Map* map = sMapMgr->FindMap(GetMapId(), _instanceId);
    return map ? map->ToInstanceMap() : nullptr;
}

void MiWowMatch::ForEachPlayer(std::function<void(Player* player)> const& func) const
{
    // Copia: func puede sacar jugadores de la partida
    GuidVector const players = _players;
    for (ObjectGuid const& guid : players)
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            func(player);
}

void MiWowMatch::SetState(MiWowMatchState state, Milliseconds duration)
{
    _state = state;
    _stateTimer = duration;
    _timerActive = duration > 0ms;
    BroadcastState();
}

void MiWowMatch::BroadcastState() const
{
    ForEachPlayer([this](Player* player) { SendState(player); });
}
