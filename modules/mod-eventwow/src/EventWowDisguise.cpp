#include "EventWowDisguise.h"
#include "Chat.h"
#include "CommandScript.h"
#include "DBCStores.h"
#include "DataMap.h"
#include "EventWowCharacters.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowProgress.h"
#include "EventWowProtocol.h"
#include "EventWowStats.h"
#include "EventWowWeapons.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "TemporarySummon.h"
#include <algorithm>
#include <cstdlib>
#include <vector>
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

    // Invocaciones de los hechizos del heroe (propios, >= 9500000): se van con el disfraz
    void DismissSummons(Player* player)
    {
        std::vector<TempSummon*> summons;
        for (Unit* controlled : player->m_Controlled)
            if (controlled->IsSummon() && controlled->GetUInt32Value(UNIT_CREATED_BY_SPELL) >= 9500000)
                summons.push_back(controlled->ToTempSummon());

        for (TempSummon* summon : summons)
            summon->UnSummon();
    }

    DisguiseSlot* GetSlot(Player const* player)
    {
        return player->CustomData.Get<DisguiseSlot>(DisguiseKey);
    }

    void ApplyWeapons(Player* player, EventWowCharacterInfo const& character)
    {
        EventWowWeapons::SetVisible(player, EQUIPMENT_SLOT_MAINHAND, character.WeaponMainHand);
        EventWowWeapons::SetVisible(player, EQUIPMENT_SLOT_OFFHAND, character.WeaponOffHand);
        EventWowWeapons::SetVisible(player, EQUIPMENT_SLOT_RANGED, 0);
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

void EventWowDisguise::Apply(Player* player, EventWowCharacterInfo const& character, bool progression)
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
    ApplyWeapons(player, character);

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

    for (std::size_t i = 0; i < character.Spells.size(); ++i)
    {
        uint32 const spellId = character.Spells[i];
        if (progression && character.SpellKinds[i] != EventWowAbilityKind::Fixed)
            continue;

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

void EventWowDisguise::ReplaceSpell(Player* player, uint32 oldSpell, uint32 newSpell)
{
    DisguiseSlot* slot = GetSlot(player);
    if (!slot)
        return;

    if (oldSpell)
    {
        auto itr = std::find(slot->AddedSpells.begin(), slot->AddedSpells.end(), oldSpell);
        if (itr != slot->AddedSpells.end())
        {
            slot->AddedSpells.erase(itr);
            player->removeSpell(oldSpell, SPEC_MASK_ALL, true);
        }
    }

    if (newSpell && !player->HasSpell(newSpell))
    {
        player->learnSpell(newSpell, true);
        slot->AddedSpells.push_back(newSpell);
    }
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
    DismissSummons(player);

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
    EventWowWeapons::RestoreEquipped(player);

    Powers const disguisePower = player->getPowerType();
    Powers const classPower = GetClassPowerType(player);
    if (disguisePower != classPower)
    {
        player->setPowerType(classPower);
        player->UpdateMaxPower(disguisePower);
    }

    player->UpdateMaxHealth();
    player->UpdateMaxPower(classPower);

    // Puntos de atributos y nivel base (si iba con progresion)
    EventWowProgress::Stop(player);

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
        PLAYERHOOK_ON_AFTER_UPDATE_MAX_POWER,
        PLAYERHOOK_ON_AFTER_SET_VISIBLE_ITEM_SLOT
    }) { }

    // Si el core vuelve a escribir una ranura de armas (equipar/desequipar), se repone la del disfraz
    void OnPlayerAfterSetVisibleItemSlot(Player* player, uint8 slot, Item* /*item*/) override
    {
        if (slot != EQUIPMENT_SLOT_MAINHAND && slot != EQUIPMENT_SLOT_OFFHAND && slot != EQUIPMENT_SLOT_RANGED)
            return;

        if (EventWowCharacterInfo const* character = EventWowDisguise::Get(player))
            ApplyWeapons(player, *character);
    }

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

// Probar un personaje sin partida (GM), sobre el jugador seleccionado o uno mismo:
//   .eventwow hero <id>    disfraza con esa ficha (modelo, armas, stats, hechizos y barra del HUD)
//   .eventwow hero <id> <nivel>  igual, con progresion (docs/heroes.md): nivel 1-30 y puntos de habilidad
//   .eventwow hero level <n>     cambia el nivel con progresion activa (tambien vale .levelup)
//   .eventwow hero off     quita el disfraz
//   .eventwow hero list    fichas cargadas
// Fuera de partida nada lo quita salvo "off", entrar en una partida o el logout (no se guarda nada).
// Con .dev on se puede lanzar todo; sin modo dev, solo los hechizos de la ficha.
using namespace Acore::ChatCommands;

class EventWow_DisguiseCommandScript : public CommandScript
{
public:
    EventWow_DisguiseCommandScript() : CommandScript("EventWow_DisguiseCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable eventwowTable =
        {
            { "hero", HandleHero, SEC_GAMEMASTER, Console::No }
        };
        static ChatCommandTable commandTable =
        {
            { "eventwow", eventwowTable }
        };
        return commandTable;
    }

    static constexpr uint8 TestMaxLevel = 30;

    static bool HandleHero(ChatHandler* handler, std::string arg, Optional<uint32> level)
    {
        if (arg == "list")
        {
            for (uint32 id : sEventWowCharacters.GetIds())
                if (EventWowCharacterInfo const* character = sEventWowCharacters.Get(id))
                    handler->PSendSysMessage("{} - {} ({} hechizos)", character->Id, character->Name, character->Spells.size());
            return true;
        }

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target)
            return false;

        if (arg == "level")
        {
            if (!level || !*level || *level > TestMaxLevel || !EventWowProgress::IsActive(target))
            {
                handler->SendErrorMessage("EventWow: uso .eventwow hero level <1-{}> (con un heroe con progresion)", TestMaxLevel);
                return false;
            }

            EventWowProgress::SetLevel(target, uint8(*level));
            return true;
        }

        if (arg == "off")
        {
            EventWowDisguise::Remove(target);
            handler->PSendSysMessage("EventWow: {} sin disfraz", target->GetName());
            return true;
        }

        uint32 const id = uint32(std::strtoul(arg.c_str(), nullptr, 10));
        EventWowCharacterInfo const* character = id ? sEventWowCharacters.Get(id) : nullptr;
        if (!character)
        {
            handler->SendErrorMessage("EventWow: uso .eventwow hero <id> [nivel] | level <n> | off | list (personaje '{}' no existe)", arg);
            return false;
        }

        if (level)
        {
            if (!*level || *level > TestMaxLevel)
            {
                handler->SendErrorMessage("EventWow: nivel 1-{}", TestMaxLevel);
                return false;
            }

            // Mismo orden que EventWowMatch::SetCharacter, con el nivel pedido
            EventWowDisguise::Remove(target);
            EventWowProgress::SetLevel(target, 1);
            EventWowDisguise::Apply(target, *character, true);
            EventWowProgress::Start(target, *character, TestMaxLevel, 1.0f);
            if (*level > 1)
                EventWowProgress::SetLevel(target, uint8(*level));
            handler->PSendSysMessage("EventWow: {} disfrazado de {} ({}) con progresion, nivel {}", target->GetName(),
                character->Name, character->Id, *level);
            return true;
        }

        EventWowDisguise::Apply(target, *character);
        handler->PSendSysMessage("EventWow: {} disfrazado de {} ({})", target->GetName(), character->Name, character->Id);
        return true;
    }
};

void AddSC_eventwow_disguise()
{
    new EventWow_DisguisePlayerScript();
    new EventWow_DisguiseSpellScript();
    new EventWow_DisguiseCommandScript();

    // Tras /reload el cliente pierde la barra: se reenvia
    EventWowProtocol::RegisterConnectListener([](Player* player)
    {
        if (sEventWowConfig.Enabled)
            EventWowDisguise::SendState(player);
    });
}
