#include "EventWowWeapons.h"
#include "Chat.h"
#include "CommandScript.h"
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"

namespace
{
    // "No necesita municion" (Thori'dal): el core manda flecha (display 5996) como proyectil sin municion
    constexpr uint32 SpellRequiresNoAmmo = 46699;

    constexpr std::array<uint8, 3> WeaponSlots = { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND, EQUIPMENT_SLOT_RANGED };

    // Objeto de esa ranura si es el que equipo Equip
    Item* GetOwnItem(Player const* player, EventWowWeapons::EquipState const& state, std::size_t index)
    {
        if (!state.Items[index])
            return nullptr;

        Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, WeaponSlots[index]);
        return item && item->GetGUID() == state.Items[index] ? item : nullptr;
    }

    bool UsesAmmo(ItemTemplate const* proto)
    {
        return proto->Class == ITEM_CLASS_WEAPON && (proto->SubClass == ITEM_SUBCLASS_WEAPON_BOW ||
            proto->SubClass == ITEM_SUBCLASS_WEAPON_GUN || proto->SubClass == ITEM_SUBCLASS_WEAPON_CROSSBOW);
    }

    // Habilidad del tipo de arma (si el druida no la tiene) y competencia para el cliente
    void GrantProficiency(Player* player, Item const* item, EventWowWeapons::EquipState& state)
    {
        ItemTemplate const* proto = item->GetTemplate();
        if (uint32 const skill = proto->GetSkill(); skill && !player->HasSkill(skill))
        {
            uint16 const max = player->GetMaxSkillValueForLevel();
            player->SetSkill(uint16(skill), 0, max, max);
            state.AddedSkills.push_back(skill);
        }

        if (proto->Class == ITEM_CLASS_WEAPON)
        {
            player->AddWeaponProficiency(1 << proto->SubClass);
            player->SendProficiency(ITEM_CLASS_WEAPON, player->GetWeaponProficiency());
        }
        else if (proto->Class == ITEM_CLASS_ARMOR)
        {
            player->AddArmorProficiency(1 << proto->SubClass);
            player->SendProficiency(ITEM_CLASS_ARMOR, player->GetArmorProficiency());
        }
    }
}

bool EventWowWeapons::FitsSlot(ItemTemplate const* proto, uint8 slot)
{
    switch (slot)
    {
        case EQUIPMENT_SLOT_MAINHAND:
            return proto->Class == ITEM_CLASS_WEAPON && (proto->InventoryType == INVTYPE_WEAPON ||
                proto->InventoryType == INVTYPE_2HWEAPON || proto->InventoryType == INVTYPE_WEAPONMAINHAND);
        case EQUIPMENT_SLOT_OFFHAND:
            return proto->InventoryType == INVTYPE_WEAPON || proto->InventoryType == INVTYPE_WEAPONOFFHAND ||
                proto->InventoryType == INVTYPE_SHIELD || proto->InventoryType == INVTYPE_HOLDABLE;
        case EQUIPMENT_SLOT_RANGED:
            return proto->Class == ITEM_CLASS_WEAPON && (proto->InventoryType == INVTYPE_RANGED ||
                proto->InventoryType == INVTYPE_THROWN || proto->InventoryType == INVTYPE_RANGEDRIGHT);
        default:
            return false;
    }
}

bool EventWowWeapons::Equip(Player* player, uint32 mainHand, uint32 offHand, uint32 ranged, EquipState& state)
{
    std::array<uint32, 3> const entries = { mainHand, offHand, ranged };
    bool equipped = false;

    for (std::size_t i = 0; i < WeaponSlots.size(); ++i)
    {
        if (!entries[i] || GetOwnItem(player, state, i))
            continue;

        state.Items[i].Clear();
        uint8 const slot = WeaponSlots[i];
        if (player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
        {
            LOG_DEBUG("module.eventwow", "EventWow: {} ya lleva un objeto en la ranura {}, no se equipa el arma {}",
                player->GetName(), slot, entries[i]);
            continue;
        }

        Item* item = player->EquipNewItem((INVENTORY_SLOT_BAG_0 << 8) | slot, entries[i], true);
        if (!item)
        {
            LOG_ERROR("module.eventwow", "EventWow: no se pudo equipar el arma {} a {}", entries[i], player->GetName());
            continue;
        }

        state.Items[i] = item->GetGUID();
        equipped = true;
        GrantProficiency(player, item, state);

        if (slot == EQUIPMENT_SLOT_OFFHAND && item->GetTemplate()->Class == ITEM_CLASS_WEAPON && !player->CanDualWield())
        {
            player->SetCanDualWield(true);
            state.AddedDualWield = true;
        }
    }

    // Tambien si el aura se perdio (se repite en cada Update del disfraz)
    if (Item const* rangedItem = GetOwnItem(player, state, 2))
    {
        if (UsesAmmo(rangedItem->GetTemplate()) && !player->HasAura(SpellRequiresNoAmmo) && player->AddAura(SpellRequiresNoAmmo, player))
            state.AddedNoAmmo = true;
    }

    return equipped;
}

void EventWowWeapons::Unequip(Player* player, EquipState& state)
{
    for (std::size_t i = 0; i < WeaponSlots.size(); ++i)
        if (GetOwnItem(player, state, i))
            player->DestroyItem(INVENTORY_SLOT_BAG_0, WeaponSlots[i], true);

    // Quitar la habilidad tambien olvida los hechizos de esa linea que hubiera aprendido con ella
    for (uint32 skill : state.AddedSkills)
        if (player->HasSkill(skill))
            player->SetSkill(uint16(skill), 0, 0, 0);

    if (state.AddedDualWield)
        player->SetCanDualWield(false);

    if (state.AddedNoAmmo)
        player->RemoveAurasDueToSpell(SpellRequiresNoAmmo);

    state = EquipState();
}

void EventWowWeapons::UpdateSkills(Player* player, EquipState const& state)
{
    uint16 const max = player->GetMaxSkillValueForLevel();
    for (uint32 skill : state.AddedSkills)
        if (player->HasSkill(skill))
            player->SetSkill(uint16(skill), 0, max, max);
}

bool EventWowWeapons::IsEquippedBy(Player const* player, EquipState const& state, uint8 slot)
{
    for (std::size_t i = 0; i < WeaponSlots.size(); ++i)
        if (WeaponSlots[i] == slot)
            return GetOwnItem(player, state, i) != nullptr;

    return false;
}

// UNIT_VIRTUAL_ITEM_SLOT_ID no sirve para jugadores (Player::SetVirtualItemSlot no lo escribe): solo los PNJ.
void EventWowWeapons::SetVisible(Player* player, uint8 slot, uint32 entry)
{
    player->SetUInt32Value(PLAYER_VISIBLE_ITEM_1_ENTRYID + (slot * 2), entry);
    player->SetUInt32Value(PLAYER_VISIBLE_ITEM_1_ENCHANTMENT + (slot * 2), 0);
}

void EventWowWeapons::RestoreEquipped(Player* player)
{
    for (uint8 slot : { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND, EQUIPMENT_SLOT_RANGED })
        player->SetVisibleItemSlot(slot, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
}

// Comandos de prueba (GM), sobre el jugador seleccionado o uno mismo:
// .eventwow weapon set <mano derecha> [mano izquierda] [distancia]   (0 = vacia)
// .eventwow weapon sheath <0|1|2>   (0 envainada, 1 cuerpo a cuerpo, 2 distancia; no tiene efecto visible: el
//                                   envainado propio lo lleva el cliente, tecla Z)
// .eventwow weapon clear   (vuelve a mostrar lo equipado de verdad)
// Solo el aspecto (el disfraz equipa armas reales, EventWowWeapons::Equip). Se pierde al equipar/desequipar algo en esa ranura o al relogear.
using namespace Acore::ChatCommands;

class EventWow_WeaponsCommandScript : public CommandScript
{
public:
    EventWow_WeaponsCommandScript() : CommandScript("EventWow_WeaponsCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable weaponTable =
        {
            { "set",    HandleWeaponSet,    SEC_GAMEMASTER, Console::No },
            { "sheath", HandleWeaponSheath, SEC_GAMEMASTER, Console::No },
            { "clear",  HandleWeaponClear,  SEC_GAMEMASTER, Console::No }
        };
        static ChatCommandTable eventwowTable =
        {
            { "weapon", weaponTable }
        };
        static ChatCommandTable commandTable =
        {
            { "eventwow", eventwowTable }
        };
        return commandTable;
    }

    static bool CheckItem(ChatHandler* handler, uint32 entry)
    {
        if (entry && !sObjectMgr->GetItemTemplate(entry))
        {
            handler->SendErrorMessage("EventWow: el objeto {} no existe en item_template", entry);
            return false;
        }
        return true;
    }

    static bool HandleWeaponSet(ChatHandler* handler, uint32 mainHand, Optional<uint32> offHand, Optional<uint32> ranged)
    {
        uint32 const off = offHand.value_or(0);
        uint32 const range = ranged.value_or(0);
        if (!CheckItem(handler, mainHand) || !CheckItem(handler, off) || !CheckItem(handler, range))
            return false;

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        EventWowWeapons::SetVisible(target, EQUIPMENT_SLOT_MAINHAND, mainHand);
        EventWowWeapons::SetVisible(target, EQUIPMENT_SLOT_OFFHAND, off);
        EventWowWeapons::SetVisible(target, EQUIPMENT_SLOT_RANGED, range);
        handler->PSendSysMessage("EventWow: armas visibles de {}: {} / {} / {}", target->GetName(), mainHand, off, range);
        return true;
    }

    static bool HandleWeaponSheath(ChatHandler* handler, uint8 state)
    {
        if (state >= MAX_SHEATH_STATE)
        {
            handler->SendErrorMessage("EventWow: estado 0 (envainada), 1 (cuerpo a cuerpo) o 2 (distancia)");
            return false;
        }

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        target->SetSheath(SheathState(state));
        handler->PSendSysMessage("EventWow: {} -> envainado {}", target->GetName(), state);
        return true;
    }

    static bool HandleWeaponClear(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        // Vuelve a mostrar lo que lleve equipado de verdad
        EventWowWeapons::RestoreEquipped(target);
        handler->PSendSysMessage("EventWow: armas visibles de {} quitadas", target->GetName());
        return true;
    }
};

void AddSC_eventwow_weapons()
{
    new EventWow_WeaponsCommandScript();
}
