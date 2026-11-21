#include "Chat.h"
#include "CommandScript.h"
#include "Creature.h"
#include "CreatureScript.h"
#include "DataMap.h"
#include "GameObject.h"
#include "GameObjectScript.h"
#include "GameTime.h"
#include "Guild.h"
#include "GuildScript.h"
#include "GuildMgr.h"
#include "CharacterCache.h"
#include "LootMgr.h"
#include "Mail.h"
#include "MailScript.h"
#include "MiWowGuildSeason.h"
#include "MiWowProtocol.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "PlayerScript.h"
#include "DBCStructure.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "ScriptedGossip.h"
#include "StringFormat.h"
#include "Util.h"

// Hooks de las temporadas de hermandad (MiWowGuildSeason): mundo, personaje, hermandad, tablon, intendente y comandos
// de GM.
namespace
{
    // Cada cuanto se revisan las auras de ventaja de un personaje (muerte, cambio de mapa, fin de temporada...)
    constexpr uint32 PerkRefreshInterval = 3 * IN_MILLISECONDS;

    constexpr char const* PerkTimerKey = "MiWowGuildPerkTimer";

    struct PerkTimer : public DataMap::Base
    {
        uint32 Elapsed = 0;
        uint64 HearthEnd = 0;  // fin (ms de juego) de la reutilizacion de la piedra de hogar ya reducida
    };

    // Piedra de hogar (objeto 6948) y su reutilizacion de 30 min
    constexpr uint32 HearthstoneSpell = 8690;

    float PercentLess(int32 value)
    {
        return std::max(0.0f, 1.0f - float(value) / 100.0f);
    }

    // Hogar presto: cada reutilizacion nueva de la piedra de hogar se acorta una vez
    void UpdateHearthstone(Player* player, PerkTimer* timer)
    {
        int32 const minutes = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Hearth);
        if (minutes <= 0 || !player->HasSpellCooldown(HearthstoneSpell))
            return;

        uint64 const now = GameTime::GetGameTimeMS().count();
        uint32 const remaining = player->GetSpellCooldownDelay(HearthstoneSpell);
        uint64 const end = now + remaining;
        // Ya acortada (margen por el redondeo del retraso)
        if (timer->HearthEnd && end + 5 * IN_MILLISECONDS >= timer->HearthEnd && end <= timer->HearthEnd + 5 * IN_MILLISECONDS)
            return;

        uint32 const reduction = std::min<uint32>(minutes * MINUTE * IN_MILLISECONDS, remaining > IN_MILLISECONDS ? remaining - IN_MILLISECONDS : 0);
        if (reduction)
            player->ModifySpellCooldown(HearthstoneSpell, -int32(reduction));
        timer->HearthEnd = end - reduction;
    }

    // Textos (npc_text, SQL db-world 2026_11_21_01): tablon (lo ve quien no tiene el parche del cliente) e
    // intendente sin hermandad
    constexpr uint32 BoardText = 9500200;
    constexpr uint32 VendorTextNoGuild = 9500201;

    void SendNoGuild(Player* player, char const* text)
    {
        ChatHandler(player->GetSession()).SendSysMessage(Acore::StringFormat("|cff00ff96[Hermandad]|r {}", text));
    }
}

class MiWow_GuildWorldScript : public WorldScript
{
public:
    MiWow_GuildWorldScript() : WorldScript("MiWow_GuildWorldScript", {
        WORLDHOOK_ON_AFTER_CONFIG_LOAD,
        WORLDHOOK_ON_STARTUP,
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        sMiWowGuild.LoadConfig();
    }

    void OnStartup() override
    {
        sMiWowGuild.Load();
    }

    void OnUpdate(uint32 diff) override
    {
        sMiWowGuild.Update(diff);
    }
};

class MiWow_GuildPlayerScript : public PlayerScript
{
public:
    MiWow_GuildPlayerScript() : PlayerScript("MiWow_GuildPlayerScript", {
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_ON_UPDATE,
        PLAYERHOOK_ON_MAP_CHANGED,
        PLAYERHOOK_ON_PLAYER_COMPLETE_QUEST,
        PLAYERHOOK_ON_BEFORE_QUEST_COMPLETE,
        PLAYERHOOK_ON_PLAYER_QUEST_ACCEPT,
        PLAYERHOOK_ON_QUEST_ABANDON,
        PLAYERHOOK_ON_BEFORE_LOOT_MONEY,
        PLAYERHOOK_ON_BEFORE_DURABILITY_REPAIR,
        PLAYERHOOK_ON_GET_REPUTATION_PRICE_DISCOUNT,
        PLAYERHOOK_ON_PLAYER_RESURRECT,
        PLAYERHOOK_ON_UPDATE_GATHERING_SKILL,
        PLAYERHOOK_ON_UPDATE_CRAFTING_SKILL
    }) { }

    void OnPlayerLogin(Player* player) override
    {
        sMiWowGuild.OnLogin(player);
        sMiWowGuild.RemoveStalePerkSpells(player);
        sMiWowGuild.RefreshPerks(player);
    }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        PerkTimer* timer = player->CustomData.GetDefault<PerkTimer>(PerkTimerKey);
        timer->Elapsed += diff;
        if (timer->Elapsed < PerkRefreshInterval)
            return;
        timer->Elapsed = 0;
        sMiWowGuild.RefreshPerks(player);
        UpdateHearthstone(player, timer);
    }

    // Ventajas con efecto del modulo (valor = efecto 1 de su hechizo, data/spells/hermandad.toml) ----------------

    // Flujo de oro: un % extra del dinero despojado va al banco de la hermandad (al personaje no se le quita nada)
    void OnPlayerBeforeLootMoney(Player* player, Loot* loot) override
    {
        if (!loot || !loot->gold)
            return;

        int32 const percent = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Gold);
        uint32 const bonus = percent > 0 ? uint32(uint64(loot->gold) * percent / 100) : 0;
        if (!bonus)
            return;

        if (Guild* guild = sGuildMgr->GetGuildById(player->GetGuildId()))
        {
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            if (guild->ModifyBankMoney(trans, bonus, true))
                CharacterDatabase.CommitTransaction(trans);
        }
    }

    // Reparaciones de hermandad
    void OnPlayerBeforeDurabilityRepair(Player* player, ObjectGuid /*npcGUID*/, ObjectGuid /*itemGUID*/, float& discountMod,
        uint8 /*guildBank*/) override
    {
        if (int32 const percent = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Repair))
            discountMod *= PercentLess(percent);
    }

    // Regateo: precios de compra de los vendedores (tambien la reparacion, que usa el mismo descuento)
    void OnPlayerGetReputationPriceDiscount(Player const* player, Creature const* /*creature*/, float& discount) override
    {
        if (int32 const percent = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Vendor))
            discount *= PercentLess(percent);
    }

    // Vuelta a la vida: el core ya ha puesto la salud/mana de la resurreccion; se suma el % extra del maximo
    void OnPlayerResurrect(Player* player, float /*restorePercent*/, bool& /*applySickness*/) override
    {
        int32 const percent = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Resurrect);
        if (percent <= 0)
            return;

        uint32 const maxHealth = player->GetMaxHealth();
        player->SetHealth(std::min<uint32>(maxHealth, player->GetHealth() + maxHealth * percent / 100));
        uint32 const maxMana = player->GetMaxPower(POWER_MANA);
        if (maxMana)
            player->SetPower(POWER_MANA, std::min<uint32>(maxMana, player->GetPower(POWER_MANA) + maxMana * percent / 100));
    }

    // Horas extra: probabilidad de un punto mas cuando la profesion sube
    void OnPlayerUpdateGatheringSkill(Player* player, uint32 /*skillId*/, uint32 /*current*/, uint32 /*gray*/, uint32 /*green*/,
        uint32 /*yellow*/, uint32& gain) override
    {
        AddProfessionPoint(player, gain);
    }

    void OnPlayerUpdateCraftingSkill(Player* player, SkillLineAbilityEntry const* /*skill*/, uint32 /*currentLevel*/, uint32& gain) override
    {
        AddProfessionPoint(player, gain);
    }

    static void AddProfessionPoint(Player* player, uint32& gain)
    {
        if (!gain)
            return;
        int32 const chance = sMiWowGuild.GetPerkValue(player, MiWowGuildPerkEffect::Profession);
        if (chance > 0 && roll_chance_i(chance))
            ++gain;
    }

    // Al entrar en un evento, campo de batalla o arena las ventajas se quitan en el acto
    void OnPlayerMapChanged(Player* player) override
    {
        sMiWowGuild.RefreshPerks(player);
    }

    // Al COMPLETAR la mision (objetivos cumplidos; Player::CompleteQuest, tambien al intentar entregarla)
    bool OnPlayerBeforeQuestComplete(Player* player, uint32 questId) override
    {
        return sMiWowGuild.CanCompleteQuest(player, questId);
    }

    void OnPlayerQuestAccept(Player* player, Quest const* quest) override
    {
        sMiWowGuild.OnQuestAccepted(player, quest->GetQuestId());
    }

    void OnPlayerQuestAbandon(Player* player, uint32 questId) override
    {
        sMiWowGuild.OnQuestAbandoned(player, questId);
    }

    // Se llama al ENTREGAR la mision (Player::RewardQuest), despues de las recompensas normales
    void OnPlayerCompleteQuest(Player* player, Quest const* quest) override
    {
        sMiWowGuild.OnQuestRewarded(player, quest);
    }
};

class MiWow_GuildScript : public GuildScript
{
public:
    MiWow_GuildScript() : GuildScript("MiWow_GuildScript", {
        GUILDHOOK_ON_ADD_MEMBER,
        GUILDHOOK_ON_REMOVE_MEMBER,
        GUILDHOOK_ON_CREATE,
        GUILDHOOK_ON_DISBAND
    }) { }

    void OnAddMember(Guild* guild, Player* player, uint8& /*rank*/) override
    {
        if (player)
            sMiWowGuild.OnGuildChanged(player, guild->GetId());
    }

    // player = nullptr si estaba desconectado: su ficha se pone al dia en su proximo login
    void OnRemoveMember(Guild* /*guild*/, Player* player, bool /*isDisbanding*/, bool /*isKicked*/) override
    {
        if (player)
            sMiWowGuild.OnGuildChanged(player, 0);
    }

    void OnCreate(Guild* guild, Player* /*leader*/, std::string const& /*name*/) override
    {
        sMiWowGuild.OnGuildCreated(guild->GetId());
    }

    void OnDisband(Guild* guild) override
    {
        sMiWowGuild.OnGuildDisbanded(guild->GetId());
    }
};

// Correo de hermandad: el correo entre dos miembros de una hermandad con la ventaja llega al instante (tambien con
// objetos). El destinatario puede estar desconectado: su hermandad sale de la cache de personajes.
class MiWow_GuildMailScript : public MailScript
{
public:
    MiWow_GuildMailScript() : MailScript("MiWow_GuildMailScript", { MAILHOOK_ON_BEFORE_MAIL_DRAFT_SEND_MAIL_TO }) { }

    void OnBeforeMailDraftSendMailTo(MailDraft* /*mailDraft*/, MailReceiver const& receiver, MailSender const& sender,
        MailCheckMask& /*checked*/, uint32& deliverDelay, uint32& /*customExpiration*/, bool& /*deleteMailItemsFromDB*/,
        bool& /*sendMail*/) override
    {
        if (!deliverDelay || sender.GetMailMessageType() != MAIL_NORMAL || !sMiWowGuild.IsEnabled())
            return;

        uint32 const senderGuild = sCharacterCache->GetCharacterGuildIdByGuid(ObjectGuid::Create<HighGuid::Player>(sender.GetSenderId()));
        uint32 const receiverGuild = sCharacterCache->GetCharacterGuildIdByGuid(ObjectGuid::Create<HighGuid::Player>(receiver.GetPlayerGUIDLow()));
        if (senderGuild && senderGuild == receiverGuild && sMiWowGuild.GuildHasPerk(senderGuild, MiWowGuildPerkEffect::Mail))
            deliverDelay = 0;
    }
};

// Tablon de la hermandad (objeto MiWow.Guild.BoardObject): da y recoge las misiones (las pone el modulo en memoria).
// Con el parche del cliente se ve la ventana del tablon (GUILD_BOARD_OPEN antes del gossip: el cliente la pone en
// lugar de la lista nativa y sus botones eligen las misiones del gossip). Sin hermandad no se puede usar.
class go_miwow_guild_board : public GameObjectScript
{
public:
    go_miwow_guild_board() : GameObjectScript("go_miwow_guild_board") { }

    bool OnGossipHello(Player* player, GameObject* go) override
    {
        if (!sMiWowGuild.IsEnabled() || !player->GetGuildId())
        {
            SendNoGuild(player, "Solo los miembros de una hermandad pueden usar el tablón.");
            return true;
        }

        MiWowGuildShowBoard(player, go);
        return true;
    }
};

void MiWowGuildShowBoard(Player* player, GameObject* go)
{
    if (MiWowProtocol::IsConnected(player->GetGUID()))
    {
        MiWowGuildSendInfo(player);
        MiWowMessage("GUILD_BOARD_OPEN").Send(player);
    }

    ClearGossipMenuFor(player);
    player->PrepareQuestMenu(go->GetGUID());
    SendGossipMenuFor(player, BoardText, go->GetGUID());
}

// Intendente de la hermandad (MiWow.Guild.VendorCreature): abre la tienda de la hermandad del cliente
class npc_miwow_guild_vendor : public CreatureScript
{
public:
    npc_miwow_guild_vendor() : CreatureScript("npc_miwow_guild_vendor") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        ClearGossipMenuFor(player);
        if (!sMiWowGuild.IsEnabled() || !player->GetGuildId() || !MiWowProtocol::IsConnected(player->GetGUID()))
        {
            SendGossipMenuFor(player, VendorTextNoGuild, creature->GetGUID());
            return true;
        }

        CloseGossipMenuFor(player);
        MiWowGuildSendInfo(player);
        MiWowMessage("GUILD_SHOP_OPEN").Send(player);
        return true;
    }
};

// Comandos de GM: .miwow guild info | points <n> | rep <n> | rotate [daily|weekly] | endseason
// Sobre el jugador seleccionado o uno mismo (points/rep: a su hermandad / a el).
using namespace Acore::ChatCommands;

class MiWow_GuildCommandScript : public CommandScript
{
public:
    MiWow_GuildCommandScript() : CommandScript("MiWow_GuildCommandScript") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable guildTable =
        {
            { "info",      HandleInfo,      SEC_GAMEMASTER,    Console::No },
            { "points",    HandlePoints,    SEC_GAMEMASTER,    Console::No },
            { "rep",       HandleRep,       SEC_GAMEMASTER,    Console::No },
            { "rotate",    HandleRotate,    SEC_ADMINISTRATOR, Console::Yes },
            { "endseason", HandleEndSeason, SEC_ADMINISTRATOR, Console::Yes }
        };
        static ChatCommandTable miwowTable =
        {
            { "guild", guildTable }
        };
        static ChatCommandTable commandTable =
        {
            { "miwow", miwowTable }
        };
        return commandTable;
    }

    static bool CheckEnabled(ChatHandler* handler)
    {
        if (sMiWowGuild.IsEnabled())
            return true;
        handler->SendErrorMessage("MiWow: temporadas de hermandad desactivadas (MiWow.Guild.Enable)");
        return false;
    }

    static bool HandleInfo(ChatHandler* handler)
    {
        if (!CheckEnabled(handler))
            return false;

        std::lock_guard<std::recursive_mutex> lock(MiWowGuildSeason::GetLock());
        Player* target = handler->getSelectedPlayerOrSelf();
        uint32 const guildId = target->GetGuildId();
        uint32 const seasonEnd = sMiWowGuild.GetSeasonEnd();
        handler->PSendSysMessage("MiWow: {} (temporada {}){}", sMiWowGuild.GetSeasonName(), sMiWowGuild.GetSeasonId(),
            seasonEnd ? Acore::StringFormat(", acaba en {}", secsToTimeString(seasonEnd - std::min<uint32>(seasonEnd, uint32(GameTime::GetGameTime().count())))) : "");

        if (!guildId)
        {
            handler->PSendSysMessage("MiWow: {} no tiene hermandad", target->GetName());
            return true;
        }

        MiWowGuildProgress const* progress = sMiWowGuild.GetProgress(guildId);
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        handler->PSendSysMessage("MiWow: <{}>: {} puntos, puesto {}, ventajas 0x{:X}", guild ? guild->GetName() : "?",
            progress ? progress->Points : 0, sMiWowGuild.GetPosition(guildId), progress ? progress->Perks : 0);

        MiWowGuildMember const* member = sMiWowGuild.GetMember(target->GetGUID().GetCounter());
        uint32 const reputation = member ? member->Reputation : 0;
        MiWowGuildRank const* rank = sMiWowGuild.GetRank(reputation);
        handler->PSendSysMessage("MiWow: {}: reputacion {} ({}), contribucion {}, hoy {}", target->GetName(), reputation,
            rank ? rank->Name : "?", member ? member->Contribution : 0, sMiWowGuild.GetDailyPointsToday(target->GetGUID().GetCounter()));
        return true;
    }

    static bool HandlePoints(ChatHandler* handler, uint32 points)
    {
        if (!CheckEnabled(handler))
            return false;

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target->GetGuildId())
        {
            handler->SendErrorMessage("MiWow: {} no tiene hermandad", target->GetName());
            return false;
        }

        uint32 const added = sMiWowGuild.AddPoints(target->GetGuildId(), target->GetGUID().GetCounter(), points, true);
        handler->PSendSysMessage("MiWow: +{} puntos para la hermandad de {}", added, target->GetName());
        return true;
    }

    static bool HandleRep(ChatHandler* handler, uint32 amount)
    {
        if (!CheckEnabled(handler))
            return false;

        Player* target = handler->getSelectedPlayerOrSelf();
        if (!target->GetGuildId())
        {
            handler->SendErrorMessage("MiWow: {} no tiene hermandad", target->GetName());
            return false;
        }

        sMiWowGuild.AddReputation(target, amount);
        handler->PSendSysMessage("MiWow: +{} de reputacion de hermandad para {}", amount, target->GetName());
        return true;
    }

    static bool HandleRotate(ChatHandler* handler, Optional<std::string> which)
    {
        if (!CheckEnabled(handler))
            return false;

        bool const daily = !which || *which != "weekly";
        bool const weekly = !which || *which != "daily";
        if (daily)
            sMiWowGuild.RotateBoard(MiWowGuildBoard::Daily);
        if (weekly)
            sMiWowGuild.RotateBoard(MiWowGuildBoard::Weekly);
        handler->PSendSysMessage("MiWow: tablon {} de hermandad: rota en el siguiente tick", daily && weekly ? "diario y semanal" : (daily ? "diario" : "semanal"));
        return true;
    }

    static bool HandleEndSeason(ChatHandler* handler)
    {
        if (!CheckEnabled(handler))
            return false;

        sMiWowGuild.EndSeason();
        handler->PSendSysMessage("MiWow: la temporada {} termina en el siguiente tick", sMiWowGuild.GetSeasonId());
        return true;
    }
};

void AddSC_miwow_guild()
{
    new MiWow_GuildWorldScript();
    new MiWow_GuildPlayerScript();
    new MiWow_GuildScript();
    new MiWow_GuildMailScript();
    new go_miwow_guild_board();
    new npc_miwow_guild_vendor();
    new MiWow_GuildCommandScript();
}
