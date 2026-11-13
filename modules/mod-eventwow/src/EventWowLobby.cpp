#include "EventWowConfig.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

// Lobby: "limbo" invisible donde el personaje queda aparcado mientras el jugador usa el panel.
//  - Cada login carga directamente en el lobby (hook del core OnPlayerOverrideLoginLocation),
//    incluso si el jugador se desconecto dentro de un minijuego.
//  - Los jugadores del lobby son invisibles para los demas (visibilidad server-side tipo GM),
//    asi el servidor no envia trafico de visibilidad entre ellos.
//  - Primer login: personaje neutro (sin objetos, sin XP).
class EventWow_LobbyPlayerScript : public PlayerScript
{
public:
    EventWow_LobbyPlayerScript() : PlayerScript("EventWow_LobbyPlayerScript", {
        PLAYERHOOK_ON_OVERRIDE_LOGIN_LOCATION,
        PLAYERHOOK_ON_LOAD_FROM_DB,
        PLAYERHOOK_ON_FIRST_LOGIN,
        PLAYERHOOK_ON_LOGIN
    }) { }

    bool OnPlayerOverrideLoginLocation(Player* /*player*/, WorldLocation& location) override
    {
        if (!sEventWowConfig.Enabled)
            return false;

        location.WorldRelocate(sEventWowConfig.Lobby);
        return true;
    }

    // Antes de entrar al mapa: ya invisible para el resto del lobby.
    // Las cuentas GM se dejan como estan (LoadFromDB ya aplico su modo GM / invisibilidad).
    void OnPlayerLoadFromDB(Player* player) override
    {
        if (!sEventWowConfig.Enabled || player->GetSession()->GetSecurity() > SEC_PLAYER)
            return;

        SetLobbyVisibility(player, true);
    }

    void OnPlayerFirstLogin(Player* player) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        RemoveAllItems(player);
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        // El progreso no existe en EventWow: sin experiencia
        player->SetPlayerFlag(PLAYER_FLAGS_NO_XP_GAIN);
    }

    // Visible solo para GMs (nivel >= moderador) mientras esta en el lobby
    static void SetLobbyVisibility(Player* player, bool inLobby)
    {
        player->SetServerSideVisibility(SERVERSIDE_VISIBILITY_GM, inLobby ? SEC_MODERATOR : SEC_PLAYER);
    }

    // Equipo, mochila y bolsas (destruir una bolsa destruye su contenido)
    static void RemoveAllItems(Player* player)
    {
        for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
            if (player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
                player->DestroyItem(INVENTORY_SLOT_BAG_0, slot, true);
    }
};

void AddSC_eventwow_lobby()
{
    new EventWow_LobbyPlayerScript();
}
