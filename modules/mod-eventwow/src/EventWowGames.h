#ifndef MOD_EVENTWOW_GAMES_H
#define MOD_EVENTWOW_GAMES_H

#include "Define.h"
#include <string>
#include <vector>

// Catalogo de minijuegos que el panel del cliente muestra (el cliente no conoce ninguno de antemano).
struct EventWowGameInfo
{
    std::string Id;          // clave estable (protocolo, colas)
    std::string Name;
    std::string Description;
    std::string Icon;        // ruta de textura del cliente
    uint8 MinPlayers = 1;
    uint8 MaxPlayers = 1;
};

class EventWowGames
{
public:
    static EventWowGames& Instance();

    void Register(EventWowGameInfo info);
    std::vector<EventWowGameInfo> const& GetAll() const { return _games; }

private:
    std::vector<EventWowGameInfo> _games;
};

#define sEventWowGames EventWowGames::Instance()

#endif
