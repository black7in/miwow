#ifndef MOD_MIWOW_LOBBY_H
#define MOD_MIWOW_LOBBY_H

#include "Define.h"

class Player;

// Entrada y salida de los eventos en un servidor tradicional (MiWowLobby.cpp). No hay lobby: el jugador busca
// partida desde el mundo y al acabar vuelve a donde estaba.
//  - Punto de vuelta = "entry point" nativo del core (el de los campos de batalla, tabla character_entry_point):
//    se guarda en la BD con el personaje, asi que sobrevive a un logout o a una caida del servidor.
//  - Login dentro del mapa de un evento (se desconecto en la partida): aparece en su punto de vuelta (o en su hogar).
namespace MiWowLobby
{
    // nullptr = puede apuntarse desde donde esta; si no, codigo de ERROR del protocolo (vivo, sin combate, fuera
    // de mazmorras/campos de batalla, sin vuelo, sin cola de campo de batalla)
    char const* CanJoinFrom(Player const* player);

    // Mapa que usa algun evento del catalogo
    bool IsEventMap(uint32 mapId);

    // Guarda la posicion actual como punto de vuelta (Player::SetEntryPoint) antes de ir a la partida
    void SaveReturnPoint(Player* player);

    // Estado base al entrar/salir de una partida: vivo, vida completa, sin combate, sin vehiculo, sin bloqueo de
    // hechizos, sin bonificaciones, sin montura ni forma y sin beneficios temporales. NUNCA toca objetos, oro, nivel, talentos ni auras pasivas.
    void RestoreBaseState(Player* player);

    // Morir en un evento no gasta el equipo (el core quita un 10 % al morir contra criaturas o al caer, salvo en
    // campos de batalla): SaveDurability al llegar a la partida, RestoreDurability al reaparecer, al salir y antes
    // del logout (devuelve lo perdido desde la foto, sin coste), ClearDurability al salir
    void SaveDurability(Player* player);
    void RestoreDurability(Player* player);
    void ClearDurability(Player* player);

    // Restaura el estado base y lo lleva a su punto de vuelta (o a su hogar)
    bool ReturnFromMatch(Player* player);
}

#endif
