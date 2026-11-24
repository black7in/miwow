#include "MiWowGames.h"
#include "MiWowMatch.h"
#include "MiWowMatchMgr.h"
#include "MiWowStats.h"
#include "Config.h"
#include "Containers.h"
#include "CreatureAI.h"
#include "GameObject.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "Random.h"
#include "ScriptMgr.h"
#include "ScriptedCreature.h"
#include "ScriptedGossip.h"
#include "TemporarySummon.h"
#include "WorldSession.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <fstream>
#include <limits>
#include <sstream>
#include <unordered_map>

// Defensa del castillo (juego "castillo", mapa 755). Individual, nivel 80, con su personaje y equipo.
// Ver docs/castillo-estado.md.
//
// Mapa: canon con un solo camino desde el portal de las oleadas hasta la torre del castillo (tools/mapgen/castlegen.py,
// Maps/Planos/defensa_castillo.json). Lo lee el servidor de <DataDir>/maps/<mapa>_castillo.txt al arrancar:
//   spawn | portal | boss | gate | start | vendor | guard  X Y Z O
//                                               aparicion, portal, jefe final, torre, jugador, intendente, guardias
//   path X Y Z                                  ruta de las oleadas (el ultimo = donde atacan la torre)
//   object | door <entry> X Y Z O               edificios opcionales (door = se ve danada con la vida)
//
// Partida: 5 etapas x (3 oleadas + jefe). Cada etapa con sus enemigos y su jefe; la dificultad sube con las etapas
// (vida/dano en el SQL, 2026_11_24_01_miwow_castle.sql) y con las oleadas (mas enemigos).
//  - El castillo es una torre: la criatura "Torre del castillo" (seleccionable: se ve su vida). Los enemigos salen
//    del portal, siguen la ruta, pelean con quien se encuentren (jugador o guardias) y al llegar atacan la torre.
//    Si su vida llega a 0 se pierde.
//  - El jefe final espera dormido junto al portal desde el principio (invoca las oleadas), sin poder ser atacado.
//    En la ultima etapa las oleadas son infinitas (cada vuelta de 3, +15 % de enemigos) y el jefe ya se puede atacar:
//    cuando el jugador (o algo suyo) le hace dano, despierta, sale con su escolta y va a por la torre (oleada del
//    jefe). El jugador decide cuando: mientras tanto sigue ganando oro.
//  - 3 guardias delante de la torre. Entre etapas reviven los caidos, se curan y la torre se repara un poco.
//  - Morir: se reaparece delante de la torre a los 8 s (el castillo sigue recibiendo golpes).
//  - Se gana al acabar con la oleada del jefe final (el y los que queden).
//  - Cada oleada superada da un bonus de oro (30 + 15 por etapa).
//  - Dificultad (Facil, Medio, Dificil, Extremo): la elige el jugador al empezar en la ventana de eleccion del
//    framework (MiWowMatch::ShowChoice; si no, Medio al minuto). Escala la vida y el dano (tambien de hechizos)
//    de los enemigos y cuantos salen en cada oleada.
//  - Oro del castillo (moneda de la partida, no se guarda): cada invasor que mata el jugador (o su mascota,
//    totems...) suma oro (mas en etapas altas y por los jefes); los que rematan los guardias no dan oro.
//  - El intendente, junto a la torre, abre la tienda (ventana del cliente): pocas mejoras que se notan en PvE y dos
//    packs, a precio fijo y sin limite (ShopOffers). Son stats temporales (MiWowStats, como un objeto) que se
//    quitan al salir de la partida (framework).
// HUD: el texto del objetivo del framework (MATCH_HUD, varias lineas) y avisos en el centro de la pantalla.
namespace
{
    constexpr uint32 NPC_CASTLE_GATE = 9500500;
    constexpr uint32 NPC_CASTLE_GUARD = 9500501;
    constexpr uint32 NPC_CASTLE_PORTAL = 9500502;
    constexpr uint32 NPC_CASTLE_VENDOR = 9500503;
    constexpr uint32 VENDOR_TEXT = 9500503;            // npc_text

    constexpr Milliseconds TickInterval = 250ms;
    constexpr Milliseconds SpawnInterval = 500ms;
    constexpr Milliseconds FirstStageDelay = 15s;
    constexpr Milliseconds StageDelay = 20s;
    constexpr Milliseconds WaveDelay = 8s;
    constexpr Milliseconds GateAlertCooldown = 15s;
    constexpr Seconds RespawnDelay = 8s;
    constexpr Milliseconds CorpseDelay = 10s;
    // Reparacion de la torre entre etapas (fraccion de la vida maxima)
    constexpr float GateRepair = 0.10f;
    // Separacion lateral al azar de los enemigos en la aparicion
    constexpr float SpawnSpread = 8.0f;

    // --- Mapa -------------------------------------------------------------------------------------------------

    struct CastleObject
    {
        uint32 Entry = 0;
        Position Pos;
        bool Door = false;
    };

    struct CastleLayout
    {
        Position Spawn;
        Position Portal;
        Position Boss;
        Position Gate;
        Position Start;
        Position Vendor;
        std::vector<Position> Guards;
        std::vector<Position> Path;
        std::vector<CastleObject> Objects;
    };

    std::unordered_map<uint32, CastleLayout> Layouts;

    bool LoadLayout(uint32 mapId, CastleLayout& layout)
    {
        // DataDir de la config (los scripts se registran antes de que World lea la suya; el valor es el mismo)
        std::string path = sConfigMgr->GetOption<std::string>("DataDir", "./");
        if (!path.empty() && path.back() != '/' && path.back() != '\\')
            path += '/';
        char name[32];
        std::snprintf(name, sizeof(name), "maps/%03u_castillo.txt", mapId);
        path += name;

        std::ifstream file(path);
        if (!file)
        {
            LOG_ERROR("module.miwow", "MiWow: castillo: no existe {} (lo genera tools/Build-Patch.ps1)", path);
            return false;
        }

        bool spawn = false, gate = false, start = false, portal = false, boss = false, vendor = false;
        std::string line;
        while (std::getline(file, line))
        {
            if (!line.empty() && line.back() == '\r')
                line.pop_back();

            std::istringstream in(line);
            std::string kind;
            in >> kind;
            float x, y, z, o;
            if (kind == "path")
            {
                if (in >> x >> y >> z)
                    layout.Path.emplace_back(x, y, z, 0.0f);
            }
            else if (kind == "object" || kind == "door")
            {
                CastleObject object;
                if (!(in >> object.Entry >> x >> y >> z >> o))
                    continue;

                object.Pos.Relocate(x, y, z, o);
                object.Door = kind == "door";
                layout.Objects.push_back(object);
            }
            else if (in >> x >> y >> z >> o)
            {
                Position const pos(x, y, z, o);
                if (kind == "spawn")
                    layout.Spawn = pos, spawn = true;
                else if (kind == "portal")
                    layout.Portal = pos, portal = true;
                else if (kind == "boss")
                    layout.Boss = pos, boss = true;
                else if (kind == "gate")
                    layout.Gate = pos, gate = true;
                else if (kind == "start")
                    layout.Start = pos, start = true;
                else if (kind == "vendor")
                    layout.Vendor = pos, vendor = true;
                else if (kind == "guard")
                    layout.Guards.push_back(pos);
            }
        }

        if (!spawn || !gate || !start || layout.Path.empty())
        {
            LOG_ERROR("module.miwow", "MiWow: castillo: {} incompleto (spawn, gate, start y path)", path);
            return false;
        }

        if (!portal)
            layout.Portal = layout.Spawn;
        if (!boss)
            layout.Boss = layout.Spawn;
        if (!vendor)
            layout.Vendor = layout.Start;

        LOG_INFO("module.miwow", "MiWow: castillo: mapa {}: ruta de {} puntos, {} guardias, {} edificios", mapId,
            layout.Path.size(), layout.Guards.size(), layout.Objects.size());
        return true;
    }

    // --- Enemigos ---------------------------------------------------------------------------------------------

    enum class CastleTarget : uint8
    {
        Victim,     // su objetivo actual
        Random,     // un jugador al azar a 40 yd (o su objetivo si no hay)
        Self        // sobre si mismo (areas alrededor)
    };

    struct CastleAbility
    {
        uint32 Spell = 0;
        Milliseconds First = 0ms;
        Milliseconds Repeat = 0ms;
        CastleTarget Target = CastleTarget::Victim;
    };

    struct CastleInvaderInfo
    {
        uint32 Entry = 0;
        std::vector<CastleAbility> Abilities;
        // Enfurecer por debajo de un % de vida (una vez)
        uint32 EnrageSpell = 0;
        float EnragePct = 0.0f;
        // Refuerzos por debajo de un % de vida (una vez); se van con el si muere
        uint32 AddEntry = 0;
        uint8 AddCount = 0;
        float AddPct = 0.0f;
    };

    // Hechizos de PNJ de mazmorras de 5 de WotLK (comprobados en el Spell.dbc; docs/castillo-estado.md)
    constexpr uint32 SPELL_CLEAVE = 15284;              // Rajar: 110 % del arma al objetivo
    constexpr uint32 SPELL_CLEAVE_2 = 15496;            // Rajar
    constexpr uint32 SPELL_MORTAL_STRIKE = 16856;       // Golpe mortal: 200 % del arma, -50 % curacion
    constexpr uint32 SPELL_WHIRLWIND = 52027;           // Torbellino
    constexpr uint32 SPELL_CHARGE = 60067;              // Cargar: dano + aturdir
    constexpr uint32 SPELL_REND = 59343;                // Desgarrar: sangrado
    constexpr uint32 SPELL_FEARSOME_ROAR = 48849;       // Rugido aterrador: -dano de los enemigos cercanos
    constexpr uint32 SPELL_ENRAGE = 8599;               // Enfurecer: +dano, +velocidad de ataque
    constexpr uint32 SPELL_SHADOW_BOLT = 53333;         // Descarga de las Sombras
    constexpr uint32 SPELL_POISON_CLOUD = 49548;        // Nube de veneno (area en el objetivo)
    constexpr uint32 SPELL_CRUSH = 50234;               // Machacar: 150 % del arma + aturdir
    constexpr uint32 SPELL_CHAIN_LIGHTNING = 48140;     // Cadena de relampagos
    constexpr uint32 SPELL_SHATTERING_STOMP = 52237;    // Pisoton destrozador: area 33 yd
    constexpr uint32 SPELL_EARTH_SHOCK = 54511;         // Choque de tierra: dano + interrumpir
    constexpr uint32 SPELL_SHADOW_VOLLEY = 57942;       // Salva de descarga de las Sombras: area 48 yd
    constexpr uint32 SPELL_FLAME_BREATH = 54282;        // Aliento de llamas: cono delante

    std::vector<CastleInvaderInfo> const InvaderInfos =
    {
        // Etapa 1: vrykul
        { 9500510, { { SPELL_CLEAVE, 5s, 9s } } },
        { 9500511, { { SPELL_MORTAL_STRIKE, 6s, 10s } } },
        { 9500519, { { SPELL_MORTAL_STRIKE, 5s, 9s }, { SPELL_CHARGE, 8s, 18s, CastleTarget::Random },
            { SPELL_WHIRLWIND, 12s, 22s, CastleTarget::Self } } },
        // Etapa 2: la jauria
        { 9500520, { { SPELL_REND, 4s, 15s } } },
        { 9500529, { { SPELL_REND, 6s, 12s }, { SPELL_FEARSOME_ROAR, 10s, 25s, CastleTarget::Self } },
            SPELL_ENRAGE, 30.0f },
        // Etapa 3: la Plaga
        { 9500531, { { SPELL_SHADOW_BOLT, 1s, 4s } } },
        { 9500539, { { SPELL_CLEAVE, 5s, 7s }, { SPELL_POISON_CLOUD, 8s, 18s, CastleTarget::Random },
            { SPELL_CRUSH, 12s, 15s } } },
        // Etapa 4: elementales
        { 9500541, { { SPELL_CHAIN_LIGHTNING, 3s, 9s } } },
        { 9500549, { { SPELL_EARTH_SHOCK, 6s, 10s }, { SPELL_SHATTERING_STOMP, 15s, 25s, CastleTarget::Self } } },
        // Etapa 5: la Legion
        { 9500550, { { SPELL_SHADOW_BOLT, 1s, 5s } } },
        { 9500551, { { SPELL_CLEAVE_2, 4s, 8s } } },
        { 9500559, { { SPELL_CLEAVE, 5s, 7s }, { SPELL_SHADOW_VOLLEY, 10s, 16s, CastleTarget::Self },
            { SPELL_FLAME_BREATH, 14s, 20s } },
            SPELL_ENRAGE, 20.0f, 9500550, 4, 50.0f },
    };

    CastleInvaderInfo const* GetInvaderInfo(uint32 entry)
    {
        auto itr = std::find_if(InvaderInfos.begin(), InvaderInfos.end(),
            [entry](CastleInvaderInfo const& info) { return info.Entry == entry; });
        return itr != InvaderInfos.end() ? &*itr : nullptr;
    }

    // --- Etapas -----------------------------------------------------------------------------------------------

    struct CastleSpawn
    {
        uint32 Entry = 0;
        uint8 Count = 0;
    };

    constexpr uint8 WavesPerStage = 3;

    struct CastleStage
    {
        char const* Name;
        std::array<std::vector<CastleSpawn>, WavesPerStage> Waves;
        uint32 Boss;
        std::vector<CastleSpawn> Escort;     // acompanan al jefe (salen antes que el)
    };

    // Al menos 20 enemigos por oleada; el jefe sale el ultimo, tras su escolta
    std::vector<CastleStage> const Stages =
    {
        { "Los vrykul",
            { { { { 9500510, 20 } }, { { 9500510, 14 }, { 9500511, 7 } }, { { 9500510, 14 }, { 9500511, 10 } } } },
            9500519, { { 9500510, 8 }, { 9500511, 6 } } },
        { "La jauría",
            { { { { 9500520, 20 } }, { { 9500520, 14 }, { 9500521, 8 } }, { { 9500520, 14 }, { 9500521, 10 } } } },
            9500529, { { 9500520, 8 }, { 9500521, 6 } } },
        { "La Plaga",
            { { { { 9500530, 18 }, { 9500531, 3 } }, { { 9500530, 16 }, { 9500531, 6 } },
                { { 9500530, 18 }, { 9500531, 8 } } } },
            9500539, { { 9500530, 10 }, { 9500531, 4 } } },
        { "Los elementales",
            { { { { 9500540, 12 }, { 9500541, 8 } }, { { 9500540, 13 }, { 9500541, 9 } },
                { { 9500540, 14 }, { 9500541, 10 } } } },
            9500549, { { 9500540, 8 }, { 9500541, 6 } } },
        { "La Legión",
            { { { { 9500550, 12 }, { 9500551, 8 } }, { { 9500550, 12 }, { 9500551, 9 }, { 9500552, 1 } },
                { { 9500550, 14 }, { 9500551, 10 }, { 9500552, 2 } } } },
            9500559, { { 9500550, 8 }, { 9500551, 6 } } },
    };

    bool IsStageBoss(uint32 entry)
    {
        return std::any_of(Stages.begin(), Stages.end(), [entry](CastleStage const& stage) { return stage.Boss == entry; });
    }

    // Oro del castillo por enemigo muerto (stage = 0..4)
    uint32 WaveGold(uint32 stage)
    {
        return 30 + 15 * stage;
    }

    // Oro del castillo por enemigo muerto (stage = 0..4)
    uint32 KillGold(uint32 entry, uint32 stage)
    {
        return IsStageBoss(entry) ? 150 + 50 * stage : 8 + 4 * stage;
    }

    // --- Dificultad -------------------------------------------------------------------------------------------

    struct CastleDifficulty
    {
        char const* Name;
        float Health;       // vida de los enemigos (x)
        float Damage;       // dano de los enemigos, golpes y hechizos (x)
        float Count;        // enemigos por oleada (x)
        char const* Info;
    };

    std::array<CastleDifficulty, 4> const Difficulties =
    { {
        { "Fácil", 0.7f, 0.7f, 0.75f, "enemigos con -30 % de vida y daño, y -25 % de enemigos" },
        { "Medio", 1.0f, 1.0f, 1.0f, "la defensa tal cual" },
        { "Difícil", 1.4f, 1.35f, 1.25f, "+40 % de vida, +35 % de daño y +25 % de enemigos" },
        { "Extremo", 2.0f, 1.8f, 1.5f, "+100 % de vida, +80 % de daño y +50 % de enemigos" },
    } };

    constexpr uint32 DefaultDifficulty = 1;
    // Etapa final: enemigos de mas por cada vuelta de las 3 oleadas
    constexpr float EndlessGrowth = 0.15f;
    constexpr Milliseconds ChooseTimeout = 60s;
    constexpr std::string_view DifficultyChoice = "dificultad";     // id de la ventana de eleccion

    // --- Tienda del intendente --------------------------------------------------------------------------------

    struct CastleStatBonus
    {
        MiWowStat Stat;
        int32 Amount;
    };

    // Lo que vende el intendente: precio fijo (no sube con las compras) y sin limite. Solo stats que se notan en PvE.
    struct CastleOffer
    {
        char const* Category;
        char const* Name;
        char const* Icon;    // Interface\\Icons\\<Icon>
        uint32 Price;
        std::vector<CastleStatBonus> Stats;
        char const* Detail;  // nullptr = "Llevas +N" de su primera stat
    };

    // Bloques que se repiten en los packs
    std::vector<CastleStatBonus> const AttributeBonus =
    {
        { MiWowStat::Strength, 150 }, { MiWowStat::Agility, 150 }, { MiWowStat::Stamina, 150 },
        { MiWowStat::Intellect, 150 }, { MiWowStat::Spirit, 150 },
    };

    std::vector<CastleStatBonus> Join(std::initializer_list<std::vector<CastleStatBonus>> parts)
    {
        std::vector<CastleStatBonus> all;
        for (auto const& part : parts)
            all.insert(all.end(), part.begin(), part.end());
        return all;
    }

    std::vector<CastleOffer> const ShopOffers =
    {
        { "Mejoras", "Vida +3000", "INV_Potion_54", 40, { { MiWowStat::Health, 3000 } }, nullptr },
        { "Mejoras", "Maná +3000", "INV_Potion_76", 40, { { MiWowStat::Mana, 3000 } }, nullptr },
        { "Mejoras", "Atributos +150", "Spell_Holy_WordFortitude", 60, AttributeBonus, nullptr },
        { "Mejoras", "Poder de ataque +300", "Ability_Warrior_BattleShout", 40, { { MiWowStat::AttackPower, 300 } }, nullptr },
        { "Mejoras", "Poder con hechizos +180", "Spell_Arcane_StarFire", 40, { { MiWowStat::SpellPower, 180 } }, nullptr },
        { "Mejoras", "Crítico +184 (~4 %)", "Ability_CriticalStrike", 50, { { MiWowStat::CritRating, 184 } }, nullptr },
        { "Mejoras", "Celeridad +132 (~4 %)", "Spell_Nature_Bloodlust", 50, { { MiWowStat::HasteRating, 132 } }, nullptr },
        { "Mejoras", "Pack de combatiente", "Ability_Warrior_WeaponMastery", 180,
            Join({ { { MiWowStat::Health, 3000 } }, AttributeBonus, { { MiWowStat::AttackPower, 300 } },
                { { MiWowStat::CritRating, 184 } }, { { MiWowStat::HasteRating, 132 } } }),
            "Vida, atributos, ataque, crítico y celeridad. Ahorras 60" },
        { "Mejoras", "Pack de hechicero", "Spell_Holy_MagicalSentry", 210,
            Join({ { { MiWowStat::Health, 3000 }, { MiWowStat::Mana, 3000 } }, AttributeBonus,
                { { MiWowStat::SpellPower, 180 } }, { { MiWowStat::CritRating, 184 } }, { { MiWowStat::HasteRating, 132 } } }),
            "Vida, maná, atributos, hechizos, crítico y celeridad. Ahorras 70" },
    };
    // Distancia maxima al intendente con la tienda abierta
    constexpr float ShopDistance = 10.0f;
    // Como mucho una actualizacion de la tienda abierta por segundo (el oro cambia con cada muerte)
    constexpr Milliseconds ShopRefreshInterval = 1s;

    std::string CreatureName(uint32 entry)
    {
        CreatureTemplate const* info = sObjectMgr->GetCreatureTemplate(entry);
        return info ? info->Name : std::to_string(entry);
    }

    std::string FormatTime(Milliseconds time)
    {
        uint32 const seconds = static_cast<uint32>(time.count() / 1000);
        char text[16];
        std::snprintf(text, sizeof(text), "%u:%02u", seconds / 60, seconds % 60);
        return text;
    }
}

// --- IA -------------------------------------------------------------------------------------------------------

// Invasor: sigue la ruta hasta la torre; pelea con lo que se encuentre (jugador, guardias) y, al acabar el combate,
// sigue la ruta desde el punto mas cercano (no vuelve a su sitio). Al final de la ruta ataca la torre.
// Dormido (el jefe final junto al portal): quieto, sin atacar y sin poder ser atacado hasta que lo despiertan.
struct npc_miwow_castle_invader : public ScriptedAI
{
    explicit npc_miwow_castle_invader(Creature* creature) : ScriptedAI(creature), _info(GetInvaderInfo(creature->GetEntry())),
        _summons(creature) { }

    void SetRoute(std::vector<Position> const* path, ObjectGuid gate, std::size_t from = 0)
    {
        _path = path;
        _gate = gate;
        _next = std::min(from, path ? path->size() : 0);
        _moveDue = true;
    }

    // Dormido: quieto y sin atacar. attackable = el jugador puede atacarlo (y al hacerle dano lo despierta);
    // si no, no se le puede atacar
    void SetDormant(bool dormant, bool attackable = false)
    {
        _dormant = dormant;
        uint32 const flags = UNIT_FLAG_NON_ATTACKABLE | UNIT_FLAG_IMMUNE_TO_PC | UNIT_FLAG_IMMUNE_TO_NPC;
        if (dormant && !attackable)
            me->SetUnitFlag(UnitFlags(flags));
        else
            me->RemoveUnitFlag(UnitFlags(flags));

        if (dormant && attackable)
            me->SetUnitFlag(UNIT_FLAG_IMMUNE_TO_NPC);   // que no lo despierten los guardias

        me->SetReactState(dormant ? REACT_PASSIVE : REACT_AGGRESSIVE);
    }

    bool IsDormant() const { return _dormant; }

    void DamageTaken(Unit* attacker, uint32& /*damage*/, DamageEffectType /*type*/, SpellSchoolMask /*school*/) override
    {
        if (_dormant && attacker && attacker->GetCharmerOrOwnerPlayerOrPlayerItself())
        {
            SetDormant(false);
            me->RemoveUnitFlag(UNIT_FLAG_IMMUNE_TO_NPC);
        }
    }

    // Dano que hace (golpes y hechizos) segun la dificultad
    void SetDamageFactor(float factor) { _damageFactor = factor; }

    // Lo remato un jugador o algo suyo (mascota, totem, guardian): da oro
    bool IsKilledByPlayer() const { return _killedByPlayer; }

    void DamageDealt(Unit* /*victim*/, uint32& damage, DamageEffectType /*type*/, SpellSchoolMask /*school*/) override
    {
        if (_damageFactor != 1.0f)
            damage = static_cast<uint32>(damage * _damageFactor);
    }

    // Refuerzos invocados desde la ultima llamada (el juego los cuenta como enemigos de la oleada)
    GuidVector TakeSummons()
    {
        GuidVector summons;
        summons.swap(_newSummons);
        return summons;
    }

    void Reset() override
    {
        _events.Reset();
        _enraged = false;
        _addsCalled = false;
    }

    void JustEngagedWith(Unit* /*who*/) override
    {
        _events.Reset();
        if (!_info)
            return;

        for (std::size_t i = 0; i < _info->Abilities.size(); ++i)
            _events.ScheduleEvent(static_cast<uint32>(i + 1), _info->Abilities[i].First);
    }

    void MovementInform(uint32 type, uint32 id) override
    {
        if (type != POINT_MOTION_TYPE || !_path || id != _next)
            return;

        // Sin correa en mazmorras, pero el "hogar" tambien avanza (por si algo lo devuelve a casa)
        me->SetHomePosition(me->GetPosition());
        ++_next;
        _moveDue = true;
    }

    void EnterEvadeMode(EvadeReason why) override
    {
        if (!_path)
        {
            ScriptedAI::EnterEvadeMode(why);
            return;
        }

        if (!_EnterEvadeMode(why))
            return;

        // Sin volver a casa: fuera de combate sigue la ruta (EVADE se quita al llegar a casa, aqui a mano)
        me->ClearUnitState(UNIT_STATE_EVADE);
        Reset();
        _next = NearestPathPoint();
        _moveDue = true;
    }

    void JustSummoned(Creature* summon) override
    {
        _summons.Summon(summon);
        _newSummons.push_back(summon->GetGUID());
        if (auto* ai = dynamic_cast<npc_miwow_castle_invader*>(summon->AI()))
        {
            ai->SetRoute(_path, _gate, _next);
            ai->SetDamageFactor(_damageFactor);
        }

        if (Unit* victim = me->GetVictim())
            summon->AI()->AttackStart(victim);
    }

    void JustDied(Unit* killer) override
    {
        _killedByPlayer = killer && killer->GetCharmerOrOwnerPlayerOrPlayerItself();
        _summons.DespawnAll();
    }

    void UpdateAI(uint32 diff) override
    {
        if (_dormant)
            return;

        if (!UpdateVictim())
        {
            // Murio su objetivo y no le queda otro: sigue enganchado al combate sin nadie a quien pegar (y asi no
            // ve a nadie nuevo). Se "evade" a nuestra manera: sale del combate y sigue la ruta (EnterEvadeMode)
            if (me->IsEngaged())
            {
                EnterEvadeMode(EVADE_REASON_NO_HOSTILES);
                return;
            }

            if (_moveDue && _path)
            {
                _moveDue = false;
                MoveNext();
            }
            return;
        }

        if (_info)
            UpdateAbilities(diff);

        DoMeleeAttackIfReady();
    }

private:
    void MoveNext()
    {
        if (_next < _path->size())
        {
            me->GetMotionMaster()->MovePoint(static_cast<uint32>(_next), (*_path)[_next]);
            return;
        }

        // Final de la ruta: a por la torre
        if (Creature* gate = ObjectAccessor::GetCreature(*me, _gate))
            if (gate->IsAlive())
                AttackStart(gate);
    }

    std::size_t NearestPathPoint() const
    {
        std::size_t best = 0;
        float bestDist = std::numeric_limits<float>::max();
        for (std::size_t i = 0; i < _path->size(); ++i)
        {
            float const dist = me->GetExactDist2dSq((*_path)[i]);
            if (dist < bestDist)
            {
                bestDist = dist;
                best = i;
            }
        }
        return best;
    }

    void UpdateAbilities(uint32 diff)
    {
        if (_info->EnrageSpell && !_enraged && me->HealthBelowPct(static_cast<int32>(_info->EnragePct)))
        {
            _enraged = true;
            DoCastSelf(_info->EnrageSpell, true);
        }

        if (_info->AddEntry && !_addsCalled && me->HealthBelowPct(static_cast<int32>(_info->AddPct)))
        {
            _addsCalled = true;
            for (uint8 i = 0; i < _info->AddCount; ++i)
            {
                Position pos = me->GetPosition();
                me->MovePosition(pos, 4.0f, static_cast<float>(i) * 2.0f * float(M_PI) / _info->AddCount);
                me->SummonCreature(_info->AddEntry, pos, TEMPSUMMON_CORPSE_TIMED_DESPAWN, 10000);
            }
        }

        _events.Update(diff);
        if (me->HasUnitState(UNIT_STATE_CASTING))
            return;

        while (uint32 const eventId = _events.ExecuteEvent())
        {
            CastleAbility const& ability = _info->Abilities[eventId - 1];
            Unit* target = me->GetVictim();
            if (ability.Target == CastleTarget::Self)
                target = me;
            else if (ability.Target == CastleTarget::Random)
                if (Unit* random = SelectTarget(SelectTargetMethod::Random, 0, 40.0f, true))
                    target = random;

            if (target)
                DoCast(target, ability.Spell);

            _events.ScheduleEvent(eventId, ability.Repeat);
            if (me->HasUnitState(UNIT_STATE_CASTING))
                return;
        }
    }

    CastleInvaderInfo const* _info;
    SummonList _summons;
    GuidVector _newSummons;
    EventMap _events;
    std::vector<Position> const* _path = nullptr;
    ObjectGuid _gate;
    std::size_t _next = 0;
    bool _moveDue = false;
    bool _dormant = false;
    bool _killedByPlayer = false;
    float _damageFactor = 1.0f;
    bool _enraged = false;
    bool _addsCalled = false;
};

// Torre del castillo: su vida es la del castillo. Quieta, no ataca, no vuelve a casa (se curaria) y no se deja curar
// (la reparacion entre etapas la hace el juego).
struct npc_miwow_castle_gate : public CreatureAI
{
    explicit npc_miwow_castle_gate(Creature* creature) : CreatureAI(creature) { }

    void InitializeAI() override
    {
        me->SetReactState(REACT_PASSIVE);
        me->SetControlled(true, UNIT_STATE_ROOT);
    }

    void UpdateAI(uint32 /*diff*/) override { }
    void MoveInLineOfSight(Unit* /*who*/) override { }
    void AttackStart(Unit* /*who*/) override { }
    void EnterEvadeMode(EvadeReason /*why*/) override { }
    void HealReceived(Unit* /*healer*/, uint32& heal) override { heal = 0; }
};

// Guardia: IA normal (ataca a los enemigos que vea y vuelve a su puesto). Si muere su objetivo y no le queda otro,
// vuelve a su puesto (si no, se quedaria enganchado al combate sin ver a nadie nuevo).
struct npc_miwow_castle_guard : public ScriptedAI
{
    explicit npc_miwow_castle_guard(Creature* creature) : ScriptedAI(creature) { }

    void UpdateAI(uint32 /*diff*/) override
    {
        if (!UpdateVictim())
        {
            if (me->IsEngaged())
                EnterEvadeMode(EVADE_REASON_NO_HOSTILES);
            return;
        }

        DoMeleeAttackIfReady();
    }
};

// --- Juego ----------------------------------------------------------------------------------------------------

class MiWowGameCastle : public MiWowMatch
{
public:
    explicit MiWowGameCastle(CastleLayout const& layout) : _layout(layout) { }

    // El jugador hablo con el intendente: tienda en el cliente (MATCH_SHOP)
    void OpenShopFor(Player* player) { OpenShop(player); }

protected:
    Seconds GetCountdown() const override { return 5s; }

    Position GetArrivalPosition(Player* /*player*/) override { return _layout.Start; }

    Position const& GetRespawnPosition(Player* /*player*/) const override { return _layout.Start; }

    void OnPlayerDied(Player* player) override
    {
        RespawnPlayer(player, RespawnDelay);
    }

    void OnStart() override
    {
        SpawnCastle();
        _phase = Phase::Choose;
        _phaseTimer = ChooseTimeout;

        std::vector<MiWowMatchChoiceOption> options;
        for (CastleDifficulty const& difficulty : Difficulties)
            options.push_back({ difficulty.Name, difficulty.Info });
        ShowChoice(std::string(DifficultyChoice), "Dificultad", "Cuanto más difícil, más fuertes y numerosos son los "
            "invasores. Si no eliges, empieza en " + std::string(Difficulties[DefaultDifficulty].Name) + ".",
            std::move(options), std::chrono::duration_cast<Seconds>(ChooseTimeout));
    }

    // Tienda: id = posicion en ShopOffers + 1
    bool BuildShop(Player* player, MiWowShop& shop) override
    {
        if (_phase == Phase::Finished)
            return false;

        shop.Title = "Intendente del castillo";
        shop.Currency = "Oro del castillo";
        shop.Amount = _gold;
        for (uint32 i = 0; i < ShopOffers.size(); ++i)
        {
            CastleOffer const& offer = ShopOffers[i];
            MiWowShopItem item;
            item.Id = i + 1;
            item.Category = offer.Category;
            item.Icon = std::string("Interface\\Icons\\") + offer.Icon;
            item.Name = offer.Name;
            if (offer.Detail)
                item.Detail = offer.Detail;
            else
            {
                int32 const total = MiWowStats::Get(player, offer.Stats.front().Stat);
                item.Detail = total ? "Llevas +" + std::to_string(total) : "Sin comprar";
            }
            item.Price = offer.Price;
            shop.Items.push_back(std::move(item));
        }
        return true;
    }

    void OnShopBuy(Player* player, uint32 id) override
    {
        if (!NearVendor(player))
        {
            CloseShop(player);
            return;
        }

        if (id == 0 || id > ShopOffers.size())
            return;

        if (Buy(player, ShopOffers[id - 1]))
            _shopGold = _gold;
        RefreshShops();
    }

    void OnPlayerChoice(Player* /*player*/, std::string_view id, uint32 index) override
    {
        if (id == DifficultyChoice)
            ChooseDifficulty(index);
    }

    void OnUpdate(Milliseconds diff) override
    {
        if (_phase == Phase::Finished)
            return;

        _elapsed += diff;
        _tick += diff;
        if (_tick < TickInterval)
            return;

        Milliseconds const step = _tick;
        _tick = 0ms;

        InstanceMap* map = GetMap();
        if (!map)
            return;

        Creature* gate = map->GetCreature(_gate);
        if (!gate || !gate->IsAlive())
        {
            Finish(false);
            return;
        }

        UpdateGate(gate, step);
        UpdateShops(step);
        CheckFinalBossAwake(map);

        std::size_t alive = 0;
        switch (_phase)
        {
            case Phase::Choose:
                _phaseTimer -= step;
                if (_phaseTimer <= 0ms)
                    ChooseDifficulty(DefaultDifficulty);
                break;
            case Phase::Prepare:
            case Phase::Pause:
                _phaseTimer -= step;
                if (_phaseTimer <= 0ms)
                    StartWave();
                break;
            case Phase::Wave:
                _spawnTimer -= step;
                while (_spawnTimer <= 0ms && !_pending.empty())
                {
                    SpawnInvader(map, _pending.front());
                    _pending.erase(_pending.begin());
                    _spawnTimer += SpawnInterval;
                }

                alive = CountInvaders(map);
                if (_pending.empty() && alive == 0)
                    WaveCleared();
                break;
            default:
                break;
        }

        if (_phase != Phase::Finished)
            UpdateHud(gate, alive + _pending.size());
    }

private:
    bool NearVendor(Player* player) const
    {
        InstanceMap* map = GetMap();
        Creature* vendor = map ? map->GetCreature(_vendor) : nullptr;
        return vendor && player->IsWithinDistInMap(vendor, ShopDistance);
    }

    // Tiendas abiertas: se cierran si el jugador se aleja; se actualizan si cambio el oro (como mucho 1/s)
    void UpdateShops(Milliseconds diff)
    {
        if (GetOpenShops().empty())
            return;

        ForEachPlayer([this](Player* player)
        {
            if (GetOpenShops().count(player->GetGUID()) && !NearVendor(player))
                CloseShop(player);
        });

        _shopTimer -= diff;
        if (_gold != _shopGold && _shopTimer <= 0ms)
        {
            _shopGold = _gold;
            _shopTimer = ShopRefreshInterval;
            RefreshShops();
        }
    }

    bool Buy(Player* player, CastleOffer const& offer)
    {
        WorldSession* session = player->GetSession();
        if (_phase == Phase::Finished)
            return false;

        if (offer.Price > _gold)
        {
            session->SendAreaTriggerMessage("Te faltan " + std::to_string(offer.Price - _gold) + " de oro.");
            return false;
        }

        _gold -= offer.Price;
        for (CastleStatBonus const& bonus : offer.Stats)
            MiWowStats::Add(player, bonus.Stat, bonus.Amount);
        session->SendAreaTriggerMessage(offer.Name);
        LOG_DEBUG("module.miwow", "MiWow: castillo: partida {}: {} compra {} por {} de oro", GetId(),
            player->GetName(), offer.Name, offer.Price);
        return true;
    }

    enum class Phase : uint8
    {
        Choose,     // eligiendo la dificultad (ventana de eleccion)
        Prepare,    // antes de la primera oleada de una etapa
        Wave,       // oleada en curso (saliendo o vivos)
        Pause,      // entre oleadas
        Finished
    };

    CastleStage const& Stage() const { return Stages[_stage]; }
    bool IsBossWave() const { return _wave >= WavesPerStage; }

    void Announce(std::string const& text) const
    {
        ForEachPlayer([&text](Player* player) { player->GetSession()->SendAreaTriggerMessage(text); });
    }

    void SpawnCastle()
    {
        InstanceMap* map = GetMap();
        if (!map)
            return;

        for (CastleObject const& object : _layout.Objects)
        {
            float const o = object.Pos.GetOrientation();
            GameObject* go = map->SummonGameObject(object.Entry, object.Pos, 0.0f, 0.0f, std::sin(o / 2.0f),
                std::cos(o / 2.0f), 0, false);
            if (!go)
            {
                LOG_ERROR("module.miwow", "MiWow: castillo: no se pudo poner el objeto {}", object.Entry);
                continue;
            }

            if (object.Door)
                _door = go->GetGUID();
        }

        if (TempSummon* gate = map->SummonCreature(NPC_CASTLE_GATE, _layout.Gate))
        {
            _gate = gate->GetGUID();
            _lastGateHealth = gate->GetMaxHealth();
        }
        else
            LOG_ERROR("module.miwow", "MiWow: castillo: no se pudo poner la torre (criatura {})", NPC_CASTLE_GATE);

        if (TempSummon* vendor = map->SummonCreature(NPC_CASTLE_VENDOR, _layout.Vendor))
            _vendor = vendor->GetGUID();
        else
            LOG_ERROR("module.miwow", "MiWow: castillo: no se pudo poner el intendente (criatura {})", NPC_CASTLE_VENDOR);

        // Portal de las oleadas y, a su lado, el jefe final dormido (despierta en su oleada)
        if (!map->SummonCreature(NPC_CASTLE_PORTAL, _layout.Portal))
            LOG_ERROR("module.miwow", "MiWow: castillo: no se pudo poner el portal (criatura {})", NPC_CASTLE_PORTAL);

        if (TempSummon* boss = map->SummonCreature(FinalBossEntry(), _layout.Boss))
        {
            if (auto* ai = dynamic_cast<npc_miwow_castle_invader*>(boss->AI()))
                ai->SetDormant(true);
            _finalBoss = boss->GetGUID();
        }

        _guards.assign(_layout.Guards.size(), ObjectGuid::Empty);
        SpawnGuards(map);
    }

    // Pone los guardias que falten (o muertos) en su puesto y cura a los vivos
    void SpawnGuards(InstanceMap* map)
    {
        for (std::size_t i = 0; i < _layout.Guards.size(); ++i)
        {
            Creature* guard = map->GetCreature(_guards[i]);
            if (guard && guard->IsAlive())
            {
                guard->SetFullHealth();
                continue;
            }

            if (guard)
                guard->DespawnOrUnsummon();

            TempSummon* summon = map->SummonCreature(NPC_CASTLE_GUARD, _layout.Guards[i]);
            _guards[i] = summon ? summon->GetGUID() : ObjectGuid::Empty;
        }
    }

    CastleDifficulty const& Difficulty() const { return Difficulties[_difficulty]; }

    void ChooseDifficulty(uint32 difficulty)
    {
        if (_phase != Phase::Choose)
            return;

        _difficulty = std::min<uint32>(difficulty, Difficulties.size() - 1);
        ClearChoice();
        LOG_INFO("module.miwow", "MiWow: castillo: partida {}: dificultad {}", GetId(), Difficulty().Name);
        Announce(std::string("Dificultad: ") + Difficulty().Name);
        StartStage(0);
    }

    // Vida y dano del enemigo segun la dificultad (una vez, al aparecer o despertar)
    void ApplyDifficulty(Creature* creature)
    {
        CastleDifficulty const& difficulty = Difficulty();
        if (difficulty.Health != 1.0f)
        {
            creature->ApplyStatPctModifier(UNIT_MOD_HEALTH, TOTAL_PCT, (difficulty.Health - 1.0f) * 100.0f);
            creature->SetFullHealth();
        }

        if (auto* ai = dynamic_cast<npc_miwow_castle_invader*>(creature->AI()))
            ai->SetDamageFactor(difficulty.Damage);
    }

    // Enemigos de un grupo de la oleada, escalados por la dificultad y las vueltas de la etapa final (al menos 1)
    void AddPending(std::vector<CastleSpawn> const& spawns)
    {
        float const factor = Difficulty().Count * (1.0f + EndlessGrowth * _cycle);
        for (CastleSpawn const& spawn : spawns)
        {
            uint32 const count = std::max<uint32>(1, static_cast<uint32>(std::lround(spawn.Count * factor)));
            _pending.insert(_pending.end(), count, spawn.Entry);
        }
    }

    void StartStage(uint32 stage)
    {
        _stage = stage;
        _wave = 0;
        _phase = Phase::Prepare;
        _phaseTimer = stage == 0 ? FirstStageDelay : StageDelay;

        if (stage > 0)
        {
            if (InstanceMap* map = GetMap())
            {
                SpawnGuards(map);
                RepairGate(map);
            }
        }

        _cycle = 0;
        LOG_INFO("module.miwow", "MiWow: castillo: partida {}: etapa {} ({})", GetId(), stage + 1, Stage().Name);
        Announce("Etapa " + std::to_string(stage + 1) + ": " + Stage().Name);
        if (IsFinalStage())
            if (InstanceMap* map = GetMap())
                PrepareFinalBoss(map);
    }

    void StartWave()
    {
        CastleStage const& stage = Stage();
        _pending.clear();
        if (IsBossWave())
        {
            AddPending(stage.Escort);
            Acore::Containers::RandomShuffle(_pending);
            _pending.push_back(stage.Boss);
            Announce("¡Jefe: " + CreatureName(stage.Boss) + "!");
        }
        else
        {
            AddPending(stage.Waves[_wave]);
            Acore::Containers::RandomShuffle(_pending);
            if (IsFinalStage())
                Announce("Oleada " + std::to_string(FinalWaveNumber()));
            else
                Announce("Oleada " + std::to_string(_wave + 1) + " de " + std::to_string(WavesPerStage));
        }

        _phase = Phase::Wave;
        _spawnTimer = 0ms;

        // El jefe final "invoca" la oleada desde el portal
        if (InstanceMap* map = GetMap())
            if (Creature* boss = map->GetCreature(_finalBoss))
                boss->HandleEmoteCommand(EMOTE_ONESHOT_SPELL_CAST_OMNI);
    }

    void WaveCleared()
    {
        uint32 const bonus = WaveGold(_stage);
        _gold += bonus;
        _goldEarned += bonus;
        Announce("¡Oleada superada! +" + std::to_string(bonus) + " de oro");

        if (!IsBossWave())
        {
            ++_wave;
            // Etapa final: las oleadas no acaban (el jefe sale cuando lo despierta el jugador)
            if (IsFinalStage() && _wave >= WavesPerStage)
            {
                _wave = 0;
                ++_cycle;
            }
            _phase = Phase::Pause;
            _phaseTimer = WaveDelay;
            return;
        }

        LOG_INFO("module.miwow", "MiWow: castillo: partida {}: etapa {} superada ({})", GetId(), _stage + 1,
            FormatTime(_elapsed));
        if (_stage + 1 >= Stages.size())
        {
            Finish(true);
            return;
        }

        Announce("¡Etapa superada! Los guardias caídos vuelven y la torre se repara un poco.");
        StartStage(_stage + 1);
    }

    static uint32 FinalBossEntry() { return Stages.back().Boss; }
    bool IsFinalStage() const { return _stage + 1 >= Stages.size(); }

    npc_miwow_castle_invader* FinalBossAI(InstanceMap* map) const
    {
        Creature* boss = map->GetCreature(_finalBoss);
        return boss && boss->IsAlive() ? dynamic_cast<npc_miwow_castle_invader*>(boss->AI()) : nullptr;
    }

    // Etapa final: el jefe se puede atacar (sigue quieto junto al portal hasta que le hagan dano)
    void PrepareFinalBoss(InstanceMap* map)
    {
        npc_miwow_castle_invader* ai = FinalBossAI(map);
        if (!ai)
            return;

        Creature* boss = map->GetCreature(_finalBoss);
        ApplyDifficulty(boss);
        ai->SetDormant(true, true);
        ai->SetRoute(&_layout.Path, _gate);
        Announce(CreatureName(FinalBossEntry()) + " espera junto al portal: atácalo cuando estés listo.");
    }

    // El jugador desperto al jefe final: sale con su escolta (oleada del jefe) y va a por la torre
    void CheckFinalBossAwake(InstanceMap* map)
    {
        if (!IsFinalStage() || _finalBoss.IsEmpty())
            return;

        npc_miwow_castle_invader* ai = FinalBossAI(map);
        if (ai && ai->IsDormant())
            return;

        if (Creature* boss = map->GetCreature(_finalBoss))
        {
            if (boss->IsAlive())
                boss->Yell("¡Basta de esbirros! Vuestra torre caerá ante mí.", LANG_UNIVERSAL);
            _invaders.push_back(boss->GetGUID());
        }
        _finalBoss.Clear();

        uint32 const wavesDone = FinalWaveNumber() - 1;
        _wave = WavesPerStage;
        _pending.clear();
        AddPending(Stage().Escort);
        Acore::Containers::RandomShuffle(_pending);
        _phase = Phase::Wave;
        _spawnTimer = 0ms;
        LOG_INFO("module.miwow", "MiWow: castillo: partida {}: jefe final despierto tras {} oleadas", GetId(),
            wavesDone);
        Announce("¡" + CreatureName(FinalBossEntry()) + " despierta!");
    }

    // Numero de oleada de la etapa final (contando todas las vueltas)
    uint32 FinalWaveNumber() const { return _cycle * WavesPerStage + _wave + 1; }

    void SpawnInvader(InstanceMap* map, uint32 entry)
    {
        Position pos = _layout.Spawn;
        pos.m_positionX += frand(-SpawnSpread, SpawnSpread);
        pos.m_positionY += frand(-SpawnSpread, SpawnSpread);
        pos.m_positionZ = map->GetHeight(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ() + 5.0f);
        if (pos.m_positionZ <= INVALID_HEIGHT)
            pos = _layout.Spawn;

        TempSummon* creature = map->SummonCreature(entry, pos);
        if (!creature)
        {
            LOG_ERROR("module.miwow", "MiWow: castillo: no se pudo invocar al enemigo {}", entry);
            return;
        }

        ApplyDifficulty(creature);
        if (auto* ai = dynamic_cast<npc_miwow_castle_invader*>(creature->AI()))
            ai->SetRoute(&_layout.Path, _gate);
        else
            LOG_ERROR("module.miwow", "MiWow: castillo: el enemigo {} no tiene la IA npc_miwow_castle_invader", entry);

        _invaders.push_back(creature->GetGUID());
    }

    // Enemigos vivos (recoge los refuerzos de los jefes; los muertos se quitan a los pocos segundos)
    std::size_t CountInvaders(InstanceMap* map)
    {
        std::size_t alive = 0;
        GuidVector summons;
        for (auto itr = _invaders.begin(); itr != _invaders.end();)
        {
            Creature* creature = map->GetCreature(*itr);
            if (!creature)
            {
                itr = _invaders.erase(itr);
                continue;
            }

            if (!creature->IsAlive())
            {
                auto const* ai = dynamic_cast<npc_miwow_castle_invader const*>(creature->AI());
                if (ai && ai->IsKilledByPlayer())
                {
                    uint32 const gold = KillGold(creature->GetEntry(), _stage);
                    _gold += gold;
                    _goldEarned += gold;
                }
                creature->DespawnOrUnsummon(CorpseDelay);
                itr = _invaders.erase(itr);
                continue;
            }

            if (auto* ai = dynamic_cast<npc_miwow_castle_invader*>(creature->AI()))
            {
                GuidVector added = ai->TakeSummons();
                summons.insert(summons.end(), added.begin(), added.end());
            }

            ++alive;
            ++itr;
        }

        for (ObjectGuid const& guid : summons)
        {
            if (Creature* summon = map->GetCreature(guid))
                ApplyDifficulty(summon);
            _invaders.push_back(guid);
            ++alive;
        }

        return alive;
    }

    void DespawnInvaders()
    {
        InstanceMap* map = GetMap();
        if (!map)
            return;

        for (ObjectGuid const& guid : _invaders)
            if (Creature* creature = map->GetCreature(guid))
                creature->DespawnOrUnsummon();

        // El jefe final, si no llego a despertar, se queda junto al portal (sin peligro: no ataca)
        _invaders.clear();
        _pending.clear();
    }

    void UpdateGate(Creature* gate, Milliseconds diff)
    {
        _gateAlertTimer -= diff;
        uint32 const health = gate->GetHealth();
        if (health < _lastGateHealth && _gateAlertTimer <= 0ms)
        {
            _gateAlertTimer = GateAlertCooldown;
            Announce("¡Están atacando la torre del castillo!");
        }

        // Avisos al bajar del 75 / 50 / 25 %
        uint32 const pct = GatePct(gate);
        for (uint32 mark : { 75u, 50u, 25u })
            if (pct < mark && _lastGatePct >= mark)
                Announce("¡La torre del castillo está al " + std::to_string(pct) + " %!");

        _lastGateHealth = health;
        _lastGatePct = pct;
        SetDoorState(pct <= 50 ? GO_DESTRUCTIBLE_DAMAGED : GO_DESTRUCTIBLE_INTACT);
    }

    void RepairGate(InstanceMap* map)
    {
        Creature* gate = map->GetCreature(_gate);
        if (!gate || !gate->IsAlive())
            return;

        uint32 const repaired = std::min<uint32>(gate->GetMaxHealth(),
            gate->GetHealth() + static_cast<uint32>(gate->GetMaxHealth() * GateRepair));
        gate->SetHealth(repaired);
        _lastGateHealth = repaired;
        _lastGatePct = GatePct(gate);
        SetDoorState(_lastGatePct <= 50 ? GO_DESTRUCTIBLE_DAMAGED : GO_DESTRUCTIBLE_INTACT);
    }

    static uint32 GatePct(Creature const* gate)
    {
        return gate->GetMaxHealth() ? static_cast<uint32>(std::ceil(100.0 * gate->GetHealth() / gate->GetMaxHealth())) : 0;
    }

    void SetDoorState(GameObjectDestructibleState state)
    {
        if (state == _doorState)
            return;

        InstanceMap* map = GetMap();
        GameObject* door = map ? map->GetGameObject(_door) : nullptr;
        if (!door)
            return;

        _doorState = state;
        door->SetDestructibleState(state);
    }

    // Lineas de "Etiqueta: valor" separadas por " - " (el cliente pinta las etiquetas en dorado)
    void UpdateHud(Creature* gate, std::size_t enemies)
    {
        if (_phase == Phase::Choose)
        {
            uint32 const seconds = static_cast<uint32>((std::max(_phaseTimer, 0ms).count() + 999) / 1000);
            std::string const text = "Dificultad: elígela en la ventana\n" +
                std::string(Difficulties[DefaultDifficulty].Name) + " en: " + std::to_string(seconds) + " s";
            if (text != _hud)
            {
                _hud = text;
                SetHud(text);
            }
            return;
        }

        std::string text = "Etapa " + std::to_string(_stage + 1) + "/" + std::to_string(Stages.size()) + ": " +
            Stage().Name + " - Dificultad: " + Difficulty().Name + "\n";
        std::string const wave = IsBossWave() ? "Jefe" : IsFinalStage() ? "Oleada " + std::to_string(FinalWaveNumber()) :
            "Oleada " + std::to_string(_wave + 1) + "/" + std::to_string(WavesPerStage);
        if (_phase == Phase::Wave)
            text += (IsBossWave() ? "Jefe: " + CreatureName(Stage().Boss) : wave + ": en curso") + " - Enemigos: " +
                std::to_string(enemies);
        else
        {
            uint32 const seconds = static_cast<uint32>((std::max(_phaseTimer, 0ms).count() + 999) / 1000);
            text += wave + ": en " + std::to_string(seconds) + " s";
        }
        text += "\nTorre: " + std::to_string(GatePct(gate)) + " % - Oro: " + std::to_string(_gold);
        if (IsFinalStage() && !_finalBoss.IsEmpty())
            text += "\n" + CreatureName(FinalBossEntry()) + ": dormido junto al portal (atácalo para despertarlo)";

        if (text != _hud)
        {
            _hud = text;
            SetHud(text);
        }
    }

    void Finish(bool win)
    {
        _phase = Phase::Finished;
        ClearChoice();
        CloseShops();
        DespawnInvaders();

        std::string summary;
        if (win)
        {
            uint32 pct = 0;
            if (InstanceMap* map = GetMap())
                if (Creature* gate = map->GetCreature(_gate))
                    pct = GatePct(gate);

            summary = "¡Has defendido el castillo! Tiempo: " + FormatTime(_elapsed) + ". Torre al " +
                std::to_string(pct) + " %.";
        }
        else
        {
            SetDoorState(GO_DESTRUCTIBLE_DESTROYED);
            summary = "El castillo ha caído en la etapa " + std::to_string(_stage + 1) + " (" +
                (IsBossWave() ? std::string("jefe") : "oleada " + std::to_string(_wave + 1)) + "). Tiempo: " +
                FormatTime(_elapsed) + ".";
        }

        summary += " Dificultad: " + std::string(Difficulty().Name) + ". Oro ganado: " + std::to_string(_goldEarned) + ".";
        LOG_INFO("module.miwow", "MiWow: castillo: partida {}: {}", GetId(), summary);
        SetResultForAll(win ? MiWowMatchResult::Win : MiWowMatchResult::Lose);
        End(summary);
    }

    CastleLayout const& _layout;
    Phase _phase = Phase::Choose;
    uint32 _stage = 0;
    uint32 _wave = 0;               // 0..WavesPerStage-1 oleadas; WavesPerStage = jefe
    uint32 _cycle = 0;              // etapa final: vueltas completas de sus 3 oleadas
    Milliseconds _phaseTimer = 0ms;
    Milliseconds _spawnTimer = 0ms;
    Milliseconds _tick = 0ms;
    Milliseconds _elapsed = 0ms;
    std::vector<uint32> _pending;   // enemigos de la oleada que faltan por salir
    GuidVector _invaders;
    ObjectGuid _finalBoss;          // dormido junto al portal hasta su oleada
    GuidVector _guards;
    ObjectGuid _gate;
    ObjectGuid _door;
    GameObjectDestructibleState _doorState = GO_DESTRUCTIBLE_INTACT;
    uint32 _lastGateHealth = 0;
    uint32 _lastGatePct = 100;
    Milliseconds _gateAlertTimer = 0ms;
    std::string _hud;
    uint32 _difficulty = DefaultDifficulty;
    ObjectGuid _vendor;
    uint32 _gold = 0;               // oro del castillo (de la partida)
    uint32 _goldEarned = 0;
    uint32 _shopGold = 0;           // oro que mostraban las tiendas abiertas
    Milliseconds _shopTimer = 0ms;
};

// Intendente del castillo: al hablarle abre la tienda de mejoras (ventana del cliente, MATCH_SHOP) de su partida
class npc_miwow_castle_vendor : public CreatureScript
{
public:
    npc_miwow_castle_vendor() : CreatureScript("npc_miwow_castle_vendor") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        ClearGossipMenuFor(player);
        if (MiWowGameCastle* game = GetGame(player, creature))
        {
            CloseGossipMenuFor(player);
            game->OpenShopFor(player);
        }
        else
            SendGossipMenuFor(player, VENDOR_TEXT, creature);
        return true;
    }

private:
    // La partida del jugador, si este intendente es el de su instancia
    static MiWowGameCastle* GetGame(Player* player, Creature* creature)
    {
        MiWowMatch* match = sMiWowMatchMgr.GetMatch(player);
        if (!match || match->GetMapId() != creature->GetMapId() || match->GetInstanceId() != creature->GetInstanceId())
            return nullptr;
        return dynamic_cast<MiWowGameCastle*>(match);
    }
};

void AddSC_miwow_game_castle()
{
    RegisterCreatureAI(npc_miwow_castle_invader);
    RegisterCreatureAI(npc_miwow_castle_gate);
    RegisterCreatureAI(npc_miwow_castle_guard);
    new npc_miwow_castle_vendor();

    // Mapa 755 (tools/mapgen/castlegen.py, Maps/Planos/defensa_castillo.json)
    MiWowGameInfo game;
    game.Id = "castillo";
    game.Name = "Defensa del castillo";
    game.Description = "Defiende la torre del castillo con tu personaje y tu equipo, ayudado por tres guardias. "
        "Cinco etapas de tres oleadas y un jefe; las oleadas salen de un portal y llegan por el único camino del "
        "cañón. En la última etapa las oleadas no acaban hasta que despiertas al señor del portal. Cada enemigo deja oro del castillo, que el "
        "intendente cambia por mejoras para la partida. Si la torre cae, pierdes. Requiere nivel 80.";
    game.Icon = "Interface\\Icons\\INV_Misc_Tournaments_banner_Human";
    game.MinPlayers = 1;
    game.MaxPlayers = 1;
    game.MaxPartySize = 1;
    game.MinLevel = 80;
    game.MapId = 755;

    CastleLayout layout;
    if (LoadLayout(game.MapId, layout))
    {
        CastleLayout const& stored = Layouts[game.MapId] = std::move(layout);
        game.Start = stored.Start;
        game.Factory = [&stored]() { return std::make_unique<MiWowGameCastle>(stored); };
    }
    else
        game.Description += " (No disponible: falta el mapa en el servidor.)";

    sMiWowGames.Register(std::move(game));
}
