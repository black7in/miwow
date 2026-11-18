#ifndef MOD_EVENTWOW_MATCH_H
#define MOD_EVENTWOW_MATCH_H

#include "Define.h"
#include "Duration.h"
#include "ObjectGuid.h"
#include "Position.h"
#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class InstanceMap;
class Player;
struct EventWowGameInfo;

enum class EventWowMatchState : uint8
{
    Loading,    // jugadores en camino a la instancia
    Picking,    // todos dentro: eleccion de personaje (solo si el juego la usa, GetPickTime())
    Countdown,  // todos dentro: cuenta atras
    Running,
    Ended       // resultado en pantalla; al terminar, vuelta al lobby
};

enum class EventWowMatchResult : uint8
{
    None,
    Win,
    Lose
};

// Clase base de un minijuego (framework). Un objeto por partida, creado por la factoria del juego
// (EventWowGameInfo::Factory) y gestionado por EventWowMatchMgr, que se encarga de la cola, la instancia,
// los teleports y la vuelta al lobby. El minijuego solo implementa los On*() y usa los helpers protegidos.
//
// Ciclo: Loading -> (todos dentro o EventWow.Match.LoadTimeout) -> [Picking] -> Countdown -> OnStart() -> Running
//        -> End() -> Ended -> (EventWow.Match.ReturnDelay) -> todos al lobby y se destruye.
// Si no queda nadie, la partida se cierra sola. Todo corre en el hilo del mundo (WorldScript::OnUpdate
// y manejadores del protocolo): guardar ObjectGuid, no punteros a Player.
class EventWowMatch
{
public:
    virtual ~EventWowMatch() = default;

    uint32 GetId() const { return _id; }
    EventWowGameInfo const& GetGame() const { return *_game; }
    uint32 GetMapId() const;
    uint32 GetInstanceId() const { return _instanceId; }
    EventWowMatchState GetState() const { return _state; }
    // Jugadores que siguen en la partida
    GuidVector const& GetPlayers() const { return _players; }
    bool HasPlayer(ObjectGuid guid) const;

    // --- Usado por EventWowMatchMgr ---
    void Init(uint32 id, EventWowGameInfo const* game, uint32 instanceId, GuidVector players);
    void Update(Milliseconds diff);
    void HandlePlayerArrived(Player* player);
    Position ArrivalPositionFor(Player* player) { return GetArrivalPosition(player); }
    // Ya no esta en la partida (abandono, logout, teleport fuera); el gestor se encarga de moverlo
    void HandlePlayerLeft(ObjectGuid guid);
    // Murio dentro de la instancia (hook OnPlayerJustDied: puede llegar desde el hilo del mapa)
    void HandlePlayerDied(Player* player);
    // Donde reaparece un jugador (tambien si cae fuera del mapa)
    void TeleportToRespawn(Player* player);
    // Ended y cumplido el tiempo de resultado (o sin jugadores): el gestor la cierra
    bool IsReadyToClose() const;
    // MATCH_STATE actual (tambien al reconectar con /reload)
    void SendState(Player* player) const;
    void SendHud(Player* player) const;
    // MATCH_PICK + MATCH_PICKS si esta en la fase de eleccion (al llegar y al reconectar)
    void SendPick(Player* player) const;
    // PICK <id personaje>: eleccion del jugador en la fase Picking (definitiva). Tambien desde el dialogo del
    // PNJ del personaje (eleccion en el mundo)
    void HandlePick(Player* player, uint32 characterId);
    // true si el jugador puede elegir ahora ese personaje (fase Picking, sin elegir aun, personaje libre)
    bool CanPick(Player* player, uint32 characterId) const;

protected:
    // --- Para los minijuegos ---
    virtual void OnPlayerArrived(Player* /*player*/) { }
    virtual void OnStart() { }
    virtual void OnUpdate(Milliseconds /*diff*/) { }
    // Cada tick en CUALQUIER estado (carga, cuenta atras, en juego, resultado), despues de OnUpdate.
    // Para lo que el juego mantiene fuera de Running (p. ej. las motos quietas en la parrilla).
    virtual void OnTick(Milliseconds /*diff*/) { }
    // Tiempo de la pantalla de resultado (Ended) antes de volver todos al lobby. Por defecto
    // EventWow.Match.ReturnDelay; el boton "Volver al lobby" (ABANDON) sale antes.
    virtual Seconds GetEndDelay() const;
    // Por defecto, fin de la partida con los resultados que haya
    virtual void OnTimerExpired() { End(); }
    virtual void OnPlayerLeft(ObjectGuid /*guid*/) { }
    virtual Seconds GetCountdown() const { return 3s; }
    // Muerte: morir nunca saca de la partida (no hay cementerio exterior). Por defecto reaparece en
    // GetRespawnPosition() a los 5 s; cada juego decide su regla (checkpoint, eliminado, esperar...).
    virtual void OnPlayerDied(Player* player) { RespawnPlayer(player, 5s); }
    virtual Position const& GetRespawnPosition(Player* player) const;
    // Donde aparece cada jugador al entrar en la instancia (antes de disfrazarse: su vehiculo se invoca ahi).
    // Se llama una vez por jugador al crear la partida, en el orden de la cola. Por defecto el Start del juego.
    virtual Position GetArrivalPosition(Player* player);
    // Personaje (EventWowCharacters.h) con el que se disfraza al llegar a la instancia. 0 = ninguno (el juego
    // lo elegira despues con SetCharacter, p. ej. tras una fase de seleccion). Por defecto: el primero que
    // ofrece el juego en eventwow_game_character (juegos donde todos son iguales, como una carrera).
    // Con fase de eleccion (GetPickTime() > 0) no se llama: cada uno elige el suyo.
    virtual uint32 GetAssignedCharacter(Player* player) const;
    // Fase de eleccion de personaje entre los del juego (eventwow_game_character), tras la carga.
    // 0s = sin fase (personaje asignado). Con menos de 2 personajes no hay nada que elegir: se asigna.
    // Al acabar el tiempo, los que no han elegido reciben uno al azar.
    virtual Seconds GetPickTime() const { return 0s; }
    // true: cada personaje solo puede elegirlo un jugador (si hay mas jugadores que personajes, se repiten)
    virtual bool IsPickUnique() const { return true; }
    // Eleccion EN EL MUNDO (estilo Warcraft 3): posiciones donde aparecen los PNJ de los personajes
    // (EventWowCharacterInfo::PickCreature), por el orden de eventwow_game_character. El jugador habla con uno
    // para elegirlo y, si la eleccion es unica, el PNJ desaparece. Vacio (por defecto) = ventana de eleccion
    // del cliente (MATCH_PICK). Personajes sin PickCreature o sin posicion no salen (solo al azar).
    virtual std::vector<Position> GetPickPositions() const { return { }; }
    // Ayuda para GetPickPositions: count posiciones en circulo alrededor de center, mirando al centro
    static std::vector<Position> MakePickCircle(Position const& center, float radius, std::size_t count);
    // Personajes del juego con PNJ de eleccion (cuantas posiciones hacen falta)
    std::size_t CountPickCreatures() const;

    // Disfraza al jugador (sustituye el disfraz anterior). Se quita solo al salir de la partida.
    bool SetCharacter(Player* player, uint32 characterId);

    // Resucita (vida completa) y lleva a GetRespawnPosition() tras delay (0s = ya). El HUD muestra la cuenta atras.
    void RespawnPlayer(Player* player, Seconds delay);

    // Termina la partida (solo en Running). summary: texto para todos (opcional)
    void End(std::string_view summary = {});
    void SetResult(ObjectGuid guid, EventWowMatchResult result);
    void SetResultForAll(EventWowMatchResult result);
    // Temporizador de Running visible en el HUD; al llegar a 0 llama a OnTimerExpired(). 0s = sin tiempo
    void SetTimer(Seconds duration);
    // Texto del objetivo en el HUD de todos
    void SetHud(std::string_view text);

    InstanceMap* GetMap() const;
    void ForEachPlayer(std::function<void(Player* player)> const& func) const;

private:
    void SetState(EventWowMatchState state, Milliseconds duration);
    // true si el temporizador del estado acaba de llegar a 0
    bool TickTimer(Milliseconds diff);
    void UpdateRespawns(Milliseconds diff);
    void DoRespawn(Player* player);
    void BroadcastState() const;
    bool UsesPicking() const;
    // true si otro jugador (no except) ya lo ha elegido y la eleccion es unica
    bool IsCharacterTaken(uint32 characterId, ObjectGuid except) const;
    void FinishPicking();
    bool UsesWorldPick() const;
    // Eleccion en el mundo: aparece el PNJ de cada personaje libre y desaparece el de los elegidos
    void UpdatePickCreatures();
    void DespawnPickCreatures();
    void BroadcastPicks() const;
    void SendPicks(Player* player) const;

    uint32 _id = 0;
    EventWowGameInfo const* _game = nullptr;
    uint32 _instanceId = 0;
    GuidVector _players;
    GuidSet _arrived;
    std::unordered_map<ObjectGuid, EventWowMatchResult> _results;

    EventWowMatchState _state = EventWowMatchState::Loading;
    // Tiempo restante del estado actual (carga, cuenta atras, temporizador de juego, resultado)
    Milliseconds _stateTimer = 0ms;
    bool _timerActive = false;
    std::string _hud;
    // Reapariciones pendientes: jugador -> tiempo restante
    std::unordered_map<ObjectGuid, Milliseconds> _respawns;
    // Fase de eleccion: jugador -> personaje elegido
    std::unordered_map<ObjectGuid, uint32> _picks;
    // Eleccion en el mundo: personaje -> su PNJ en la instancia
    std::unordered_map<uint32, ObjectGuid> _pickCreatures;
    // Mantenimiento de los disfraces (volver a subir al vehiculo), cada segundo
    Milliseconds _disguiseTimer = 0ms;
    // Efectos de las casillas de inventario (EventWowInventory), cada 250 ms
    Milliseconds _inventoryTimer = 0ms;
};

#endif
