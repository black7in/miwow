#ifndef MOD_EVENTWOW_DISGUISE_H
#define MOD_EVENTWOW_DISGUISE_H

#include "Define.h"

class Player;
struct EventWowCharacterInfo;

// Disfraz: convierte el contenedor (elfo de la noche druida) en un personaje de minijuego
// (EventWowCharacters.h) y lo deshace sin dejar rastro. Nada se guarda en BD:
//  - Modelo: display y display nativo (asi las auras de transformacion vuelven al disfraz, no a la raza).
//  - Escala.
//  - Armas visibles de la ficha (EventWowWeapons.h: solo el aspecto); al quitar, vuelven las equipadas.
//  - Vida/poder maximos = base del personaje + lo que el motor sume sobre el contenedor sin disfraz (stats,
//    auras): hooks OnPlayerAfterUpdateMaxHealth/MaxPower (al final del calculo del core).
//  - Stats del personaje (EventWowStats, como un objeto equipado); se restan al quitar el disfraz.
//  - Tipo de poder (mana/ira/energia), como las formas del druida.
//  - Hechizos temporales (learnSpell temporal: no se guardan). Mientras va disfrazado (salvo modo dev)
//    solo puede lanzar esos (OnSpellCheckCast); los desencadenados y los de objetos no cuentan. Los de un vehiculo los lanza
//    la criatura, no el jugador: no les afecta.
//  - Las invocaciones de sus hechizos (p. ej. el necrofago de Arthas) desaparecen al quitar el disfraz.
//  - Vehiculo (opcional): se invoca la criatura junto a el y se le sube al asiento 0. Update() le vuelve a
//    subir si se baja, y si el vehiculo muere o queda lejos (p. ej. tras reaparecer) invoca otro. Al quitar
//    el disfraz se le baja y el vehiculo desaparece.
// El estado vive en Player::CustomData: desaparece con el logout.
// Quien lo quita: EventWowMatchMgr::RemovePlayer (fin, abandono, salir de la instancia, logout) y
// EventWowLobby::RestoreBaseState.
//
// Protocolo: MATCH_CHARACTER <id> <nombre> <icono> <hechizo>... | MATCH_CHARACTER 0 (sin disfraz)
namespace EventWowDisguise
{
    // Sustituye el disfraz actual si lo hay. progression: solo aprende los hechizos fijos (Kind 0); el resto los
    // aprende EventWowProgress con puntos (ReplaceSpell).
    void Apply(Player* player, EventWowCharacterInfo const& character, bool progression = false);
    // Cambia un hechizo temporal del disfraz por otro (rango siguiente). oldSpell 0 = aprender sin quitar.
    void ReplaceSpell(Player* player, uint32 oldSpell, uint32 newSpell);
    void Remove(Player* player);

    // Personaje con el que va disfrazado (nullptr = ninguno)
    EventWowCharacterInfo const* Get(Player const* player);

    // Periodico (hilo del mundo, EventWowMatch): mantiene al jugador montado en su vehiculo.
    // No hace nada muerto, en modo dev o sin vehiculo.
    void Update(Player* player);

    void SendState(Player* player);
}

#endif
