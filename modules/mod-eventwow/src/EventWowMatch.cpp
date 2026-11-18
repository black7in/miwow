#include "EventWowMatch.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDisguise.h"
#include "EventWowProgress.h"
#include "EventWowGames.h"
#include "EventWowInventory.h"
#include "EventWowMatchMgr.h"
#include "EventWowProtocol.h"
#include "Log.h"
#include "Map.h"
#include "MapMgr.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "Random.h"
#include "TemporarySummon.h"
#include <cmath>
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

    // Sesion abierta: ya en marcha; cada uno tiene su propio plazo para llegar
    if (game->OpenSession)
    {
        _state = EventWowMatchState::Running;
        _stateTimer = 0ms;
        _timerActive = false;
        for (ObjectGuid const& guid : _players)
            _joining[guid] = sEventWowConfig.MatchLoadTimeout;
    }
}

void EventWowMatch::AddPlayer(ObjectGuid guid)
{
    if (HasPlayer(guid))
        return;

    _players.push_back(guid);
    _joining[guid] = sEventWowConfig.MatchLoadTimeout;
}

std::size_t EventWowMatch::GetFreeSlots() const
{
    return _players.size() < _game->MaxPlayers ? _game->MaxPlayers - _players.size() : 0;
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
            sEventWowMatchMgr.RemovePlayer(*this, guid, false);
        }

        if (_players.empty())
            return;
    }

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

    _inventoryTimer += diff;
    if (_game->InventorySlots && _inventoryTimer >= 250ms)
    {
        _inventoryTimer = 0ms;
        ForEachPlayer([this](Player* player)
        {
            if (player->GetInstanceId() == _instanceId)
                EventWowInventory::Update(player, _game->InventorySlots);
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

            if (UsesPicking())
            {
                SetState(EventWowMatchState::Picking, GetPickTime());
                UpdatePickCreatures();
                ForEachPlayer([this](Player* player) { SendPick(player); });
            }
            else
                SetState(EventWowMatchState::Countdown, GetCountdown());
            break;
        }
        case EventWowMatchState::Picking:
            if (expired)
                FinishPicking();
            break;
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

    if (!_players.empty())
        OnTick(diff);
}

Seconds EventWowMatch::GetEndDelay() const
{
    return sEventWowConfig.MatchReturnDelay;
}

void EventWowMatch::HandlePlayerArrived(Player* player)
{
    _arrived.insert(player->GetGUID());
    _joining.erase(player->GetGUID());

    SendState(player);
    SendHud(player);
    if (!UsesPicking())
        if (uint32 const characterId = GetAssignedCharacter(player))
            SetCharacter(player, characterId);

    OnPlayerArrived(player);
}

// Fase de eleccion --------------------------------------------------------------------------------

bool EventWowMatch::UsesPicking() const
{
    return GetPickTime() > 0s && sEventWowCharacters.GetForGame(_game->Id).size() >= 2;
}

bool EventWowMatch::UsesWorldPick() const
{
    return UsesPicking() && !GetPickPositions().empty();
}

bool EventWowMatch::CanPick(Player* player, uint32 characterId) const
{
    ObjectGuid const guid = player->GetGUID();
    if (_state != EventWowMatchState::Picking || !HasPlayer(guid) || _picks.count(guid))
        return false;

    std::vector<uint32> const& characters = sEventWowCharacters.GetForGame(_game->Id);
    return std::find(characters.begin(), characters.end(), characterId) != characters.end()
        && !IsCharacterTaken(characterId, guid);
}

std::vector<Position> EventWowMatch::MakePickCircle(Position const& center, float radius, std::size_t count)
{
    std::vector<Position> positions;
    for (std::size_t i = 0; i < count; ++i)
    {
        float const angle = 2.0f * float(M_PI) * float(i) / float(count);
        Position pos(center.GetPositionX() + radius * std::cos(angle), center.GetPositionY() + radius * std::sin(angle),
            center.GetPositionZ());
        pos.SetOrientation(pos.GetAbsoluteAngle(&center));
        positions.push_back(pos);
    }

    return positions;
}

std::size_t EventWowMatch::CountPickCreatures() const
{
    std::size_t count = 0;
    for (uint32 id : sEventWowCharacters.GetForGame(_game->Id))
        if (EventWowCharacterInfo const* character = sEventWowCharacters.Get(id))
            if (character->PickCreature)
                ++count;

    return count;
}

void EventWowMatch::UpdatePickCreatures()
{
    InstanceMap* map = GetMap();
    if (!map || _state != EventWowMatchState::Picking || !UsesWorldPick())
        return;

    std::vector<Position> const positions = GetPickPositions();
    std::size_t next = 0;
    for (uint32 id : sEventWowCharacters.GetForGame(_game->Id))
    {
        EventWowCharacterInfo const* character = sEventWowCharacters.Get(id);
        if (!character || !character->PickCreature)
            continue;

        if (next >= positions.size())
        {
            LOG_ERROR("module.eventwow", "EventWow: juego '{}': mas personajes con PNJ de eleccion que posiciones ({})",
                _game->Id, positions.size());
            break;
        }

        Position spawn = positions[next++];
        auto itr = _pickCreatures.find(id);
        Creature* creature = itr != _pickCreatures.end() ? map->GetCreature(itr->second) : nullptr;

        // Elegido (eleccion unica): fuera su PNJ
        if (IsCharacterTaken(id, ObjectGuid::Empty))
        {
            if (creature)
                creature->DespawnOrUnsummon();
            _pickCreatures.erase(id);
            continue;
        }

        if (creature)
            continue;

        float const ground = map->GetHeight(spawn.GetPositionX(), spawn.GetPositionY(), spawn.GetPositionZ() + 5.0f);
        if (ground > INVALID_HEIGHT)
            spawn.m_positionZ = ground;

        TempSummon* summon = map->SummonCreature(character->PickCreature, spawn);
        if (!summon)
        {
            LOG_ERROR("module.eventwow", "EventWow: no se pudo invocar el PNJ de eleccion {} ({})", character->PickCreature, character->Name);
            continue;
        }

        // El PNJ solo pone nombre y dialogo: el aspecto es el de la ficha
        if (character->DisplayId)
        {
            summon->SetNativeDisplayId(character->DisplayId);
            summon->SetDisplayId(character->DisplayId);
        }
        summon->SetObjectScale(character->Scale);
        // Sin arma en la derecha, el arma de distancia en la mano (como se probo con el arco de Sylvanas)
        summon->SetVirtualItem(0, character->WeaponMainHand ? character->WeaponMainHand : character->WeaponRanged);
        summon->SetVirtualItem(1, character->WeaponOffHand);
        summon->SetVirtualItem(2, 0);
        _pickCreatures[id] = summon->GetGUID();
    }
}

void EventWowMatch::DespawnPickCreatures()
{
    if (InstanceMap* map = GetMap())
        for (auto const& [id, guid] : _pickCreatures)
            if (Creature* creature = map->GetCreature(guid))
                creature->DespawnOrUnsummon();

    _pickCreatures.clear();
}

bool EventWowMatch::IsCharacterTaken(uint32 characterId, ObjectGuid except) const
{
    if (!IsPickUnique())
        return false;

    for (auto const& [guid, picked] : _picks)
        if (picked == characterId && guid != except)
            return true;

    return false;
}

void EventWowMatch::HandlePick(Player* player, uint32 characterId)
{
    ObjectGuid const guid = player->GetGUID();
    if (_state != EventWowMatchState::Picking || !HasPlayer(guid) || _picks.count(guid))
        return;

    std::vector<uint32> const& characters = sEventWowCharacters.GetForGame(_game->Id);
    if (std::find(characters.begin(), characters.end(), characterId) == characters.end())
    {
        EventWowMessage("ERROR").Add("PICK_INVALID").Send(player);
        return;
    }

    if (IsCharacterTaken(characterId, guid))
    {
        EventWowMessage("ERROR").Add("PICK_TAKEN").Send(player);
        SendPicks(player);
        return;
    }

    if (!SetCharacter(player, characterId))
        return;

    _picks[guid] = characterId;
    BroadcastPicks();
    UpdatePickCreatures();

    // Todos han elegido: no hace falta esperar al tiempo
    if (std::all_of(_players.begin(), _players.end(), [this](ObjectGuid const& g) { return _picks.count(g) > 0; }))
        FinishPicking();
}

void EventWowMatch::FinishPicking()
{
    if (_state != EventWowMatchState::Picking)
        return;

    // Al azar para los que no han elegido: primero entre los libres; si no queda ninguno, entre todos
    std::vector<uint32> const& characters = sEventWowCharacters.GetForGame(_game->Id);
    ForEachPlayer([this, &characters](Player* player)
    {
        ObjectGuid const guid = player->GetGUID();
        if (_picks.count(guid))
            return;

        std::vector<uint32> free;
        for (uint32 id : characters)
            if (!IsCharacterTaken(id, guid))
                free.push_back(id);

        std::vector<uint32> const& pool = free.empty() ? characters : free;
        uint32 const characterId = pool[urand(0, static_cast<uint32>(pool.size()) - 1)];
        if (SetCharacter(player, characterId))
            _picks[guid] = characterId;
    });

    BroadcastPicks();
    DespawnPickCreatures();
    SetState(EventWowMatchState::Countdown, GetCountdown());
}

// MATCH_PICK <unico 0/1> <n> (<id> <nombre> <icono> <descripcion> <hechizos "id,id,..."> <vehiculo 0/1>) x n
void EventWowMatch::SendPick(Player* player) const
{
    if (_state != EventWowMatchState::Picking)
        return;

    // Eleccion en el mundo: sin ventana (el cliente solo la abre con MATCH_PICK); el HUD muestra el tiempo
    if (UsesWorldPick())
    {
        SendPicks(player);
        return;
    }

    std::vector<uint32> const& characters = sEventWowCharacters.GetForGame(_game->Id);
    EventWowMessage message("MATCH_PICK");
    message.Add(IsPickUnique() ? 1 : 0).Add(static_cast<uint32>(characters.size()));
    for (uint32 id : characters)
    {
        EventWowCharacterInfo const* character = sEventWowCharacters.Get(id);
        std::string spells;
        for (uint32 spellId : character->Spells)
        {
            if (!spells.empty())
                spells += ',';
            spells += std::to_string(spellId);
        }

        message.Add(character->Id).Add(character->Name).Add(character->Icon).Add(character->Description)
            .Add(spells).Add(character->VehicleEntry ? 1 : 0);
    }

    message.Send(player);
    SendPicks(player);
}

// MATCH_PICKS <n> (<nombre jugador> <id personaje, 0 = sin elegir>) x n
void EventWowMatch::SendPicks(Player* player) const
{
    EventWowMessage message("MATCH_PICKS");
    message.Add(static_cast<uint32>(_players.size()));
    for (ObjectGuid const& guid : _players)
    {
        Player* member = ObjectAccessor::FindConnectedPlayer(guid);
        auto itr = _picks.find(guid);
        message.Add(member ? member->GetName() : std::string("?")).Add(itr != _picks.end() ? itr->second : 0);
    }

    message.Send(player);
}

void EventWowMatch::BroadcastPicks() const
{
    ForEachPlayer([this](Player* player) { SendPicks(player); });
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

    // Progresion (nivel 1 -> MaxLevel, puntos de habilidad): el nivel inicial antes del disfraz, que mide la vida y
    // el poder nativos al aplicarse
    if (_game->MaxLevel)
    {
        EventWowDisguise::Remove(player);
        EventWowProgress::SetLevel(player, 1);
        EventWowDisguise::Apply(player, *character, true);
        EventWowProgress::Start(player, *character, _game->MaxLevel, _game->XpRate);
        return true;
    }

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
    _joining.erase(guid);
    _results.erase(guid);
    _respawns.erase(guid);
    _picks.erase(guid);
    OnPlayerLeft(guid);

    if (_state == EventWowMatchState::Picking && !_players.empty())
    {
        if (std::all_of(_players.begin(), _players.end(), [this](ObjectGuid const& g) { return _picks.count(g) > 0; }))
            FinishPicking();
        else
        {
            BroadcastPicks();
            // Lo que habia elegido vuelve a estar libre
            UpdatePickCreatures();
        }
    }
}

bool EventWowMatch::IsReadyToClose() const
{
    return _players.empty() || (_state == EventWowMatchState::Ended && !_timerActive);
}

// MATCH_STATE <LOADING|WAITING|PICKING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
//   LOADING: en camino (sigue en el lobby / pantalla de carga); WAITING: dentro, esperando al resto.
//   PICKING: eleccion de personaje (MATCH_PICK / MATCH_PICKS).
//   segundos: lo que queda del estado (cuenta atras, temporizador de juego, vuelta al lobby); 0 = sin tiempo
void EventWowMatch::SendState(Player* player) const
{
    char const* state = "LOADING";
    switch (_state)
    {
        case EventWowMatchState::Loading:
            state = _arrived.count(player->GetGUID()) ? "WAITING" : "LOADING";
            break;
        case EventWowMatchState::Running:
            // Sesion abierta: quien aun no ha llegado esta cargando aunque la partida ya este en marcha
            state = _joining.count(player->GetGUID()) ? "LOADING" : "RUNNING";
            break;
        case EventWowMatchState::Picking:
            state = "PICKING";
            break;
        case EventWowMatchState::Countdown:
            state = "COUNTDOWN";
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

    SetState(EventWowMatchState::Ended, GetEndDelay());
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

Position EventWowMatch::GetArrivalPosition(Player* /*player*/)
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
