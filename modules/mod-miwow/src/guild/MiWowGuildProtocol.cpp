#include "CharacterCache.h"
#include "DataMap.h"
#include "GameObject.h"
#include "GameTime.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "MiWowGuildSeason.h"
#include "MiWowProtocol.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "StringConvert.h"
#include "WorldSession.h"
#include <algorithm>

// Ventana de la hermandad (cliente: MiWowGuild.lua). Ver "Hermandad" en docs/protocolo.md.
//   Cliente -> servidor: GUILD_INFO (al abrir la ventana o al recibir GUILD_DIRTY con ella abierta),
//                        GUILD_BUY <objeto> (tienda, junto al intendente)
//   Servidor -> cliente: GUILD_STATE, GUILD_RANKS, GUILD_PERKS, GUILD_PRIZES, GUILD_BOARD, GUILD_RANKING,
//                        GUILD_MEMBERS, GUILD_VENDOR (respuesta); GUILD_DIRTY (algo cambio); GUILD_BOARD_OPEN (tablon,
//                        antes de su gossip); GUILD_SHOP_OPEN (intendente)
namespace
{
    // Una peticion por segundo como mucho; una compra cada medio segundo
    constexpr uint32 InfoCooldownMs = 1000;
    constexpr uint32 BuyCooldownMs = 500;
    constexpr std::size_t RankingSize = 10;

    constexpr char const* InfoTimeKey = "MiWowGuildInfoTime";
    constexpr char const* BuyTimeKey = "MiWowGuildBuyTime";
    constexpr char const* ReopenTimeKey = "MiWowGuildReopenTime";
    // Distancia al tablon para volver a abrirlo (algo mas que la de interaccion de los objetos)
    constexpr float BoardReopenRange = 10.0f;

    struct InfoTime : public DataMap::Base
    {
        uint32 LastMs = 0;
    };

    // Tipo de mision para la ventana: individual, de grupo o de banda (QuestInfoID de banda: sus objetivos avanzan en
    // banda, comportamiento nativo)
    enum class QuestKind : uint8
    {
        Individual = 0,
        Group = 1,
        Raid = 2
    };

    QuestKind GetQuestKind(MiWowGuildQuest const* guildQuest, Quest const* quest)
    {
        uint32 const type = quest->GetType();
        if (type == QUEST_TYPE_RAID || type == QUEST_TYPE_RAID_10 || type == QUEST_TYPE_RAID_25)
            return QuestKind::Raid;
        return guildQuest->RequiredMembers > 0 ? QuestKind::Group : QuestKind::Individual;
    }

    bool CheckCooldown(Player* player, char const* key, uint32 cooldownMs)
    {
        InfoTime* time = player->CustomData.GetDefault<InfoTime>(key);
        uint32 const now = uint32(GameTime::GetGameTimeMS().count());
        if (time->LastMs && now - time->LastMs < cooldownMs)
            return false;
        time->LastMs = now;
        return true;
    }

    // Estado de una mision del tablon para este personaje
    enum class BoardStatus : uint8
    {
        Available = 0,
        InProgress = 1,
        Complete = 2,  // lista para entregar
        Done = 3,      // ya entregada (hoy / esta semana / para siempre)
        Blocked = 4    // no se completo en grupo: hay que abandonarla y repetirla
    };

    uint32 SecondsUntil(uint32 when)
    {
        uint32 const now = uint32(GameTime::GetGameTime().count());
        return when > now ? when - now : 0;
    }

    std::string GetQuestTitle(Player* player, Quest const* quest)
    {
        std::string title = quest->GetTitle();
        if (QuestLocale const* locale = sObjectMgr->GetQuestLocale(quest->GetQuestId()))
            ObjectMgr::GetLocaleString(locale->Title, player->GetSession()->GetSessionDbLocaleIndex(), title);
        return title;
    }

    std::string GetItemName(Player* player, ItemTemplate const* proto)
    {
        std::string name = proto->Name1;
        if (ItemLocale const* locale = sObjectMgr->GetItemLocale(proto->ItemId))
            ObjectMgr::GetLocaleString(locale->Name, player->GetSession()->GetSessionDbLocaleIndex(), name);
        return name;
    }

    BoardStatus GetBoardStatus(Player* player, Quest const* quest)
    {
        switch (player->GetQuestStatus(quest->GetQuestId()))
        {
            case QUEST_STATUS_INCOMPLETE:
            case QUEST_STATUS_FAILED:
                return sMiWowGuild.IsQuestBlocked(player->GetGUID().GetCounter(), quest->GetQuestId())
                    ? BoardStatus::Blocked : BoardStatus::InProgress;
            case QUEST_STATUS_COMPLETE:
                return BoardStatus::Complete;
            default:
                break;
        }

        if (quest->IsDaily() && !player->SatisfyQuestDay(quest, false))
            return BoardStatus::Done;
        if (quest->IsWeekly() && !player->SatisfyQuestWeek(quest, false))
            return BoardStatus::Done;
        if (!quest->IsDailyOrWeekly() && !quest->IsRepeatable() && player->GetQuestRewardStatus(quest->GetQuestId()))
            return BoardStatus::Done;
        return BoardStatus::Available;
    }

    // GUILD_STATE <en hermandad 0/1> <temporada> <nombre> <segundos que quedan, 0 = sin fin> <puntos> <puesto>
    //   <puntos de la siguiente ventaja, 0 = ninguna> <reputacion> <rango> <reputacion del rango>
    //   <siguiente rango, "" = maximo> <reputacion del siguiente> <contribucion> <puntos hoy> <limite diario, 0 = sin>
    //   <segundos desde el inicio de la temporada>
    void SendState(Player* player)
    {
        uint32 const guildId = player->GetGuildId();
        MiWowGuildProgress const* progress = guildId ? sMiWowGuild.GetProgress(guildId) : nullptr;
        uint64 const points = progress ? progress->Points : 0;
        MiWowGuildPerk const* nextPerk = guildId ? sMiWowGuild.GetNextPerk(points) : nullptr;

        MiWowGuildMember const* member = sMiWowGuild.GetMember(player->GetGUID().GetCounter());
        bool const sameGuild = member && guildId && member->GuildId == guildId;
        uint32 const reputation = sameGuild ? member->Reputation : 0;
        MiWowGuildRank const* rank = sMiWowGuild.GetRank(reputation);
        MiWowGuildRank const* nextRank = sMiWowGuild.GetNextRank(reputation);
        uint32 const seasonEnd = sMiWowGuild.GetSeasonEnd();

        MiWowMessage("GUILD_STATE")
            .Add(guildId ? 1 : 0)
            .Add(sMiWowGuild.GetSeasonId())
            .Add(sMiWowGuild.GetSeasonName())
            .Add(seasonEnd ? std::max<uint32>(1, SecondsUntil(seasonEnd)) : 0)
            .Add(points)
            .Add(guildId ? sMiWowGuild.GetPosition(guildId) : 0)
            .Add(nextPerk ? nextPerk->Points : 0)
            .Add(reputation)
            .Add(rank ? std::string_view(rank->Name) : std::string_view())
            .Add(rank ? rank->Reputation : 0)
            .Add(nextRank ? std::string_view(nextRank->Name) : std::string_view())
            .Add(nextRank ? nextRank->Reputation : 0)
            .Add(sameGuild ? member->Contribution : 0)
            .Add(sMiWowGuild.GetDailyPointsToday(player->GetGUID().GetCounter()))
            .Add(sMiWowGuild.GetConfig().DailyCap)
            .Add(uint32(GameTime::GetGameTime().count()) - std::min<uint32>(sMiWowGuild.GetSeasonStart(), uint32(GameTime::GetGameTime().count())))
            .Send(player);
    }

    // GUILD_PRIZES <n> (<puesto> <objeto> <cantidad>) x n
    void SendPrizes(Player* player)
    {
        auto const prizes = sMiWowGuild.GetPrizes();
        MiWowMessage message("GUILD_PRIZES");
        message.Add(uint32(prizes.size()));
        for (auto const& [position, item] : prizes)
            message.Add(position).Add(item.first).Add(item.second);
        message.Send(player);
    }

    // GUILD_RANKS <n> (<rango> <nombre> <reputacion>) x n
    void SendRanks(Player* player)
    {
        auto const& ranks = sMiWowGuild.GetRanks();
        MiWowMessage message("GUILD_RANKS");
        message.Add(uint32(ranks.size()));
        for (MiWowGuildRank const& rank : ranks)
            message.Add(rank.Rank).Add(rank.Name).Add(rank.Reputation);
        message.Send(player);
    }

    // GUILD_PERKS <n> (<puntos> <hechizo> <desbloqueada 0/1>) x n
    void SendPerks(Player* player)
    {
        MiWowGuildProgress const* progress = player->GetGuildId() ? sMiWowGuild.GetProgress(player->GetGuildId()) : nullptr;
        auto const& perks = sMiWowGuild.GetPerks();
        MiWowMessage message("GUILD_PERKS");
        message.Add(uint32(perks.size()));
        for (MiWowGuildPerk const& perk : perks)
            message.Add(perk.Points).Add(perk.SpellId).Add(progress && (progress->Perks & (1u << perk.Id)) ? 1 : 0);
        message.Send(player);
    }

    // GUILD_BOARD <segundos para la rotacion diaria> <semanal> <n>
    //   (<mision> <tablon 0/1> <titulo> <puntos> <reputacion> <miembros> <reclamada 0/1> <estado 0-4>
    //    <nivel, -1 = el del personaje> <tipo 0 individual/1 grupo/2 banda>) x n
    void SendBoard(Player* player)
    {
        MiWowGuildProgress const* progress = player->GetGuildId() ? sMiWowGuild.GetProgress(player->GetGuildId()) : nullptr;

        std::vector<uint32> board = sMiWowGuild.GetBoard();
        // Diarias primero
        std::stable_sort(board.begin(), board.end(), [](uint32 a, uint32 b)
        {
            return uint8(sMiWowGuild.GetQuest(a)->Board) < uint8(sMiWowGuild.GetQuest(b)->Board);
        });

        MiWowMessage message("GUILD_BOARD");
        message.Add(SecondsUntil(sMiWowGuild.GetDailyExpires())).Add(SecondsUntil(sMiWowGuild.GetWeeklyExpires()));

        std::vector<std::pair<MiWowGuildQuest const*, Quest const*>> entries;
        for (uint32 questId : board)
            if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                entries.emplace_back(sMiWowGuild.GetQuest(questId), quest);

        message.Add(uint32(entries.size()));
        for (auto const& [guildQuest, quest] : entries)
        {
            message.Add(quest->GetQuestId())
                .Add(uint8(guildQuest->Board))
                .Add(GetQuestTitle(player, quest))
                .Add(guildQuest->Points)
                .Add(guildQuest->Reputation)
                .Add(guildQuest->RequiredMembers)
                .Add(progress && progress->Claims.count(quest->GetQuestId()) ? 1 : 0)
                .Add(uint8(GetBoardStatus(player, quest)))
                .Add(quest->GetQuestLevel())
                .Add(uint8(GetQuestKind(guildQuest, quest)));
        }
        message.Send(player);
    }

    // GUILD_RANKING <puesto propio, 0 = sin puntos> <n> (<hermandad> <puntos>) x n
    void SendRanking(Player* player)
    {
        std::vector<MiWowGuildStanding> const standings = sMiWowGuild.GetStandings();
        uint32 position = 0;
        for (std::size_t i = 0; i < standings.size(); ++i)
            if (standings[i].GuildId == player->GetGuildId())
                position = uint32(i + 1);

        std::size_t const count = std::min(RankingSize, standings.size());
        MiWowMessage message("GUILD_RANKING");
        message.Add(position).Add(uint32(count));
        for (std::size_t i = 0; i < count; ++i)
        {
            Guild* guild = sGuildMgr->GetGuildById(standings[i].GuildId);
            message.Add(guild ? std::string_view(guild->GetName()) : std::string_view("?")).Add(standings[i].Points);
        }
        message.Send(player);
    }

    // GUILD_MEMBERS <n> (<personaje> <contribucion> <rango>) x n
    void SendMembers(Player* player)
    {
        MiWowMessage message("GUILD_MEMBERS");
        if (!player->GetGuildId())
        {
            message.Add(0).Send(player);
            return;
        }

        auto const standings = sMiWowGuild.GetMemberStandings(player->GetGuildId());
        std::size_t const count = std::min(RankingSize, standings.size());
        message.Add(uint32(count));
        for (std::size_t i = 0; i < count; ++i)
        {
            std::string name;
            if (!sCharacterCache->GetCharacterNameByGuid(ObjectGuid::Create<HighGuid::Player>(standings[i].first), name))
                name = "?";
            MiWowGuildRank const* rank = sMiWowGuild.GetRank(standings[i].second->Reputation);
            message.Add(name).Add(standings[i].second->Contribution).Add(rank ? std::string_view(rank->Name) : std::string_view());
        }
        message.Send(player);
    }

    // GUILD_VENDOR <n> (<objeto> <nombre> <rango minimo> <precio en cobre> <cantidad>) x n
    void SendVendor(Player* player)
    {
        std::vector<MiWowGuildVendorItem> const items = sMiWowGuild.GetActiveVendorItems();
        MiWowMessage message("GUILD_VENDOR");
        std::vector<std::pair<MiWowGuildVendorItem, ItemTemplate const*>> entries;
        for (MiWowGuildVendorItem const& item : items)
            if (ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item.ItemEntry))
                entries.emplace_back(item, proto);

        message.Add(uint32(entries.size()));
        for (auto const& [item, proto] : entries)
            message.Add(item.ItemEntry).Add(GetItemName(player, proto)).Add(item.Rank)
                .Add(item.Price ? item.Price : proto->BuyPrice).Add(std::max<uint32>(1, proto->BuyCount));
        message.Send(player);
    }

    void HandleInfo(Player* player, MiWowProtocol::Args const& /*args*/)
    {
        if (!sMiWowGuild.IsEnabled())
        {
            MiWowMessage("ERROR").Add("GUILD_DISABLED").Send(player);
            return;
        }

        if (!CheckCooldown(player, InfoTimeKey, InfoCooldownMs))
            return;

        MiWowGuildSendInfo(player);
    }

    // GUILD_BOARD_REOPEN: vuelta al tablon tras aceptar/entregar una mision (el core cierra el gossip). Solo si sigue
    // junto a un tablon y en hermandad; si no, nada.
    void HandleBoardReopen(Player* player, MiWowProtocol::Args const& /*args*/)
    {
        if (!sMiWowGuild.IsEnabled() || !player->GetGuildId() || !player->IsAlive() ||
            !CheckCooldown(player, ReopenTimeKey, BuyCooldownMs))
            return;

        if (GameObject* board = player->FindNearestGameObject(sMiWowGuild.GetConfig().BoardObject, BoardReopenRange, true))
            MiWowGuildShowBoard(player, board);
    }

    // GUILD_BUY <objeto>: el resultado llega como en un vendedor (objeto, errores nativos) + GUILD_DIRTY
    void HandleBuy(Player* player, MiWowProtocol::Args const& args)
    {
        if (!sMiWowGuild.IsEnabled() || args.empty() || !CheckCooldown(player, BuyTimeKey, BuyCooldownMs))
            return;

        Optional<uint32> const itemEntry = Acore::StringTo<uint32>(args[0]);
        if (!itemEntry)
            return;

        sMiWowGuild.BuyItem(player, *itemEntry);
        MiWowMessage("GUILD_DIRTY").Send(player);
    }
}

void MiWowGuildSendInfo(Player* player)
{
    // Tambien cuenta como peticion (el cliente vuelve a pedir al abrir la ventana)
    player->CustomData.GetDefault<InfoTime>(InfoTimeKey)->LastMs = uint32(GameTime::GetGameTimeMS().count());

    std::lock_guard<std::recursive_mutex> lock(MiWowGuildSeason::GetLock());
    SendState(player);
    SendRanks(player);
    SendPerks(player);
    SendPrizes(player);
    SendBoard(player);
    SendRanking(player);
    SendMembers(player);
    SendVendor(player);
}

void AddSC_miwow_guild_protocol()
{
    MiWowProtocol::RegisterHandler("GUILD_INFO", HandleInfo);
    MiWowProtocol::RegisterHandler("GUILD_BUY", HandleBuy);
    MiWowProtocol::RegisterHandler("GUILD_BOARD_REOPEN", HandleBoardReopen);
}
