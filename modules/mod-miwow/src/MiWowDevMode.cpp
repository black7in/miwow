#include "DataMap.h"
#include "MiWowConfig.h"
#include "MiWowDevMode.h"
#include "MiWowProtocol.h"
#include "Player.h"
#include "ScriptMgr.h"

// Modo dev = .gm on o .dev on (comandos del core; quien puede usarlos lo decide su RBAC).
//  - Servidor: en modo dev no se aplican las reglas de MiWow dentro del mundo (MiWowDevMode.h).
//  - Cliente: recibe DEV_MODE y puede ocultar el panel para usar la interfaz nativa ("Ocultar panel" / /miwow).
//    Ocultar o mostrar el panel es solo del cliente: no toca ningun flag.
//  - El core no avisa al cambiar el modo GM: se comprueba cada CheckInterval para los conectados.
//  - .gm y .dev empiezan desactivados en cada login (.dev se quita aqui; .gm con el override
//    GM.LoginState = 0 de mod_miwow.conf.dist).
//
//   Servidor -> cliente: DEV_MODE <0|1> (al conectar y en cada cambio)
bool MiWowDevMode::IsActive(Player const* player)
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
        DevModeState* state = player->CustomData.GetDefault<DevModeState>("MiWowDevMode");
        state->Sent = MiWowDevMode::IsActive(player);
        MiWowMessage("DEV_MODE").Add(state->Sent ? 1 : 0).Send(player);
    }
}

class MiWow_DevModeWorldScript : public WorldScript
{
public:
    MiWow_DevModeWorldScript() : WorldScript("MiWow_DevModeWorldScript", {
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnUpdate(uint32 diff) override
    {
        if (!sMiWowConfig.Enabled)
            return;

        _timer += Milliseconds(diff);
        if (_timer < CheckInterval)
            return;

        _timer = 0ms;
        MiWowProtocol::ForEachConnected([](Player* player)
        {
            DevModeState const* state = player->CustomData.Get<DevModeState>("MiWowDevMode");
            if (!state || state->Sent == MiWowDevMode::IsActive(player))
                return;

            SendState(player);
        });
    }

private:
    Milliseconds _timer = 0ms;
};

class MiWow_DevModePlayerScript : public PlayerScript
{
public:
    MiWow_DevModePlayerScript() : PlayerScript("MiWow_DevModePlayerScript", {
        PLAYERHOOK_ON_LOGIN
    }) { }

    // .dev no se conserva entre sesiones (.gm tampoco: GM.LoginState = 0)
    void OnPlayerLogin(Player* player) override
    {
        if (sMiWowConfig.Enabled && player->IsDeveloper())
            player->SetDeveloper(false);
    }
};

void AddSC_miwow_dev_mode()
{
    MiWowProtocol::RegisterConnectListener(SendState);

    new MiWow_DevModeWorldScript();
    new MiWow_DevModePlayerScript();
}
