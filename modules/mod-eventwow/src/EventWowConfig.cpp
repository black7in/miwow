#include "EventWowConfig.h"
#include "Config.h"
#include "Log.h"
#include "ScriptMgr.h"

EventWowConfig& EventWowConfig::Instance()
{
    static EventWowConfig instance;
    return instance;
}

void EventWowConfig::Load()
{
    Enabled = sConfigMgr->GetOption<bool>("EventWow.Enable", true);
    CharacterRace = sConfigMgr->GetOption<uint8>("EventWow.Character.Race", 1);
    CharacterClass = sConfigMgr->GetOption<uint8>("EventWow.Character.Class", 1);

    LOG_INFO("module.eventwow", "EventWow: {} (raza {}, clase {})",
        Enabled ? "activado" : "desactivado", CharacterRace, CharacterClass);
}

class EventWow_WorldScript : public WorldScript
{
public:
    EventWow_WorldScript() : WorldScript("EventWow_WorldScript", {
        WORLDHOOK_ON_AFTER_CONFIG_LOAD
    }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        sEventWowConfig.Load();
    }
};

void AddSC_eventwow_config()
{
    new EventWow_WorldScript();
}
