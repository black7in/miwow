#ifndef MOD_MIWOW_MATCH_H
#define MOD_MIWOW_MATCH_H

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
struct MiWowGameInfo;

enum class MiWowMatchState : uint8
{
    Loading,    // jugadores en camino a la instancia
    Countdown,  // todos dentro: cuenta atras
    Running,
    Ended       // resultado en pantalla; al terminar, vuelta a donde estaba
};

enum class MiWowMatchResult : uint8
{
    None,
    Win,
    Lose
};

// Clase base de un minijuego (framework). Un objeto por partida, creado por la factoria del juego
// (MiWowGameInfo::Factory) y gestionado por MiWowMatchMgr, que se encarga de la cola, la instancia,
// los teleports y la vuelta a donde estaba. El minijuego solo implementa los On*() y usa los helpers protegidos.
//
// Ciclo: Loading -> (todos dentro o MiWow.Match.LoadTimeout) -> Countdown -> OnStart() -> Running
//        -> End() -> Ended -> (MiWow.Match.ReturnDelay) -> todos a donde estaban y se destruye.
// Si no queda nadie, la partida se cierra sola. Todo corre en el hilo del mundo (WorldScript::OnUpdate
// y manejadores del protocolo): guardar ObjectGuid, no punteros a Player.
class MiWowMatch
{
public:
    virtual ~MiWowMatch() = default;

    uint32 GetId() const { return _id; }
    MiWowGameInfo const& GetGame() const { return *_game; }
    uint32 GetMapId() const;
    uint32 GetInstanceId() const { return _instanceId; }
    MiWowMatchState GetState() const { return _state; }
    // Jugadores que siguen en la partida
    GuidVector const& GetPlayers() const { return _players; }
    bool HasPlayer(ObjectGuid guid) const;

    // --- Usado por MiWowMatchMgr ---
    void Init(uint32 id, MiWowGameInfo const* game, uint32 instanceId, GuidVector players);
    // Sesion abierta (MiWowGameInfo::OpenSession): un jugador mas en camino a la partida ya en marcha. Si no llega
    // en MiWow.Match.LoadTimeout, queda fuera.
    void AddPlayer(ObjectGuid guid);
    // Plazas libres (sesion abierta)
    std::size_t GetFreeSlots() const;
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

protected:
    // --- Para los minijuegos ---
    virtual void OnPlayerArrived(Player* /*player*/) { }
    virtual void OnStart() { }
    virtual void OnUpdate(Milliseconds /*diff*/) { }
    // Cada tick en CUALQUIER estado (carga, cuenta atras, en juego, resultado), despues de OnUpdate.
    // Para lo que el juego mantiene fuera de Running (p. ej. las motos quietas en la parrilla).
    virtual void OnTick(Milliseconds /*diff*/) { }
    // Tiempo de la pantalla de resultado (Ended) antes de volver todos al lobby. Por defecto
    // MiWow.Match.ReturnDelay; el boton "Volver al lobby" (ABANDON) sale antes.
    virtual Seconds GetEndDelay() const;
    // Por defecto, fin de la partida con los resultados que haya
    virtual void OnTimerExpired() { End(); }
    virtual void OnPlayerLeft(ObjectGuid /*guid*/) { }
    virtual Seconds GetCountdown() const { return 3s; }
    // Muerte: morir nunca saca de la partida (no hay cementerio exterior). Por defecto reaparece en
    // GetRespawnPosition() a los 5 s; cada juego decide su regla (checkpoint, eliminado, esperar...).
    virtual void OnPlayerDied(Player* player) { RespawnPlayer(player, 5s); }
    virtual Position const& GetRespawnPosition(Player* player) const;
    // Donde aparece cada jugador al entrar en la instancia (su vehiculo, si lo hay, se invoca ahi).
    // Se llama una vez por jugador al crear la partida, en el orden de la cola. Por defecto el Start del juego.
    virtual Position GetArrivalPosition(Player* player);
    // Vehiculo (creature_template con VehicleId) en el que va cada jugador mientras esta en la partida
    // (MiWowVehicle.h). 0 = a pie (por defecto). Se asigna al llegar; el juego puede retrasar el montaje.
    virtual uint32 GetVehicleEntry() const { return 0; }
    // true: en la partida no se pueden lanzar hechizos propios (clase, monturas...), solo objetos (MiWowSpellLock.h)
    virtual bool BlocksPlayerSpells() const { return false; }

    // Resucita (vida completa) y lleva a GetRespawnPosition() tras delay (0s = ya). El HUD muestra la cuenta atras.
    void RespawnPlayer(Player* player, Seconds delay);

    // Termina la partida (solo en Running). summary: texto para todos (opcional)
    void End(std::string_view summary = {});
    void SetResult(ObjectGuid guid, MiWowMatchResult result);
    void SetResultForAll(MiWowMatchResult result);
    // Temporizador de Running visible en el HUD; al llegar a 0 llama a OnTimerExpired(). 0s = sin tiempo
    void SetTimer(Seconds duration);
    // Texto del objetivo en el HUD de todos
    void SetHud(std::string_view text);

    InstanceMap* GetMap() const;
    void ForEachPlayer(std::function<void(Player* player)> const& func) const;

private:
    void SetState(MiWowMatchState state, Milliseconds duration);
    // true si el temporizador del estado acaba de llegar a 0
    bool TickTimer(Milliseconds diff);
    void UpdateRespawns(Milliseconds diff);
    void DoRespawn(Player* player);
    void BroadcastState() const;

    uint32 _id = 0;
    MiWowGameInfo const* _game = nullptr;
    uint32 _instanceId = 0;
    GuidVector _players;
    GuidSet _arrived;
    std::unordered_map<ObjectGuid, MiWowMatchResult> _results;

    MiWowMatchState _state = MiWowMatchState::Loading;
    // Tiempo restante del estado actual (carga, cuenta atras, temporizador de juego, resultado)
    Milliseconds _stateTimer = 0ms;
    bool _timerActive = false;
    std::string _hud;
    // Reapariciones pendientes: jugador -> tiempo restante
    std::unordered_map<ObjectGuid, Milliseconds> _respawns;
    // Mantenimiento de los vehiculos (volver a subir), cada segundo
    Milliseconds _vehicleTimer = 0ms;
    // Sesion abierta: jugadores en camino -> tiempo que les queda para llegar
    std::unordered_map<ObjectGuid, Milliseconds> _joining;
};

#endif
