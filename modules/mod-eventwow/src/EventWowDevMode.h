#ifndef MOD_EVENTWOW_DEV_MODE_H
#define MOD_EVENTWOW_DEV_MODE_H

class Player;

// Modo dev (EventWowDevMode.cpp): .gm on o .dev on.
// Regla general: las reglas de EventWow dentro del mundo (muerte y salida en partida, restricciones del lobby,
// interfaz) solo se aplican a jugadores; en modo dev el personaje funciona como en AzerothCore normal.
// No afecta al login ni a las reglas de cuenta (lobby al entrar, un personaje, raza/clase fijas): esas, para todos.
namespace EventWowDevMode
{
    bool IsActive(Player const* player);
}

#endif
