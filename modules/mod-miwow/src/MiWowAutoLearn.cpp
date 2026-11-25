#include "MiWowConfig.h"
#include "MiWowDevMode.h"
#include "MiWowLobby.h"
#include "MiWowProtocol.h"
#include "DataMap.h"
#include "DBCStores.h"
#include "DisableMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "Trainer.h"

// Auto-aprendizaje: al conectarse, subir de nivel o aprender un talento, el personaje aprende gratis lo que le
// ensenaria su entrenador de clase (y, segun config, lo de las misiones de clase, las armas y la equitacion).
// Sustituye al script de Eluna Mod_Auto_Aprendizaje.lua, pero sin listas de hechizos escritas a mano:
//  - Hechizos de clase y rangos de talento: los entrenadores de clase del core (tablas trainer/trainer_spell), como
//    `.learn my class`. Nivel, hechizo previo (ReqAbility) y raza/faccion (IsSpellFitByClassAndRace: portales,
//    Heroismo/Ansia de sangre, Sello de venganza/corrupcion...) los comprueba el propio core. Un rango de talento
//    pide el rango anterior, asi que solo sale si el jugador tiene el talento.
//  - Hechizos de mision: las misiones de clase (RequiredClasses) con RewardSpell, al nivel minimo de la mision.
//  - Armas y equitacion: tablas cortas abajo (los ensenan maestros de armas / de equitacion, no el de clase).
// Solo ANADE hechizos y objetos (totems); nunca quita nada del personaje.
//
// Lo aprendido se manda al cliente (SPELLS_LEARNED, docs/protocolo.md) para la ventana "Nueva habilidad" estilo
// retail (MiWowLevelUp.lua). En el login el protocolo aun no esta conectado: se guarda y se manda tras el HELLO.
namespace
{
    struct LevelSpell
    {
        uint32 SpellId;
        uint8 Level;
        uint32 ReqSpell;
    };

    // Equitacion (los de entrenador de monturas). Las monturas de clase (paladin, brujo, DK) salen solas de su
    // entrenador / mision cuando se tiene el rango de equitacion que piden.
    LevelSpell const RidingApprentice  = { 33388, 20, 0 };
    LevelSpell const RidingJourneyman  = { 33391, 40, 33388 };
    LevelSpell const RidingExpert      = { 34090, 60, 33391 };
    LevelSpell const RidingArtisan     = { 34091, 70, 34090 };
    LevelSpell const ColdWeatherFlying = { 54197, 77, 34090 };

    // Habilidades de armas por clase (las ensenan los maestros de armas). Parada y doble empunadura son del
    // entrenador de clase. Indice = clase.
    std::vector<LevelSpell> const Proficiencies[MAX_CLASSES] =
    {
        { },
        // Guerrero
        { { 196, 1, 0 }, { 197, 1, 0 }, { 198, 1, 0 }, { 199, 1, 0 }, { 200, 1, 0 }, { 201, 1, 0 }, { 202, 1, 0 },
          { 227, 1, 0 }, { 264, 1, 0 }, { 266, 1, 0 }, { 1180, 1, 0 }, { 5011, 1, 0 }, { 15590, 1, 0 } },
        // Paladin
        { { 196, 1, 0 }, { 197, 1, 0 }, { 198, 1, 0 }, { 199, 1, 0 }, { 200, 1, 0 }, { 201, 1, 0 }, { 202, 1, 0 } },
        // Cazador
        { { 196, 1, 0 }, { 197, 1, 0 }, { 200, 1, 0 }, { 201, 1, 0 }, { 202, 1, 0 }, { 227, 1, 0 }, { 264, 1, 0 },
          { 266, 1, 0 }, { 1180, 1, 0 }, { 5011, 1, 0 }, { 15590, 1, 0 } },
        // Picaro
        { { 196, 1, 0 }, { 198, 1, 0 }, { 201, 1, 0 }, { 264, 1, 0 }, { 266, 1, 0 }, { 1180, 1, 0 }, { 5011, 1, 0 },
          { 15590, 1, 0 } },
        // Sacerdote
        { { 198, 1, 0 }, { 227, 1, 0 }, { 1180, 1, 0 }, { 5009, 1, 0 } },
        // Caballero de la Muerte
        { { 196, 1, 0 }, { 197, 1, 0 }, { 198, 1, 0 }, { 199, 1, 0 }, { 200, 1, 0 }, { 201, 1, 0 }, { 202, 1, 0 } },
        // Chaman
        { { 196, 1, 0 }, { 197, 1, 0 }, { 198, 1, 0 }, { 199, 1, 0 }, { 227, 1, 0 }, { 1180, 1, 0 }, { 15590, 1, 0 } },
        // Mago
        { { 201, 1, 0 }, { 227, 1, 0 }, { 1180, 1, 0 }, { 5009, 1, 0 } },
        // Brujo
        { { 201, 1, 0 }, { 227, 1, 0 }, { 1180, 1, 0 }, { 5009, 1, 0 } },
        // (sin clase 10)
        { },
        // Druida
        { { 198, 1, 0 }, { 199, 1, 0 }, { 200, 1, 0 }, { 227, 1, 0 }, { 1180, 1, 0 }, { 15590, 1, 0 } },
    };

    // Totems del chaman (en 3.3.5 son objetos que dan sus misiones): objeto, nivel.
    std::pair<uint32, uint8> const ShamanTotems[] =
    {
        { 5175, 4 },  // Totem de tierra
        { 5176, 10 }, // Totem de fuego
        { 5177, 20 }, // Totem de agua
        { 5178, 30 }, // Totem de aire
    };

    enum class Reason
    {
        Login,  // todo (lo pendiente de antes del modulo, o de cambios de config)
        Level,  // todo
        Talent  // solo el entrenador de clase: es donde estan los rangos de talento
    };

    // Hechizos aprendidos que aun no se han mandado al cliente (login: el protocolo conecta despues)
    std::string const PendingKey = "MiWowAutoLearnPending";

    struct PendingSpells : public DataMap::Base
    {
        std::vector<uint32> Spells;
    };

    using Learned = std::vector<uint32>;

    // Primer hechizo LEARN_SPELL de un hechizo (las entradas "castables" de entrenador y los RewardSpell de mision
    // se lanzan y ensenan otro); 0 si no tiene.
    uint32 LearnSpellTarget(uint32 spellId)
    {
        if (SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId))
            for (SpellEffectInfo const& effect : info->GetEffects())
                if (effect.IsEffect(SPELL_EFFECT_LEARN_SPELL) && effect.TriggerSpell)
                    return effect.TriggerSpell;
        return 0;
    }

    // Hechizo que da de verdad una entrada de entrenador
    uint32 TaughtSpell(Trainer::Spell const& trainerSpell)
    {
        uint32 taught = LearnSpellTarget(trainerSpell.SpellId);
        return taught ? taught : trainerSpell.SpellId;
    }

    bool IsTalentRank(uint32 spellId)
    {
        return GetTalentSpellPos(sSpellMgr->GetFirstSpellInChain(spellId)) != nullptr;
    }

    void LearnClassSpells(Player* player, Learned& learned)
    {
        MiWowConfig::AutoLearnConfig const& cfg = sMiWowConfig.AutoLearn;

        for (Trainer::Trainer const* trainer : sObjectMgr->GetClassTrainers(player->getClass()))
        {
            if (!trainer->IsTrainerValidForPlayer(player))
                continue;

            for (Trainer::Spell const& trainerSpell : trainer->GetSpells())
            {
                if (!trainer->CanTeachSpell(player, &trainerSpell))
                    continue;

                uint32 taught = TaughtSpell(trainerSpell);
                if (!cfg.TalentRanks && IsTalentRank(taught))
                    continue;

                // Igual que Trainer::TeachSpell, sin coste ni NPC
                if (!trainerSpell.IsCastable())
                    player->learnSpell(trainerSpell.SpellId, false);
                else if (sScriptMgr->OnPlayerCanLearnSpell(player, trainerSpell.SpellId))
                    player->CastSpell(player, trainerSpell.SpellId, true);

                // un script puede negar el aprendizaje: solo cuenta si de verdad lo tiene
                if (player->HasSpell(taught))
                    learned.push_back(taught);
            }
        }
    }

    void LearnQuestSpells(Player* player, Learned& learned)
    {
        for (auto const& [questId, quest] : sObjectMgr->GetQuestTemplates())
        {
            if (!quest->GetRequiredClasses() || !quest->GetRewSpellCast())
                continue;

            uint32 level = quest->GetMinLevel() ? quest->GetMinLevel() : uint32(std::max(0, quest->GetQuestLevel()));
            if (player->GetLevel() < level)
                continue;

            if (!player->SatisfyQuestClass(quest, false) || !player->SatisfyQuestRace(quest, false))
                continue;

            // RewardSpell se lanza y ensena otro hechizo: ese es el que cuenta
            uint32 taught = LearnSpellTarget(quest->GetRewSpellCast());
            if (!taught || player->HasSpell(taught))
                continue;

            if (DisableMgr::IsDisabledFor(DISABLE_TYPE_QUEST, questId, player))
                continue;

            player->learnQuestRewardedSpells(quest); // no da especialidades de profesion
            if (player->HasSpell(taught))
                learned.push_back(taught);
        }
    }

    void LearnLevelSpell(Player* player, LevelSpell const& spell, Learned& learned)
    {
        if (player->GetLevel() < spell.Level || player->HasSpell(spell.SpellId))
            return;

        if (spell.ReqSpell && !player->HasSpell(spell.ReqSpell))
            return;

        if (!player->IsSpellFitByClassAndRace(spell.SpellId))
            return;

        player->learnSpell(spell.SpellId, false);
        if (player->HasSpell(spell.SpellId))
            learned.push_back(spell.SpellId);
    }

    void LearnRiding(Player* player, Learned& learned)
    {
        MiWowConfig::AutoLearnConfig const& cfg = sMiWowConfig.AutoLearn;

        if (cfg.RidingApprentice)
            LearnLevelSpell(player, RidingApprentice, learned);
        if (cfg.RidingJourneyman)
            LearnLevelSpell(player, RidingJourneyman, learned);
        if (cfg.RidingExpert)
            LearnLevelSpell(player, RidingExpert, learned);
        if (cfg.RidingArtisan)
            LearnLevelSpell(player, RidingArtisan, learned);
        if (cfg.ColdWeatherFlying)
            LearnLevelSpell(player, ColdWeatherFlying, learned);
    }

    void LearnProficiencies(Player* player, Learned& learned)
    {
        for (LevelSpell const& spell : Proficiencies[player->getClass()])
            LearnLevelSpell(player, spell, learned);
    }

    void AddShamanTotems(Player* player)
    {
        if (player->getClass() != CLASS_SHAMAN)
            return;

        for (auto const& [itemId, level] : ShamanTotems)
            if (player->GetLevel() >= level && !player->HasItemCount(itemId, 1, true))
                player->AddItem(itemId, 1);
    }

    // SPELLS_LEARNED <n> <hechizo>... (si no esta conectado, se guarda para el HELLO)
    void SendLearned(Player* player, Learned const& learned)
    {
        if (learned.empty())
            return;

        if (!MiWowProtocol::IsConnected(player->GetGUID()))
        {
            PendingSpells* pending = player->CustomData.GetDefault<PendingSpells>(PendingKey);
            pending->Spells.insert(pending->Spells.end(), learned.begin(), learned.end());
            return;
        }

        MiWowMessage message("SPELLS_LEARNED");
        message.Add(uint32(learned.size()));
        for (uint32 spellId : learned)
            message.Add(spellId);
        message.Send(player);
    }

    void SendPending(Player* player)
    {
        PendingSpells* pending = player->CustomData.Get<PendingSpells>(PendingKey);
        if (!pending)
            return;

        Learned spells = std::move(pending->Spells);
        player->CustomData.Erase(PendingKey);
        SendLearned(player, spells);
    }

    void AutoLearn(Player* player, Reason reason)
    {
        MiWowConfig::AutoLearnConfig const& cfg = sMiWowConfig.AutoLearn;
        if (!sMiWowConfig.Enabled || !cfg.Enabled)
            return;

        // Modo dev (.gm on / .dev on) = AzerothCore normal, salvo que la config lo active tambien ahi
        if (!cfg.DevMode && MiWowDevMode::IsActive(player))
            return;

        // En un evento no se sube de nivel; lo pendiente se aprende al volver (login o siguiente nivel).
        if (MiWowLobby::IsEventMap(player->GetMapId()))
            return;

        if (player->getClass() >= MAX_CLASSES)
            return;

        bool const onlyTrainer = reason == Reason::Talent;
        Learned learned;

        // Equitacion primero: algunas monturas de clase la piden. Se repite mientras aprenda algo nuevo porque un
        // hechizo puede ser el requisito de otro (rangos, monturas de clase).
        for (uint8 pass = 0; pass < 10; ++pass)
        {
            std::size_t const before = learned.size();

            if (!onlyTrainer)
            {
                LearnRiding(player, learned);

                if (cfg.Proficiencies)
                    LearnProficiencies(player, learned);
            }

            if (cfg.ClassSpells)
                LearnClassSpells(player, learned);

            if (!onlyTrainer && cfg.ClassSpells && cfg.QuestSpells)
                LearnQuestSpells(player, learned);

            if (learned.size() == before)
                break;
        }

        if (!onlyTrainer && cfg.ClassSpells && cfg.QuestSpells)
            AddShamanTotems(player);

        SendLearned(player, learned);
    }
}

class MiWow_AutoLearnPlayerScript : public PlayerScript
{
public:
    MiWow_AutoLearnPlayerScript() : PlayerScript("MiWow_AutoLearnPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_LEVEL_CHANGED,
        PLAYERHOOK_ON_PLAYER_LEARN_TALENTS
    }) { }

    void OnPlayerLogin(Player* player) override
    {
        AutoLearn(player, Reason::Login);
    }

    void OnPlayerLevelChanged(Player* player, uint8 /*oldLevel*/) override
    {
        AutoLearn(player, Reason::Level);
    }

    // Un talento nuevo con rangos de entrenador (Golpe mortal, Choque Sagrado...): sus rangos ya alcanzados.
    void OnPlayerLearnTalents(Player* player, uint32 /*talentId*/, uint32 /*talentRank*/, uint32 /*spellId*/) override
    {
        if (sMiWowConfig.AutoLearn.TalentRanks)
            AutoLearn(player, Reason::Talent);
    }
};

void AddSC_miwow_auto_learn()
{
    new MiWow_AutoLearnPlayerScript();
    MiWowProtocol::RegisterConnectListener(SendPending);
}
