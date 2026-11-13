#ifndef MOD_EVENTWOW_CONFIG_H
#define MOD_EVENTWOW_CONFIG_H

#include "Define.h"
#include "Position.h"

// Valores de mod_eventwow.conf, cacheados al cargar/recargar la configuracion.
struct EventWowConfig
{
    bool Enabled = true;
    uint8 CharacterRace = 1;  // RACE_HUMAN
    uint8 CharacterClass = 1; // CLASS_WARRIOR

    // Punto ancla del lobby: entrada en cada login y retorno al salir de un minijuego
    WorldLocation Lobby;

    void Load();

    static EventWowConfig& Instance();
};

#define sEventWowConfig EventWowConfig::Instance()

#endif
