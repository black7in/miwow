#ifndef MOD_EVENTWOW_CONFIG_H
#define MOD_EVENTWOW_CONFIG_H

#include "Define.h"
#include "Duration.h"
#include "Position.h"

// Valores de mod_eventwow.conf, cacheados al cargar/recargar la configuracion.
struct EventWowConfig
{
    bool Enabled = true;
    uint8 CharacterRace = 4;   // RACE_NIGHTELF
    uint8 CharacterClass = 11; // CLASS_DRUID

    // Punto ancla del lobby: entrada en cada login y retorno al salir de un minijuego
    WorldLocation Lobby;

    // Partidas (EventWowMatchMgr)
    Seconds QueueFillWait = 15s;     // espera para llenar hasta MaxPlayers si ya hay MinPlayers
    Seconds QueueAcceptTimeout = 20s; // tiempo para aceptar una partida encontrada
    Seconds MatchLoadTimeout = 30s;  // jugadores que no llegan a la instancia en este tiempo quedan fuera
    Seconds MatchReturnDelay = 8s;   // resultado en pantalla antes de volver al lobby

    // Heroes: agilidad extra -> velocidad de ataque (EventWowDisguise, docs/heroes.md sec. 4 regla 4)
    float AgilityHasteMax = 1770.0f;   // % maximo (agilidad infinita)
    float AgilityHasteHalf = 1000.0f;  // agilidad con la que se llega a la mitad del maximo
    uint32 AttackMinInterval = 150;    // ms: ningun ataque automatico baja de esto por la agilidad
    // Heroes: intelecto extra -> celeridad con hechizos (EventWowDisguise, docs/heroes.md sec. 4 regla 5)
    float IntellectHasteMax = 300.0f;   // % maximo (intelecto infinito): lanzamiento / 4
    float IntellectHasteHalf = 1000.0f; // intelecto con el que se llega a la mitad del maximo
    uint32 SpellCastMinTime = 500;      // ms: la celeridad no baja un lanzamiento de aqui (no alarga los mas cortos)

    void Load();

    static EventWowConfig& Instance();
};

#define sEventWowConfig EventWowConfig::Instance()

#endif
