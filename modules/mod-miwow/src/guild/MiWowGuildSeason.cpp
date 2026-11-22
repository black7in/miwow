#include "MiWowGuildSeason.h"
#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "GameObject.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "Guild.h"
#include "GuildMgr.h"
#include "Item.h"
#include "Log.h"
#include "Mail.h"
#include "Map.h"
#include "MiWowLobby.h"
#include "MiWowProtocol.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSessionMgr.h"
#include <algorithm>
#include <mutex>
#include <random>

namespace
{
    // Rotaciones y fin de temporada: se comprueban cada minuto
    constexpr uint32 UpdateInterval = 60 * IN_MILLISECONDS;

    constexpr char const* ChatPrefix = "|cff00ff96[Hermandad]|r ";

    // Categoria del registro de misiones (QuestSort.dbc 400 "Hermandad", SQL db-world 2026_11_21_01)
    constexpr int32 GuildQuestSort = -400;

    // Distancia maxima al intendente para comprar
    constexpr float ShopRange = 10.0f;

    // Estado compartido: los scripts de jugador corren en los hilos de los mapas (MapUpdate.Threads > 1)
    std::recursive_mutex& StateLock = MiWowGuildSeason::GetLock();

    // Peticiones de GM (comandos en el hilo de su mapa): se ejecutan en el hilo del mundo, porque cambian la lista
    // de misiones/objetos de los PNJ, que leen todos los mapas
    bool PendingEndSeason = false;
    bool PendingRotate[2] = { false, false };

    uint32 Now()
    {
        return uint32(GameTime::GetGameTime().count());
    }

    uint32 Today()
    {
        return Now() / DAY;
    }

    uint64 BlockKey(ObjectGuid::LowType guid, uint32 questId)
    {
        return (uint64(guid) << 32) | questId;
    }

    void SendChat(Player* player, std::string const& text)
    {
        ChatHandler(player->GetSession()).SendSysMessage(ChatPrefix + text);
    }

    void BroadcastToGuild(uint32 guildId, std::string const& text)
    {
        Guild* guild = sGuildMgr->GetGuildById(guildId);
        if (!guild)
            return;

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_SYSTEM, LANG_UNIVERSAL, nullptr, nullptr, ChatPrefix + text);
        guild->BroadcastPacket(&data);
    }

    void BroadcastToServer(std::string const& text)
    {
        sWorldSessionMgr->DoForAllOnlinePlayers([&text](Player* player)
        {
            ChatHandler(player->GetSession()).SendSysMessage(ChatPrefix + text);
        });
    }
}

std::recursive_mutex& MiWowGuildSeason::GetLock()
{
    static std::recursive_mutex lock;
    return lock;
}

MiWowGuildSeason& MiWowGuildSeason::Instance()
{
    static MiWowGuildSeason instance;
    return instance;
}

void MiWowGuildSeason::LoadConfig()
{
    _config.Enabled = sConfigMgr->GetOption<bool>("MiWow.Guild.Enable", true);
    _config.SeasonDays = sConfigMgr->GetOption<uint32>("MiWow.Guild.Season.Days", 30);
    _config.Announce = sConfigMgr->GetOption<bool>("MiWow.Guild.Season.Announce", true);
    _config.DailyCap = sConfigMgr->GetOption<uint32>("MiWow.Guild.DailyCap", 0);
    _config.ResetRepOnLeave = sConfigMgr->GetOption<bool>("MiWow.Guild.ResetRepOnLeave", true);
    _config.BoardDaily = sConfigMgr->GetOption<uint32>("MiWow.Guild.Board.Daily", 5);
    _config.BoardWeekly = sConfigMgr->GetOption<uint32>("MiWow.Guild.Board.Weekly", 2);
    _config.BoardObject = sConfigMgr->GetOption<uint32>("MiWow.Guild.BoardObject", 9500200);
    _config.VendorCreature = sConfigMgr->GetOption<uint32>("MiWow.Guild.VendorCreature", 9500201);
    _config.VendorItemCount = sConfigMgr->GetOption<uint32>("MiWow.Guild.Vendor.ItemCount", 10);
}

// Carga ---------------------------------------------------------------------------------------------------------

void MiWowGuildSeason::Load()
{
    if (!_config.Enabled)
    {
        LOG_INFO("module.miwow", "MiWow: temporadas de hermandad desactivadas");
        return;
    }

    std::lock_guard<std::recursive_mutex> lock(StateLock);

    if (!sObjectMgr->GetGameObjectTemplate(_config.BoardObject))
        LOG_ERROR("module.miwow", "MiWow: MiWow.Guild.BoardObject {} no existe (sin tablon no hay misiones)",
            _config.BoardObject);
    if (!sObjectMgr->GetCreatureTemplate(_config.VendorCreature))
        LOG_ERROR("module.miwow", "MiWow: MiWow.Guild.VendorCreature {} no existe", _config.VendorCreature);

    LoadDefinitions();
    LoadState();
    _loaded = true;
    _updateTimer = UpdateInterval;  // rotaciones pendientes en el primer tick

    // Tablon: primera vez, o el servidor estuvo apagado durante una rotacion (Update lo hace en el primer tick)
    ApplyBoardToObject();

    // Tienda: los de la temporada actual o una seleccion nueva
    if (_vendorActive.empty())
        RefreshVendor();

    LOG_INFO("module.miwow", "MiWow: temporada de hermandad {} ('{}'), {} hermandades con puntos, {} personajes",
        _seasonId, GetSeasonName(), _progress.size(), _members.size());
}

void MiWowGuildSeason::LoadDefinitions()
{
    _quests.clear();
    if (QueryResult result = WorldDatabase.Query(
        "SELECT `QuestId`, `Board`, `Points`, `Reputation`, `RequiredMembers` FROM `miwow_guild_quest` WHERE `Enabled` = 1"))
    {
        do
        {
            Field* fields = result->Fetch();
            MiWowGuildQuest quest;
            quest.QuestId = fields[0].Get<uint32>();
            quest.Board = fields[1].Get<uint8>() == 1 ? MiWowGuildBoard::Weekly : MiWowGuildBoard::Daily;
            quest.Points = fields[2].Get<uint32>();
            quest.Reputation = fields[3].Get<uint32>();
            quest.RequiredMembers = fields[4].Get<uint8>();

            Quest const* questTemplate = sObjectMgr->GetQuestTemplate(quest.QuestId);
            if (!questTemplate)
            {
                LOG_ERROR("module.miwow", "MiWow: miwow_guild_quest {}: la mision no existe, ignorada", quest.QuestId);
                continue;
            }
            if (questTemplate->GetZoneOrSort() != GuildQuestSort)
                LOG_WARN("module.miwow", "MiWow: miwow_guild_quest {}: QuestSortID {} (con -400 sale en la categoria "
                    "Hermandad del registro)", quest.QuestId, questTemplate->GetZoneOrSort());
            _quests[quest.QuestId] = quest;
        } while (result->NextRow());
    }

    _perks.clear();
    if (QueryResult result = WorldDatabase.Query(
        "SELECT `PerkId`, `Points`, `SpellId`, `Effect` FROM `miwow_guild_perk` ORDER BY `Points`"))
    {
        // Efectos del modulo; cualquier otro nombre = efecto del aura (agrupa los rangos)
        static std::unordered_map<std::string, MiWowGuildPerkEffect> const effects =
        {
            { "gold",       MiWowGuildPerkEffect::Gold },
            { "hearth",     MiWowGuildPerkEffect::Hearth },
            { "repair",     MiWowGuildPerkEffect::Repair },
            { "vendor",     MiWowGuildPerkEffect::Vendor },
            { "resurrect",  MiWowGuildPerkEffect::Resurrect },
            { "mail",       MiWowGuildPerkEffect::Mail },
            { "profession", MiWowGuildPerkEffect::Profession }
        };

        do
        {
            Field* fields = result->Fetch();
            MiWowGuildPerk perk;
            perk.Id = fields[0].Get<uint8>();
            perk.Points = fields[1].Get<uint32>();
            perk.SpellId = fields[2].Get<uint32>();
            perk.Group = fields[3].Get<std::string>();
            auto effect = effects.find(perk.Group);
            if (effect != effects.end())
                perk.Effect = effect->second;

            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(perk.SpellId);
            if (perk.Id >= 32)
                LOG_ERROR("module.miwow", "MiWow: miwow_guild_perk {}: PerkId debe ser 0-31, ignorada", perk.Id);
            else if (!spellInfo)
                LOG_ERROR("module.miwow", "MiWow: miwow_guild_perk {}: el hechizo {} no existe, ignorada", perk.Id, perk.SpellId);
            else
            {
                if (perk.Group.empty())
                    perk.Group = std::to_string(perk.Id);
                perk.Value = spellInfo->Effects[EFFECT_0].CalcValue();
                _perks.push_back(perk);
            }
        } while (result->NextRow());
    }

    _ranks.clear();
    if (QueryResult result = WorldDatabase.Query("SELECT `Rank`, `Name`, `Reputation` FROM `miwow_guild_rank` ORDER BY `Reputation`"))
    {
        do
        {
            Field* fields = result->Fetch();
            _ranks.push_back({ fields[0].Get<uint8>(), fields[1].Get<std::string>(), fields[2].Get<uint32>() });
        } while (result->NextRow());
    }
    if (_ranks.empty() || _ranks.front().Reputation != 0)
        _ranks.insert(_ranks.begin(), { 0, "Recluta", 0 });

    _vendorPool.clear();
    if (QueryResult result = WorldDatabase.Query(
        "SELECT `ItemEntry`, `Rank`, `Price` FROM `miwow_guild_vendor` WHERE `Enabled` = 1"))
    {
        do
        {
            Field* fields = result->Fetch();
            MiWowGuildVendorItem item{ fields[0].Get<uint32>(), fields[1].Get<uint8>(), fields[2].Get<uint32>() };
            if (!sObjectMgr->GetItemTemplate(item.ItemEntry))
            {
                LOG_ERROR("module.miwow", "MiWow: miwow_guild_vendor {}: el objeto no existe, ignorado", item.ItemEntry);
                continue;
            }
            _vendorPool.push_back(item);
        } while (result->NextRow());
    }

    _seasons.clear();
    if (QueryResult result = WorldDatabase.Query("SELECT `SeasonId`, `Name`, `DurationDays` FROM `miwow_guild_season`"))
    {
        do
        {
            Field* fields = result->Fetch();
            _seasons[fields[0].Get<uint32>()] = { fields[1].Get<std::string>(), fields[2].Get<uint16>() };
        } while (result->NextRow());
    }

    _prizes.clear();
    if (QueryResult result = WorldDatabase.Query("SELECT `SeasonId`, `Position`, `ItemEntry`, `ItemCount` FROM `miwow_guild_prize`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const entry = fields[2].Get<uint32>();
            if (!sObjectMgr->GetItemTemplate(entry))
            {
                LOG_ERROR("module.miwow", "MiWow: miwow_guild_prize: el objeto {} no existe, ignorado", entry);
                continue;
            }
            _prizes[fields[0].Get<uint32>()][fields[1].Get<uint8>()].emplace_back(entry, std::max<uint32>(1, fields[3].Get<uint16>()));
        } while (result->NextRow());
    }

    LOG_INFO("module.miwow", "MiWow: hermandad: {} misiones, {} ventajas, {} rangos, {} objetos de intendente",
        _quests.size(), _perks.size(), _ranks.size(), _vendorPool.size());
}

void MiWowGuildSeason::LoadState()
{
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT `SeasonId`, `StartTime`, `DailyExpires`, `WeeklyExpires` FROM `miwow_guild_state` WHERE `Id` = 1"))
    {
        Field* fields = result->Fetch();
        _seasonId = std::max<uint32>(1, fields[0].Get<uint32>());
        _seasonStart = fields[1].Get<uint32>();
        _dailyExpires = fields[2].Get<uint32>();
        _weeklyExpires = fields[3].Get<uint32>();
    }
    else
    {
        _seasonId = 1;
        _seasonStart = Now();
        _dailyExpires = 0;
        _weeklyExpires = 0;
        SaveState();
    }

    // Hermandades que ya no existen (disueltas con el servidor apagado, borradas a mano...)
    _progress.clear();
    if (QueryResult result = CharacterDatabase.Query("SELECT `GuildId`, `Points`, `Perks` FROM `miwow_guild_progress`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const guildId = fields[0].Get<uint32>();
            if (!sGuildMgr->GetGuildById(guildId))
            {
                CharacterDatabase.Execute("DELETE FROM `miwow_guild_progress` WHERE `GuildId` = {}", guildId);
                CharacterDatabase.Execute("DELETE FROM `miwow_guild_claim` WHERE `GuildId` = {}", guildId);
                continue;
            }
            _progress[guildId] = { fields[1].Get<uint64>(), fields[2].Get<uint32>(), {} };
        } while (result->NextRow());
    }

    if (QueryResult result = CharacterDatabase.Query("SELECT `GuildId`, `QuestId` FROM `miwow_guild_claim`"))
    {
        do
        {
            Field* fields = result->Fetch();
            auto itr = _progress.find(fields[0].Get<uint32>());
            if (itr != _progress.end())
                itr->second.Claims.insert(fields[1].Get<uint32>());
        } while (result->NextRow());
    }

    _members.clear();
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT `Guid`, `GuildId`, `Reputation`, `Contribution`, `DailyPoints`, `DailyDay` FROM `miwow_guild_member`"))
    {
        do
        {
            Field* fields = result->Fetch();
            MiWowGuildMember member;
            member.GuildId = fields[1].Get<uint32>();
            member.Reputation = fields[2].Get<uint32>();
            member.Contribution = fields[3].Get<uint32>();
            member.DailyPoints = fields[4].Get<uint32>();
            member.DailyDay = fields[5].Get<uint32>();
            _members[fields[0].Get<uint32>()] = member;
        } while (result->NextRow());
    }

    _blockedQuests.clear();
    if (QueryResult result = CharacterDatabase.Query("SELECT `Guid`, `QuestId` FROM `miwow_guild_quest_block`"))
    {
        do
        {
            Field* fields = result->Fetch();
            _blockedQuests.insert(BlockKey(fields[0].Get<uint32>(), fields[1].Get<uint32>()));
        } while (result->NextRow());
    }

    _board.clear();
    if (QueryResult result = CharacterDatabase.Query("SELECT `QuestId` FROM `miwow_guild_board`"))
    {
        do
        {
            uint32 const questId = result->Fetch()[0].Get<uint32>();
            if (_quests.count(questId))
                _board.push_back(questId);
        } while (result->NextRow());
    }

    _vendorActive.clear();
    if (QueryResult result = CharacterDatabase.Query(
        "SELECT `ItemEntry` FROM `miwow_guild_vendor_active` WHERE `SeasonId` = {}", _seasonId))
    {
        do
        {
            uint32 const entry = result->Fetch()[0].Get<uint32>();
            auto itr = std::find_if(_vendorPool.begin(), _vendorPool.end(),
                [entry](MiWowGuildVendorItem const& item) { return item.ItemEntry == entry; });
            if (itr != _vendorPool.end())
                _vendorActive.push_back(entry);
        } while (result->NextRow());
    }
}

void MiWowGuildSeason::SaveState() const
{
    CharacterDatabase.Execute("REPLACE INTO `miwow_guild_state` (`Id`, `SeasonId`, `StartTime`, `DailyExpires`, `WeeklyExpires`) "
        "VALUES (1, {}, {}, {}, {})", _seasonId, _seasonStart, _dailyExpires, _weeklyExpires);
}

void MiWowGuildSeason::SaveMember(ObjectGuid::LowType guid, MiWowGuildMember const& member) const
{
    CharacterDatabase.Execute("REPLACE INTO `miwow_guild_member` (`Guid`, `GuildId`, `Reputation`, `Contribution`, `DailyPoints`, `DailyDay`) "
        "VALUES ({}, {}, {}, {}, {}, {})", guid, member.GuildId, member.Reputation, member.Contribution, member.DailyPoints, member.DailyDay);
}

void MiWowGuildSeason::SaveProgress(uint32 guildId, MiWowGuildProgress const& progress) const
{
    CharacterDatabase.Execute("REPLACE INTO `miwow_guild_progress` (`GuildId`, `Points`, `Perks`) VALUES ({}, {}, {})",
        guildId, progress.Points, progress.Perks);
}

// Ciclo ---------------------------------------------------------------------------------------------------------

void MiWowGuildSeason::Update(uint32 diff)
{
    if (!IsEnabled())
        return;

    bool pending;
    {
        std::lock_guard<std::recursive_mutex> lock(StateLock);
        pending = PendingEndSeason || PendingRotate[0] || PendingRotate[1];
    }

    _updateTimer += diff;
    if (_updateTimer < UpdateInterval && !pending)
        return;
    _updateTimer = 0;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    uint32 const now = Now();

    uint32 const seasonEnd = GetSeasonEnd();
    if (PendingEndSeason || (seasonEnd && now >= seasonEnd))
    {
        PendingEndSeason = false;
        DoEndSeason();
    }

    // Rotacion con el reinicio de misiones del servidor. Si World aun no ha avanzado su proximo reinicio (lo hace en
    // su propio Update), se espera al siguiente tick para no rotar dos veces.
    for (MiWowGuildBoard board : { MiWowGuildBoard::Daily, MiWowGuildBoard::Weekly })
    {
        bool const daily = board == MiWowGuildBoard::Daily;
        uint32& expires = daily ? _dailyExpires : _weeklyExpires;
        bool& forced = PendingRotate[daily ? 0 : 1];
        if (!forced && now < expires)
            continue;

        uint32 const next = uint32((daily ? sWorld->GetNextDailyQuestsResetTime() : sWorld->GetNextWeeklyQuestsResetTime()).count());
        if (next <= now)
            continue;

        forced = false;
        DoRotateBoard(board);
        expires = next;
        SaveState();
    }
}

// Comandos de GM (hilo de un mapa): lo hace el hilo del mundo en el siguiente tick (Update)
void MiWowGuildSeason::RotateBoard(MiWowGuildBoard board)
{
    std::lock_guard<std::recursive_mutex> lock(StateLock);
    PendingRotate[board == MiWowGuildBoard::Daily ? 0 : 1] = true;
}

void MiWowGuildSeason::EndSeason()
{
    std::lock_guard<std::recursive_mutex> lock(StateLock);
    PendingEndSeason = true;
}

void MiWowGuildSeason::DoRotateBoard(MiWowGuildBoard board)
{
    // Salen las de este tablon (y sus reclamaciones)
    std::vector<uint32> kept;
    for (uint32 questId : _board)
    {
        MiWowGuildQuest const* quest = GetQuest(questId);
        if (quest && quest->Board != board)
        {
            kept.push_back(questId);
            continue;
        }
        for (auto& [guildId, progress] : _progress)
            progress.Claims.erase(questId);
        CharacterDatabase.Execute("DELETE FROM `miwow_guild_claim` WHERE `QuestId` = {}", questId);
        CharacterDatabase.Execute("DELETE FROM `miwow_guild_board` WHERE `QuestId` = {}", questId);
    }
    _board = std::move(kept);

    std::vector<uint32> pool;
    for (auto const& [questId, quest] : _quests)
        if (quest.Board == board)
            pool.push_back(questId);

    std::shuffle(pool.begin(), pool.end(), std::mt19937{ std::random_device{}() });
    uint32 const count = std::min<uint32>(board == MiWowGuildBoard::Daily ? _config.BoardDaily : _config.BoardWeekly, uint32(pool.size()));
    for (uint32 i = 0; i < count; ++i)
    {
        _board.push_back(pool[i]);
        CharacterDatabase.Execute("REPLACE INTO `miwow_guild_board` (`QuestId`, `Board`) VALUES ({}, {})", pool[i], uint32(board));
    }

    ApplyBoardToObject();
    LOG_INFO("module.miwow", "MiWow: tablon {} de hermandad: {} misiones", board == MiWowGuildBoard::Daily ? "diario" : "semanal", count);
    NotifyChanged(0);
}

// El tablon ofrece sus misiones y recoge todas las de hermandad (aunque ya hayan rotado). Solo en el hilo del mundo
// o al arrancar: los mapas leen estas listas.
void MiWowGuildSeason::ApplyBoardToObject()
{
    uint32 const entry = _config.BoardObject;
    if (!sObjectMgr->GetGameObjectTemplate(entry))
        return;

    QuestRelations* starters = sObjectMgr->GetGOQuestRelationMap();
    QuestRelations* enders = sObjectMgr->GetGOQuestInvolvedRelationMap();
    starters->erase(entry);
    enders->erase(entry);

    for (uint32 questId : _board)
        starters->emplace(entry, questId);
    for (auto const& [questId, quest] : _quests)
        enders->emplace(entry, questId);
}

void MiWowGuildSeason::RefreshVendor()
{
    _vendorActive.clear();

    std::vector<MiWowGuildVendorItem> pool = _vendorPool;
    std::shuffle(pool.begin(), pool.end(), std::mt19937{ std::random_device{}() });
    uint32 const count = std::min<uint32>(_config.VendorItemCount, uint32(pool.size()));
    // Ordenados por rango: la tienda los muestra en este orden
    pool.resize(count);
    std::stable_sort(pool.begin(), pool.end(),
        [](MiWowGuildVendorItem const& a, MiWowGuildVendorItem const& b) { return a.Rank < b.Rank; });

    CharacterDatabase.Execute("DELETE FROM `miwow_guild_vendor_active`");
    for (MiWowGuildVendorItem const& item : pool)
    {
        _vendorActive.push_back(item.ItemEntry);
        CharacterDatabase.Execute("INSERT INTO `miwow_guild_vendor_active` (`ItemEntry`, `SeasonId`) VALUES ({}, {})",
            item.ItemEntry, _seasonId);
    }

    LOG_INFO("module.miwow", "MiWow: tienda de la temporada {}: {} objetos", _seasonId, count);
}

// Temporada -----------------------------------------------------------------------------------------------------

std::string MiWowGuildSeason::GetSeasonName() const
{
    auto itr = _seasons.find(_seasonId);
    if (itr != _seasons.end() && !itr->second.first.empty())
        return itr->second.first;
    return Acore::StringFormat("Temporada {}", _seasonId);
}

uint32 MiWowGuildSeason::GetSeasonEnd() const
{
    auto itr = _seasons.find(_seasonId);
    uint32 const days = itr != _seasons.end() ? itr->second.second : _config.SeasonDays;
    return days ? _seasonStart + days * DAY : 0;
}

void MiWowGuildSeason::DoEndSeason()
{
    std::vector<MiWowGuildStanding> const standings = GetStandings();
    LOG_INFO("module.miwow", "MiWow: fin de la temporada de hermandad {} ({} hermandades con puntos)", _seasonId, standings.size());

    std::string const seasonName = GetSeasonName();
    for (std::size_t i = 0; i < standings.size() && i < 10; ++i)
    {
        Guild* guild = sGuildMgr->GetGuildById(standings[i].GuildId);
        std::string name = guild ? guild->GetName() : "";
        CharacterDatabase.EscapeString(name);
        CharacterDatabase.Execute("REPLACE INTO `miwow_guild_history` (`SeasonId`, `Position`, `GuildId`, `GuildName`, `Points`) "
            "VALUES ({}, {}, {}, '{}', {})", _seasonId, i + 1, standings[i].GuildId, name, standings[i].Points);
    }

    AwardPrizes(standings);

    if (_config.Announce)
    {
        BroadcastToServer(Acore::StringFormat("¡Ha terminado la {}!", seasonName));
        for (std::size_t i = 0; i < standings.size() && i < 3; ++i)
            if (Guild* guild = sGuildMgr->GetGuildById(standings[i].GuildId))
                BroadcastToServer(Acore::StringFormat("{}.º puesto: <{}> con {} puntos.", i + 1, guild->GetName(), standings[i].Points));
    }

    // Todo a 0 salvo la reputacion personal
    _progress.clear();
    for (auto& [guid, member] : _members)
        member.Contribution = 0;
    CharacterDatabase.Execute("DELETE FROM `miwow_guild_progress`");
    CharacterDatabase.Execute("DELETE FROM `miwow_guild_claim`");
    CharacterDatabase.Execute("UPDATE `miwow_guild_member` SET `Contribution` = 0");

    ++_seasonId;
    _seasonStart = Now();
    SaveState();
    RefreshVendor();

    if (_config.Announce)
        BroadcastToServer(Acore::StringFormat("Comienza la {}.", GetSeasonName()));

    // Las ventajas se quitan solas (RefreshPerks cada pocos segundos)
    NotifyChanged(0);
}

void MiWowGuildSeason::AwardPrizes(std::vector<MiWowGuildStanding> const& standings)
{
    auto seasonItr = _prizes.find(_seasonId);
    if (seasonItr == _prizes.end())
        seasonItr = _prizes.find(0);
    if (seasonItr == _prizes.end())
        return;

    for (std::size_t i = 0; i < standings.size(); ++i)
    {
        uint8 const position = uint8(i + 1);
        auto prizeItr = seasonItr->second.find(position);
        if (prizeItr == seasonItr->second.end())
            continue;

        Guild* guild = sGuildMgr->GetGuildById(standings[i].GuildId);
        if (!guild)
            continue;

        MailDraft draft(Acore::StringFormat("{}: {}.º puesto", GetSeasonName(), position),
            Acore::StringFormat("¡Enhorabuena! Tu hermandad <{}> ha quedado en el puesto {} de la {} con {} puntos.",
                guild->GetName(), position, GetSeasonName(), standings[i].Points));

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        uint32 items = 0;
        for (auto const& [entry, count] : prizeItr->second)
        {
            if (items >= MAX_MAIL_ITEMS)
            {
                LOG_ERROR("module.miwow", "MiWow: premio del puesto {}: mas de {} objetos, sobran", position, MAX_MAIL_ITEMS);
                break;
            }
            if (Item* item = Item::CreateItem(entry, count, nullptr))
            {
                item->SaveToDB(trans);
                draft.AddItem(item);
                ++items;
            }
        }
        draft.SendMailTo(trans, MailReceiver(guild->GetLeaderGUID().GetCounter()), MailSender(MAIL_NORMAL, 0, MAIL_STATIONERY_GM));
        CharacterDatabase.CommitTransaction(trans);

        LOG_INFO("module.miwow", "MiWow: premio del puesto {} enviado al lider de <{}>", position, guild->GetName());
    }
}

// Personajes ----------------------------------------------------------------------------------------------------

// Ficha del personaje al dia con su hermandad actual. Si cambio (entro, salio, le expulsaron desconectado, se
// disolvio...), la contribucion se pierde y la reputacion segun ResetRepOnLeave.
MiWowGuildMember& MiWowGuildSeason::SyncMember(ObjectGuid::LowType guid, uint32 guildId)
{
    MiWowGuildMember& member = _members[guid];
    if (member.GuildId == guildId)
        return member;

    if (member.GuildId != 0)
    {
        member.Contribution = 0;
        if (_config.ResetRepOnLeave)
            member.Reputation = 0;
    }
    member.GuildId = guildId;
    SaveMember(guid, member);
    return member;
}

void MiWowGuildSeason::OnLogin(Player* player)
{
    if (!IsEnabled())
        return;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    if (player->GetGuildId() || _members.count(guid))
        SyncMember(guid, player->GetGuildId());
}

void MiWowGuildSeason::OnGuildChanged(Player* player, uint32 guildId)
{
    if (!IsEnabled())
        return;

    {
        std::lock_guard<std::recursive_mutex> lock(StateLock);
        ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
        MiWowGuildMember const* old = GetMember(guid);
        bool const hadReputation = old && old->Reputation > 0;
        uint32 const oldGuild = old ? old->GuildId : 0;
        SyncMember(guid, guildId);

        if (oldGuild && oldGuild != guildId && hadReputation && _config.ResetRepOnLeave)
            SendChat(player, "Has dejado la hermandad: tu reputación de hermandad vuelve a 0.");
    }

    // Las ventajas se quitan/ponen en el hilo del propio personaje (RefreshPerks, cada pocos segundos): quien le
    // expulsa o le invita puede estar en otro mapa

    NotifyChanged(0);
}

void MiWowGuildSeason::OnGuildCreated(uint32 /*guildId*/)
{
    NotifyChanged(0);
}

void MiWowGuildSeason::OnGuildDisbanded(uint32 guildId)
{
    if (!IsEnabled())
        return;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    _progress.erase(guildId);
    CharacterDatabase.Execute("DELETE FROM `miwow_guild_progress` WHERE `GuildId` = {}", guildId);
    CharacterDatabase.Execute("DELETE FROM `miwow_guild_claim` WHERE `GuildId` = {}", guildId);
    // Las fichas de los miembros se ponen al dia al conectarse (SyncMember)
    NotifyChanged(0);
}

// Como el diseno original (HasGuildMembersInGroup): miembros de la misma hermandad en el grupo o banda, conectados
// (vivos o muertos, en cualquier mapa), contando al personaje
uint32 MiWowGuildSeason::CountGuildMembersInGroup(Player* player) const
{
    uint32 const guildId = player->GetGuildId();
    Group const* group = player->GetGroup();
    if (!group)
        return 1;

    uint32 count = 0;
    for (GroupReference const* itr = group->GetFirstMember(); itr; itr = itr->next())
        if (Player const* member = itr->GetSource())
            if (member->GetGuildId() == guildId)
                ++count;
    return count;
}

bool MiWowGuildSeason::CanCompleteQuest(Player* player, uint32 questId)
{
    if (!IsEnabled())
        return true;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    MiWowGuildQuest const* guildQuest = GetQuest(questId);
    if (!guildQuest)
        return true;

    Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
    std::string const title = quest ? quest->GetTitle() : std::to_string(questId);
    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    uint64 const key = BlockKey(guid, questId);

    if (_blockedQuests.count(key))
    {
        SendChat(player, Acore::StringFormat("«{}» no se completó en grupo: abandónala y vuelve a hacerla.", title));
        return false;
    }

    std::string reason;
    if (!player->GetGuildId())
        reason = "hace falta pertenecer a una hermandad";
    else if (guildQuest->RequiredMembers > 0)
    {
        uint32 const members = CountGuildMembersInGroup(player);
        if (!player->GetGroup())
            reason = "hay que ir en grupo";
        else if (members < guildQuest->RequiredMembers)
            reason = Acore::StringFormat("hacían falta {} miembros de tu hermandad en el grupo (había {})",
                guildQuest->RequiredMembers, members);
    }

    if (reason.empty())
        return true;

    _blockedQuests.insert(key);
    CharacterDatabase.Execute("REPLACE INTO `miwow_guild_quest_block` (`Guid`, `QuestId`) VALUES ({}, {})", guid, questId);
    SendChat(player, Acore::StringFormat("«{}» no se completa: {}. Abandónala y vuelve a hacerla.", title, reason));
    NotifyChanged(player->GetGuildId());
    return false;
}

void MiWowGuildSeason::OnQuestAccepted(Player* player, uint32 questId)
{
    OnQuestAbandoned(player, questId);
}

// Aceptar o abandonar: se quita el bloqueo y la ventana del personaje se pone al dia
void MiWowGuildSeason::OnQuestAbandoned(Player* player, uint32 questId)
{
    if (!IsEnabled())
        return;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    if (!GetQuest(questId))
        return;

    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    if (_blockedQuests.erase(BlockKey(guid, questId)))
        CharacterDatabase.Execute("DELETE FROM `miwow_guild_quest_block` WHERE `Guid` = {} AND `QuestId` = {}", guid, questId);
    MiWowMessage("GUILD_DIRTY").Send(player);
}

bool MiWowGuildSeason::IsQuestBlocked(ObjectGuid::LowType guid, uint32 questId) const
{
    return _blockedQuests.count(BlockKey(guid, questId)) != 0;
}

void MiWowGuildSeason::OnQuestRewarded(Player* player, Quest const* quest)
{
    if (!IsEnabled())
        return;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    MiWowGuildQuest const* guildQuest = GetQuest(quest->GetQuestId());
    if (!guildQuest)
        return;

    uint32 const guildId = player->GetGuildId();
    if (!guildId)
    {
        SendChat(player, "No perteneces a ninguna hermandad: sin recompensa de hermandad.");
        return;
    }

    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    SyncMember(guid, guildId);

    if (guildQuest->Reputation)
        AddReputation(player, guildQuest->Reputation);

    if (!guildQuest->Points)
    {
        NotifyChanged(guildId);
        return;
    }

    // Individual: puntos en cada entrega. De grupo (el grupo ya se comprobo al completarla, CanCompleteQuest): los
    // puntos solo la primera vez que la entrega la hermandad mientras sigue en el tablon; el resto, solo reputacion
    if (guildQuest->RequiredMembers > 0)
    {
        MiWowGuildProgress& progress = _progress[guildId];
        if (progress.Claims.count(quest->GetQuestId()))
        {
            SendChat(player, "Tu hermandad ya entregó esta misión de grupo: solo recibes reputación.");
            NotifyChanged(guildId);
            return;
        }
        progress.Claims.insert(quest->GetQuestId());
        CharacterDatabase.Execute("REPLACE INTO `miwow_guild_claim` (`GuildId`, `QuestId`, `ClaimedBy`, `ClaimedAt`) VALUES ({}, {}, {}, {})",
            guildId, quest->GetQuestId(), guid, Now());
    }

    uint32 const added = AddPoints(guildId, guid, guildQuest->Points);
    if (!added)
    {
        SendChat(player, "Has llegado al límite diario de puntos de temporada.");
        NotifyChanged(guildId);
        return;
    }

    uint64 const total = _progress[guildId].Points;
    if (guildQuest->RequiredMembers > 0)
        BroadcastToGuild(guildId, Acore::StringFormat("¡La hermandad completó «{}»: +{} puntos! (temporada: {})",
            quest->GetTitle(), added, total));
    else
        BroadcastToGuild(guildId, Acore::StringFormat("{} completó «{}»: +{} puntos. (temporada: {})",
            player->GetName(), quest->GetTitle(), added, total));
}

uint32 MiWowGuildSeason::AddPoints(uint32 guildId, ObjectGuid::LowType contributor, uint32 points, bool ignoreCap)
{
    std::lock_guard<std::recursive_mutex> lock(StateLock);
    if (!guildId || !points)
        return 0;

    MiWowGuildMember* member = nullptr;
    if (contributor)
    {
        member = &SyncMember(contributor, guildId);
        uint32 const today = Today();
        if (member->DailyDay != today)
        {
            member->DailyDay = today;
            member->DailyPoints = 0;
        }

        if (_config.DailyCap && !ignoreCap)
        {
            uint32 const remaining = _config.DailyCap > member->DailyPoints ? _config.DailyCap - member->DailyPoints : 0;
            points = std::min(points, remaining);
            if (!points)
                return 0;
        }

        member->DailyPoints += points;
        member->Contribution += points;
        SaveMember(contributor, *member);
    }

    MiWowGuildProgress& progress = _progress[guildId];
    progress.Points += points;
    SaveProgress(guildId, progress);
    CheckPerks(guildId);
    NotifyChanged(guildId);
    return points;
}

void MiWowGuildSeason::AddReputation(Player* player, uint32 amount)
{
    std::lock_guard<std::recursive_mutex> lock(StateLock);
    if (!amount || !player->GetGuildId())
        return;

    ObjectGuid::LowType const guid = player->GetGUID().GetCounter();
    MiWowGuildMember& member = SyncMember(guid, player->GetGuildId());
    MiWowGuildRank const* before = GetRank(member.Reputation);
    member.Reputation += amount;
    SaveMember(guid, member);

    SendChat(player, Acore::StringFormat("+{} de reputación de hermandad (total: {}).", amount, member.Reputation));
    MiWowGuildRank const* after = GetRank(member.Reputation);
    if (after && after != before)
    {
        SendChat(player, Acore::StringFormat("¡Nuevo rango de hermandad: {}!", after->Name));
        BroadcastToGuild(player->GetGuildId(), Acore::StringFormat("{} ha alcanzado el rango {}.", player->GetName(), after->Name));
    }
    NotifyChanged(player->GetGuildId());
}

// Ventajas nuevas: solo cambia el estado; cada miembro se pone el aura en su propio hilo (RefreshPerks)
void MiWowGuildSeason::CheckPerks(uint32 guildId)
{
    MiWowGuildProgress& progress = _progress[guildId];
    bool changed = false;
    for (MiWowGuildPerk const& perk : _perks)
    {
        uint32 const flag = 1u << perk.Id;
        if ((progress.Perks & flag) || progress.Points < perk.Points)
            continue;

        progress.Perks |= flag;
        changed = true;
        // Sin nombre: el DBC del servidor esta en ingles (la ventana del cliente la muestra en su idioma)
        BroadcastToGuild(guildId, Acore::StringFormat("¡Nueva ventaja de hermandad desbloqueada ({} puntos)! Mírala con /temporada.",
            perk.Points));
        LOG_INFO("module.miwow", "MiWow: la hermandad {} desbloquea la ventaja {} (hechizo {})", guildId, perk.Id, perk.SpellId);
    }

    if (changed)
        SaveProgress(guildId, progress);
}

MiWowGuildPerk const* MiWowGuildSeason::GetActivePerk(uint32 unlocked, std::string const& group) const
{
    // _perks va por Points ascendente: gana la ultima
    MiWowGuildPerk const* best = nullptr;
    for (MiWowGuildPerk const& perk : _perks)
        if (perk.Group == group && (unlocked & (1u << perk.Id)))
            best = &perk;
    return best;
}

int32 MiWowGuildSeason::GetPerkValue(Player const* player, MiWowGuildPerkEffect effect) const
{
    // Valen en todas partes (decision del usuario 2026-11-21: tambien eventos, campos de batalla y arenas)
    uint32 const guildId = player->GetGuildId();
    if (!IsEnabled() || !guildId)
        return 0;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    MiWowGuildProgress const* progress = GetProgress(guildId);
    if (!progress)
        return 0;

    int32 value = 0;
    for (MiWowGuildPerk const& perk : _perks)
        if (perk.Effect == effect && (progress->Perks & (1u << perk.Id)))
            value = perk.Value;
    return value;
}

bool MiWowGuildSeason::GuildHasPerk(uint32 guildId, MiWowGuildPerkEffect effect) const
{
    if (!IsEnabled() || !guildId)
        return false;

    std::lock_guard<std::recursive_mutex> lock(StateLock);
    MiWowGuildProgress const* progress = GetProgress(guildId);
    if (!progress)
        return false;

    for (MiWowGuildPerk const& perk : _perks)
        if (perk.Effect == effect && (progress->Perks & (1u << perk.Id)))
            return true;
    return false;
}

void MiWowGuildSeason::RemoveStalePerkSpells(Player* player)
{
    // Rango de los hechizos de ventaja (data/spells/hermandad.toml)
    constexpr uint32 PerkSpellFirst = 9504000;
    constexpr uint32 PerkSpellLast = 9504099;

    std::vector<uint32> stale;
    for (auto const& [spellId, spell] : player->GetSpellMap())
    {
        if (spellId < PerkSpellFirst || spellId > PerkSpellLast || spell->State == PLAYERSPELL_REMOVED)
            continue;

        // Copia: clang < 16 no deja capturar un structured binding en una lambda
        uint32 const id = spellId;
        bool const isPerk = IsEnabled() && std::any_of(_perks.begin(), _perks.end(),
            [id](MiWowGuildPerk const& perk) { return perk.SpellId == id; });
        if (!isPerk)
            stale.push_back(spellId);
    }

    // removeSpell cambia el mapa: despues de recorrerlo
    for (uint32 spellId : stale)
    {
        LOG_INFO("module.miwow", "MiWow: {} olvida el hechizo de ventaja {} (ya no es ventaja de hermandad)",
            player->GetName(), spellId);
        player->removeSpell(spellId, SPEC_MASK_ALL, false);
    }
}

void MiWowGuildSeason::RefreshPerks(Player* player)
{
    if (!IsEnabled() || _perks.empty())
        return;

    // Pasivas que debe saber: de cada grupo, el rango mas alto desbloqueado
    std::unordered_set<uint32> wanted;
    if (uint32 const guildId = player->GetGuildId())
    {
        std::lock_guard<std::recursive_mutex> lock(StateLock);
        if (MiWowGuildProgress const* progress = GetProgress(guildId))
            for (MiWowGuildPerk const& perk : _perks)
                if (GetActivePerk(progress->Perks, perk.Group) == &perk)
                    wanted.insert(perk.SpellId);
    }

    // Hechizos pasivos aprendidos (libro de hechizos, pestana General; como los raciales): el aura no se envia al
    // cliente (Aura::CanBeSentToClient), no sale en los beneficios y sigue tras morir. Se guardan en character_spell:
    // al conectar se comprueban otra vez (expulsado desconectado, temporada nueva...). Mensaje nativo al aprender/olvidar.
    for (MiWowGuildPerk const& perk : _perks)
    {
        bool const want = wanted.count(perk.SpellId) != 0;
        bool const has = player->HasSpell(perk.SpellId);
        if (want && !has)
            player->learnSpell(perk.SpellId);
        else if (!want && has)
            player->removeSpell(perk.SpellId, SPEC_MASK_ALL, false);
    }
}

bool MiWowGuildSeason::BuyItem(Player* player, uint32 itemEntry)
{
    if (!IsEnabled())
        return false;

    if (!player->GetGuildId())
    {
        SendChat(player, "Solo los miembros de una hermandad pueden comprar en la tienda de la hermandad.");
        return false;
    }

    Creature* vendor = player->FindNearestCreature(_config.VendorCreature, ShopRange);
    if (!vendor)
    {
        SendChat(player, "Habla con el intendente de la hermandad para comprar.");
        return false;
    }

    uint32 price = 0;
    {
        std::lock_guard<std::recursive_mutex> lock(StateLock);
        auto active = std::find(_vendorActive.begin(), _vendorActive.end(), itemEntry);
        auto itr = std::find_if(_vendorPool.begin(), _vendorPool.end(),
            [itemEntry](MiWowGuildVendorItem const& item) { return item.ItemEntry == itemEntry; });
        if (active == _vendorActive.end() || itr == _vendorPool.end())
        {
            SendChat(player, "Ese objeto no está a la venta esta temporada.");
            return false;
        }

        MiWowGuildMember const* member = GetMember(player->GetGUID().GetCounter());
        MiWowGuildRank const* rank = GetRank(member && member->GuildId == player->GetGuildId() ? member->Reputation : 0);
        if (!rank || rank->Rank < itr->Rank)
        {
            auto required = std::find_if(_ranks.begin(), _ranks.end(), [&](MiWowGuildRank const& r) { return r.Rank == itr->Rank; });
            player->SendBuyError(BUY_ERR_REPUTATION_REQUIRE, vendor, itemEntry, 0);
            SendChat(player, Acore::StringFormat("Necesitas el rango de hermandad {} para comprar esto.",
                required != _ranks.end() ? required->Name : std::to_string(itr->Rank)));
            return false;
        }
        price = itr->Price;
    }

    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemEntry);
    if (!proto)
        return false;

    uint32 const count = std::max<uint32>(1, proto->BuyCount);
    if (!price)
        price = proto->BuyPrice;

    if (!player->HasEnoughMoney(price))
    {
        player->SendBuyError(BUY_ERR_NOT_ENOUGHT_MONEY, vendor, itemEntry, 0);
        return false;
    }

    ItemPosCountVec dest;
    InventoryResult const result = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, itemEntry, count);
    if (result != EQUIP_ERR_OK)
    {
        player->SendEquipError(result, nullptr, nullptr, itemEntry);
        return false;
    }

    player->ModifyMoney(-int32(price));
    if (Item* item = player->StoreNewItem(dest, itemEntry, true, Item::GenerateItemRandomPropertyId(itemEntry)))
        player->SendNewItem(item, count, true, false);

    LOG_DEBUG("module.miwow", "MiWow: {} compra {} x{} en la tienda de la hermandad por {} cobre", player->GetName(),
        itemEntry, count, price);
    return true;
}

// Consultas -----------------------------------------------------------------------------------------------------

MiWowGuildProgress const* MiWowGuildSeason::GetProgress(uint32 guildId) const
{
    auto itr = _progress.find(guildId);
    return itr != _progress.end() ? &itr->second : nullptr;
}

MiWowGuildMember const* MiWowGuildSeason::GetMember(ObjectGuid::LowType guid) const
{
    auto itr = _members.find(guid);
    return itr != _members.end() ? &itr->second : nullptr;
}

MiWowGuildQuest const* MiWowGuildSeason::GetQuest(uint32 questId) const
{
    auto itr = _quests.find(questId);
    return itr != _quests.end() ? &itr->second : nullptr;
}

std::vector<MiWowGuildVendorItem> MiWowGuildSeason::GetActiveVendorItems() const
{
    std::vector<MiWowGuildVendorItem> items;
    for (uint32 entry : _vendorActive)
    {
        auto itr = std::find_if(_vendorPool.begin(), _vendorPool.end(),
            [entry](MiWowGuildVendorItem const& item) { return item.ItemEntry == entry; });
        if (itr != _vendorPool.end())
            items.push_back(*itr);
    }
    return items;
}

std::vector<std::pair<uint8, std::pair<uint32, uint32>>> MiWowGuildSeason::GetPrizes() const
{
    std::vector<std::pair<uint8, std::pair<uint32, uint32>>> result;
    auto seasonItr = _prizes.find(_seasonId);
    if (seasonItr == _prizes.end())
        seasonItr = _prizes.find(0);
    if (seasonItr == _prizes.end())
        return result;

    for (auto const& [position, items] : seasonItr->second)
        for (auto const& item : items)
            result.push_back({ position, item });
    std::sort(result.begin(), result.end(), [](auto const& a, auto const& b) { return a.first < b.first; });
    return result;
}

MiWowGuildRank const* MiWowGuildSeason::GetRank(uint32 reputation) const
{
    MiWowGuildRank const* result = nullptr;
    for (MiWowGuildRank const& rank : _ranks)
        if (reputation >= rank.Reputation)
            result = &rank;
    return result;
}

MiWowGuildRank const* MiWowGuildSeason::GetNextRank(uint32 reputation) const
{
    for (MiWowGuildRank const& rank : _ranks)
        if (rank.Reputation > reputation)
            return &rank;
    return nullptr;
}

MiWowGuildPerk const* MiWowGuildSeason::GetNextPerk(uint64 points) const
{
    for (MiWowGuildPerk const& perk : _perks)
        if (perk.Points > points)
            return &perk;
    return nullptr;
}

std::vector<MiWowGuildStanding> MiWowGuildSeason::GetStandings() const
{
    std::vector<MiWowGuildStanding> standings;
    for (auto const& [guildId, progress] : _progress)
        if (progress.Points > 0 && sGuildMgr->GetGuildById(guildId))
            standings.push_back({ guildId, progress.Points });

    // Empates: la hermandad mas antigua (id menor) primero
    std::sort(standings.begin(), standings.end(), [](MiWowGuildStanding const& a, MiWowGuildStanding const& b)
    {
        return a.Points != b.Points ? a.Points > b.Points : a.GuildId < b.GuildId;
    });
    return standings;
}

uint32 MiWowGuildSeason::GetPosition(uint32 guildId) const
{
    std::vector<MiWowGuildStanding> const standings = GetStandings();
    for (std::size_t i = 0; i < standings.size(); ++i)
        if (standings[i].GuildId == guildId)
            return uint32(i + 1);
    return 0;
}

std::vector<std::pair<ObjectGuid::LowType, MiWowGuildMember const*>> MiWowGuildSeason::GetMemberStandings(uint32 guildId) const
{
    std::vector<std::pair<ObjectGuid::LowType, MiWowGuildMember const*>> result;
    Guild* guild = sGuildMgr->GetGuildById(guildId);
    if (!guild)
        return result;

    for (auto const& [guid, member] : _members)
        if (member.GuildId == guildId && guild->GetMember(ObjectGuid::Create<HighGuid::Player>(guid)))
            result.emplace_back(guid, &member);

    std::sort(result.begin(), result.end(), [](auto const& a, auto const& b)
    {
        if (a.second->Contribution != b.second->Contribution)
            return a.second->Contribution > b.second->Contribution;
        return a.second->Reputation > b.second->Reputation;
    });
    return result;
}

uint32 MiWowGuildSeason::GetDailyPointsToday(ObjectGuid::LowType guid) const
{
    MiWowGuildMember const* member = GetMember(guid);
    return member && member->DailyDay == Today() ? member->DailyPoints : 0;
}

void MiWowGuildSeason::NotifyChanged(uint32 guildId) const
{
    MiWowMessage const message("GUILD_DIRTY");
    MiWowProtocol::ForEachConnected([&](Player* player)
    {
        if (!guildId || player->GetGuildId() == guildId)
            message.Send(player);
    });
}
