#ifndef MOD_MIWOW_DEV_MODE_H
#define MOD_MIWOW_DEV_MODE_H

class Player;

// Modo dev (MiWowDevMode.cpp): .gm on o .dev on.
// Regla general: las reglas de MiWow dentro del mundo (muerte y salida en partida, desde donde buscar partida,
// interfaz) solo se aplican a jugadores; en modo dev el personaje funciona como en AzerothCore normal.
// No afecta al login (punto de vuelta si se desconecto en una partida): eso, para todos.
namespace MiWowDevMode
{
    bool IsActive(Player const* player);
}

#endif
