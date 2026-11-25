#ifndef MOD_MIWOW_CONFIG_H
#define MOD_MIWOW_CONFIG_H

#include "Define.h"
#include "Duration.h"
#include "Position.h"
#include <string>

// Valores de mod_miwow.conf, cacheados al cargar/recargar la configuracion.
struct MiWowConfig
{
    bool Enabled = true;

    // Partidas (MiWowMatchMgr)
    Seconds QueueFillWait = 15s;     // espera para llenar hasta MaxPlayers si ya hay MinPlayers
    Seconds QueueAcceptTimeout = 20s; // tiempo para aceptar una partida encontrada
    Seconds MatchLoadTimeout = 30s;  // jugadores que no llegan a la instancia en este tiempo quedan fuera
    Seconds MatchReturnDelay = 8s;   // resultado en pantalla antes de volver a donde estaba

    // Auto-aprendizaje (MiWowAutoLearn)
    struct AutoLearnConfig
    {
        bool Enabled = true;
        bool DevMode = true;          // tambien en modo dev (.gm on / .dev on)
        bool ClassSpells = true;      // lo del entrenador de clase
        bool QuestSpells = true;      // lo de las misiones de clase (y totems del chaman)
        bool TalentRanks = true;      // rangos de entrenador de los talentos que se tienen
        bool Proficiencies = false;   // habilidades de armas
        bool RidingApprentice = false;
        bool RidingJourneyman = false;
        bool RidingExpert = false;
        bool RidingArtisan = false;
        bool ColdWeatherFlying = false;
    } AutoLearn;

    // Voz de grupo (MiWowVoice). El enlace se abre al arrancar: cambiar Host/Port/Secret pide reiniciar.
    struct VoiceConfig
    {
        bool Enabled = false;
        std::string LinkHost = "127.0.0.1";
        uint16 LinkPort = 8091;
        std::string LinkSecret;
    } Voice;

    void Load();

    static MiWowConfig& Instance();
};

#define sMiWowConfig MiWowConfig::Instance()

#endif
