#include "EventWowGames.h"
#include "EventWowMatch.h"

// Minijuego de prueba del corte vertical: valida cola -> instancia -> partida -> fin -> lobby.
// Entra solo, cuenta atras, aguanta el temporizador y gana. Se puede abandonar en cualquier momento.
// Mapa provisional: Sima Ignea (389), entrada (areatrigger_teleport 2230). Hay criaturas mas adentro.
class EventWowGameTest : public EventWowMatch
{
public:
    explicit EventWowGameTest(Seconds duration = 30s) : _duration(duration) { }

protected:
    void OnStart() override
    {
        SetHud("Aguanta hasta que acabe el tiempo.");
        SetTimer(_duration);
    }

    void OnTimerExpired() override
    {
        SetResultForAll(EventWowMatchResult::Win);
        End("¡Prueba superada!");
    }

private:
    Seconds _duration;
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

    // Misma prueba para varios jugadores: valida la cola en grupo y el emparejamiento de grupos/individuales
    EventWowGameInfo group = game;
    group.Id = "test_group";
    group.Name = "Prueba en grupo";
    group.Description = "Minijuego de prueba para 1-5 jugadores: busca partida solo o con tu grupo, aguantad 30 segundos "
        "en la instancia y volved al lobby.";
    group.Icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude";
    group.MaxPlayers = 5;
    group.MaxPartySize = 5;

    // Prototipo de vehiculo: su personaje (eventwow_game_character) va montado en una moto
    EventWowGameInfo vehicle = game;
    vehicle.Id = "test_vehicle";
    vehicle.Name = "Prueba en moto";
    vehicle.Description = "Prototipo de vehiculo en solitario: conduce la moto durante 60 segundos y vuelve al lobby.";
    vehicle.Icon = "Interface\\Icons\\Spell_Nature_Swiftness";
    vehicle.Factory = []() { return std::make_unique<EventWowGameTest>(60s); };

    sEventWowGames.Register(std::move(game));
    sEventWowGames.Register(std::move(group));
    sEventWowGames.Register(std::move(vehicle));
}
