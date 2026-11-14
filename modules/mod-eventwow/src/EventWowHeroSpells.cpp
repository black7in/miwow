// Hechizos de heroe que los efectos del Spell.dbc solos no pueden hacer (docs/hechizos.md). Los hechizos se
// generan con tools/spellgen; la clave `script` de la ficha los enlaza aqui (spell_script_names).
//
// Ademas, regla general para NUESTRAS invocaciones (hechizos >= 9500000 con efecto de invocacion):
//  - Si el efecto de invocacion lleva EffectTriggerSpell (clave `trigger` de la ficha, el efecto SUMMON no lo usa),
//    el invocado recibe ese aura: asi cada rango puede sacar una criatura mas fuerte con la misma entrada.
//  - Una invocacion nueva sustituye a las anteriores del mismo hechizo (cualquier rango) del mismo dueno: p. ej. el
//    necrofago permanente de Arthas se puede volver a levantar cuando esta a punto de morir.
//  - Un necrofago (26125) invocado por un jugador recibe las auras nativas de escala de mascota de caballero de la
//    Muerte (70 % de la fuerza y 30 % del aguante del dueno, spell_dk_pet_scaling). El core solo se las pone a las
//    mascotas permanentes (Pet.cpp, IsPet()), y nuestras invocaciones son temporales (no se guardan en BD).
#include "AllCreatureScript.h"
#include "Creature.h"
#include "Player.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "SpellScript.h"
#include "SpellScriptLoader.h"
#include "TemporarySummon.h"
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

        NPC_EVENTWOW_RISEN_GHOUL = 26125
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

            // Sustituye a las anteriores del mismo hechizo (mismo primer rango)
            uint32 const firstSpell = sSpellMgr->GetFirstSpellInChain(spellId);
            std::vector<TempSummon*> previous;
            for (Unit* controlled : summoner->m_Controlled)
                if (controlled != creature && controlled->IsSummon() && controlled->GetEntry() == creature->GetEntry()
                    && sSpellMgr->GetFirstSpellInChain(controlled->GetUInt32Value(UNIT_CREATED_BY_SPELL)) == firstSpell)
                    previous.push_back(controlled->ToTempSummon());

            for (TempSummon* summon : previous)
                summon->UnSummon();

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
    new EventWow_HeroSummonScript();
}
