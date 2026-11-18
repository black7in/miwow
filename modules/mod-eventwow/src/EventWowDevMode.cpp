#include "DataMap.h"
#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowProtocol.h"
#include "Player.h"
#include "ScriptMgr.h"

// Modo dev = .gm on o .dev on (comandos del core; quien puede usarlos lo decide su RBAC).
//  - Servidor: en modo dev no se aplican las reglas de EventWow dentro del mundo (EventWowDevMode.h).
//  - Cliente: recibe DEV_MODE y puede ocultar el panel para usar la interfaz nativa ("Ocultar panel" / /eventwow).
//    Ocultar o mostrar el panel es solo del cliente: no toca ningun flag.
//  - El core no avisa al cambiar el modo GM: se comprueba cada CheckInterval para los conectados.
//  - .gm y .dev empiezan desactivados en cada login (.dev se quita aqui; .gm con el override
//    GM.LoginState = 0 de mod_eventwow.conf.dist).
//
//   Servidor -> cliente: DEV_MODE <0|1> (al conectar y en cada cambio)
bool EventWowDevMode::IsActive(Player const* player)
{
    return player->IsDeveloper() || player->IsGameMaster();
}

namespace
{
    constexpr Milliseconds CheckInterval = 250ms;

    struct DevModeState : public DataMap::Base
    {
        bool Sent = false;  // ultimo DEV_MODE enviado
    };

    void SendState(Player* player)
    {
        DevModeState* state = player->CustomData.GetDefault<DevModeState>("EventWowDevMode");
        state->Sent = EventWowDevMode::IsActive(player);
        EventWowMessage("DEV_MODE").Add(state->Sent ? 1 : 0).Send(player);
    }
}

class EventWow_DevModeWorldScript : public WorldScript
{
public:
    EventWow_DevModeWorldScript() : WorldScript("EventWow_DevModeWorldScript", {
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnUpdate(uint32 diff) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        _timer += Milliseconds(diff);
        if (_timer < CheckInterval)
            return;

        _timer = 0ms;
        EventWowProtocol::ForEachConnected([](Player* player)
        {
            DevModeState const* state = player->CustomData.Get<DevModeState>("EventWowDevMode");
            if (!state || state->Sent == EventWowDevMode::IsActive(player))
                return;

            SendState(player);
        });
    }

private:
    Milliseconds _timer = 0ms;
};

class EventWow_DevModePlayerScript : public PlayerScript
{
public:
    EventWow_DevModePlayerScript() : PlayerScript("EventWow_DevModePlayerScript", {
        PLAYERHOOK_ON_LOGIN
    }) { }

    // .dev no se conserva entre sesiones (.gm tampoco: GM.LoginState = 0)
    void OnPlayerLogin(Player* player) override
    {
        if (sEventWowConfig.Enabled && player->IsDeveloper())
            player->SetDeveloper(false);
    }
};

void AddSC_eventwow_dev_mode()
{
    EventWowProtocol::RegisterConnectListener(SendState);

    new EventWow_DevModeWorldScript();
    new EventWow_DevModePlayerScript();
}
