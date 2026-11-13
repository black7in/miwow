#ifndef MOD_EVENTWOW_DISGUISE_H
#define MOD_EVENTWOW_DISGUISE_H

class Player;
struct EventWowCharacterInfo;

// Disfraz: convierte el contenedor (elfo de la noche druida) en un personaje de minijuego
// (EventWowCharacters.h) y lo deshace sin dejar rastro. Nada se guarda en BD:
//  - Modelo: display y display nativo (asi las auras de transformacion vuelven al disfraz, no a la raza).
//  - Escala.
//  - Vida/poder maximos fijos: hooks OnPlayerAfterUpdateMaxHealth/MaxPower (al final del calculo del core).
//  - Tipo de poder (mana/ira/energia), como las formas del druida.
//  - Hechizos temporales (learnSpell temporal: no se guardan). Mientras va disfrazado (salvo modo dev)
//    solo puede lanzar esos (OnSpellCheckCast); los desencadenados no cuentan.
// El estado vive en Player::CustomData: desaparece con el logout.
// Quien lo quita: EventWowMatchMgr::RemovePlayer (fin, abandono, salir de la instancia, logout) y
// EventWowLobby::RestoreBaseState.
//
// Protocolo: MATCH_CHARACTER <id> <nombre> <icono> <hechizo>... | MATCH_CHARACTER 0 (sin disfraz)
namespace EventWowDisguise
{
    // Sustituye el disfraz actual si lo hay
    void Apply(Player* player, EventWowCharacterInfo const& character);
    void Remove(Player* player);

    // Personaje con el que va disfrazado (nullptr = ninguno)
    EventWowCharacterInfo const* Get(Player const* player);

    void SendState(Player* player);
}

#endif
