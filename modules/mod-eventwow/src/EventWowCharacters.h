#ifndef MOD_EVENTWOW_CHARACTERS_H
#define MOD_EVENTWOW_CHARACTERS_H

#include "Define.h"
#include "EventWowStats.h"
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

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
    std::vector<uint32> Spells; // por orden de ranura (barra del HUD)
    // Vehiculo opcional (creature_template con VehicleId): el disfrazado va siempre montado en el asiento 0.
    // Sus hechizos, velocidad y vida son los de la criatura (barra nativa de vehiculo). 0 = a pie.
    uint32 VehicleEntry = 0;
    // Bonificaciones de stats del personaje (eventwow_character_stat), como las de un objeto: se suman a las
    // nativas del contenedor y el motor calcula lo derivado (EventWowStats.h)
    std::vector<std::pair<EventWowStat, int32>> Stats;
    // Armas visibles (item_template, solo el aspecto: ni stats ni habilidad; EventWowWeapons.h). 0 = sin arma.
    // No hay ranura de distancia: el cliente no la dibuja (los arcos van en la mano derecha).
    uint32 WeaponMainHand = 0;
    uint32 WeaponOffHand = 0;
    // PNJ (creature_template) que lo representa en la eleccion en el mundo (EventWowMatch::GetPickPositions).
    // Solo pone nombre y dialogo: modelo, escala y armas salen de esta ficha. 0 = no se puede elegir en el mundo.
    uint32 PickCreature = 0;

    bool HasSpell(uint32 spellId) const;
};

class EventWowCharacters
{
public:
    static EventWowCharacters& Instance();

    // Al arrancar (BD world ya cargada). Descarta lo que no sea valido y lo avisa en el log.
    void Load();

    EventWowCharacterInfo const* Get(uint32 id) const;
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
