#ifndef MOD_EVENTWOW_INVENTORY_H
#define MOD_EVENTWOW_INVENTORY_H

#include "Define.h"

class Player;

// Inventario de partida estilo Dota/Warcraft III: N casillas (EventWowGameInfo::InventorySlots) = las N primeras
// ranuras de la mochila nativa. Los objetos NO se equipan: llevarlos en una casilla ya da sus efectos.
//  - Stats de item_template (stat_type/stat_value, armadura) -> EventWowStats, una vez por objeto (no por cantidad).
//  - Hechizos "Equipar:" (spelltrigger 1) -> aura en el jugador mientras lo lleva. Si varios objetos dan el mismo
//    hechizo, el aura no se acumula (como las pasivas unicas de Dota); si el aura se pierde (muerte), vuelve.
//    Los efectos "al golpear" se hacen con auras de este tipo (el aura lleva el proc).
//  - Hechizos "Uso:" funcionan de forma nativa desde la mochila (activas con su reutilizacion).
//  - Dano de arma: no (el motor solo lo lee de la mano equipada); las armas dan stats (poder de ataque...).
// El jugador no puede equipar nada en partida ni comprar si las N casillas estan llenas (salvo los instantaneos,
// EventWowShop.h, que no ocupan casilla). Lo que haya mas alla de la casilla N no cuenta (el cliente no lo muestra).
// Fuera de partida no hay objetos (EventWowLobby::ClearInventory). El estado vive en Player::CustomData.
namespace EventWowInventory
{
    // Mochila nativa (INVENTORY_SLOT_ITEM_START..END)
    constexpr uint8 MaxSlots = 16;

    // Periodico (hilo del mundo, EventWowMatch): aplica/quita los efectos de lo que haya cambiado en las casillas
    void Update(Player* player, uint8 slots);

    // Quita todos los efectos aplicados y olvida el estado (salir de la partida). Antes de EventWowStats::Reset.
    void Clear(Player* player);
}

#endif
