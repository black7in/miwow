#ifndef MOD_MIWOW_VEHICLE_H
#define MOD_MIWOW_VEHICLE_H

#include "Define.h"

class Player;
struct Position;

// Vehiculo de partida (opcional por juego, MiWowMatch::GetVehicleEntry): el jugador, con su personaje y equipo,
// va montado en una criatura-vehiculo (creature_template con VehicleId) en el asiento 0. Nada se guarda.
//  - Se invoca junto a el y se le sube pasado VehicleEnterDelay (ver .cpp); Update() le vuelve a subir si se baja, y
//    si el vehiculo muere o queda lejos (p. ej. tras reaparecer) invoca otro.
//  - Al quitarlo se le baja y el vehiculo desaparece.
// El estado vive en Player::CustomData: desaparece con el logout.
// Quien lo quita: MiWowMatchMgr::RemovePlayer (fin, abandono, salir de la instancia, logout),
// MiWowLobby::RestoreBaseState y el logout.
namespace MiWowVehicle
{
    // Sustituye el vehiculo actual si lo hay
    void Assign(Player* player, uint32 entry);
    void Remove(Player* player);
    bool HasVehicle(Player const* player);

    // Periodico (hilo del mundo, MiWowMatch): mantiene al jugador montado en su vehiculo.
    // No hace nada muerto, en modo dev o sin vehiculo asignado.
    void Update(Player* player);
    // Baja al jugador y hace desaparecer su vehiculo; el siguiente Update invoca uno nuevo donde este el jugador.
    // Para recolocar a alguien con vehiculo sin Vehicle::TeleportVehicle (que lo baja y lo sube por clic).
    void DismissVehicle(Player* player);
    // Para juegos que montan en un momento concreto (p. ej. la carrera: "¡Todos a sus motos!"): HoldVehicle hace que
    // Update no invoque el vehiculo; MountVehicle lo invoca (en at, o junto al jugador) y le sube ya, y desde ahi
    // Update vuelve a mantenerle montado. Devuelve si ha quedado montado (si no, el motivo va al log).
    void HoldVehicle(Player* player);
    bool MountVehicle(Player* player, Position const* at = nullptr);
}

#endif
