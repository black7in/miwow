#include "MiWowStats.h"
#include "Chat.h"
#include "CommandScript.h"
#include "DataMap.h"
#include "ItemTemplate.h"
#include "Player.h"
#include "StringFormat.h"
#include <algorithm>
#include <array>
#include <string>

namespace
{
    std::string const StatsKey = "MiWowStats";

    std::array<std::string_view, std::size_t(MiWowStat::Count)> const Keys =
    {
        "str", "agi", "sta", "int", "spi",
        "health", "mana", "armor", "ap", "rap", "sp",
        "crit", "haste", "hit", "expertise", "dodge", "parry", "block", "resilience", "armorpen",
        "spellpen", "mp5", "hp5"
    };

    struct StatsSlot : public DataMap::Base
    {
        std::array<int32, std::size_t(MiWowStat::Count)> Values = { };
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
    void ApplyStat(Player* player, MiWowStat stat, int32 value, bool apply)
    {
        switch (stat)
        {
            case MiWowStat::Strength:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_STRENGTH, STAT_STRENGTH, value, apply);
                break;
            case MiWowStat::Agility:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_AGILITY, STAT_AGILITY, value, apply);
                break;
            case MiWowStat::Stamina:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_STAMINA, STAT_STAMINA, value, apply);
                break;
            case MiWowStat::Intellect:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_INTELLECT, STAT_INTELLECT, value, apply);
                break;
            case MiWowStat::Spirit:
                ApplyPrimaryStat(player, UNIT_MOD_STAT_SPIRIT, STAT_SPIRIT, value, apply);
                break;
            case MiWowStat::Health:
                player->HandleStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, float(value), apply);
                break;
            case MiWowStat::Mana:
                player->HandleStatFlatModifier(UNIT_MOD_MANA, BASE_VALUE, float(value), apply);
                break;
            case MiWowStat::Armor:
                player->HandleStatFlatModifier(UNIT_MOD_ARMOR, TOTAL_VALUE, float(value), apply);
                break;
            case MiWowStat::AttackPower:
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER, TOTAL_VALUE, float(value), apply);
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER_RANGED, TOTAL_VALUE, float(value), apply);
                break;
            case MiWowStat::RangedAttackPower:
                player->HandleStatFlatModifier(UNIT_MOD_ATTACK_POWER_RANGED, TOTAL_VALUE, float(value), apply);
                break;
            case MiWowStat::SpellPower:
                player->ApplySpellPowerBonus(value, apply);
                break;
            case MiWowStat::CritRating:
                ApplyRatings(player, { CR_CRIT_MELEE, CR_CRIT_RANGED, CR_CRIT_SPELL }, value, apply);
                break;
            case MiWowStat::HasteRating:
                ApplyRatings(player, { CR_HASTE_MELEE, CR_HASTE_RANGED, CR_HASTE_SPELL }, value, apply);
                break;
            case MiWowStat::HitRating:
                ApplyRatings(player, { CR_HIT_MELEE, CR_HIT_RANGED, CR_HIT_SPELL }, value, apply);
                break;
            case MiWowStat::ExpertiseRating:
                ApplyRatings(player, { CR_EXPERTISE }, value, apply);
                break;
            case MiWowStat::DodgeRating:
                ApplyRatings(player, { CR_DODGE }, value, apply);
                break;
            case MiWowStat::ParryRating:
                ApplyRatings(player, { CR_PARRY }, value, apply);
                break;
            case MiWowStat::BlockRating:
                ApplyRatings(player, { CR_BLOCK }, value, apply);
                break;
            case MiWowStat::ResilienceRating:
                ApplyRatings(player, { CR_CRIT_TAKEN_MELEE, CR_CRIT_TAKEN_RANGED, CR_CRIT_TAKEN_SPELL }, value, apply);
                break;
            case MiWowStat::ArmorPenRating:
                ApplyRatings(player, { CR_ARMOR_PENETRATION }, value, apply);
                break;
            case MiWowStat::SpellPenetration:
                player->ApplySpellPenetrationBonus(value, apply);
                break;
            case MiWowStat::ManaRegen:
                player->ApplyManaRegenBonus(value, apply);
                break;
            case MiWowStat::HealthRegen:
                player->ApplyHealthRegenBonus(value, apply);
                break;
            default:
                break;
        }
    }
}

std::string_view MiWowStats::GetKey(MiWowStat stat)
{
    return stat < MiWowStat::Count ? Keys[std::size_t(stat)] : std::string_view();
}

std::optional<MiWowStat> MiWowStats::FromKey(std::string_view key)
{
    for (std::size_t i = 0; i < Keys.size(); ++i)
        if (Keys[i] == key)
            return MiWowStat(i);

    return std::nullopt;
}

std::optional<MiWowStat> MiWowStats::FromItemMod(uint32 itemMod)
{
    switch (itemMod)
    {
        case ITEM_MOD_MANA:                    return MiWowStat::Mana;
        case ITEM_MOD_HEALTH:                  return MiWowStat::Health;
        case ITEM_MOD_AGILITY:                 return MiWowStat::Agility;
        case ITEM_MOD_STRENGTH:                return MiWowStat::Strength;
        case ITEM_MOD_INTELLECT:               return MiWowStat::Intellect;
        case ITEM_MOD_SPIRIT:                  return MiWowStat::Spirit;
        case ITEM_MOD_STAMINA:                 return MiWowStat::Stamina;
        case ITEM_MOD_DODGE_RATING:            return MiWowStat::DodgeRating;
        case ITEM_MOD_PARRY_RATING:            return MiWowStat::ParryRating;
        case ITEM_MOD_BLOCK_RATING:            return MiWowStat::BlockRating;
        case ITEM_MOD_HIT_RATING:              return MiWowStat::HitRating;
        case ITEM_MOD_CRIT_RATING:             return MiWowStat::CritRating;
        case ITEM_MOD_RESILIENCE_RATING:       return MiWowStat::ResilienceRating;
        case ITEM_MOD_HASTE_RATING:            return MiWowStat::HasteRating;
        case ITEM_MOD_EXPERTISE_RATING:        return MiWowStat::ExpertiseRating;
        case ITEM_MOD_ATTACK_POWER:            return MiWowStat::AttackPower;
        case ITEM_MOD_RANGED_ATTACK_POWER:     return MiWowStat::RangedAttackPower;
        case ITEM_MOD_MANA_REGENERATION:       return MiWowStat::ManaRegen;
        case ITEM_MOD_ARMOR_PENETRATION_RATING: return MiWowStat::ArmorPenRating;
        case ITEM_MOD_SPELL_POWER:             return MiWowStat::SpellPower;
        case ITEM_MOD_HEALTH_REGEN:            return MiWowStat::HealthRegen;
        case ITEM_MOD_SPELL_PENETRATION:       return MiWowStat::SpellPenetration;
        default:                               return std::nullopt;
    }
}

void MiWowStats::Add(Player* player, MiWowStat stat, int32 amount)
{
    if (!amount || stat >= MiWowStat::Count)
        return;

    StatsSlot* slot = player->CustomData.GetDefault<StatsSlot>(StatsKey);
    slot->Values[std::size_t(stat)] += amount;
    ApplyStat(player, stat, amount, true);
}

int32 MiWowStats::Get(Player const* player, MiWowStat stat)
{
    StatsSlot const* slot = player->CustomData.Get<StatsSlot>(StatsKey);
    return slot && stat < MiWowStat::Count ? slot->Values[std::size_t(stat)] : 0;
}

void MiWowStats::Reset(Player* player)
{
    StatsSlot const* slot = player->CustomData.Get<StatsSlot>(StatsKey);
    if (!slot)
        return;

    auto const values = slot->Values;
    player->CustomData.Erase(StatsKey);

    for (std::size_t i = 0; i < values.size(); ++i)
        if (values[i])
            ApplyStat(player, MiWowStat(i), values[i], false);
}

// Comandos de prueba (GM): .miwow stat add <stat> <valor> | reset | list
// Sobre el jugador seleccionado o uno mismo. Fuera de partida duran hasta el proximo estado base.
using namespace Acore::ChatCommands;

class MiWow_StatsCommandScript : public CommandScript
{
public:
    MiWow_StatsCommandScript() : CommandScript("MiWow_StatsCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable statTable =
        {
            { "add",   HandleStatAdd,   SEC_GAMEMASTER, Console::No },
            { "reset", HandleStatReset, SEC_GAMEMASTER, Console::No },
            { "list",  HandleStatList,  SEC_GAMEMASTER, Console::No }
        };
        static ChatCommandTable miwowTable =
        {
            { "stat", statTable }
        };
        static ChatCommandTable commandTable =
        {
            { "miwow", miwowTable }
        };
        return commandTable;
    }

    static std::string GetKeyList()
    {
        std::string list;
        for (std::size_t i = 0; i < std::size_t(MiWowStat::Count); ++i)
        {
            if (!list.empty())
                list += ", ";
            list += MiWowStats::GetKey(MiWowStat(i));
        }
        return list;
    }

    static bool HandleStatAdd(ChatHandler* handler, std::string key, int32 value)
    {
        std::optional<MiWowStat> stat = MiWowStats::FromKey(key);
        if (!stat)
        {
            handler->SendErrorMessage("Stat desconocida '{}'. Validas: {}", key, GetKeyList());
            return false;
        }

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        MiWowStats::Add(target, *stat, value);
        handler->PSendSysMessage("MiWow: {} {} {:+} (total {:+})", target->GetName(), key, value,
            MiWowStats::Get(target, *stat));
        return true;
    }

    static bool HandleStatReset(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        MiWowStats::Reset(target);
        handler->PSendSysMessage("MiWow: bonificaciones de {} quitadas", target->GetName());
        return true;
    }

    static bool HandleStatList(ChatHandler* handler)
    {
        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        std::string list;
        for (std::size_t i = 0; i < std::size_t(MiWowStat::Count); ++i)
        {
            if (int32 const value = MiWowStats::Get(target, MiWowStat(i)))
            {
                if (!list.empty())
                    list += ", ";
                list += Acore::StringFormat("{} {:+}", MiWowStats::GetKey(MiWowStat(i)), value);
            }
        }

        handler->PSendSysMessage("MiWow: bonificaciones de {}: {}", target->GetName(), list.empty() ? "ninguna" : list);
        return true;
    }
};

void AddSC_miwow_stats()
{
    new MiWow_StatsCommandScript();
}
