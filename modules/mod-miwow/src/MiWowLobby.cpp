#include "MiWowLobby.h"
#include "DataMap.h"
#include "MiWowConfig.h"
#include "MiWowGames.h"
#include "MiWowSpellLock.h"
#include "MiWowStats.h"
#include "MiWowVehicle.h"
#include "Item.h"
#include "Map.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <algorithm>
#include <vector>

namespace
{
    // Login dentro del mapa de un evento: se resucita al terminar de cargar (OnPlayerLogin)
    std::string const RelocatedKey = "MiWowLoginRelocated";

    struct RelocatedFlag : public DataMap::Base { };

    // Durabilidad del equipo al llegar a la partida (SaveDurability)
    std::string const DurabilityKey = "MiWowDurability";

    struct DurabilitySlot : public DataMap::Base
    {
        std::vector<std::pair<ObjectGuid, uint32>> Items;  // objeto equipado -> durabilidad
    };
}

char const* MiWowLobby::CanJoinFrom(Player const* player)
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

bool MiWowLobby::IsEventMap(uint32 mapId)
{
    // Solo el rango propio (MiWowGames::Validate no deja otros): las maquetas del panel llevan MapId 0
    return mapId >= MiWowFirstMapId && mapId <= MiWowLastMapId;
}

void MiWowLobby::SaveReturnPoint(Player* player)
{
    // Ya dentro de un evento (p. ej. modo dev): se conserva el punto de vuelta que tuviera
    if (IsEventMap(player->GetMapId()))
        return;

    player->SetEntryPoint();
}

void MiWowLobby::RestoreBaseState(Player* player)
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
    MiWowVehicle::Remove(player);
    MiWowSpellLock::Clear(player);
    MiWowStats::Reset(player);
    player->SetFullHealth();
}

void MiWowLobby::SaveDurability(Player* player)
{
    DurabilitySlot* slot = player->CustomData.GetDefault<DurabilitySlot>(DurabilityKey);
    slot->Items.clear();
    for (uint8 i = EQUIPMENT_SLOT_START; i < EQUIPMENT_SLOT_END; ++i)
        if (Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, i))
            if (item->GetUInt32Value(ITEM_FIELD_MAXDURABILITY))
                slot->Items.emplace_back(item->GetGUID(), item->GetUInt32Value(ITEM_FIELD_DURABILITY));
}

void MiWowLobby::RestoreDurability(Player* player)
{
    DurabilitySlot const* slot = player->CustomData.Get<DurabilitySlot>(DurabilityKey);
    if (!slot)
        return;

    for (uint8 i = EQUIPMENT_SLOT_START; i < EQUIPMENT_SLOT_END; ++i)
    {
        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, i);
        if (!item)
            continue;

        auto itr = std::find_if(slot->Items.begin(), slot->Items.end(),
            [item](std::pair<ObjectGuid, uint32> const& saved) { return saved.first == item->GetGUID(); });
        uint32 const current = item->GetUInt32Value(ITEM_FIELD_DURABILITY);
        if (itr == slot->Items.end() || current >= itr->second)
            continue;

        // Como Player::DurabilityRepair, sin coste y hasta la durabilidad que tenia al llegar
        item->SetUInt32Value(ITEM_FIELD_DURABILITY, itr->second);
        item->SetState(ITEM_CHANGED, player);
        if (!current)
            player->_ApplyItemMods(item, i, true);
    }
}

void MiWowLobby::ClearDurability(Player* player)
{
    player->CustomData.Erase(DurabilityKey);
}

bool MiWowLobby::ReturnFromMatch(Player* player)
{
    RestoreBaseState(player);
    return player->TeleportToEntryPoint();
}

// Login dentro del mapa de un evento: la partida ya no existe (se pierde con el logout), asi que aparece en su punto
// de vuelta. Sin el hook, el core lo mandaria a la entrada de la mazmorra o a su hogar.
class MiWow_LobbyPlayerScript : public PlayerScript
{
public:
    MiWow_LobbyPlayerScript() : PlayerScript("MiWow_LobbyPlayerScript", {
        PLAYERHOOK_ON_OVERRIDE_LOGIN_LOCATION,
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_BEFORE_LOGOUT
    }) { }

    // Antes de guardar el personaje (OnPlayerLogout, que saca de la partida, llega despues de SaveToDB)
    void OnPlayerBeforeLogout(Player* player) override
    {
        MiWowLobby::RestoreDurability(player);
    }

    bool OnPlayerOverrideLoginLocation(Player* player, WorldLocation& location) override
    {
        if (!sMiWowConfig.Enabled || !MiWowLobby::IsEventMap(location.GetMapId()))
            return false;

        WorldLocation const& entry = player->GetEntryPoint();
        if (entry.GetMapId() != MAPID_INVALID && !MiWowLobby::IsEventMap(entry.GetMapId()))
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
        // Pudo desconectarse muerto o en su vehiculo (el vehiculo no se guarda, pero la muerte si)
        if (!player->IsAlive())
            MiWowLobby::RestoreBaseState(player);
    }
};

void AddSC_miwow_lobby()
{
    new MiWow_LobbyPlayerScript();
}
