#include "EventWowGames.h"
#include "EventWowMatch.h"

// Asedio (mapa 751, Maps/Warcraft/Mi_Mapa_XHero.w3x): defensa del castillo estilo hero siege. Plan y funcion
// de cada region en docs/asedio.md. Paso actual: eleccion de personaje (fase Picking del framework) y
// recorrer el mapa; las oleadas, el castillo y las fases llegan en los pasos siguientes.
// Personajes: eventwow_game_character del juego 'asedio' (SQL del modulo), ajustables sin compilar.
class EventWowGameSiege : public EventWowMatch
{
protected:
    Seconds GetPickTime() const override { return 30s; }
    bool IsPickUnique() const override { return true; }

    void OnStart() override
    {
        SetHud("Explora el mapa del asedio. (Las oleadas llegarán en el siguiente paso.)");
        SetTimer(10min);
    }

    void OnTimerExpired() override
    {
        SetResultForAll(EventWowMatchResult::Win);
        End("Fin de la exploración.");
    }
};

void AddSC_eventwow_game_siege()
{
    EventWowGameInfo game;
    game.Id = "asedio";
    game.Name = "Asedio";
    game.Description = "Defended el castillo de las oleadas de la Plaga junto a tu grupo (1-5 jugadores). "
        "Elige tu héroe al empezar. (En construcción: de momento solo la elección y el mapa.)";
    game.Icon = "Interface\\Icons\\Spell_Frost_FrostShock";
    game.MinPlayers = 1;
    game.MaxPlayers = 5;
    game.MaxPartySize = 5;
    game.InventorySlots = 6;
    game.MapId = 751;
    // Punto de inicio del jugador 1 del mapa de WC3 (lo imprime mapgen)
    game.Start.Relocate(-731.33f, -403.33f, 1.0f, 3.14f);
    game.Factory = []() { return std::make_unique<EventWowGameSiege>(); };

    sEventWowGames.Register(std::move(game));
}
