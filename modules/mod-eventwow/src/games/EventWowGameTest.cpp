#include "EventWowGames.h"
#include "EventWowMatch.h"

// Minijuego de prueba del corte vertical: valida cola -> instancia -> partida -> fin -> lobby.
// Entra solo, cuenta atras, aguanta el temporizador y gana. Se puede abandonar en cualquier momento.
// Mapa provisional: Sima Ignea (389), entrada (areatrigger_teleport 2230). Hay criaturas mas adentro.
class EventWowGameTest : public EventWowMatch
{
protected:
    void OnStart() override
    {
        SetHud("Aguanta hasta que acabe el tiempo.");
        SetTimer(30s);
    }

    void OnTimerExpired() override
    {
        SetResultForAll(EventWowMatchResult::Win);
        End("¡Prueba superada!");
    }
};

void AddSC_eventwow_game_test()
{
    EventWowGameInfo game;
    game.Id = "test";
    game.Name = "Prueba";
    game.Description = "Minijuego de prueba en solitario: aguanta 30 segundos en la instancia y vuelve al lobby.";
    game.Icon = "Interface\\Icons\\INV_Misc_QuestionMark";
    game.MinPlayers = 1;
    game.MaxPlayers = 1;
    game.MapId = 389;
    game.Start.Relocate(3.81f, -14.82f, -17.84f, 4.39f);
    game.Factory = []() { return std::make_unique<EventWowGameTest>(); };

    sEventWowGames.Register(std::move(game));
}
