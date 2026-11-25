#include "MiWowConfig.h"
#include "Config.h"
#include "Log.h"
#include "ScriptMgr.h"
#include <algorithm>

MiWowConfig& MiWowConfig::Instance()
{
    static MiWowConfig instance;
    return instance;
}

void MiWowConfig::Load()
{
    Enabled = sConfigMgr->GetOption<bool>("MiWow.Enable", true);

    QueueFillWait = Seconds(sConfigMgr->GetOption<uint32>("MiWow.Queue.FillWait", 15));
    QueueAcceptTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("MiWow.Queue.AcceptTimeout", 20)));
    MatchLoadTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("MiWow.Match.LoadTimeout", 30)));
    MatchReturnDelay = Seconds(sConfigMgr->GetOption<uint32>("MiWow.Match.ReturnDelay", 8));

    AutoLearn.Enabled = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Enable", true);
    AutoLearn.DevMode = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.DevMode", true);
    AutoLearn.ClassSpells = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.ClassSpells", true);
    AutoLearn.QuestSpells = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.QuestSpells", true);
    AutoLearn.TalentRanks = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.TalentRanks", true);
    AutoLearn.Proficiencies = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Proficiencies", false);
    AutoLearn.RidingApprentice = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Riding.Apprentice", false);
    AutoLearn.RidingJourneyman = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Riding.Journeyman", false);
    AutoLearn.RidingExpert = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Riding.Expert", false);
    AutoLearn.RidingArtisan = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Riding.Artisan", false);
    AutoLearn.ColdWeatherFlying = sConfigMgr->GetOption<bool>("MiWow.AutoLearn.Riding.ColdWeather", false);

    LOG_INFO("module.miwow", "MiWow: {}", Enabled ? "activado" : "desactivado");
}

class MiWow_WorldScript : public WorldScript
{
public:
    MiWow_WorldScript() : WorldScript("MiWow_WorldScript", {
        WORLDHOOK_ON_AFTER_CONFIG_LOAD
    }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        sMiWowConfig.Load();
    }
};

void AddSC_miwow_config()
{
    new MiWow_WorldScript();
}
