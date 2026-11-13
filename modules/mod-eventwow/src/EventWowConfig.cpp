#include "EventWowConfig.h"
#include "Config.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <algorithm>
#include <cmath>

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

    Lobby.WorldRelocate(
        sConfigMgr->GetOption<uint32>("EventWow.Lobby.MapId", 1),
        sConfigMgr->GetOption<float>("EventWow.Lobby.X", 16226.2f),
        sConfigMgr->GetOption<float>("EventWow.Lobby.Y", 16257.0f),
        sConfigMgr->GetOption<float>("EventWow.Lobby.Z", 13.2022f),
        sConfigMgr->GetOption<float>("EventWow.Lobby.O", 1.65007f));

    QueueFillWait = Seconds(sConfigMgr->GetOption<uint32>("EventWow.Queue.FillWait", 15));
    QueueAcceptTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("EventWow.Queue.AcceptTimeout", 20)));
    MatchLoadTimeout = Seconds(std::max<uint32>(5, sConfigMgr->GetOption<uint32>("EventWow.Match.LoadTimeout", 30)));
    MatchReturnDelay = Seconds(sConfigMgr->GetOption<uint32>("EventWow.Match.ReturnDelay", 8));

    LOG_INFO("module.eventwow", "EventWow: {} (raza {}, clase {}, lobby mapa {} [{}, {}, {}])",
        Enabled ? "activado" : "desactivado", CharacterRace, CharacterClass,
        Lobby.GetMapId(), Lobby.GetPositionX(), Lobby.GetPositionY(), Lobby.GetPositionZ());
}

class EventWow_WorldScript : public WorldScript
{
public:
    EventWow_WorldScript() : WorldScript("EventWow_WorldScript", {
        WORLDHOOK_ON_AFTER_CONFIG_LOAD,
        WORLDHOOK_ON_STARTUP
    }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        sEventWowConfig.Load();
    }

    // playercreateinfo (SQL del modulo) debe apuntar al mismo lobby que la config,
    // para que el primer login cargue directamente ahi.
    void OnStartup() override
    {
        if (!sEventWowConfig.Enabled)
            return;

        PlayerInfo const* info = sObjectMgr->GetPlayerInfo(sEventWowConfig.CharacterRace, sEventWowConfig.CharacterClass);
        if (!info)
        {
            LOG_ERROR("module.eventwow", "EventWow: no existe playercreateinfo para raza {} / clase {}",
                sEventWowConfig.CharacterRace, sEventWowConfig.CharacterClass);
            return;
        }

        WorldLocation const& lobby = sEventWowConfig.Lobby;
        bool const matches = info->mapId == lobby.GetMapId()
            && std::fabs(info->positionX - lobby.GetPositionX()) < 1.0f
            && std::fabs(info->positionY - lobby.GetPositionY()) < 1.0f
            && std::fabs(info->positionZ - lobby.GetPositionZ()) < 1.0f;

        if (!matches)
            LOG_ERROR("module.eventwow", "EventWow: playercreateinfo (mapa {} [{}, {}, {}]) no coincide con EventWow.Lobby "
                "(mapa {} [{}, {}, {}]). Los personajes nuevos naceran fuera del lobby.",
                info->mapId, info->positionX, info->positionY, info->positionZ,
                lobby.GetMapId(), lobby.GetPositionX(), lobby.GetPositionY(), lobby.GetPositionZ());
    }
};

void AddSC_eventwow_config()
{
    new EventWow_WorldScript();
}
