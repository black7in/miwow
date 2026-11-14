#include "EventWowLobby.h"
#include "EventWowConfig.h"
#include "EventWowDisguise.h"
#include "EventWowInventory.h"
#include "EventWowStats.h"
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
    EventWowDisguise::Remove(player);
    EventWowInventory::Clear(player);
    EventWowStats::Reset(player);
    ClearInventory(player);
    player->SetFullHealth();
}

// Equipo, mochila y bolsas (destruir una bolsa destruye su contenido)
void EventWowLobby::ClearInventory(Player* player)
{
    for (uint8 slot = EQUIPMENT_SLOT_START; slot < INVENTORY_SLOT_ITEM_END; ++slot)
        if (player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot))
            player->DestroyItem(INVENTORY_SLOT_BAG_0, slot, true);

    // Lo vendido en la tienda (recompra)
    for (uint8 slot = BUYBACK_SLOT_START; slot < BUYBACK_SLOT_END; ++slot)
        player->RemoveItemFromBuyBackSlot(slot, true);

    player->SetMoney(0);
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
//  - Cada login: personaje neutro (sin objetos ni oro, sin XP).
class EventWow_LobbyPlayerScript : public PlayerScript
{
public:
    EventWow_LobbyPlayerScript() : PlayerScript("EventWow_LobbyPlayerScript", {
        PLAYERHOOK_ON_OVERRIDE_LOGIN_LOCATION,
        PLAYERHOOK_ON_LOAD_FROM_DB,
        PLAYERHOOK_ON_LOGIN,
        PLAYERHOOK_NOT_VISIBLE_GLOBALLY_FOR
    }) { }

    // La invisibilidad del lobby (SetVisibility) es solo para el mapa. En las listas globales del core
    // (amigos y sus avisos de conexion, /who) un jugador del lobby debe verse conectado.
    // false = visible globalmente (Player::IsVisibleGloballyFor). Las cuentas GM no pasan por aqui con nuestra
    // invisibilidad: su visibilidad la gestiona el core.
    bool OnPlayerNotVisibleGloballyFor(Player* player, Player const* /*viewer*/) override
    {
        return !sEventWowConfig.Enabled || player->GetSession()->GetSecurity() > SEC_PLAYER;
    }

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

    void OnPlayerLogin(Player* player) override
    {
        if (!sEventWowConfig.Enabled)
            return;

        // El progreso no existe en EventWow: sin experiencia
        player->SetPlayerFlag(PLAYER_FLAGS_NO_XP_GAIN);

        // Sin tutoriales: todos vistos (por cuenta; se guarda en BD). El cliente ya recibio los flags al
        // autenticarse, asi que se reenvian (el primer login tambien queda cubierto).
        WorldSession* session = player->GetSession();
        bool changed = false;
        for (uint8 i = 0; i < MAX_ACCOUNT_TUTORIAL_VALUES; ++i)
        {
            if (session->GetTutorialInt(i) != 0xFFFFFFFF)
            {
                session->SetTutorialInt(i, 0xFFFFFFFF);
                changed = true;
            }
        }

        if (changed)
            session->SendTutorialsData();

        // Oro y objetos solo existen dentro de una partida (pudo desconectarse en ella)
        EventWowLobby::ClearInventory(player);

        // Pudo desconectarse muerto (p. ej. dentro de una partida): siempre vivo en el lobby
        if (!player->IsAlive())
            EventWowLobby::RestoreBaseState(player);
    }
};

void AddSC_eventwow_lobby()
{
    new EventWow_LobbyPlayerScript();
}
