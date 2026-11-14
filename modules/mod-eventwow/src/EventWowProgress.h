#ifndef MOD_EVENTWOW_PROGRESS_H
#define MOD_EVENTWOW_PROGRESS_H

#include "Define.h"

class Player;
struct EventWowCharacterInfo;

// Progresion del heroe dentro de una partida (docs/heroes.md): nivel REAL de WoW de 1 a MaxLevel con la XP nativa
// (barra, aviso y animacion de subida, reparto en grupo), un punto por nivel para las habilidades del disfraz.
//  - Basicas (Kind 1): rango maximo = (nivel + 1) / 2. Definitiva (2): un rango a nivel 6, 12 y 18.
//    Suprema (3): sola al llegar a MaxLevel (sin punto). Fijas (0): siempre aprendidas (EventWowDisguise).
//  - Atributos: cada punto suma las stats de eventwow_character_attribute (desde nivel 2). Maximo = MaxLevel menos
//    los rangos de basicas y definitiva (con 4 x 4 + 3 y nivel 30: 11).
//  - Un rango = un hechizo propio (spell_ranks): se cambia el aprendido por el siguiente (EventWowDisguise::ReplaceSpell).
//  - XP: OnPlayerGiveXP la multiplica (EventWowGameInfo::XpRate) y la corta en MaxLevel. Sin XP fuera (PLAYER_FLAGS_NO_XP_GAIN).
//  - Bloqueados con progresion: talentos (siempre salvo modo dev), logros y correo de recompensa de nivel.
// El estado vive en Player::CustomData. Stop() (lo llama EventWowDisguise::Remove) quita los atributos y devuelve
// el nivel base (StartPlayerLevel); el login tambien lo devuelve si se desconecto a mitad de partida.
//
// Protocolo: MATCH_ABILITIES <nivel> <max> <puntos> <atrib> <atrib max> <atrib mejorable 0/1> <stats atrib "clave:valor,...">
//            <n> (<rango> <rango max ahora> <rango total> <mejorable 0/1> <hechizo actual> <hechizo siguiente>) x n
//            | MATCH_ABILITIES 0 (sin progresion: todo aprendido, sin "+")
//            Cliente: UPGRADE <casilla 0..n-1 | attr>
namespace EventWowProgress
{
    bool IsActive(Player const* player);

    // Pone el nivel (GiveLevel) con sus efectos: lo usan Start y el comando de prueba
    void SetLevel(Player* player, uint8 level);
    // Con el disfraz ya aplicado en modo progresion (EventWowDisguise::Apply(..., true)) y el nivel inicial puesto
    void Start(Player* player, EventWowCharacterInfo const& character, uint8 maxLevel, float xpRate);
    // Quita atributos y estado, nivel base y sin XP. Sin progresion no hace nada.
    void Stop(Player* player);
    // slot = indice del hechizo en la ficha; -1 = atributos. false si no se puede.
    bool Upgrade(Player* player, int32 slot);

    void SendState(Player* player);
}

#endif
