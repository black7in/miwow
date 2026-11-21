#include "EventWowGames.h"
#include "EventWowMatch.h"
#include "Map.h"
#include "Player.h"
#include "SharedDefines.h"

// Minijuego de prueba: valida cola -> instancia -> partida -> fin -> vuelta a donde estaba.
// Entra, cuenta atras, aguanta el temporizador y gana. Se puede abandonar en cualquier momento.
// Mapa: 750 EventWowTest (propio; antes Sima Ignea 389, pero las partidas solo van en mapas propios).
class EventWowGameTest : public EventWowMatch
{
public:
    explicit EventWowGameTest(Seconds duration = 30s, uint32 vehicleEntry = 0) : _duration(duration), _vehicleEntry(vehicleEntry) { }

protected:
    uint32 GetVehicleEntry() const override { return _vehicleEntry; }

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
    uint32 _vehicleEntry;
};

void AddSC_eventwow_game_test()
{
    EventWowGameInfo game;
    game.Id = "test";
    game.Name = "Prueba";
    game.Description = "Minijuego de prueba en solitario: aguanta 30 segundos en la instancia y vuelve a donde estabas.";
    game.Icon = "Interface\\Icons\\INV_Misc_QuestionMark";
    game.MinPlayers = 1;
    game.MaxPlayers = 1;
    game.MapId = 750;
    game.Start.Relocate(-208.67f, -286.67f, 1.0f, 3.14f);
    game.Factory = []() { return std::make_unique<EventWowGameTest>(); };

    // Misma prueba para varios jugadores: valida la cola en grupo y el emparejamiento de grupos/individuales
    EventWowGameInfo group = game;
    group.Id = "test_group";
    group.Name = "Prueba en grupo";
    group.Description = "Minijuego de prueba para 1-5 jugadores: busca partida solo o con tu grupo, aguantad 30 segundos "
        "en la instancia y volved a donde estabais.";
    group.Icon = "Interface\\Icons\\Spell_Holy_PrayerOfFortitude";
    group.MaxPlayers = 5;
    group.MaxPartySize = 5;

    // Prototipo de vehiculo: va montado en una moto (9500000, copia sin nombre de la Salvaged Chopper, SQL _13_05)
    EventWowGameInfo vehicle = game;
    vehicle.Id = "test_vehicle";
    vehicle.Name = "Prueba en moto";
    vehicle.Description = "Prototipo de vehiculo en solitario: conduce la moto durante 60 segundos y vuelve a donde estabas.";
    vehicle.Icon = "Interface\\Icons\\Spell_Nature_Swiftness";
    vehicle.Factory = []() { return std::make_unique<EventWowGameTest>(60s, 9500000); };

    // Primer mapa propio (750, convertido de Maps/Warcraft/test.w3m con tools/mapgen): inicio = punto de inicio del
    // jugador 1 del mapa de WC3 (lo imprime mapgen). 5 minutos para recorrerlo.
    EventWowGameInfo map = game;
    map.Id = "test_map";
    map.Name = "Prueba de mapa";
    map.Description = "Primer mapa propio convertido desde Warcraft 3: recorrelo durante 5 minutos.";
    map.Icon = "Interface\\Icons\\INV_Misc_Map_01";
    map.MaxPlayers = 5;
    map.MaxPartySize = 5;
    map.Factory = []() { return std::make_unique<EventWowGameTest>(300s); };

    sEventWowGames.Register(std::move(game));
    sEventWowGames.Register(std::move(group));
    sEventWowGames.Register(std::move(map));
    sEventWowGames.Register(std::move(vehicle));
}
