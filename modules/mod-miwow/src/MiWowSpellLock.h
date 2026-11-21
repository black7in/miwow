#ifndef MOD_MIWOW_SPELL_LOCK_H
#define MOD_MIWOW_SPELL_LOCK_H

class Player;

// Bloqueo de hechizos de partida (opcional por juego, MiWowMatch::BlocksPlayerSpells): el jugador no puede lanzar
// sus propios hechizos (clase, monturas, juguetes...), p. ej. para que en el parkour nadie use Traslacion o la forma
// de viaje. Se permiten los desencadenados y los de objetos (pociones...). Los hechizos de un vehiculo los lanza la
// criatura, no el jugador: no les afecta. En modo dev no actua.
// El estado vive en Player::CustomData (lo lee el hook de hechizos, hilo del mapa): desaparece con el logout.
// Quien lo quita: MiWowMatchMgr::RemovePlayer y MiWowLobby::RestoreBaseState.
namespace MiWowSpellLock
{
    void Set(Player* player);
    void Clear(Player* player);
    bool IsLocked(Player const* player);
}

#endif
