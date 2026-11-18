#include "EventWowLobby.h"
#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowDisguise.h"
#include "EventWowGames.h"
#include "EventWowInventory.h"
#include "EventWowStats.h"
#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"

namespace
{
    // Login dentro del mapa de un evento: se resucita al terminar de cargar (OnPlayerLogin)
    std::string const RelocatedKey = "EventWowLoginRelocated";

    struct RelocatedFlag : public DataMap::Base { };
}

char const* EventWowLobby::CanJoinFrom(Player const* player)
{
    if (!player->IsAlive())
        return "QUEUE_DEAD";

    if (player->IsInCombat())
        return "QUEUE_IN_COMBAT";

    if (player->IsInFlight())
        return "QUEUE_IN_FLIGHT";

    if (player->GetMap()->Instanceable())
        return "QUEUE_IN_INSTANCE";

    if (player->InBattlegroundQueue())
        return "QUEUE_IN_BG_QUEUE";

    return nullptr;
}

bool EventWowLobby::IsEventMap(uint32 mapId)
{
    for (EventWowGameInfo const& game : sEventWowGames.GetAll())
        if (game.MapId == mapId)
            return true;

    return false;
}

void EventWowLobby::SaveReturnPoint(Player* player)
{
    // Ya dentro de un evento (p. ej. modo dev): se conserva el punto de vuelta que tuviera
    if (IsEventMap(player->GetMapId()))
        return;

    player->SetEntryPoint();
}

void EventWowLobby::RestoreBaseState(Player* player)
{
    if (!player->IsAlive())
    {
        player->ResurrectPlayer(1.0f);
        player->SpawnCorpseBones();
    }

    player->CombatStop(true);
    // Como al entrar a una arena: beneficios temporales fuera; pasivas (talentos, raciales), auras de paladin,
    // actitudes y debilitaciones que sobreviven a la muerte se quedan
    player->RemoveArenaAuras();
    player->RemoveAurasByType(SPELL_AURA_MOUNTED);
    player->RemoveAurasByType(SPELL_AURA_MOD_SHAPESHIFT);
    EventWowDisguise::Remove(player);
    EventWowInventory::Clear(player);
    EventWowStats::Reset(player);
    player->SetFullHealth();
}

bool EventWowLobby::ReturnFromMatch(Player* player)
{
    RestoreBaseState(player);
    return player->TeleportToEntryPoint();
}

// Login dentro del mapa de un evento: la partida ya no existe (se pierde con el logout), asi que aparece en su punto
// de vuelta. Sin el hook, el core lo mandaria a la entrada de la mazmorra o a su hogar.
class EventWow_LobbyPlayerScript : public PlayerScript
{
public:
    EventWow_LobbyPlayerScript() : PlayerScript("EventWow_LobbyPlayerScript", {
        PLAYERHOOK_ON_OVERRIDE_LOGIN_LOCATION,
        PLAYERHOOK_ON_LOGIN
    }) { }

    bool OnPlayerOverrideLoginLocation(Player* player, WorldLocation& location) override
    {
        if (!sEventWowConfig.Enabled || !EventWowLobby::IsEventMap(location.GetMapId()))
            return false;

        WorldLocation const& entry = player->GetEntryPoint();
        if (entry.GetMapId() != MAPID_INVALID && !EventWowLobby::IsEventMap(entry.GetMapId()))
            location.WorldRelocate(entry);
        else
            location.WorldRelocate(player->m_homebindMapId, player->m_homebindX, player->m_homebindY,
                player->m_homebindZ, player->GetOrientation());

        player->CustomData.GetDefault<RelocatedFlag>(RelocatedKey);
        return true;
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!player->CustomData.Get<RelocatedFlag>(RelocatedKey))
            return;

        player->CustomData.Erase(RelocatedKey);
        // Pudo desconectarse muerto o disfrazado (el disfraz no se guarda, pero la muerte si)
        if (!player->IsAlive())
            EventWowLobby::RestoreBaseState(player);
    }
};

void AddSC_eventwow_lobby()
{
    new EventWow_LobbyPlayerScript();
}
