// Hechizos de heroe que los efectos del Spell.dbc solos no pueden hacer (docs/hechizos.md). Los hechizos se
// generan con tools/spellgen; la clave `script` de la ficha los enlaza aqui (spell_script_names).
//
// Ademas, regla general para NUESTRAS invocaciones (hechizos >= 9500000 con efecto de invocacion):
//  - Si el efecto de invocacion lleva EffectTriggerSpell (clave `trigger` de la ficha, el efecto SUMMON no lo usa),
//    el invocado recibe ese aura: asi cada rango puede sacar una criatura mas fuerte con la misma entrada.
//  - Una invocacion CONTROLABLE nueva sustituye a las anteriores del mismo hechizo (cualquier rango) del mismo dueno:
//    p. ej. el necrofago permanente de Arthas se puede volver a levantar cuando esta a punto de morir. Los guardianes
//    no (varios por lanzamiento: lobos de Thrall, esqueletos de Kel'Thuzad...; se van al acabar su duracion).
//  - Un necrofago (26125) invocado por un jugador recibe las auras nativas de escala de mascota de caballero de la
//    Muerte (70 % de la fuerza y 30 % del aguante del dueno, spell_dk_pet_scaling). El core solo se las pone a las
//    mascotas permanentes (Pet.cpp, IsPet()), y nuestras invocaciones son temporales (no se guardan en BD).
#include "AllCreatureScript.h"
#include "SpellAuraEffects.h"
#include "SpellAuras.h"
#include "Creature.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include "TemporarySummon.h"
#include <algorithm>
#include <vector>

namespace
{
    constexpr uint32 FirstEventWowSpell = 9500000;

    enum EventWowHeroSpellIds : uint32
    {
        // Espiral de la muerte del caballero de la Muerte: dano (proyectil) y sanacion, con la cantidad que se pase
        SPELL_EVENTWOW_DEATH_COIL_DAMAGE = 47632,
        SPELL_EVENTWOW_DEATH_COIL_HEAL   = 47633,

        // Escala de mascota de caballero de la Muerte (spell_dk_pet_scaling)
        SPELL_EVENTWOW_DK_PET_SCALING_01 = 54566,
        SPELL_EVENTWOW_DK_PET_SCALING_02 = 51996,
        SPELL_EVENTWOW_DK_PET_SCALING_03 = 61697,

        NPC_EVENTWOW_RISEN_GHOUL = 26125,

        // Flecha negra de Sylvanas: esqueleto al morir el objetivo (data/spells/sylvanas.toml)
        SPELL_EVENTWOW_BLACK_ARROW_SKELETON = 9500423,
        // Reencarnacion de Cairne agotada (data/spells/comun.toml)
        SPELL_EVENTWOW_REINCARNATION_EXHAUSTED = 9509010
    };
}

// Espiral de la Muerte (Arthas): dana a un enemigo o sana a un aliado (cualquiera, no solo no-muertos) la misma
// cantidad (valor del efecto 1, un valor por rango).
class spell_eventwow_death_coil : public SpellScript
{
    PrepareSpellScript(spell_eventwow_death_coil);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_EVENTWOW_DEATH_COIL_DAMAGE, SPELL_EVENTWOW_DEATH_COIL_HEAL });
    }

    SpellCastResult CheckCast()
    {
        Unit* caster = GetCaster();
        Unit* target = GetExplTargetUnit();
        if (!target)
            return SPELL_FAILED_BAD_TARGETS;

        if (caster->IsFriendlyTo(target))
            return target->IsFullHealth() ? SPELL_FAILED_ALREADY_AT_FULL_HEALTH : SPELL_CAST_OK;

        if (!caster->IsValidAttackTarget(target))
            return SPELL_FAILED_BAD_TARGETS;

        return caster->isInFront(target) ? SPELL_CAST_OK : SPELL_FAILED_UNIT_NOT_INFRONT;
    }

    void HandleDummy(SpellEffIndex /*effIndex*/)
    {
        Unit* caster = GetCaster();
        Unit* target = GetHitUnit();
        if (!target)
            return;

        int32 amount = GetEffectValue();
        caster->CastCustomSpell(target, caster->IsFriendlyTo(target) ? SPELL_EVENTWOW_DEATH_COIL_HEAL : SPELL_EVENTWOW_DEATH_COIL_DAMAGE,
            &amount, nullptr, nullptr, true);
    }

    void Register() override
    {
        OnCheckCast += SpellCheckCastFn(spell_eventwow_death_coil::CheckCast);
        OnEffectHitTarget += SpellEffectFn(spell_eventwow_death_coil::HandleDummy, EFFECT_0, SPELL_EFFECT_DUMMY);
    }
};

// Flecha negra (Sylvanas): si el objetivo muere con el dano en el tiempo puesto, se levanta un esqueleto guardian en
// su sitio (9500423, 20 s). No con jugadores.
class spell_eventwow_black_arrow : public AuraScript
{
    PrepareAuraScript(spell_eventwow_black_arrow);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_EVENTWOW_BLACK_ARROW_SKELETON });
    }

    void HandleRemove(AuraEffect const* /*aurEff*/, AuraEffectHandleModes /*mode*/)
    {
        if (GetTargetApplication()->GetRemoveMode() != AURA_REMOVE_BY_DEATH)
            return;

        Unit* caster = GetCaster();
        Unit* target = GetTarget();
        if (!caster || target->IsPlayer())
            return;

        caster->CastSpell(target->GetPositionX(), target->GetPositionY(), target->GetPositionZ(),
            SPELL_EVENTWOW_BLACK_ARROW_SKELETON, true);
    }

    void Register() override
    {
        AfterEffectRemove += AuraEffectRemoveFn(spell_eventwow_black_arrow::HandleRemove, EFFECT_0, SPELL_AURA_PERIODIC_DAMAGE,
            AURA_EFFECT_HANDLE_REAL);
    }
};

// Reencarnacion (Cairne, pasiva): escudo infinito que solo actua ante un golpe mortal. Renace al instante con el
// valor del efecto 1 (% de vida) y queda "Reencarnacion agotada" el valor del efecto 2 (segundos). Como Burlar a la
// muerte del picaro (spell_rog_cheat_death).
class spell_eventwow_reincarnation : public AuraScript
{
    PrepareAuraScript(spell_eventwow_reincarnation);

    bool Validate(SpellInfo const* /*spellInfo*/) override
    {
        return ValidateSpellInfo({ SPELL_EVENTWOW_REINCARNATION_EXHAUSTED });
    }

    void CalculateAmount(AuraEffect const* /*aurEff*/, int32& amount, bool& /*canBeRecalculated*/)
    {
        // Infinito: el core empieza cada golpe con 0 absorbido y decide Absorb
        amount = -1;
    }

    void Absorb(AuraEffect* /*aurEff*/, DamageInfo& dmgInfo, uint32& absorbAmount)
    {
        Unit* target = GetTarget();
        if (dmgInfo.GetDamage() < target->GetHealth() || target->HasAura(SPELL_EVENTWOW_REINCARNATION_EXHAUSTED))
            return;

        absorbAmount = dmgInfo.GetDamage();

        int32 const healthPct = GetSpellInfo()->Effects[EFFECT_0].CalcValue();
        int32 const cooldown = GetSpellInfo()->Effects[EFFECT_1].CalcValue();
        target->SetHealth(std::max<uint32>(1, target->CountPctFromMaxHealth(healthPct)));

        // Lanzado (no anadido) para que se vea el efecto de Reencarnacion; la duracion es la del rango
        target->CastSpell(target, SPELL_EVENTWOW_REINCARNATION_EXHAUSTED, true);
        if (Aura* exhausted = target->GetAura(SPELL_EVENTWOW_REINCARNATION_EXHAUSTED))
        {
            exhausted->SetMaxDuration(cooldown * IN_MILLISECONDS);
            exhausted->SetDuration(cooldown * IN_MILLISECONDS);
        }
    }

    void Register() override
    {
        DoEffectCalcAmount += AuraEffectCalcAmountFn(spell_eventwow_reincarnation::CalculateAmount, EFFECT_0, SPELL_AURA_SCHOOL_ABSORB);
        OnEffectAbsorb += AuraEffectAbsorbFn(spell_eventwow_reincarnation::Absorb, EFFECT_0);
    }
};

class EventWow_HeroSummonScript : public AllCreatureScript
{
public:
    EventWow_HeroSummonScript() : AllCreatureScript("EventWow_HeroSummonScript") { }

    void OnCreatureAddWorld(Creature* creature) override
    {
        if (!creature->IsSummon())
            return;

        uint32 const spellId = creature->GetUInt32Value(UNIT_CREATED_BY_SPELL);
        if (spellId < FirstEventWowSpell)
            return;

        // Al terminar de entrar en el mundo (siguiente actualizacion de la criatura): auras con todo inicializado
        creature->m_Events.AddEventAtOffset([creature, spellId]()
        {
            Unit* summoner = creature->ToTempSummon()->GetSummonerUnit();
            if (!summoner || !summoner->IsPlayer())
                return;

            // Controlable: sustituye a las anteriores del mismo hechizo (mismo primer rango)
            if (creature->IsControllableGuardian())
            {
                uint32 const firstSpell = sSpellMgr->GetFirstSpellInChain(spellId);
                std::vector<TempSummon*> previous;
                for (Unit* controlled : summoner->m_Controlled)
                    if (controlled != creature && controlled->IsSummon() && controlled->GetEntry() == creature->GetEntry()
                        && sSpellMgr->GetFirstSpellInChain(controlled->GetUInt32Value(UNIT_CREATED_BY_SPELL)) == firstSpell)
                        previous.push_back(controlled->ToTempSummon());

                for (TempSummon* summon : previous)
                    summon->UnSummon();
            }

            if (creature->GetEntry() == NPC_EVENTWOW_RISEN_GHOUL)
                for (uint32 scaling : { SPELL_EVENTWOW_DK_PET_SCALING_01, SPELL_EVENTWOW_DK_PET_SCALING_02, SPELL_EVENTWOW_DK_PET_SCALING_03 })
                    creature->AddAura(scaling, creature);

            if (SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(spellId))
                for (SpellEffectInfo const& effect : spellInfo->Effects)
                    if ((effect.Effect == SPELL_EFFECT_SUMMON || effect.Effect == SPELL_EFFECT_SUMMON_PET)
                        && effect.MiscValue == int32(creature->GetEntry()) && effect.TriggerSpell)
                        creature->AddAura(effect.TriggerSpell, creature);
        }, 1ms);
    }
};

void AddSC_eventwow_hero_spells()
{
    RegisterSpellScript(spell_eventwow_death_coil);
    RegisterSpellScript(spell_eventwow_black_arrow);
    RegisterSpellScript(spell_eventwow_reincarnation);
    new EventWow_HeroSummonScript();
}
