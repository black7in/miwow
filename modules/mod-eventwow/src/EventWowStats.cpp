#include "EventWowStats.h"
#include "Chat.h"
#include "CommandScript.h"
#include "DataMap.h"
#include "Player.h"
#include "StringFormat.h"
#include <array>
#include <string>

namespace
{
    std::string const StatsKey = "EventWowStats";

    std::array<std::string_view, std::size_t(EventWowStat::Count)> const Keys =
    {
        "str", "agi", "sta", "int", "spi",
        "health", "mana", "armor", "ap", "rap", "sp",
        "crit", "haste", "hit", "expertise", "dodge", "parry", "block", "resilience", "armorpen",
        "spellpen", "mp5", "hp5"
    };

    struct StatsSlot : public DataMap::Base
    {
        std::array<int32, std::size_t(EventWowStat::Count)> Values = { };
    };

    void ApplyPrimaryStat(Player* player, UnitMods unitMod, Stats stat, int32 value, bool apply)
    {
        player->HandleStatFlatModifier(unitMod, BASE_VALUE, float(value), apply);
        player->UpdateStatBuffMod(stat);
    }

    void ApplyRatings(Player* player, std::initializer_list<CombatRating> ratings, int32 value, bool apply)
    {
        for (CombatRating rating : ratings)
            player->ApplyRatingMod(rating, value, apply);
    }

    // Igual que Player::_ApplyItemBonuses para el ITEM_MOD equivalente
    void ApplyStat(Player* player, EventWowStat stat, int32 value, bool apply)
    {
        switch (stat)
        {
            case EventWowStat::Strength:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_STRENGTH, STAT_STRENGTH, value, apply);
                break;
            case EventWowStat::Agility:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_AGILITY, STAT_AGILITY, value, apply);
                break;
            case EventWowStat::Stamina:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_STAMINA, STAT_STAMINA, value, apply);
                break;
            case EventWowStat::Intellect:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_INTELLECT, STAT_INTELLECT, value, apply);
                break;
            case EventWowStat::Spirit:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_SPIRIT, STAT_SPIRIT, value, apply);
                break;
            case EventWowStat::Health:
                player->HandleStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, float(value), apply);
                break;
            case EventWowStat::Mana:
                player->HandleStatFlatModifier(UNIT_MOD_MANA, BASE_VALUE, float(value), apply);
                break;
            case EventWowStat::Armor:
                player->HandleStatFlatModifier(UNIT_MOD_ARMOR, TOTAL_VALUE, float(value), apply);
                break;
            case EventWowStat::AttackPower:
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER, TOTAL_VALUE, float(value), apply);
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER_RANGED, TOTAL_VALUE, float(value), apply);
                break;
            case EventWowStat::RangedAttackPower:
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER_RANGED, TOTAL_VALUE, float(value), apply);
                break;
            case EventWowStat::SpellPower:
                player->ApplySpellPowerBonus(value, apply);
                break;
            case EventWowStat::CritRating:
                ApplyRatings(player, { CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL }, value, apply);
                break;
            case EventWowStat::HasteRating:
                ApplyRatings(player, { CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL }, value, apply);
                break;
            case EventWowStat::HitRating:
                ApplyRatings(player, { CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL }, value, apply);
                break;
            case EventWowStat::ExpertiseRating:
                ApplyRatings(player, { CR_EXPERTISE }, value, apply);
                break;
            case EventWowStat::DodgeRating:
                ApplyRatings(player, { CR_DODGE }, value, apply);
                break;
            case EventWowStat::ParryRating:
                ApplyRatings(player, { CR_PARRY }, value, apply);
                break;
            case EventWowStat::BlockRating:
                ApplyRatings(player, { CR_BLOCK }, value, apply);
                break;
            case EventWowStat::ResilienceRating:
                ApplyRatings(player, { CR_CRIT_TAKEN_MELEE, CR_CRIT_TAKEN_RANGED, CR_CRIT_TAKEN_SPELL }, value, apply);
                break;
            case EventWowStat::ArmorPenRating:
                ApplyRatings(player, { CR_ARMOR_PENETRATION }, value, apply);
                break;
            case EventWowStat::SpellPenetration:
                player->ApplySpellPenetrationBonus(value, apply);
                break;
            case EventWowStat::ManaRegen:
                player->ApplyManaRegenBonus(value, apply);
                break;
            case EventWowStat::HealthRegen:
                player->ApplyHealthRegenBonus(value, apply);
                break;
            default:
                break;
        }
    }
}

std::string_view EventWowStats::GetKey(EventWowStat stat)
{
    return stat < EventWowStat::Count ? Keys[std::size_t(stat)] : std::string_view();
}

std::optional<EventWowStat> EventWowStats::FromKey(std::string_view key)
{
    for (std::size_t i = 0; i < Keys.size(); ++i)
        if (Keys[i] == key)
            return EventWowStat(i);

    return std::nullopt;
}

void EventWowStats::Add(Player* player, EventWowStat stat, int32 amount)
{
    if (!amount || stat >= EventWowStat::Count)
        return;

    StatsSlot* slot = player->CustomData.GetDefault<StatsSlot>(StatsKey);
    slot->Values[std::size_t(stat)] += amount;
    ApplyStat(player, stat, amount, true);
}

int32 EventWowStats::Get(Player const* player, EventWowStat stat)
{
    StatsSlot const* slot = player->CustomData.Get<StatsSlot>(StatsKey);
    return slot && stat < EventWowStat::Count ? slot->Values[std::size_t(stat)] : 0;
}

void EventWowStats::Reset(Player* player)
{
    StatsSlot const* slot = player->CustomData.Get<StatsSlot>(StatsKey);
    if (!slot)
        return;

    auto const values = slot->Values;
    player->CustomData.Erase(StatsKey);

    for (std::size_t i = 0; i < values.size(); ++i)
        if (values[i])
            ApplyStat(player, EventWowStat(i), values[i], false);
}

// Comandos de prueba (GM): .eventwow stat add <stat> <valor> | reset | list
// Sobre el jugador seleccionado o uno mismo. Fuera de partida duran hasta el proximo estado base.
using namespace Acore::ChatCommands;

class EventWow_StatsCommandScript : public CommandScript
{
public:
    EventWow_StatsCommandScript() : CommandScript("EventWow_StatsCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable statTable =
        {
            { "add",   HandleStatAdd,   SEC_GAMEMASTER, Console::No },
            { "reset", HandleStatReset, SEC_GAMEMASTER, Console::No },
            { "list",  HandleStatList,  SEC_GAMEMASTER, Console::No }
        };
        static ChatCommandTable eventwowTable =
        {
            { "stat", statTable }
        };
        static ChatCommandTable commandTable =
        {
            { "eventwow", eventwowTable }
        };
        return commandTable;
    }

    static std::string GetKeyList()
    {
        std::string list;
        for (std::size_t i = 0; i < std::size_t(EventWowStat::Count); ++i)
        {
            if (!list.empty())
                list += ", ";
            list += EventWowStats::GetKey(EventWowStat(i));
        }
        return list;
    }

    static bool HandleStatAdd(ChatHandler* handler, std::string key, int32 value)
    {
        std::optional<EventWowStat> stat = EventWowStats::FromKey(key);
        if (!stat)
        {
            handler->SendErrorMessage("Stat desconocida '{}'. Validas: {}", key, GetKeyList());
            return false;
        }

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        EventWowStats::Add(target, *stat, value);
        handler->PSendSysMessage("EventWow: {} {} {:+} (total {:+})", target->GetName(), key, value,
            EventWowStats::Get(target, *stat));
        return true;
    }

    static bool HandleStatReset(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        EventWowStats::Reset(target);
        handler->PSendSysMessage("EventWow: bonificaciones de {} quitadas", target->GetName());
        return true;
    }

    static bool HandleStatList(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        std::string list;
        for (std::size_t i = 0; i < std::size_t(EventWowStat::Count); ++i)
        {
            if (int32 const value = EventWowStats::Get(target, EventWowStat(i)))
            {
                if (!list.empty())
                    list += ", ";
                list += Acore::StringFormat("{} {:+}", EventWowStats::GetKey(EventWowStat(i)), value);
            }
        }

        handler->PSendSysMessage("EventWow: bonificaciones de {}: {}", target->GetName(), list.empty() ? "ninguna" : list);
        return true;
    }
};

void AddSC_eventwow_stats()
{
    new EventWow_StatsCommandScript();
}
