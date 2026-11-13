#include "EventWowDisguise.h"
#include "DBCStores.h"
#include "DataMap.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowProtocol.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Spell.h"
#include "SpellInfo.h"

namespace
{
    std::string const DisguiseKey = "EventWowDisguise";

    // Lo leen los hooks de stats y de hechizos (hilos de mapa): solo datos del propio jugador
    struct DisguiseSlot : public DataMap::Base
    {
        uint32 CharacterId = 0;
        // Hechizos que anadio el disfraz (los que el personaje ya conocia no se le quitan)
        std::vector<uint32> AddedSpells;
    };

    DisguiseSlot* GetSlot(Player const* player)
    {
        return player->CustomData.Get<DisguiseSlot>(DisguiseKey);
    }

    Powers GetClassPowerType(Player const* player)
    {
        ChrClassesEntry const* entry = sChrClassesStore.LookupEntry(player->getClass());
        return entry ? Powers(entry->powerType) : POWER_MANA;
    }
}

EventWowCharacterInfo const* EventWowDisguise::Get(Player const* player)
{
    DisguiseSlot const* slot = GetSlot(player);
    return slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
}

void EventWowDisguise::Apply(Player* player, EventWowCharacterInfo const& character)
{
    if (GetSlot(player))
        Remove(player);

    DisguiseSlot* slot = player->CustomData.GetDefault<DisguiseSlot>(DisguiseKey);
    slot->CharacterId = character.Id;

    if (character.DisplayId)
    {
        player->SetNativeDisplayId(character.DisplayId);
        player->RestoreDisplayId();
    }

    player->SetObjectScale(character.Scale);

    Powers const power = Powers(character.PowerType);
    if (player->getPowerType() != power)
        player->setPowerType(power);

    // Con el slot ya puesto, los hooks fijan los maximos
    player->UpdateMaxHealth();
    player->UpdateMaxPower(power);
    player->SetFullHealth();
    player->SetPower(power, power == POWER_RAGE ? 0 : player->GetMaxPower(power));

    for (uint32 spellId : character.Spells)
    {
        if (player->HasSpell(spellId))
            continue;

        player->learnSpell(spellId, true);
        slot->AddedSpells.push_back(spellId);
    }

    LOG_DEBUG("module.eventwow", "EventWow: {} disfrazado de {} ({})", player->GetName(), character.Name, character.Id);
    SendState(player);
}

void EventWowDisguise::Remove(Player* player)
{
    DisguiseSlot const* slot = GetSlot(player);
    if (!slot)
        return;

    std::vector<uint32> const spells = slot->AddedSpells;
    // Primero fuera el slot: a partir de aqui los hooks ya no fuerzan nada
    player->CustomData.Erase(DisguiseKey);

    for (uint32 spellId : spells)
        player->removeSpell(spellId, SPEC_MASK_ALL, true);

    // Display nativo de la raza/sexo; RestoreDisplayId respeta las auras de transformacion que queden
    player->InitDisplayIds();
    player->RestoreDisplayId();
    player->SetObjectScale(1.0f);

    Powers const disguisePower = player->getPowerType();
    Powers const classPower = GetClassPowerType(player);
    if (disguisePower != classPower)
    {
        player->setPowerType(classPower);
        player->UpdateMaxPower(disguisePower);
    }

    player->UpdateMaxHealth();
    player->UpdateMaxPower(classPower);

    LOG_DEBUG("module.eventwow", "EventWow: {} sin disfraz", player->GetName());
    SendState(player);
}

void EventWowDisguise::SendState(Player* player)
{
    EventWowCharacterInfo const* character = Get(player);
    if (!character)
    {
        EventWowMessage("MATCH_CHARACTER").Add(0).Send(player);
        return;
    }

    EventWowMessage message("MATCH_CHARACTER");
    message.Add(character->Id).Add(character->Name).Add(character->Icon);
    for (uint32 spellId : character->Spells)
        message.Add(spellId);

    message.Send(player);
}

class EventWow_DisguisePlayerScript : public PlayerScript
{
public:
    EventWow_DisguisePlayerScript() : PlayerScript("EventWow_DisguisePlayerScript", {
        PLAYERHOOK_ON_AFTER_UPDATE_MAX_HEALTH,
        PLAYERHOOK_ON_AFTER_UPDATE_MAX_POWER
    }) { }

    void OnPlayerAfterUpdateMaxHealth(Player* player, float& value) override
    {
        if (EventWowCharacterInfo const* character = EventWowDisguise::Get(player))
            if (character->Health)
                value = float(character->Health);
    }

    void OnPlayerAfterUpdateMaxPower(Player* player, Powers& power, float& value) override
    {
        if (EventWowCharacterInfo const* character = EventWowDisguise::Get(player))
            if (character->MaxPower && power == Powers(character->PowerType))
                value = float(character->MaxPower);
    }
};

// Disfrazado solo se lanzan los hechizos del personaje (no los del druida contenedor)
class EventWow_DisguiseSpellScript : public AllSpellScript
{
public:
    EventWow_DisguiseSpellScript() : AllSpellScript("EventWow_DisguiseSpellScript", {
        ALLSPELLHOOK_ON_SPELL_CHECK_CAST
    }) { }

    void OnSpellCheckCast(Spell* spell, bool /*strict*/, SpellCastResult& res) override
    {
        if (res != SPELL_CAST_OK || spell->IsTriggered())
            return;

        Player const* player = spell->GetCaster() ? spell->GetCaster()->ToPlayer() : nullptr;
        if (!player || EventWowDevMode::IsActive(player))
            return;

        EventWowCharacterInfo const* character = EventWowDisguise::Get(player);
        if (character && !character->HasSpell(spell->GetSpellInfo()->Id))
            res = SPELL_FAILED_SPELL_UNAVAILABLE;
    }
};

void AddSC_eventwow_disguise()
{
    new EventWow_DisguisePlayerScript();
    new EventWow_DisguiseSpellScript();

    // Tras /reload el cliente pierde la barra: se reenvia
    EventWowProtocol::RegisterConnectListener([](Player* player)
    {
        if (sEventWowConfig.Enabled)
            EventWowDisguise::SendState(player);
    });
}
