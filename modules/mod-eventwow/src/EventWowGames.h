#ifndef MOD_EVENTWOW_GAMES_H
#define MOD_EVENTWOW_GAMES_H

#include "Define.h"
#include "Position.h"
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

class EventWowMatch;

using EventWowMatchFactory = std::function<std::unique_ptr<EventWowMatch>()>;

// Catalogo de minijuegos que el panel del cliente muestra (el cliente no conoce ninguno de antemano).
struct EventWowGameInfo
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
    // Casillas de inventario de partida (EventWowInventory.h, estilo Dota: 6). 0 = el juego no usa objetos.
    // Los libros instantaneos (EventWowShop.h) no ocupan casilla.
    uint8 InventorySlots = 0;
    // Progresion (EventWowProgress.h): el heroe empieza a nivel 1 y sube con la XP nativa hasta MaxLevel, con
    // puntos para sus habilidades. 0 = sin niveles (el personaje lleva el rango 1 de todo). XpRate multiplica la XP.
    uint8 MaxLevel = 0;
    float XpRate = 1.0f;
    // Sesion siempre abierta (p. ej. el parkour): sin cola ni confirmacion; al buscar partida se entra directamente
    // en una partida del juego que ya este en marcha con hueco (MaxPlayers = maximo por instancia) o se crea una.
    // La partida empieza ya en Running (sin carga comun, eleccion ni cuenta atras: no hay OnStart), cada jugador
    // entra y sale cuando quiere (OnPlayerArrived / OnPlayerLeft) y se cierra cuando no queda nadie.
    bool OpenSession = false;

    // Partida: mapa de mazmorra/banda (con instance_template) donde se crea una instancia por partida,
    // punto de aparicion y factoria de la clase del minijuego (EventWowMatch.h).
    // Sin factoria el juego aparece en el panel pero no se puede buscar partida (maqueta).
    uint32 MapId = 0;
    Position Start;
    EventWowMatchFactory Factory;

    bool IsPlayable() const { return Factory != nullptr; }
};

class EventWowGames
{
public:
    static EventWowGames& Instance();

    void Register(EventWowGameInfo info);
    EventWowGameInfo const* GetGame(std::string_view id) const;
    std::vector<EventWowGameInfo> const& GetAll() const { return _games; }

    // Al arrancar: desactiva (quita la factoria) los juegos cuyo mapa no sirve para partidas
    void Validate();

private:
    std::vector<EventWowGameInfo> _games;
};

#define sEventWowGames EventWowGames::Instance()

#endif
