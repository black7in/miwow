#ifndef MOD_EVENTWOW_WEAPONS_H
#define MOD_EVENTWOW_WEAPONS_H

#include "Define.h"

class Player;

// Armas visibles sin equipar. El cliente dibuja las armas de un jugador a partir de
// PLAYER_VISIBLE_ITEM_<ranura>_ENTRYID (lo mismo que usa la transfiguracion), no del objeto equipado: escribir ahi
// el ID de un objeto (p. ej. un "Monster - ..." de PNJ) lo hace visible sin stats ni habilidad de arma.
// Probado: sale sobre un modelo transformado y la tecla Z la envaina/desenvaina. La ranura de distancia no se
// dibuja. Un arma con sheath = 0 (arcos de PNJ) no se ve envainada: copias propias en 9500200-9500299 (SQL).
// Las usa el disfraz (EventWowDisguise) con las armas de la ficha; el core las pisa al equipar/desequipar.
namespace EventWowWeapons
{
    // slot = EQUIPMENT_SLOT_MAINHAND / OFFHAND / RANGED; entry 0 = vacia
    void SetVisible(Player* player, uint8 slot, uint32 entry);
    // Vuelve a mostrar lo que lleva equipado de verdad en las ranuras de armas
    void RestoreEquipped(Player* player);
}

#endif
