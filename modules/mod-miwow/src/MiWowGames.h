#ifndef MOD_MIWOW_GAMES_H
#define MOD_MIWOW_GAMES_H

#include "Define.h"
#include "Position.h"
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

class MiWowMatch;

using MiWowMatchFactory = std::function<std::unique_ptr<MiWowMatch>()>;

// Catalogo de minijuegos que el panel del cliente muestra (el cliente no conoce ninguno de antemano).
struct MiWowGameInfo
{
    std::string Id;          // clave estable (protocolo, colas)
    std::string Name;
    std::string Description;
    std::string Icon;        // ruta de textura del cliente
    uint8 MinPlayers = 1;
    uint8 MaxPlayers = 1;
    // Tamano maximo de un grupo (nativo) que puede buscar partida junto. 1 = solo individual.
    // Validate() lo limita a MaxPlayers y al tamano de grupo (MAXGROUPSIZE = 5).
    uint8 MaxPartySize = 1;
    // Sesion siempre abierta (p. ej. el parkour): sin cola ni confirmacion; al buscar partida se entra directamente
    // en una partida del juego que ya este en marcha con hueco (MaxPlayers = maximo por instancia) o se crea una.
    // La partida empieza ya en Running (sin carga comun, eleccion ni cuenta atras: no hay OnStart), cada jugador
    // entra y sale cuando quiere (OnPlayerArrived / OnPlayerLeft) y se cierra cuando no queda nadie.
    bool OpenSession = false;
    // Nivel minimo para buscar partida (0 = cualquiera). Lo comprueba la cola para cada miembro (no en modo dev).
    uint8 MinLevel = 0;

    // Partida: mapa PROPIO de MiWow (MiWowFirstMapId-MiWowLastMapId, de mazmorra/banda con instance_template)
    // donde se crea una instancia por partida, punto de aparicion y factoria de la clase del minijuego (MiWowMatch.h).
    // Sin factoria el juego aparece en el panel pero no se puede buscar partida (maqueta).
    uint32 MapId = 0;
    Position Start;
    MiWowMatchFactory Factory;

    bool IsPlayable() const { return Factory != nullptr; }
};

// Mapas propios de MiWow (docs/mapas.md). Solo en ellos hay partidas: todo lo que el modulo hace por "estar en
// el mapa de un evento" (p. ej. el punto de vuelta al hacer login) no puede alcanzar a una mazmorra real.
constexpr uint32 MiWowFirstMapId = 750;
constexpr uint32 MiWowLastMapId = 799;

class MiWowGames
{
public:
    static MiWowGames& Instance();

    void Register(MiWowGameInfo info);
    MiWowGameInfo const* GetGame(std::string_view id) const;
    std::vector<MiWowGameInfo> const& GetAll() const { return _games; }

    // Al arrancar: desactiva (quita la factoria) los juegos cuyo mapa no sirve para partidas o no es propio
    void Validate();

private:
    std::vector<MiWowGameInfo> _games;
};

#define sMiWowGames MiWowGames::Instance()

#endif
