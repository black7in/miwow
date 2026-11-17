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
#include "Item.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "TemporarySummon.h"
#include <algorithm>
#include <array>
#include <cmath>
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
        // Disparo automatico (AutoAttackSpell) pedido con el clic derecho o la casilla 1: el core lo corta al
        // moverse o al lanzar otro hechizo; se vuelve a lanzar al pararse mientras siga con ese objetivo
        ObjectGuid AutoAttackTarget;
        uint32 AutoAttackBusyMs = 0; // > 0: hace poco se movia o lanzaba (si el disparo falta, se reanuda)
        // Armas equipadas de verdad mientras dura el disfraz (EventWowWeapons::Equip)
        EventWowWeapons::EquipState Weapons;
        // Celeridad de ataque aplicada por la agilidad (UpdateAgilityHaste), % por tipo de ataque
        std::array<float, 3> AgilityHaste = { };
        uint32 AgilityHasteTimer = 0;
    };

    constexpr std::array<WeaponAttackType, 3> AgilityHasteTypes = { BASE_ATTACK, OFF_ATTACK, RANGED_ATTACK };
    constexpr uint32 AgilityHasteInterval = 250; // ms entre recalculos

    void ApplyAgilityHaste(Player* player, WeaponAttackType type, float pct, bool apply)
    {
        if (pct > 0.0f)
            player->ApplyAttackTimePercentMod(type, pct, apply);
    }

    // Regla propia (docs/heroes.md sec. 4 regla 4): agilidad extra -> celeridad de todos los ataques automaticos,
    // Max x agi / (agi + Half), con un suelo de AttackMinInterval ms contando el resto de celeridad (objetos,
    // auras). Mismo mecanismo que las auras nativas de celeridad (el cliente recibe el intervalo nuevo).
    void UpdateAgilityHaste(Player* player, DisguiseSlot* slot)
    {
        float const agility = std::max(0.0f, player->GetStat(STAT_AGILITY) - player->GetCreateStat(STAT_AGILITY));
        float const wanted = sEventWowConfig.AgilityHasteMax * agility / (agility + sEventWowConfig.AgilityHasteHalf);
        float const minInterval = float(sEventWowConfig.AttackMinInterval);

        for (std::size_t i = 0; i < AgilityHasteTypes.size(); ++i)
        {
            WeaponAttackType const type = AgilityHasteTypes[i];
            float const current = slot->AgilityHaste[i];
            float pct = wanted;
            if (minInterval > 0.0f)
            {
                // Intervalo con todo lo demas (sin nuestra parte): +X % divide el intervalo entre (1 + X/100)
                float const interval = player->GetFloatValue(UNIT_FIELD_BASEATTACKTIME + AsUnderlyingType(type)) *
                    (100.0f + current) / 100.0f;
                pct = std::min(pct, std::max(0.0f, (interval / minInterval - 1.0f) * 100.0f));
            }

            if (std::fabs(pct - current) < 0.1f)
                continue;

            ApplyAgilityHaste(player, type, current, false);
            ApplyAgilityHaste(player, type, pct, true);
            slot->AgilityHaste[i] = pct;
        }
    }

    // Margen tras moverse/lanzar en el que un disparo desaparecido se reanuda (el core lo corta en su Update)
    constexpr uint32 AutoAttackResumeWindow = 600;

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

    // Equipa las armas de la ficha que falten (tambien repone una destruida). true si equipo alguna.
    bool ApplyWeapons(Player* player, DisguiseSlot* slot, EventWowCharacterInfo const& character)
    {
        return EventWowWeapons::Equip(player, character.WeaponMainHand, character.WeaponOffHand, character.WeaponRanged,
            slot->Weapons);
    }

    // Dano por golpe cuerpo a cuerpo de la ficha a su nivel, para un arma de esa velocidad (ms): los numeros de la
    // ficha son a AttackSpeed y se escalan para dar el mismo dano por segundo (arma lenta = golpes mas fuertes)
    void GetMeleeDamage(Player const* player, EventWowCharacterInfo const& character, uint32 delay, float& minDamage, float& maxDamage)
    {
        float const bonus = character.AttackPerLevel * float(std::max<int32>(0, int32(player->GetLevel()) - 1));
        float const scale = delay ? float(delay) / float(character.AttackSpeed) : 1.0f;
        minDamage = (character.AttackMin + bonus) * scale;
        maxDamage = (character.AttackMax + bonus) * scale;
    }

    // Ataque basico de la ficha. Sin AttackSpeed no se toca nada. Se repite al cambiar de nivel y al reponer un arma.
    //  - Disparo automatico: con arma de distancia el intervalo es el suyo (lo pone el core al equiparla); sin ella
    //    (lanzadores), AttackSpeed. El dano es del hechizo.
    //  - Cuerpo a cuerpo: dano de la ficha en cada mano con arma (la izquierda con la penalizacion nativa); el
    //    intervalo es el del arma o, sin arma en la derecha, AttackSpeed.
    void ApplyAttack(Player* player, EventWowCharacterInfo const& character)
    {
        if (!character.HasAttack())
            return;

        if (character.AutoAttackSpell)
        {
            if (!player->GetWeaponForAttack(RANGED_ATTACK))
                player->SetAttackTime(RANGED_ATTACK, character.AttackSpeed);
            return;
        }

        for (WeaponAttackType attackType : { BASE_ATTACK, OFF_ATTACK })
        {
            Item const* weapon = player->GetWeaponForAttack(attackType);
            if (attackType == OFF_ATTACK && !weapon)
                continue;

            uint32 const delay = weapon ? weapon->GetTemplate()->Delay : character.AttackSpeed;
            float minDamage = 0.0f;
            float maxDamage = 0.0f;
            GetMeleeDamage(player, character, delay, minDamage, maxDamage);
            player->SetBaseWeaponDamage(attackType, MINDAMAGE, minDamage);
            player->SetBaseWeaponDamage(attackType, MAXDAMAGE, maxDamage);
            player->SetAttackTime(attackType, delay);
            player->UpdateDamagePhysical(attackType);
        }
    }

    // Como sin arma (las armas del disfraz ya se destruyeron: EventWowWeapons::Unequip)
    void RestoreAttack(Player* player, EventWowCharacterInfo const& character)
    {
        if (!character.HasAttack())
            return;

        if (player->GetCurrentSpell(CURRENT_AUTOREPEAT_SPELL))
            player->InterruptSpell(CURRENT_AUTOREPEAT_SPELL);

        player->SetBaseWeaponDamage(BASE_ATTACK, MINDAMAGE, BASE_MINDAMAGE);
        player->SetBaseWeaponDamage(BASE_ATTACK, MAXDAMAGE, BASE_MAXDAMAGE);
        player->SetAttackTime(BASE_ATTACK, BASE_ATTACK_TIME);
        player->SetAttackTime(RANGED_ATTACK, BASE_ATTACK_TIME);
        player->UpdateDamagePhysical(BASE_ATTACK);
    }

    // Disparo automatico contra el objetivo (clic derecho o reanudar). true si se lanzo.
    bool StartAutoAttack(Player* player, DisguiseSlot* slot, EventWowCharacterInfo const& character, Unit* victim)
    {
        slot->AutoAttackTarget = victim->GetGUID();
        slot->AutoAttackBusyMs = 0;
        if (Spell const* current = player->GetCurrentSpell(CURRENT_AUTOREPEAT_SPELL))
            if (current->GetSpellInfo()->Id == character.AutoAttackSpell && current->m_targets.GetUnitTargetGUID() == victim->GetGUID())
                return true;

        return player->CastSpell(victim, character.AutoAttackSpell, false) == SPELL_CAST_OK;
    }

    // Cada actualizacion del jugador: reanuda el disparo cortado por moverse o por lanzar otro hechizo. Si falta
    // estando quieto y sin lanzar (lo cancelo el jugador, Esc, objetivo fuera de alcance...) se olvida.
    void UpdateAutoAttack(Player* player, DisguiseSlot* slot, uint32 diff)
    {
        EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId);
        if (!character || !character->AutoAttackSpell)
            return;

        bool const busy = player->isMoving() || player->IsNonMeleeSpellCast(false, false, true);

        // El disparo en curso (desde la barra o el clic derecho) marca el objetivo
        if (Spell const* current = player->GetCurrentSpell(CURRENT_AUTOREPEAT_SPELL))
        {
            if (current->GetSpellInfo()->Id == character->AutoAttackSpell)
            {
                slot->AutoAttackTarget = current->m_targets.GetUnitTargetGUID();
                // Moviendose: el core lo corta en esta misma actualizacion
                slot->AutoAttackBusyMs = busy ? AutoAttackResumeWindow : 0;
            }
            else
                slot->AutoAttackTarget.Clear();
            return;
        }

        if (!slot->AutoAttackTarget)
            return;

        if (!player->IsAlive() || player->GetTarget() != slot->AutoAttackTarget)
        {
            slot->AutoAttackTarget.Clear();
            return;
        }

        if (busy)
        {
            slot->AutoAttackBusyMs = AutoAttackResumeWindow;
            return;
        }

        if (!slot->AutoAttackBusyMs)
        {
            slot->AutoAttackTarget.Clear();
            return;
        }

        slot->AutoAttackBusyMs = diff >= slot->AutoAttackBusyMs ? 0 : slot->AutoAttackBusyMs - diff;
        Unit* victim = ObjectAccessor::GetUnit(*player, slot->AutoAttackTarget);
        if (!victim || !victim->IsAlive() || !player->IsValidAttackTarget(victim) || !StartAutoAttack(player, slot, *character, victim))
            slot->AutoAttackTarget.Clear();
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
    // Antes de medir los maximos nativos (las armas no llevan stats). Su dano lo fija ApplyAttack al final.
    ApplyWeapons(player, slot, character);

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

    ApplyAttack(player, character);

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
    EventWowWeapons::EquipState weapons = slot->Weapons;
    std::array<float, 3> const agilityHaste = slot->AgilityHaste;
    EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId);
    // Primero fuera el slot: a partir de aqui los hooks ya no fuerzan nada
    player->CustomData.Erase(DisguiseKey);

    for (std::size_t i = 0; i < AgilityHasteTypes.size(); ++i)
        ApplyAgilityHaste(player, AgilityHasteTypes[i], agilityHaste[i], false);

    DismissVehicle(player, vehicleGuid);
    DismissSummons(player);

    EventWowWeapons::Unequip(player, weapons);
    if (character)
        RestoreAttack(player, *character);

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

    // Puntos de atributos y nivel base (si iba con progresion)
    EventWowProgress::Stop(player);

    LOG_DEBUG("module.eventwow", "EventWow: {} sin disfraz", player->GetName());
    SendState(player);
}

void EventWowDisguise::Update(Player* player)
{
    DisguiseSlot* slot = GetSlot(player);
    if (!slot || !player->IsInWorld() || !player->IsAlive() || player->IsBeingTeleported())
        return;

    EventWowCharacterInfo const* character = sEventWowCharacters.Get(slot->CharacterId);
    if (!character)
        return;

    // Un arma que ya no esta (destruida, o el core la quito) se vuelve a equipar
    if (ApplyWeapons(player, slot, *character))
        ApplyAttack(player, *character);

    if (!character->VehicleEntry || slot->VehicleFailed || player->GetVehicle() || EventWowDevMode::IsActive(player))
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
        PLAYERHOOK_ON_APPLY_WEAPON_DAMAGE,
        PLAYERHOOK_CAN_UNEQUIP_ITEM,
        PLAYERHOOK_ON_BEFORE_LOGOUT,
        PLAYERHOOK_ON_LEVEL_CHANGED,
        PLAYERHOOK_CAN_ATTACK_SWING,
        PLAYERHOOK_ON_UPDATE
    }) { }

    // El dano cuerpo a cuerpo sube con el nivel; la habilidad de arma anadida, tambien (tabla de golpe)
    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        DisguiseSlot* slot = GetSlot(player);
        EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
        if (!character)
            return;

        EventWowWeapons::UpdateSkills(player, slot->Weapons);
        ApplyAttack(player, *character);
    }

    // Si el core vuelve a aplicar un arma cuerpo a cuerpo (p. ej. al recalcular todas las bonificaciones), su dano
    // es el de la ficha, no el del objeto. (El intervalo lo vuelve a fijar el core al del arma: es el mismo.)
    void OnPlayerApplyWeaponDamage(Player* player, uint8 slot, ItemTemplate const* proto, float& minDamage, float& maxDamage,
        uint8 damageIndex) override
    {
        if (slot != EQUIPMENT_SLOT_MAINHAND && slot != EQUIPMENT_SLOT_OFFHAND)
            return;

        EventWowCharacterInfo const* character = EventWowDisguise::Get(player);
        if (!character || !character->HasAttack() || character->AutoAttackSpell)
            return;

        if (damageIndex)
        {
            minDamage = maxDamage = 0.0f;
            return;
        }

        GetMeleeDamage(player, *character, proto->Delay, minDamage, maxDamage);
    }

    // El disfraz se quita ANTES de guardar el personaje (OnPlayerLogout llega despues de SaveToDB): si no, las
    // armas equipadas se guardan y al hacer login el core no las puede cargar (el druida no tiene la habilidad) y
    // las manda por correo. Vale para partidas (su RemovePlayer de despues ya no encuentra disfraz) y .eventwow hero.
    void OnPlayerBeforeLogout(Player* player) override
    {
        EventWowDisguise::Remove(player);
    }

    // Las armas del disfraz no se pueden quitar, cambiar ni destruir
    bool OnPlayerCanUnequipItem(Player* player, uint16 pos, bool /*swap*/) override
    {
        DisguiseSlot const* slot = GetSlot(player);
        if (!slot || (pos >> 8) != INVENTORY_SLOT_BAG_0)
            return true;

        return !EventWowWeapons::IsEquippedBy(player, slot->Weapons, uint8(pos & 0xFF));
    }

    // Clic derecho / "Atacar" sobre un enemigo: los heroes a distancia y lanzadores disparan en vez de golpear
    bool OnPlayerCanAttackSwing(Player* player, Unit* victim) override
    {
        DisguiseSlot* slot = GetSlot(player);
        EventWowCharacterInfo const* character = slot ? sEventWowCharacters.Get(slot->CharacterId) : nullptr;
        if (!character || !character->AutoAttackSpell || !victim)
            return true;

        StartAutoAttack(player, slot, *character, victim);
        return false;
    }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        if (DisguiseSlot* slot = GetSlot(player))
        {
            UpdateAutoAttack(player, slot, diff);

            slot->AgilityHasteTimer += diff;
            if (slot->AgilityHasteTimer >= AgilityHasteInterval)
            {
                slot->AgilityHasteTimer = 0;
                UpdateAgilityHaste(player, slot);
            }
        }
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
