#include "EventWowCharacters.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "EventWowConfig.h"
#include "EventWowGames.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "SpellMgr.h"
#include <algorithm>

bool EventWowCharacterInfo::HasSpell(uint32 spellId) const
{
    return std::find(Spells.begin(), Spells.end(), spellId) != Spells.end();
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

    //                                                 0     1       2              3       4            5        6         7            8           9
    if (QueryResult result = WorldDatabase.Query("SELECT `Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, "
        "`VehicleEntry` FROM `eventwow_character`"))
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

    //                                                 0              1
    if (QueryResult result = WorldDatabase.Query("SELECT `CharacterId`, `SpellId` FROM `eventwow_character_spell` ORDER BY `CharacterId`, `Slot`"))
    {
        do
        {
            Field* fields = result->Fetch();
            uint32 const characterId = fields[0].Get<uint32>();
            uint32 const spellId = fields[1].Get<uint32>();

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

            if (!itr->second.HasSpell(spellId))
                itr->second.Spells.push_back(spellId);
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

std::vector<uint32> const& EventWowCharacters::GetForGame(std::string_view gameId) const
{
    static std::vector<uint32> const empty;
    auto itr = _gameCharacters.find(std::string(gameId));
    return itr != _gameCharacters.end() ? itr->second : empty;
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
