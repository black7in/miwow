#include "EventWowGames.h"
#include "EventWowMatch.h"
#include "Map.h"
#include "Player.h"
#include "SharedDefines.h"

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

// Prototipo de tienda: cada jugador recibe oro al empezar y hay un mercader junto al inicio (EventWowShop.h).
// Libros = instantaneos (stats al comprarlos); la pocion va a la mochila y se usa (Inventory = true).
class EventWowGameTestShop : public EventWowGameTest
{
public:
    EventWowGameTestShop() : EventWowGameTest(180s) { }

protected:
    static constexpr uint32 VendorEntry = 9500100;
    static constexpr int32 StartMoney = 200 * GOLD;

    void OnStart() override
    {
        EventWowGameTest::OnStart();
        SetHud("Compra libros al mercader y mira como suben tus stats.");

        // Delante del punto de inicio, mirando hacia el
        if (InstanceMap* map = GetMap())
            map->SummonCreature(VendorEntry, Position(2.86f, -17.66f, -17.84f, 1.25f));

        ForEachPlayer([](Player* player)
        {
            player->ModifyMoney(StartMoney);
        });
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

    // Prototipo de tienda (oro de partida, libros de stats instantaneos, pocion en la mochila)
    EventWowGameInfo shop = game;
    shop.Id = "test_shop";
    shop.Name = "Prueba de tienda";
    shop.Description = "Prototipo de tienda en solitario: empiezas con 200 de oro; compra libros de stats y pociones "
        "al mercader durante 3 minutos.";
    shop.Icon = "Interface\\Icons\\INV_Misc_Coin_01";
    shop.Inventory = true;
    shop.Factory = []() { return std::make_unique<EventWowGameTestShop>(); };

    // Primer mapa propio (750, convertido de Maps/Warcraft/test.w3m con tools/mapgen): inicio = punto de inicio del
    // jugador 1 del mapa de WC3 (lo imprime mapgen). 5 minutos para recorrerlo.
    EventWowGameInfo map = game;
    map.Id = "test_map";
    map.Name = "Prueba de mapa";
    map.Description = "Primer mapa propio convertido desde Warcraft 3: recorrelo durante 5 minutos.";
    map.Icon = "Interface\\Icons\\INV_Misc_Map_01";
    map.MaxPlayers = 5;
    map.MaxPartySize = 5;
    map.MapId = 750;
    map.Start.Relocate(-208.67f, -286.67f, 1.0f, 3.14f);
    map.Factory = []() { return std::make_unique<EventWowGameTest>(300s); };

    sEventWowGames.Register(std::move(game));
    sEventWowGames.Register(std::move(group));
    sEventWowGames.Register(std::move(map));
    sEventWowGames.Register(std::move(vehicle));
    sEventWowGames.Register(std::move(shop));
}
