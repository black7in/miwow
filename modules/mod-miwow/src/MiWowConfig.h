#ifndef MOD_MIWOW_CONFIG_H
#define MOD_MIWOW_CONFIG_H

#include "Define.h"
#include "Duration.h"
#include "Position.h"

// Valores de mod_miwow.conf, cacheados al cargar/recargar la configuracion.
struct MiWowConfig
{
    bool Enabled = true;

    // Partidas (MiWowMatchMgr)
    Seconds QueueFillWait = 15s;     // espera para llenar hasta MaxPlayers si ya hay MinPlayers
    Seconds QueueAcceptTimeout = 20s; // tiempo para aceptar una partida encontrada
    Seconds MatchLoadTimeout = 30s;  // jugadores que no llegan a la instancia en este tiempo quedan fuera
    Seconds MatchReturnDelay = 8s;   // resultado en pantalla antes de volver a donde estaba

    void Load();

    static MiWowConfig& Instance();
};

#define sMiWowConfig MiWowConfig::Instance()

#endif
