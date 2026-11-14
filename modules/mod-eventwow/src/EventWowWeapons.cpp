#include "EventWowWeapons.h"
#include "Chat.h"
#include "CommandScript.h"
#include "ObjectMgr.h"
#include "Player.h"

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
// .eventwow weapon clear
// Se pierde al equipar/desequipar algo en esa ranura o al relogear.
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

        for (uint8 slot : { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND, EQUIPMENT_SLOT_RANGED })
            EventWowWeapons::SetVisible(target, slot, 0);
        handler->PSendSysMessage("EventWow: armas visibles de {} quitadas", target->GetName());
        return true;
    }
};

void AddSC_eventwow_weapons()
{
    new EventWow_WeaponsCommandScript();
}
