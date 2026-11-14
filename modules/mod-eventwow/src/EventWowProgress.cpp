#include "EventWowProgress.h"
#include "DataMap.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowDisguise.h"
#include "EventWowProtocol.h"
#include "EventWowStats.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellMgr.h"
#include "StringConvert.h"
#include "World.h"
#include <algorithm>
#include <string>
#include <vector>

namespace
{
    std::string const ProgressKey = "EventWowProgress";

    struct ProgressSlot : public DataMap::Base
    {
        uint32 CharacterId = 0;
        uint8 MaxLevel = 0;
        float XpRate = 1.0f;
        // Rango aprendido de cada hechizo de la ficha (0 = sin aprender)
        std::vector<uint8> Ranks;
        uint8 AttributeRank = 0;
    };

    ProgressSlot* GetSlot(Player const* player)
    {
        return player->CustomData.Get<ProgressSlot>(ProgressKey);
    }

    uint8 GetTotalRanks(uint32 firstSpell)
    {
        uint8 const rank = sSpellMgr->GetSpellRank(sSpellMgr->GetLastSpellInChain(firstSpell));
        return rank ? rank : 1;
    }

    // Rango maximo que permite el nivel actual
    uint8 GetMaxRankNow(EventWowAbilityKind kind, uint8 totalRanks, uint8 level, uint8 maxLevel)
    {
        uint8 allowed = totalRanks;
        switch (kind)
        {
            case EventWowAbilityKind::Basic:
                allowed = (level + 1) / 2;
                break;
            case EventWowAbilityKind::Ultimate:
                allowed = level >= 18 ? 3 : (level >= 12 ? 2 : (level >= 6 ? 1 : 0));
                break;
            case EventWowAbilityKind::Supreme:
                allowed = level >= maxLevel ? 1 : 0;
                break;
            case EventWowAbilityKind::Fixed:
                break;
        }

        return std::min(allowed, totalRanks);
    }

    bool UsesPoints(EventWowAbilityKind kind)
    {
        return kind == EventWowAbilityKind::Basic || kind == EventWowAbilityKind::Ultimate;
    }

    // Puntos de atributos posibles en la partida: lo que sobra al subir todas las habilidades
    uint8 GetAttributeMax(EventWowCharacterInfo const& character, uint8 maxLevel)
    {
        if (character.AttributeStats.empty())
            return 0;

        int32 left = maxLevel;
        for (std::size_t i = 0; i < character.Spells.size(); ++i)
            if (UsesPoints(character.SpellKinds[i]))
                left -= GetTotalRanks(character.Spells[i]);

        return uint8(std::max(0, left));
    }

    // Desde nivel 2 (el primer punto es para una habilidad)
    uint8 GetAttributeMaxNow(uint8 attributeMax, uint8 level)
    {
        return std::min<uint8>(attributeMax, level >= 2 ? level - 1 : 0);
    }

    int32 GetPoints(Player const* player, ProgressSlot const* slot, EventWowCharacterInfo const& character)
    {
        int32 spent = slot->AttributeRank;
        for (std::size_t i = 0; i < character.Spells.size(); ++i)
            if (UsesPoints(character.SpellKinds[i]))
                spent += slot->Ranks[i];

        return std::max(0, int32(player->GetLevel()) - spent);
    }

    // Lo que no cuesta puntos: la suprema al llegar al nivel maximo
    void UpdateAutomatic(Player* player, ProgressSlot* slot, EventWowCharacterInfo const& character)
    {
        for (std::size_t i = 0; i < character.Spells.size(); ++i)
        {
            if (character.SpellKinds[i] != EventWowAbilityKind::Supreme || slot->Ranks[i])
                continue;

            if (GetMaxRankNow(EventWowAbilityKind::Supreme, 1, player->GetLevel(), slot->MaxLevel))
            {
                EventWowDisguise::ReplaceSpell(player, 0, character.Spells[i]);
                slot->Ranks[i] = 1;
            }
        }
    }

    void ApplyAttributes(Player* player, EventWowCharacterInfo const& character, int32 times)
    {
        for (auto const& [stat, value] : character.AttributeStats)
            EventWowStats::Add(player, stat, value * times);
    }

    // XP que falta para llegar al nivel maximo (lo que se puede ganar como mucho)
    uint32 GetXpToMaxLevel(Player const* player, uint8 maxLevel)
    {
        uint8 const level = player->GetLevel();
        if (level >= maxLevel)
            return 0;

        uint32 needed = player->GetUInt32Value(PLAYER_NEXT_LEVEL_XP) - std::min(player->GetUInt32Value(PLAYER_XP),
            player->GetUInt32Value(PLAYER_NEXT_LEVEL_XP));
        for (uint8 next = level + 1; next < maxLevel; ++next)
            needed += sObjectMgr->GetXPForLevel(next);

        return needed;
    }
}

bool EventWowProgress::IsActive(Player const* player)
{
    return GetSlot(player) != nullptr;
}

void EventWowProgress::SetLevel(Player* player, uint8 level)
{
    player->GiveLevel(level);
    player->SetUInt32Value(PLAYER_XP, 0);
}

void EventWowProgress::Start(Player* player, EventWowCharacterInfo const& character, uint8 maxLevel, float xpRate)
{
    ProgressSlot* slot = player->CustomData.GetDefault<ProgressSlot>(ProgressKey);
    slot->CharacterId = character.Id;
    slot->MaxLevel = maxLevel;
    slot->XpRate = xpRate;
    slot->AttributeRank = 0;
    slot->Ranks.assign(character.Spells.size(), 0);
    // Los fijos ya los aprendio el disfraz (rango 1)
    for (std::size_t i = 0; i < character.Spells.size(); ++i)
        if (character.SpellKinds[i] == EventWowAbilityKind::Fixed)
            slot->Ranks[i] = 1;

    player->RemovePlayerFlag(PLAYER_FLAGS_NO_XP_GAIN);
    UpdateAutomatic(player, slot, character);
    SendState(player);
}

void EventWowProgress::Stop(Player* player)
{
    ProgressSlot const* slot = GetSlot(player);
    if (!slot)
        return;

    if (EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId))
        ApplyAttributes(player, *character, -int32(slot->AttributeRank));

    player->CustomData.Erase(ProgressKey);

    SetLevel(player, uint8(sWorld->getIntConfig(CONFIG_START_PLAYER_LEVEL)));
    player->SetPlayerFlag(PLAYER_FLAGS_NO_XP_GAIN);
    SendState(player);
}

bool EventWowProgress::Upgrade(Player* player, int32 index)
{
    ProgressSlot* slot = GetSlot(player);
    EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
    if (!character || GetPoints(player, slot, *character) <= 0)
        return false;

    uint8 const level = player->GetLevel();
    if (index < 0)
    {
        uint8 const attributeMax = GetAttributeMax(*character, slot->MaxLevel);
        if (slot->AttributeRank >= GetAttributeMaxNow(attributeMax, level))
            return false;

        ++slot->AttributeRank;
        ApplyAttributes(player, *character, 1);
        SendState(player);
        return true;
    }

    std::size_t const i = std::size_t(index);
    if (i >= character->Spells.size() || !UsesPoints(character->SpellKinds[i]))
        return false;

    uint32 const first = character->Spells[i];
    uint8 const rank = slot->Ranks[i];
    if (rank >= GetMaxRankNow(character->SpellKinds[i], GetTotalRanks(first), level, slot->MaxLevel))
        return false;

    uint32 const next = sSpellMgr->GetSpellWithRank(first, rank + 1, true);
    if (!next)
        return false;

    EventWowDisguise::ReplaceSpell(player, rank ? sSpellMgr->GetSpellWithRank(first, rank) : 0, next);
    slot->Ranks[i] = rank + 1;
    SendState(player);
    return true;
}

void EventWowProgress::SendState(Player* player)
{
    ProgressSlot const* slot = GetSlot(player);
    EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
    if (!character)
    {
        EventWowMessage("MATCH_ABILITIES").Add(0).Send(player);
        return;
    }

    uint8 const level = player->GetLevel();
    int32 const points = GetPoints(player, slot, *character);
    uint8 const attributeMax = GetAttributeMax(*character, slot->MaxLevel);
    bool const attributeUp = points > 0 && slot->AttributeRank < GetAttributeMaxNow(attributeMax, level);

    std::string attributeStats;
    for (auto const& [stat, value] : character->AttributeStats)
    {
        if (!attributeStats.empty())
            attributeStats += ',';
        attributeStats += std::string(EventWowStats::GetKey(stat)) + ':' + std::to_string(value);
    }

    EventWowMessage message("MATCH_ABILITIES");
    message.Add(level).Add(slot->MaxLevel).Add(points).Add(slot->AttributeRank).Add(attributeMax).Add(attributeUp ? 1 : 0)
        .Add(attributeStats).Add(static_cast<uint32>(character->Spells.size()));

    for (std::size_t i = 0; i < character->Spells.size(); ++i)
    {
        uint32 const first = character->Spells[i];
        EventWowAbilityKind const kind = character->SpellKinds[i];
        uint8 const rank = slot->Ranks[i];
        uint8 const total = GetTotalRanks(first);
        uint8 const maxNow = GetMaxRankNow(kind, total, level, slot->MaxLevel);
        bool const canUp = points > 0 && UsesPoints(kind) && rank < maxNow;
        uint32 const current = rank ? sSpellMgr->GetSpellWithRank(first, rank) : 0;
        uint32 const next = rank < total ? sSpellMgr->GetSpellWithRank(first, rank + 1, true) : 0;

        message.Add(rank).Add(maxNow).Add(total).Add(canUp ? 1 : 0).Add(current).Add(next);
    }

    message.Send(player);
}

class EventWow_ProgressPlayerScript : public PlayerScript
{
public:
    EventWow_ProgressPlayerScript() : PlayerScript("EventWow_ProgressPlayerScript", {
        PLAYERHOOK_ON_LEVEL_CHANGED,
        PLAYERHOOK_ON_GIVE_EXP,
        PLAYERHOOK_CAN_LEARN_TALENT,
        PLAYERHOOK_ON_BEFORE_ACHI_COMPLETE,
        PLAYERHOOK_CAN_GIVE_MAIL_REWARD_AT_GIVE_LEVEL,
        PLAYERHOOK_ON_LOGIN
    }) { }

    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        ProgressSlot* slot = GetSlot(player);
        EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
        if (!character)
            return;

        // El bono de descanso no pasa por OnPlayerGiveXP y podria pasarse del maximo
        if (player->GetLevel() > slot->MaxLevel)
        {
            EventWowProgress::SetLevel(player, slot->MaxLevel);
            return;
        }

        UpdateAutomatic(player, slot, *character);
        EventWowProgress::SendState(player);
    }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
    {
        ProgressSlot const* slot = GetSlot(player);
        if (!slot)
            return;

        amount = std::min(uint32(float(amount) * slot->XpRate), GetXpToMaxLevel(player, slot->MaxLevel));
    }

    // Los talentos no existen en EventWow (el motor da puntos desde nivel 10)
    bool OnPlayerCanLearnTalent(Player* player, TalentEntry const* /*talent*/, uint32 /*rank*/) override
    {
        return !sEventWowConfig.Enabled || EventWowDevMode::IsActive(player);
    }

    bool OnPlayerBeforeAchievementComplete(Player* player, AchievementEntry const* /*achievement*/) override
    {
        return !EventWowProgress::IsActive(player);
    }

    bool OnPlayerCanGiveMailRewardAtGiveLevel(Player* /*player*/, uint8 /*level*/) override
    {
        return !sEventWowConfig.Enabled;
    }

    // Se desconecto a mitad de partida: el nivel de partida quedo guardado
    void OnPlayerLogin(Player* player) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        uint8 const baseLevel = uint8(sWorld->getIntConfig(CONFIG_START_PLAYER_LEVEL));
        if (player->GetLevel() != baseLevel)
            EventWowProgress::SetLevel(player, baseLevel);
    }
};

void AddSC_eventwow_progress()
{
    new EventWow_ProgressPlayerScript();

    // UPGRADE <casilla 0..n-1 | attr>
    EventWowProtocol::RegisterHandler("UPGRADE", [](Player* player, EventWowProtocol::Args const& args)
    {
        if (args.empty())
            return;

        if (args[0] == "attr")
            EventWowProgress::Upgrade(player, -1);
        else if (Optional<uint32> slot = Acore::StringTo<uint32>(args[0]))
            EventWowProgress::Upgrade(player, int32(*slot));
    });

    // Tras /reload el cliente pierde el estado
    EventWowProtocol::RegisterConnectListener([](Player* player)
    {
        if (sEventWowConfig.Enabled)
            EventWowProgress::SendState(player);
    });
}
