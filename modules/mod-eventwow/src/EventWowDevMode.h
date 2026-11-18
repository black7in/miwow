#ifndef MOD_EVENTWOW_DEV_MODE_H
#define MOD_EVENTWOW_DEV_MODE_H

class Player;

// Modo dev (EventWowDevMode.cpp): .gm on o .dev on.
// Regla general: las reglas de EventWow dentro del mundo (muerte y salida en partida, desde donde buscar partida,
// interfaz) solo se aplican a jugadores; en modo dev el personaje funciona como en AzerothCore normal.
// No afecta al login (punto de vuelta si se desconecto en una partida): eso, para todos.
namespace EventWowDevMode
{
    bool IsActive(Player const* player);
}

#endif
