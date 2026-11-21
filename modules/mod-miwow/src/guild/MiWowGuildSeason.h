#ifndef MOD_MIWOW_GUILD_SEASON_H
#define MOD_MIWOW_GUILD_SEASON_H

#include "Define.h"
#include "ObjectGuid.h"
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class GameObject;
class Player;
class Quest;

// Temporadas de hermandad (rama tradicional). Diseno original: mod-guild-season (newserver-wotlk), rehecho sin tocar
// el esquema ni el core: definiciones en tablas miwow_guild_* de la BD world, estado en la BD characters.
//  - Puntos de temporada: de la hermandad, desbloquean ventajas (auras) y deciden la clasificacion. Vuelven a 0
//    con cada temporada; el podio recibe premios por correo (al lider).
//  - Reputacion personal: permanente, da rangos (miwow_guild_rank) que abren objetos del intendente.
//  - Contribucion: puntos aportados por cada miembro en la temporada (clasificacion interna).
//  - Tablon (objeto MiWow.Guild.BoardObject): misiones diarias/semanales al azar entre las de miwow_guild_quest; las
//    ofrece y las recoge el propio tablon. Categoria "Hermandad" del registro: QuestSortID -400 (QuestSort.dbc 400).
//  - Tienda: la del intendente (MiWow.Guild.VendorCreature), propia (ventana del cliente, GUILD_BUY): objetos de la
//    temporada por rango de reputacion, precio propio.
// Todo en el hilo del mundo (scripts, WorldScript::OnUpdate, handlers del protocolo).
enum class MiWowGuildBoard : uint8
{
    Daily = 0,
    Weekly = 1
};

struct MiWowGuildQuest
{
    uint32 QuestId = 0;
    MiWowGuildBoard Board = MiWowGuildBoard::Daily;
    uint32 Points = 0;
    uint32 Reputation = 0;
    uint8 RequiredMembers = 0;
};

// Efecto de una ventaja (miwow_guild_perk.Effect). Aura = lo hace el aura del hechizo (montura, experiencia,
// reputacion, honor); el resto lo hace el modulo con el valor del efecto 1 del hechizo (data/spells/hermandad.toml).
enum class MiWowGuildPerkEffect : uint8
{
    Aura = 0,
    Gold,        // % extra del dinero despojado al banco de la hermandad
    Hearth,      // minutos menos de reutilizacion de la piedra de hogar
    Repair,      // % menos al reparar
    Vendor,      // % menos en los vendedores
    Resurrect,   // % extra de salud/mana al resucitar
    Mail,        // correo instantaneo entre miembros
    Profession   // % de probabilidad de un punto extra de profesion
};

struct MiWowGuildPerk
{
    uint8 Id = 0;
    uint32 Points = 0;
    uint32 SpellId = 0;
    std::string Group;  // Effect de la tabla: las ventajas del mismo grupo son rangos (solo vale la mas alta)
    MiWowGuildPerkEffect Effect = MiWowGuildPerkEffect::Aura;
    int32 Value = 0;    // efecto 1 del hechizo
};

struct MiWowGuildRank
{
    uint8 Rank = 0;
    std::string Name;
    uint32 Reputation = 0;
};

struct MiWowGuildVendorItem
{
    uint32 ItemEntry = 0;
    uint8 Rank = 0;
    uint32 Price = 0;  // cobre; 0 = precio de compra del objeto
};

struct MiWowGuildProgress
{
    uint64 Points = 0;
    uint32 Perks = 0;  // bit = PerkId
    std::unordered_set<uint32> Claims;  // misiones de grupo ya entregadas (mientras siguen en el tablon)
};

struct MiWowGuildMember
{
    uint32 GuildId = 0;
    uint32 Reputation = 0;
    uint32 Contribution = 0;
    uint32 DailyPoints = 0;
    uint32 DailyDay = 0;
};

struct MiWowGuildConfig
{
    bool Enabled = true;
    uint32 SeasonDays = 30;
    bool Announce = true;
    uint32 DailyCap = 0;
    bool ResetRepOnLeave = true;
    uint32 BoardDaily = 5;
    uint32 BoardWeekly = 2;
    uint32 BoardObject = 9500200;
    uint32 VendorCreature = 9500201;
    uint32 VendorItemCount = 10;
};

// Posicion en la clasificacion global
struct MiWowGuildStanding
{
    uint32 GuildId = 0;
    uint64 Points = 0;
};

class MiWowGuildSeason
{
public:
    static MiWowGuildSeason& Instance();

    void LoadConfig();
    void Load();      // al arrancar el mundo (despues de cargar hermandades y misiones)
    void Update(uint32 diff);

    MiWowGuildConfig const& GetConfig() const { return _config; }
    // Los scripts de jugador corren en los hilos de los mapas: quien lea varias cosas seguidas (protocolo,
    // comandos) toma este cerrojo; los metodos que cambian el estado ya lo toman
    static std::recursive_mutex& GetLock();
    bool IsEnabled() const { return _config.Enabled && _loaded; }

    // Personaje
    void OnLogin(Player* player);
    void OnGuildChanged(Player* player, uint32 guildId);  // entra (guildId) o sale (0) estando conectado
    void OnGuildCreated(uint32 guildId);
    void OnGuildDisbanded(uint32 guildId);
    // Al COMPLETAR una mision de hermandad (objetivos cumplidos: matar al jefe, al aceptarla si no tiene objetivos...):
    // hace falta hermandad y, si es de grupo, ir en grupo con RequiredMembers miembros en el mismo mapa. Si no, no se
    // completa y queda bloqueada hasta abandonarla y volver a aceptarla (si no, se completaria al ir en grupo a
    // entregarla: el core vuelve a intentar completarla al entregar). false = no se completa (ya avisado).
    bool CanCompleteQuest(Player* player, uint32 questId);
    void OnQuestAccepted(Player* player, uint32 questId);
    void OnQuestAbandoned(Player* player, uint32 questId);
    bool IsQuestBlocked(ObjectGuid::LowType guid, uint32 questId) const;
    void OnQuestRewarded(Player* player, Quest const* quest);
    // Ensena/quita las pasivas de ventaja segun la hermandad (al conectar y cada pocos segundos)
    void RefreshPerks(Player* player);
    // Al conectar: olvida los hechizos de ventaja (PerkSpellFirst-Last) que ya no son ventaja (fila quitada de
    // miwow_guild_perk o sistema desactivado: RefreshPerks ya no los revisa)
    void RemoveStalePerkSpells(Player* player);
    // Valor de la ventaja activa con ese efecto para el personaje (0 = ninguna)
    int32 GetPerkValue(Player const* player, MiWowGuildPerkEffect effect) const;
    // La hermandad tiene desbloqueada alguna ventaja con ese efecto (sin mirar a ningun personaje: correo)
    bool GuildHasPerk(uint32 guildId, MiWowGuildPerkEffect effect) const;
    // Compra en la tienda de la hermandad (junto al intendente). false = no (ya avisado)
    bool BuyItem(Player* player, uint32 itemEntry);

    // Consultas (protocolo, comandos)
    uint32 GetSeasonId() const { return _seasonId; }
    std::string GetSeasonName() const;
    uint32 GetSeasonStart() const { return _seasonStart; }
    uint32 GetSeasonEnd() const;  // unix; 0 = sin fin
    uint32 GetDailyExpires() const { return _dailyExpires; }
    uint32 GetWeeklyExpires() const { return _weeklyExpires; }
    MiWowGuildProgress const* GetProgress(uint32 guildId) const;
    MiWowGuildMember const* GetMember(ObjectGuid::LowType guid) const;
    MiWowGuildQuest const* GetQuest(uint32 questId) const;
    std::vector<MiWowGuildPerk> const& GetPerks() const { return _perks; }
    std::vector<MiWowGuildRank> const& GetRanks() const { return _ranks; }
    std::vector<uint32> const& GetBoard() const { return _board; }
    std::vector<MiWowGuildVendorItem> GetActiveVendorItems() const;
    // Premios de la temporada actual (o los de SeasonId 0): puesto -> (objeto, cantidad)
    std::vector<std::pair<uint8, std::pair<uint32, uint32>>> GetPrizes() const;
    MiWowGuildRank const* GetRank(uint32 reputation) const;
    MiWowGuildRank const* GetNextRank(uint32 reputation) const;
    MiWowGuildPerk const* GetNextPerk(uint64 points) const;
    std::vector<MiWowGuildStanding> GetStandings() const;  // hermandades con puntos, de mas a menos
    uint32 GetPosition(uint32 guildId) const;               // 1.. (0 = sin puntos)
    // Miembros de la hermandad (actuales) con su ficha, de mas a menos contribucion
    std::vector<std::pair<ObjectGuid::LowType, MiWowGuildMember const*>> GetMemberStandings(uint32 guildId) const;
    uint32 GetDailyPointsToday(ObjectGuid::LowType guid) const;

    // GM / pruebas
    uint32 AddPoints(uint32 guildId, ObjectGuid::LowType contributor, uint32 points, bool ignoreCap = false);
    void AddReputation(Player* player, uint32 amount);
    // Se hacen en el siguiente Update (hilo del mundo: cambian las listas de los PNJ, que leen todos los mapas)
    void RotateBoard(MiWowGuildBoard board);
    void EndSeason();

    // Avisa a los miembros conectados de la hermandad (0 = a todos) de que su informacion cambio
    void NotifyChanged(uint32 guildId) const;

private:
    MiWowGuildSeason() = default;

    void LoadDefinitions();
    void LoadState();
    void SaveState() const;
    MiWowGuildMember& SyncMember(ObjectGuid::LowType guid, uint32 guildId);
    void SaveMember(ObjectGuid::LowType guid, MiWowGuildMember const& member) const;
    void SaveProgress(uint32 guildId, MiWowGuildProgress const& progress) const;
    void CheckPerks(uint32 guildId);
    void DoRotateBoard(MiWowGuildBoard board);
    void DoEndSeason();
    void AwardPrizes(std::vector<MiWowGuildStanding> const& standings);
    void ApplyBoardToObject();
    void RefreshVendor();
    uint32 CountGuildMembersInGroup(Player* player) const;
    // La ventaja que vale de un grupo: la desbloqueada con mas puntos
    MiWowGuildPerk const* GetActivePerk(uint32 unlocked, std::string const& group) const;

    MiWowGuildConfig _config;
    bool _loaded = false;
    uint32 _updateTimer = 0;

    // Definiciones (world)
    std::unordered_map<uint32, MiWowGuildQuest> _quests;
    std::vector<MiWowGuildPerk> _perks;  // por Points ascendente
    std::vector<MiWowGuildRank> _ranks;  // por Reputation ascendente
    std::vector<MiWowGuildVendorItem> _vendorPool;
    std::unordered_map<uint32, std::pair<std::string, uint32>> _seasons;  // SeasonId -> nombre, dias
    // SeasonId -> puesto -> (objeto, cantidad)
    std::unordered_map<uint32, std::unordered_map<uint8, std::vector<std::pair<uint32, uint32>>>> _prizes;

    // Estado (characters)
    uint32 _seasonId = 1;
    uint32 _seasonStart = 0;
    uint32 _dailyExpires = 0;
    uint32 _weeklyExpires = 0;
    std::vector<uint32> _board;
    std::vector<uint32> _vendorActive;
    std::unordered_map<uint32, MiWowGuildProgress> _progress;
    std::unordered_map<ObjectGuid::LowType, MiWowGuildMember> _members;
    std::unordered_set<uint64> _blockedQuests;  // (guid << 32) | mision
};

#define sMiWowGuild MiWowGuildSeason::Instance()

// Toda la informacion de la ventana (MiWowGuildProtocol.cpp): GUILD_STATE, _RANKS, _PERKS, _PRIZES, _BOARD, _RANKING,
// _MEMBERS, _VENDOR. Toma el cerrojo.
void MiWowGuildSendInfo(Player* player);

// Abre el tablon (MiWowGuildScripts.cpp): GUILD_BOARD_OPEN + la info y el gossip con sus misiones. Al hacer clic en el
// objeto y al volver de la ventana de misiones (GUILD_BOARD_REOPEN: el core cierra el gossip al aceptar/entregar).
void MiWowGuildShowBoard(Player* player, GameObject* go);

#endif
