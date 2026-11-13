#include "EventWowLobby.h"
#include "EventWowConfig.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

// El mapa no basta: la Isla de los GM esta en Kalimdor (mapa 1), igual que Orgrimmar y otros cementerios
bool EventWowLobby::IsInLobby(Player const* player)
{
    WorldLocation const& lobby = sEventWowConfig.Lobby;
    return player->GetMapId() == lobby.GetMapId() && player->GetExactDist2d(&lobby) <= Radius;
}

// Visible solo para GMs (nivel >= moderador) mientras esta en el lobby
void EventWowLobby::SetVisibility(Player* player, bool inLobby)
{
    if (player->GetSession()->GetSecurity() > SEC_PLAYER)
        return;

    player->SetServerSideVisibility(SERVERSIDE_VISIBILITY_GM, inLobby ? SEC_MODERATOR : SEC_PLAYER);
}

void EventWowLobby::RestoreBaseState(Player* player)
{
    if (!player->IsAlive())
    {
        player->ResurrectPlayer(1.0f);
        player->SpawnCorpseBones();
    }

    player->CombatStop(true);
    player->RemoveAllAuras();
    player->SetFullHealth();
}

bool EventWowLobby::ReturnToLobby(Player* player)
{
    RestoreBaseState(player);
    SetVisibility(player, true);
    return player->TeleportTo(sEventWowConfig.Lobby);
}

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

    // Antes de entrar al mapa: ya invisible para el resto del lobby
    void OnPlayerLoadFromDB(Player* player) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        EventWowLobby::SetVisibility(player, true);
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

        // Pudo desconectarse muerto (p. ej. dentro de una partida): siempre vivo en el lobby
        if (!player->IsAlive())
            EventWowLobby::RestoreBaseState(player);
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
