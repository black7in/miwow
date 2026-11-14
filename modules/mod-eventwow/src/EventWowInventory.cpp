#include "EventWowInventory.h"
#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowShop.h"
#include "EventWowStats.h"
#include "Item.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include <algorithm>
#include <array>
#include <unordered_map>

namespace
{
    std::string const InventoryKey = "EventWowInventory";

    // Lo leen los hooks de compra/equipar (hilos de mapa): solo datos del propio jugador
    struct InventoryState : public DataMap::Base
    {
        // Casillas del juego actual (0 = sin inventario)
        uint8 Slots = 0;
        // Objeto (entrada) cuyos efectos estan aplicados en cada casilla; 0 = vacia
        std::array<uint32, EventWowInventory::MaxSlots> Entries{};
        // Hechizo "Equipar:" -> numero de objetos que lo dan
        std::unordered_map<uint32, uint32> Spells;
    };

    InventoryState* GetSlot(Player const* player)
    {
        return player->CustomData.Get<InventoryState>(InventoryKey);
    }

    uint8 ToNativeSlot(uint8 box)
    {
        return INVENTORY_SLOT_ITEM_START + box;
    }

    // Hechizos que se mantienen como aura (los que no crean aura no se pueden "llevar")
    bool IsCarriedSpell(ItemTemplate const* proto, uint8 index, SpellInfo const*& spellInfo)
    {
        _Spell const& spell = proto->Spells[index];
        if (spell.SpellId <= 0 || spell.SpellTrigger != ITEM_SPELLTRIGGER_ON_EQUIP)
            return false;

        spellInfo = sSpellMgr->GetSpellInfo(spell.SpellId);
        return spellInfo && spellInfo->HasAnyAura();
    }

    void ApplyItem(Player* player, InventoryState& slot, uint32 entry, bool apply)
    {
        ItemTemplate const* proto = entry ? sObjectMgr->GetItemTemplate(entry) : nullptr;
        if (!proto)
            return;

        int32 const sign = apply ? 1 : -1;
        for (uint32 i = 0; i < proto->StatsCount && i < MAX_ITEM_PROTO_STATS; ++i)
            if (std::optional<EventWowStat> stat = EventWowStats::FromItemMod(proto->ItemStat[i].ItemStatType))
                EventWowStats::Add(player, *stat, sign * proto->ItemStat[i].ItemStatValue);

        if (proto->Armor)
            EventWowStats::Add(player, EventWowStat::Armor, sign * int32(proto->Armor));

        for (uint8 i = 0; i < MAX_ITEM_PROTO_SPELLS; ++i)
        {
            SpellInfo const* spellInfo = nullptr;
            if (!IsCarriedSpell(proto, i, spellInfo))
                continue;

            uint32& count = slot.Spells[spellInfo->Id];
            if (apply)
            {
                if (count++ == 0 && player->IsAlive())
                    player->CastSpell(player, spellInfo, true);
            }
            else if (count <= 1)
            {
                slot.Spells.erase(spellInfo->Id);
                player->RemoveAurasDueToSpell(spellInfo->Id, player->GetGUID());
            }
            else
                --count;
        }
    }

    // Cabe una compra en las casillas? (pila del mismo objeto con hueco o casilla vacia)
    bool HasRoom(Player const* player, uint8 slots, ItemTemplate const* proto, uint32 count)
    {
        for (uint8 box = 0; box < slots; ++box)
        {
            Item const* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, ToNativeSlot(box));
            if (!item)
                return true;

            if (item->GetEntry() == proto->ItemId && item->GetCount() + count <= proto->GetMaxStackSize())
                return true;
        }

        return false;
    }

    // Reglas de inventario activas para este jugador (en partida con inventario y sin modo dev)
    uint8 GetActiveSlots(Player const* player)
    {
        InventoryState const* slot = GetSlot(player);
        if (!slot || !slot->Slots || EventWowDevMode::IsActive(player))
            return 0;

        return slot->Slots;
    }
}

void EventWowInventory::Update(Player* player, uint8 slots)
{
    slots = std::min(slots, MaxSlots);
    InventoryState* slot = player->CustomData.GetDefault<InventoryState>(InventoryKey);
    slot->Slots = slots;

    for (uint8 box = 0; box < MaxSlots; ++box)
    {
        uint32 entry = 0;
        if (box < slots)
            if (Item const* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, ToNativeSlot(box)))
                if (!sEventWowShop.IsInstant(item->GetEntry()))
                    entry = item->GetEntry();

        if (entry == slot->Entries[box])
            continue;

        ApplyItem(player, *slot, slot->Entries[box], false);
        slot->Entries[box] = entry;
        ApplyItem(player, *slot, entry, true);
    }

    // Auras perdidas (muerte, disipadas...): vuelven mientras lleve el objeto
    if (player->IsAlive())
        for (auto const& [spellId, count] : slot->Spells)
            if (!player->HasAura(spellId, player->GetGUID()))
                player->CastSpell(player, spellId, true);
}

void EventWowInventory::Clear(Player* player)
{
    InventoryState* slot = GetSlot(player);
    if (!slot)
        return;

    for (uint32& entry : slot->Entries)
    {
        ApplyItem(player, *slot, entry, false);
        entry = 0;
    }

    player->CustomData.Erase(InventoryKey);
}

class EventWow_InventoryPlayerScript : public PlayerScript
{
public:
    EventWow_InventoryPlayerScript() : PlayerScript("EventWow_InventoryPlayerScript", {
        PLAYERHOOK_ON_BEFORE_BUY_ITEM_FROM_VENDOR,
        PLAYERHOOK_CAN_EQUIP_ITEM
    }) { }

    // Compra: solo si cabe en las casillas (los instantaneos siempre: se destruyen al momento)
    void OnPlayerBeforeBuyItemFromVendor(Player* player, ObjectGuid /*vendorguid*/, uint32 /*vendorslot*/, uint32& item,
        uint8 count, uint8 bag, uint8 slot) override
    {
        uint8 const slots = GetActiveSlots(player);
        if (!slots || !item || sEventWowShop.IsInstant(item))
            return;

        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
        if (!proto)
            return;

        // Destino elegido por el cliente (arrastrar a una ranura): solo una de las casillas
        bool const chosen = bag != NULL_BAG || slot != NULL_SLOT;
        bool const valid = chosen
            ? bag == INVENTORY_SLOT_BAG_0 && slot >= ToNativeSlot(0) && slot < ToNativeSlot(slots)
            : HasRoom(player, slots, proto, std::max<uint32>(1, count));

        if (!valid)
        {
            player->SendEquipError(EQUIP_ERR_INVENTORY_FULL, nullptr, nullptr, item);
            item = 0;  // cancela la compra (Player::BuyItemFromVendorSlot)
        }
    }

    // En partida nada se equipa: los objetos funcionan desde las casillas
    bool OnPlayerCanEquipItem(Player* player, uint8 /*slot*/, uint16& /*dest*/, Item* /*pItem*/, bool /*swap*/,
        bool notLoading) override
    {
        return !notLoading || !GetActiveSlots(player);
    }
};

void AddSC_eventwow_inventory()
{
    new EventWow_InventoryPlayerScript();
}
