#ifndef MOD_EVENTWOW_LOBBY_H
#define MOD_EVENTWOW_LOBBY_H

class Player;

// Lobby: "limbo" invisible donde el personaje queda aparcado mientras el jugador usa el panel
// (EventWowLobby.cpp). Helpers usados tambien al entrar/salir de un minijuego.
namespace EventWowLobby
{
    // Distancia al punto ancla que cuenta como "en el lobby" (mismo mapa)
    constexpr float Radius = 250.0f;

    bool IsInLobby(Player const* player);

    // En el lobby los jugadores solo son visibles para GMs (sin trafico de visibilidad entre ellos).
    // No toca a las cuentas GM (su modo GM / invisibilidad lo gestiona el core).
    void SetVisibility(Player* player, bool inLobby);

    // Estado base del personaje: vivo, vida completa, sin auras, combate ni disfraz
    void RestoreBaseState(Player* player);

    // Restaura el estado base, lo hace invisible y lo lleva al punto ancla del lobby
    bool ReturnToLobby(Player* player);
}

#endif
