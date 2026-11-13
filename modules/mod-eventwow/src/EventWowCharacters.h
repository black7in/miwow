#ifndef MOD_EVENTWOW_CHARACTERS_H
#define MOD_EVENTWOW_CHARACTERS_H

#include "Define.h"
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
    uint32 Health = 0;          // vida maxima fija
    uint8 PowerType = 0;        // Powers: 0 mana, 1 ira, 3 energia
    uint32 MaxPower = 0;        // maximo fijo del PowerType (ira/energia en unidades internas: 100 de ira = 1000)
    std::vector<uint32> Spells; // por orden de ranura (barra del HUD)

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

private:
    std::unordered_map<uint32, EventWowCharacterInfo> _characters;
    std::unordered_map<std::string, std::vector<uint32>> _gameCharacters;
};

#define sEventWowCharacters EventWowCharacters::Instance()

#endif
