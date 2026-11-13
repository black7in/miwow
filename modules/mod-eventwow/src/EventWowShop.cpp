#include "EventWowShop.h"
#include "DatabaseEnv.h"
#include "EventWowConfig.h"
#include "EventWowStats.h"
#include "Item.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <algorithm>
#include <optional>

namespace
{
    // Stat de item_template -> EventWowStat (las mismas que aplica Player::_ApplyItemBonuses)
    std::optional<EventWowStat> FromItemMod(uint32 type)
    {
        switch (type)
        {
            case ITEM_MOD_MANA:                    return EventWowStat::Mana;
            case ITEM_MOD_HEALTH:                  return EventWowStat::Health;
            case ITEM_MOD_AGILITY:                 return EventWowStat::Agility;
            case ITEM_MOD_STRENGTH:                return EventWowStat::Strength;
            case ITEM_MOD_INTELLECT:               return EventWowStat::Intellect;
            case ITEM_MOD_SPIRIT:                  return EventWowStat::Spirit;
            case ITEM_MOD_STAMINA:                 return EventWowStat::Stamina;
            case ITEM_MOD_DODGE_RATING:            return EventWowStat::DodgeRating;
            case ITEM_MOD_PARRY_RATING:            return EventWowStat::ParryRating;
            case ITEM_MOD_BLOCK_RATING:            return EventWowStat::BlockRating;
            case ITEM_MOD_HIT_RATING:              return EventWowStat::HitRating;
            case ITEM_MOD_CRIT_RATING:             return EventWowStat::CritRating;
            case ITEM_MOD_RESILIENCE_RATING:       return EventWowStat::ResilienceRating;
            case ITEM_MOD_HASTE_RATING:            return EventWowStat::HasteRating;
            case ITEM_MOD_EXPERTISE_RATING:        return EventWowStat::ExpertiseRating;
            case ITEM_MOD_ATTACK_POWER:            return EventWowStat::AttackPower;
            case ITEM_MOD_RANGED_ATTACK_POWER:     return EventWowStat::RangedAttackPower;
            case ITEM_MOD_MANA_REGENERATION:       return EventWowStat::ManaRegen;
            case ITEM_MOD_ARMOR_PENETRATION_RATING: return EventWowStat::ArmorPenRating;
            case ITEM_MOD_SPELL_POWER:             return EventWowStat::SpellPower;
            case ITEM_MOD_HEALTH_REGEN:            return EventWowStat::HealthRegen;
            case ITEM_MOD_SPELL_PENETRATION:       return EventWowStat::SpellPenetration;
            default:                               return std::nullopt;
        }
    }
}

EventWowShop& EventWowShop::Instance()
{
    static EventWowShop instance;
    return instance;
}

void EventWowShop::Load()
{
    _itemFlags.clear();

    //                                                 0        1
    if (QueryResult result = WorldDatabase.Query("SELECT `Entry`, `Flags` FROM `eventwow_item`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const entry = fields[0].Get<uint32>();
            uint32 const flags = fields[1].Get<uint32>();

            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry);
            if (!proto)
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_item: el objeto {} no existe", entry);
                continue;
            }

            if ((flags & EVENTWOW_ITEM_FLAG_INSTANT) && !proto->StatsCount && !proto->Armor)
                LOG_WARN("module.eventwow", "EventWow: objeto instantaneo {} ({}) sin stats: no hara nada", entry, proto->Name1);

            _itemFlags[entry] = flags;
        } while (result->NextRow());
    }

    LOG_INFO("module.eventwow", "EventWow: {} objeto(s) de tienda cargados", _itemFlags.size());
}

uint32 EventWowShop::GetFlags(uint32 itemEntry) const
{
    auto itr = _itemFlags.find(itemEntry);
    return itr != _itemFlags.end() ? itr->second : 0;
}

class EventWow_ShopPlayerScript : public PlayerScript
{
public:
    EventWow_ShopPlayerScript() : PlayerScript("EventWow_ShopPlayerScript", {
        PLAYERHOOK_ON_AFTER_STORE_OR_EQUIP_NEW_ITEM
    }) { }

    // Compra a un vendedor ya cobrada y guardada en la mochila: los instantaneos se aplican y desaparecen.
    // (Al comprar necesita hueco en la mochila aunque no se quede en ella.)
    void OnPlayerAfterStoreOrEquipNewItem(Player* player, uint32 /*vendorslot*/, Item* item, uint8 count, uint8 /*bag*/,
        uint8 /*slot*/, ItemTemplate const* proto, Creature* /*vendor*/, VendorItem const* /*crItem*/, bool /*bStore*/) override
    {
        if (!item || !proto || !sEventWowShop.IsInstant(proto->ItemId))
            return;

        int32 const amount = std::max<int32>(1, count);
        for (uint32 i = 0; i < proto->StatsCount && i < MAX_ITEM_PROTO_STATS; ++i)
            if (std::optional<EventWowStat> stat = FromItemMod(proto->ItemStat[i].ItemStatType))
                EventWowStats::Add(player, *stat, proto->ItemStat[i].ItemStatValue * amount);

        if (proto->Armor)
            EventWowStats::Add(player, EventWowStat::Armor, int32(proto->Armor) * amount);

        player->DestroyItem(item->GetBagSlot(), item->GetSlot(), true);
    }
};

class EventWow_ShopWorldScript : public WorldScript
{
public:
    EventWow_ShopWorldScript() : WorldScript("EventWow_ShopWorldScript", {
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnStartup() override
    {
        if (sEventWowConfig.Enabled)
            sEventWowShop.Load();
    }
};

void AddSC_eventwow_shop()
{
    new EventWow_ShopPlayerScript();
    new EventWow_ShopWorldScript();
}
