// Armas visibles sin equipar (PROTOTIPO, solo comandos de prueba).
//
// El cliente dibuja las armas de un jugador a partir de PLAYER_VISIBLE_ITEM_<ranura>_ENTRYID (lo mismo que usa la
// transfiguracion), no del objeto equipado. Escribir ahi el ID de un objeto (p. ej. los "Monster - ..." de los PNJ)
// hace que se vea sin darle stats ni pedir la habilidad del arma. UNIT_VIRTUAL_ITEM_SLOT_ID no sirve para jugadores
// (Player::SetVirtualItemSlot no lo escribe).
//
// .eventwow weapon set <mano derecha> [mano izquierda] [distancia]   (0 = vacia)
// .eventwow weapon sheath <0|1|2>                                      (0 envainada, 1 cuerpo a cuerpo, 2 distancia)
// .eventwow weapon clear
// Sobre el jugador seleccionado o uno mismo. Se pierde al equipar/desequipar algo en esa ranura o al relogear.
#include "Chat.h"
#include "CommandScript.h"
#include "ObjectMgr.h"
#include "Player.h"

using namespace Acore::ChatCommands;

namespace
{
    void SetVisibleWeapon(Player* player, uint8 slot, uint32 entry)
    {
        player->SetUInt32Value(PLAYER_VISIBLE_ITEM_1_ENTRYID + (slot * 2), entry);
        player->SetUInt32Value(PLAYER_VISIBLE_ITEM_1_ENCHANTMENT + (slot * 2), 0);
    }
}

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

        SetVisibleWeapon(target, EQUIPMENT_SLOT_MAINHAND, mainHand);
        SetVisibleWeapon(target, EQUIPMENT_SLOT_OFFHAND, off);
        SetVisibleWeapon(target, EQUIPMENT_SLOT_RANGED, range);
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
            SetVisibleWeapon(target, slot, 0);
        handler->PSendSysMessage("EventWow: armas visibles de {} quitadas", target->GetName());
        return true;
    }
};

void AddSC_eventwow_weapons()
{
    new EventWow_WeaponsCommandScript();
}
