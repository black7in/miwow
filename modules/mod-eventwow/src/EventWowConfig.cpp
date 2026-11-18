#include "EventWowConfig.h"
#include "Config.h"
#include "Log.h"
#include "ScriptMgr.h"
#include <algorithm>

EventWowConfig& EventWowConfig::Instance()
{
    static EventWowConfig instance;
    return instance;
}

void EventWowConfig::Load()
{
    Enabled = sConfigMgr->GetOption<bool>("EventWow.Enable", true);

    QueueFillWait = Seconds(sConfigMgr->GetOption<uint32>("EventWow.Queue.FillWait", 15));
    QueueAcceptTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("EventWow.Queue.AcceptTimeout", 20)));
    MatchLoadTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("EventWow.Match.LoadTimeout", 30)));
    MatchReturnDelay = Seconds(sConfigMgr->GetOption<uint32>("EventWow.Match.ReturnDelay", 8));

    AgilityHasteMax = std::max(0.0f, sConfigMgr->GetOption<float>("EventWow.Hero.AgilityHaste.Max", 1770.0f));
    AgilityHasteHalf = std::max(1.0f, sConfigMgr->GetOption<float>("EventWow.Hero.AgilityHaste.Half", 1000.0f));
    AttackMinInterval = sConfigMgr->GetOption<uint32>("EventWow.Hero.AttackMinInterval", 150);
    IntellectHasteMax = std::max(0.0f, sConfigMgr->GetOption<float>("EventWow.Hero.IntellectHaste.Max", 300.0f));
    IntellectHasteHalf = std::max(1.0f, sConfigMgr->GetOption<float>("EventWow.Hero.IntellectHaste.Half", 1000.0f));
    SpellCastMinTime = sConfigMgr->GetOption<uint32>("EventWow.Hero.SpellCastMinTime", 500);

    LOG_INFO("module.eventwow", "EventWow: {}", Enabled ? "activado" : "desactivado");
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
