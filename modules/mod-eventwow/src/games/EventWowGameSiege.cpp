#include "EventWowGames.h"
#include "EventWowMatch.h"

// Asedio (mapa 751, Maps/Warcraft/Mi_Mapa_XHero.w3x): defensa del castillo estilo hero siege. Plan y funcion
// de cada region en docs/asedio.md. Paso actual: eleccion de personaje (fase Picking del framework) y
// recorrer el mapa; las oleadas, el castillo y las fases llegan en los pasos siguientes.
// Personajes: eventwow_game_character del juego 'asedio' (SQL del modulo), ajustables sin compilar.
// Eleccion estilo Warcraft 3: los heroes esperan en circulo en la region Inicio; se elige hablando con uno.
class EventWowGameSiege : public EventWowMatch
{
public:
    // Centro de la region Inicio (O43110) del mapa de WC3 (lo imprime mapgen): circulo de heroes y entrada
    static inline Position const PickCenter = { -715.33f, -407.33f, 0.0f, 3.14f };

protected:
    Seconds GetPickTime() const override { return 60s; }
    bool IsPickUnique() const override { return true; }

    std::vector<Position> GetPickPositions() const override
    {
        return MakePickCircle(PickCenter, 16.0f, CountPickCreatures());
    }

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
    game.MaxLevel = 30;
    game.MapId = 751;
    // Entrada (y reaparicion por defecto) = centro del circulo de heroes. Antes: punto del jugador 1 de WC3
    // (-731.33, -403.33), fuera del circulo.
    game.Start.Relocate(EventWowGameSiege::PickCenter.GetPositionX(), EventWowGameSiege::PickCenter.GetPositionY(), 1.0f,
        EventWowGameSiege::PickCenter.GetOrientation());
    game.Factory = []() { return std::make_unique<EventWowGameSiege>(); };

    sEventWowGames.Register(std::move(game));
}
