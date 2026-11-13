#ifndef MOD_EVENTWOW_MATCH_H
#define MOD_EVENTWOW_MATCH_H

#include "Define.h"
#include "Duration.h"
#include "ObjectGuid.h"
#include <functional>
#include <string>
#include <string_view>
#include <unordered_map>

class InstanceMap;
class Player;
struct EventWowGameInfo;

enum class EventWowMatchState : uint8
{
    Loading,    // jugadores en camino a la instancia
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
// Ciclo: Loading -> (todos dentro o EventWow.Match.LoadTimeout) -> Countdown -> OnStart() -> Running
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
    // Ya no esta en la partida (abandono, logout, teleport fuera); el gestor se encarga de moverlo
    void HandlePlayerLeft(ObjectGuid guid);
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
    // Por defecto, fin de la partida con los resultados que haya
    virtual void OnTimerExpired() { End(); }
    virtual void OnPlayerLeft(ObjectGuid /*guid*/) { }
    virtual Seconds GetCountdown() const { return 3s; }

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
    void BroadcastState() const;

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
};

#endif
