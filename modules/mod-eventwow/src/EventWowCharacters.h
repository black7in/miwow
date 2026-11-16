#ifndef MOD_EVENTWOW_CHARACTERS_H
#define MOD_EVENTWOW_CHARACTERS_H

#include "Define.h"
#include "EventWowStats.h"
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

// Tipo de cada hechizo de la ficha (eventwow_character_spell.Kind). Con progresion (EventWowProgress.h) los
// tipos 1-3 empiezan sin aprender y se mejoran con puntos; sin progresion se aprende el rango 1 de todos.
enum class EventWowAbilityKind : uint8
{
    Fixed    = 0,   // siempre aprendido (juegos sin niveles, ataques basicos...)
    Basic    = 1,   // rango maximo = (nivel + 1) / 2
    Ultimate = 2,   // rangos a nivel 6, 12, 18
    Supreme  = 3    // sola al llegar al nivel maximo (sin punto)
};

// Personaje jugable de un minijuego: lo que el disfraz (EventWowDisguise.h) aplica al contenedor.
// Se carga de la BD world (tablas eventwow_character*, SQL del modulo); 0 en un campo = no se cambia.
struct EventWowCharacterInfo
{
    uint32 Id = 0;
    std::string Name;
    std::string Description;
    std::string Icon;           // ruta de textura del cliente
    uint32 DisplayId = 0;       // modelo (CreatureDisplayInfo)
    float Scale = 1.0f;
    // Vida/poder BASE: el motor suma encima lo que den las stats (Aguante, Intelecto, libros...) y auras
    uint32 Health = 0;          // vida maxima base
    uint8 PowerType = 0;        // Powers: 0 mana, 1 ira, 3 energia
    uint32 MaxPower = 0;        // maximo base del PowerType (ira/energia en unidades internas: 100 de ira = 1000)
    std::vector<uint32> Spells; // primer rango, por orden de ranura (barra del HUD)
    std::vector<EventWowAbilityKind> SpellKinds; // uno por hechizo de Spells
    // Vehiculo opcional (creature_template con VehicleId): el disfrazado va siempre montado en el asiento 0.
    // Sus hechizos, velocidad y vida son los de la criatura (barra nativa de vehiculo). 0 = a pie.
    uint32 VehicleEntry = 0;
    // Bonificaciones de stats del personaje (eventwow_character_stat), como las de un objeto: se suman a las
    // nativas del contenedor y el motor calcula lo derivado (EventWowStats.h)
    std::vector<std::pair<EventWowStat, int32>> Stats;
    // Lo que da cada punto de "Atributos" (eventwow_character_attribute), solo con progresion
    std::vector<std::pair<EventWowStat, int32>> AttributeStats;
    // Armas (item_template, propias 9500200-9500299): el disfraz las EQUIPA de verdad mientras dura (el servidor,
    // sin las comprobaciones de equipar) y da la habilidad de arma que falte al druida (EventWowWeapons::Equip).
    // Asi el cliente anima cada tipo de arma de forma nativa (disparo con arco/escopeta, doble empunadura...).
    // 0 = sin arma. Un arma en la mano izquierda golpea (doble empunadura, penalizacion nativa del 50 %).
    uint32 WeaponMainHand = 0;
    uint32 WeaponOffHand = 0;
    uint32 WeaponRanged = 0;    // arco, escopeta, ballesta o arrojadiza (ranura de distancia)
    // PNJ (creature_template) que lo representa en la eleccion en el mundo (EventWowMatch::GetPickPositions).
    // Solo pone nombre y dialogo: modelo, escala y armas salen de esta ficha. 0 = no se puede elegir en el mundo.
    uint32 PickCreature = 0;
    // Ataque basico (docs/heroes.md, "Ataque basico"). AttackSpeed 0 = sin configurar (no se toca nada).
    // Con AttackSpeed, la casilla 1 de la barra es el ataque: AutoAttackSpell (disparo automatico con
    // SPELL_ATTR2_AUTO_REPEAT; el clic derecho lo lanza en vez de golpear, EventWowDisguise) o, con 0, "Atacar"
    // nativo cuerpo a cuerpo con AttackMin-AttackMax por golpe (+ AttackPerLevel por nivel sobre el 1).
    // AttackSpeed es la velocidad de REFERENCIA de esos numeros: con arma, el intervalo es el del arma (velocidad
    // normal de su tipo) y el dano por golpe se escala por (velocidad del arma / AttackSpeed): mismo dano por
    // segundo con un arma lenta o rapida. Sin arma, AttackSpeed es el intervalo.
    // El dano de un disparo lo pone el hechizo (per_level en spellgen); su intervalo es el del arma de distancia
    // o, sin ella (lanzadores), AttackSpeed.
    uint32 AutoAttackSpell = 0;
    float AttackMin = 0.0f;
    float AttackMax = 0.0f;
    float AttackPerLevel = 0.0f;
    uint32 AttackSpeed = 0;     // ms entre golpes/disparos

    static constexpr uint32 MeleeAttackSpell = 6603; // "Atacar"

    bool HasAttack() const { return AttackSpeed != 0; }
    uint32 GetAttackSpell() const { return AutoAttackSpell ? AutoAttackSpell : MeleeAttackSpell; }

    // true si es uno de sus hechizos (cualquier rango)
    bool HasSpell(uint32 spellId) const;
};

class EventWowCharacters
{
public:
    static EventWowCharacters& Instance();

    // Al arrancar (BD world ya cargada). Descarta lo que no sea valido y lo avisa en el log.
    void Load();

    EventWowCharacterInfo const* Get(uint32 id) const;
    // Todos los personajes cargados, por Id
    std::vector<uint32> GetIds() const;
    // Personajes que ofrece un juego (eventwow_game_character), por orden. Vacio = el juego no disfraza.
    std::vector<uint32> const& GetForGame(std::string_view gameId) const;
    // Personaje cuyo PNJ de eleccion es esa criatura (nullptr = ninguno)
    EventWowCharacterInfo const* GetByPickCreature(uint32 creatureEntry) const;

private:
    std::unordered_map<uint32, EventWowCharacterInfo> _characters;
    std::unordered_map<std::string, std::vector<uint32>> _gameCharacters;
    std::unordered_map<uint32, uint32> _pickCreatures; // criatura -> personaje
};

#define sEventWowCharacters EventWowCharacters::Instance()

#endif
