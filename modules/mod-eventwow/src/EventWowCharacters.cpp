#include "EventWowCharacters.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "EventWowConfig.h"
#include "EventWowGames.h"
#include "EventWowWeapons.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include <algorithm>

bool EventWowCharacterInfo::HasSpell(uint32 spellId) const
{
    // Misma cadena (cualquier rango): la ficha puede llevar un rango nativo cualquiera (fijas) o el primero
    // (progresion, EventWowProgress sube de rango)
    uint32 const first = sSpellMgr->GetFirstSpellInChain(spellId);
    return std::any_of(Spells.begin(), Spells.end(), [first](uint32 spell)
    {
        return sSpellMgr->GetFirstSpellInChain(spell) == first;
    });
}

EventWowCharacters& EventWowCharacters::Instance()
{
    static EventWowCharacters instance;
    return instance;
}

void EventWowCharacters::Load()
{
    _characters.clear();
    _gameCharacters.clear();
    _pickCreatures.clear();

    //                                                 0     1       2              3       4            5        6         7            8
    if (QueryResult result = WorldDatabase.Query("SELECT `Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, "
        // 9               10                11               12              13                 14
        "`VehicleEntry`, `WeaponMainHand`, `WeaponOffHand`, `PickCreature`, `AutoAttackSpell`, `AttackMin`, "
        // 15           16                17             18
        "`AttackMax`, `AttackPerLevel`, `AttackSpeed`, `WeaponRanged` FROM `eventwow_character`"))
    {
        do
        {
            Field* fields = result->Fetch();
            EventWowCharacterInfo info;
            info.Id = fields[0].Get<uint32>();
            info.Name = fields[1].Get<std::string>();
            info.Description = fields[2].Get<std::string>();
            info.Icon = fields[3].Get<std::string>();
            info.DisplayId = fields[4].Get<uint32>();
            info.Scale = fields[5].Get<float>();
            info.Health = fields[6].Get<uint32>();
            info.PowerType = fields[7].Get<uint8>();
            info.MaxPower = fields[8].Get<uint32>();
            info.VehicleEntry = fields[9].Get<uint32>();
            info.WeaponMainHand = fields[10].Get<uint32>();
            info.WeaponOffHand = fields[11].Get<uint32>();
            info.PickCreature = fields[12].Get<uint32>();
            info.AutoAttackSpell = fields[13].Get<uint32>();
            info.AttackMin = fields[14].Get<float>();
            info.AttackMax = fields[15].Get<float>();
            info.AttackPerLevel = fields[16].Get<float>();
            info.AttackSpeed = fields[17].Get<uint32>();
            info.WeaponRanged = fields[18].Get<uint32>();

            if (info.AutoAttackSpell)
            {
                SpellInfo const* attack = sSpellMgr->GetSpellInfo(info.AutoAttackSpell);
                if (!attack || !attack->HasAttribute(SPELL_ATTR2_AUTO_REPEAT))
                {
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): AutoAttackSpell {} no existe o no se repite solo "
                        "(SPELL_ATTR2_AUTO_REPEAT), ataca cuerpo a cuerpo", info.Id, info.Name, info.AutoAttackSpell);
                    info.AutoAttackSpell = 0;
                }
            }

            if (info.HasAttack() && info.AttackMax < info.AttackMin)
                info.AttackMax = info.AttackMin;

            // Se equipan sin las comprobaciones del core: aqui se valida que cada una va en su ranura
            for (auto [weapon, slot] : { std::pair{ &info.WeaponMainHand, uint8(EQUIPMENT_SLOT_MAINHAND) },
                std::pair{ &info.WeaponOffHand, uint8(EQUIPMENT_SLOT_OFFHAND) }, std::pair{ &info.WeaponRanged, uint8(EQUIPMENT_SLOT_RANGED) } })
            {
                if (!*weapon)
                    continue;

                ItemTemplate const* proto = sObjectMgr->GetItemTemplate(*weapon);
                if (!proto)
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): el arma {} no existe en item_template, se ignora",
                        info.Id, info.Name, *weapon);
                else if (!EventWowWeapons::FitsSlot(proto, slot))
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): el objeto {} (tipo de inventario {}) no va en la ranura {}, se ignora",
                        info.Id, info.Name, *weapon, proto->InventoryType, slot);
                else
                    continue;

                *weapon = 0;
            }

            if (ItemTemplate const* mainHand = info.WeaponMainHand ? sObjectMgr->GetItemTemplate(info.WeaponMainHand) : nullptr)
            {
                if (mainHand->InventoryType == INVTYPE_2HWEAPON && info.WeaponOffHand)
                {
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): arma a dos manos {} con mano izquierda {}, se ignora la izquierda",
                        info.Id, info.Name, info.WeaponMainHand, info.WeaponOffHand);
                    info.WeaponOffHand = 0;
                }
            }

            if (info.PickCreature)
            {
                if (!sObjectMgr->GetCreatureTemplate(info.PickCreature))
                {
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): PickCreature {} no existe, no se puede elegir en el mundo",
                        info.Id, info.Name, info.PickCreature);
                    info.PickCreature = 0;
                }
                else if (!_pickCreatures.emplace(info.PickCreature, info.Id).second)
                {
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): PickCreature {} ya es de otro personaje, se ignora",
                        info.Id, info.Name, info.PickCreature);
                    info.PickCreature = 0;
                }
            }

            if (info.VehicleEntry)
            {
                CreatureTemplate const* vehicle = sObjectMgr->GetCreatureTemplate(info.VehicleEntry);
                if (!vehicle || !vehicle->VehicleId)
                {
                    LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): la criatura {} no existe o no es un vehiculo, va a pie",
                        info.Id, info.Name, info.VehicleEntry);
                    info.VehicleEntry = 0;
                }
            }

            if (info.DisplayId && !sCreatureDisplayInfoStore.LookupEntry(info.DisplayId))
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): DisplayId {} no existe, se ignora el modelo",
                    info.Id, info.Name, info.DisplayId);
                info.DisplayId = 0;
            }

            if (info.Scale <= 0.0f)
                info.Scale = 1.0f;

            if (info.PowerType != POWER_MANA && info.PowerType != POWER_RAGE && info.PowerType != POWER_ENERGY)
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): PowerType {} no soportado (0 mana, 1 ira, 3 energia), se usa mana",
                    info.Id, info.Name, info.PowerType);
                info.PowerType = POWER_MANA;
            }

            _characters.emplace(info.Id, std::move(info));
        } while (result->NextRow());
    }

    //                                                 0              1          2
    if (QueryResult result = WorldDatabase.Query("SELECT `CharacterId`, `SpellId`, `Kind` FROM `eventwow_character_spell` ORDER BY `CharacterId`, `Slot`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const characterId = fields[0].Get<uint32>();
            uint32 const spellId = fields[1].Get<uint32>();
            uint8 kind = fields[2].Get<uint8>();

            auto itr = _characters.find(characterId);
            if (itr == _characters.end())
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_character_spell: el personaje {} no existe", characterId);
                continue;
            }

            if (!sSpellMgr->GetSpellInfo(spellId))
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): el hechizo {} no existe", characterId, itr->second.Name, spellId);
                continue;
            }

            if (kind > uint8(EventWowAbilityKind::Supreme))
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): Kind {} del hechizo {} no existe (0-3), se usa 0",
                    characterId, itr->second.Name, kind, spellId);
                kind = 0;
            }

            // La progresion sube de rango desde el primero; las fijas pueden ser cualquier rango (p. ej. el maximo nativo)
            if (kind != uint8(EventWowAbilityKind::Fixed) && sSpellMgr->GetFirstSpellInChain(spellId) != spellId)
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): el hechizo {} (con progresion) no es el primer rango de su cadena",
                    characterId, itr->second.Name, spellId);

            if (!itr->second.HasSpell(spellId))
            {
                itr->second.Spells.push_back(spellId);
                itr->second.SpellKinds.push_back(EventWowAbilityKind(kind));
            }
        } while (result->NextRow());
    }

    // El ataque basico va primero en la barra (casilla 1, tecla 1), siempre aprendido
    for (auto& [id, character] : _characters)
    {
        if (!character.HasAttack() || character.HasSpell(character.GetAttackSpell()))
            continue;

        character.Spells.insert(character.Spells.begin(), character.GetAttackSpell());
        character.SpellKinds.insert(character.SpellKinds.begin(), EventWowAbilityKind::Fixed);
    }

    //                                                 0              1       2
    if (QueryResult result = WorldDatabase.Query("SELECT `CharacterId`, `Stat`, `Value` FROM `eventwow_character_stat`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const characterId = fields[0].Get<uint32>();
            std::string const key = fields[1].Get<std::string>();
            int32 const value = fields[2].Get<int32>();

            auto itr = _characters.find(characterId);
            if (itr == _characters.end())
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_character_stat: el personaje {} no existe", characterId);
                continue;
            }

            std::optional<EventWowStat> stat = EventWowStats::FromKey(key);
            if (!stat)
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): stat desconocida '{}'", characterId, itr->second.Name, key);
                continue;
            }

            if (value)
                itr->second.Stats.emplace_back(*stat, value);
        } while (result->NextRow());
    }

    //                                                 0              1       2
    if (QueryResult result = WorldDatabase.Query("SELECT `CharacterId`, `Stat`, `Value` FROM `eventwow_character_attribute`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const characterId = fields[0].Get<uint32>();
            std::string const key = fields[1].Get<std::string>();
            int32 const value = fields[2].Get<int32>();

            auto itr = _characters.find(characterId);
            if (itr == _characters.end())
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_character_attribute: el personaje {} no existe", characterId);
                continue;
            }

            std::optional<EventWowStat> stat = EventWowStats::FromKey(key);
            if (!stat)
            {
                LOG_ERROR("module.eventwow", "EventWow: personaje {} ({}): stat de atributo desconocida '{}'", characterId, itr->second.Name, key);
                continue;
            }

            if (value)
                itr->second.AttributeStats.emplace_back(*stat, value);
        } while (result->NextRow());
    }

    //                                                 0         1
    if (QueryResult result = WorldDatabase.Query("SELECT `GameId`, `CharacterId` FROM `eventwow_game_character` ORDER BY `GameId`, `Sort`, `CharacterId`"))
    {
        do
        {
            Field* fields = result->Fetch();
            std::string const gameId = fields[0].Get<std::string>();
            uint32 const characterId = fields[1].Get<uint32>();

            if (!sEventWowGames.GetGame(gameId))
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_game_character: el juego '{}' no existe", gameId);
                continue;
            }

            if (!Get(characterId))
            {
                LOG_ERROR("module.eventwow", "EventWow: eventwow_game_character: el personaje {} (juego '{}') no existe", characterId, gameId);
                continue;
            }

            _gameCharacters[gameId].push_back(characterId);
        } while (result->NextRow());
    }

    LOG_INFO("module.eventwow", "EventWow: {} personaje(s) de minijuego cargados", _characters.size());
}

EventWowCharacterInfo const* EventWowCharacters::Get(uint32 id) const
{
    auto itr = _characters.find(id);
    return itr != _characters.end() ? &itr->second : nullptr;
}

std::vector<uint32> EventWowCharacters::GetIds() const
{
    std::vector<uint32> ids;
    for (auto const& [id, character] : _characters)
        ids.push_back(id);

    std::sort(ids.begin(), ids.end());
    return ids;
}

std::vector<uint32> const& EventWowCharacters::GetForGame(std::string_view gameId) const
{
    static std::vector<uint32> const empty;
    auto itr = _gameCharacters.find(std::string(gameId));
    return itr != _gameCharacters.end() ? itr->second : empty;
}

EventWowCharacterInfo const* EventWowCharacters::GetByPickCreature(uint32 creatureEntry) const
{
    auto itr = _pickCreatures.find(creatureEntry);
    return itr != _pickCreatures.end() ? Get(itr->second) : nullptr;
}

class EventWow_CharactersWorldScript : public WorldScript
{
public:
    EventWow_CharactersWorldScript() : WorldScript("EventWow_CharactersWorldScript", {
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnStartup() override
    {
        if (sEventWowConfig.Enabled)
            sEventWowCharacters.Load();
    }
};

void AddSC_eventwow_characters()
{
    new EventWow_CharactersWorldScript();
}
