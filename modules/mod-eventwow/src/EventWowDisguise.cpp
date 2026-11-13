#include "EventWowDisguise.h"
#include "DBCStores.h"
#include "DataMap.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowProtocol.h"
#include "EventWowStats.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "TemporarySummon.h"
#include <algorithm>
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
        // Vehiculo invocado (en el mapa del jugador)
        ObjectGuid VehicleGuid;
        // No se pudo invocar: no se reintenta (evita repetirlo en cada Update)
        bool VehicleFailed = false;
        // Maximos nativos del contenedor al disfrazarse (sin las stats del personaje). Lo que el motor sume
        // por encima (stats del personaje, libros, auras) se suma a la vida/poder base del personaje.
        float NativeHealth = 0.0f;
        float NativePower = 0.0f;
    };

    // Mas lejos que esto (reaparicion, teleport) se invoca otro vehiculo en vez de subir al antiguo
    constexpr float VehicleMaxDistance = 10.0f;

    void SummonVehicle(Player* player, DisguiseSlot* slot, uint32 entry)
    {
        TempSummon* vehicle = player->SummonCreature(entry, *player, TEMPSUMMON_MANUAL_DESPAWN);
        if (!vehicle || !vehicle->IsVehicle())
        {
            if (vehicle)
                vehicle->DespawnOrUnsummon();

            LOG_ERROR("module.eventwow", "EventWow: no se pudo invocar el vehiculo {} para {}", entry, player->GetName());
            slot->VehicleGuid.Clear();
            slot->VehicleFailed = true;
            return;
        }

        // Amistoso para su conductor (y para su equipo cuando haya equipos)
        vehicle->SetFaction(player->GetFaction());
        slot->VehicleGuid = vehicle->GetGUID();
        player->EnterVehicle(vehicle, 0);
    }

    // Baja al jugador y hace desaparecer el vehiculo (si sigue en su mapa)
    void DismissVehicle(Player* player, ObjectGuid vehicleGuid)
    {
        if (player->GetVehicle())
            player->ExitVehicle();

        if (!vehicleGuid)
            return;

        if (Creature* vehicle = ObjectAccessor::GetCreature(*player, vehicleGuid))
            vehicle->DespawnOrUnsummon();
    }

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

    // CharacterId aun 0: los hooks no actuan hasta medir los maximos nativos
    DisguiseSlot* slot = player->CustomData.GetDefault<DisguiseSlot>(DisguiseKey);

    if (character.DisplayId)
    {
        player->SetNativeDisplayId(character.DisplayId);
        player->RestoreDisplayId();
    }

    player->SetObjectScale(character.Scale);

    Powers const power = Powers(character.PowerType);
    if (player->getPowerType() != power)
        player->setPowerType(power);

    player->UpdateMaxHealth();
    player->UpdateMaxPower(power);
    slot->NativeHealth = float(player->GetMaxHealth());
    slot->NativePower = float(player->GetMaxPower(power));
    slot->CharacterId = character.Id;

    // Stats del personaje (como un objeto equipado): el motor recalcula todo lo derivado
    for (auto const& [stat, value] : character.Stats)
        EventWowStats::Add(player, stat, value);

    // Con el slot completo, los hooks fijan los maximos: base del personaje + lo que sumen las stats
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

    if (character.VehicleEntry)
        SummonVehicle(player, slot, character.VehicleEntry);

    LOG_DEBUG("module.eventwow", "EventWow: {} disfrazado de {} ({})", player->GetName(), character.Name, character.Id);
    SendState(player);
}

void EventWowDisguise::Remove(Player* player)
{
    DisguiseSlot const* slot = GetSlot(player);
    if (!slot)
        return;

    std::vector<uint32> const spells = slot->AddedSpells;
    ObjectGuid const vehicleGuid = slot->VehicleGuid;
    EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId);
    // Primero fuera el slot: a partir de aqui los hooks ya no fuerzan nada
    player->CustomData.Erase(DisguiseKey);

    DismissVehicle(player, vehicleGuid);

    // Solo las stats del personaje; las de la partida (libros...) las quita EventWowStats::Reset
    if (character)
        for (auto const& [stat, value] : character->Stats)
            EventWowStats::Add(player, stat, -value);

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

void EventWowDisguise::Update(Player* player)
{
    DisguiseSlot* slot = GetSlot(player);
    if (!slot || slot->VehicleFailed || player->GetVehicle())
        return;

    EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId);
    if (!character || !character->VehicleEntry)
        return;

    if (!player->IsInWorld() || !player->IsAlive() || player->IsBeingTeleported() || EventWowDevMode::IsActive(player))
        return;

    Creature* vehicle = slot->VehicleGuid ? ObjectAccessor::GetCreature(*player, slot->VehicleGuid) : nullptr;
    if (vehicle && (!vehicle->IsAlive() || vehicle->GetExactDist(player) > VehicleMaxDistance))
    {
        vehicle->DespawnOrUnsummon();
        vehicle = nullptr;
    }

    if (vehicle)
        player->EnterVehicle(vehicle, 0);
    else
        SummonVehicle(player, slot, character->VehicleEntry);
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

    // Vida maxima = vida base del personaje + lo que el motor sume sobre el contenedor sin disfraz
    // (Aguante y vida de las stats, auras...). Asi Health es la base y las stats la suben de forma nativa.
    void OnPlayerAfterUpdateMaxHealth(Player* player, float& value) override
    {
        DisguiseSlot const* slot = GetSlot(player);
        EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
        if (character && character->Health)
            value = std::max(1.0f, float(character->Health) + value - slot->NativeHealth);
    }

    // Igual para el poder del personaje (Intelecto y mana de las stats suben el mana)
    void OnPlayerAfterUpdateMaxPower(Player* player, Powers& power, float& value) override
    {
        DisguiseSlot const* slot = GetSlot(player);
        EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
        if (character && character->MaxPower && power == Powers(character->PowerType))
            value = std::max(0.0f, float(character->MaxPower) + value - slot->NativePower);
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
        // Desencadenados y los de objetos (pociones de la tienda...) siempre se permiten
        if (res != SPELL_CAST_OK || spell->IsTriggered() || spell->m_castItemGUID)
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
