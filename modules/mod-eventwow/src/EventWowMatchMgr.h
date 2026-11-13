#ifndef MOD_EVENTWOW_MATCH_MGR_H
#define MOD_EVENTWOW_MATCH_MGR_H

#include "Define.h"
#include "Duration.h"
#include "ObjectGuid.h"
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

class EventWowMatch;
class Player;
struct EventWowGameInfo;

// Colas de minijuegos, emparejamiento e instancias de partida (EventWowMatchMgr.cpp).
//  - Una cola por juego; un jugador solo puede estar en una cola o en una partida.
//  - Emparejamiento: con MaxPlayers en cola, o con MinPlayers tras EventWow.Queue.FillWait.
//  - Cada partida tiene su propia instancia de un mapa de mazmorra: el modulo crea el InstanceSave y los
//    hooks del core OnPlayerOverrideInstanceDestination / OnPlayerOverrideInstanceEnter mandan ahi a sus
//    jugadores sin grupos ni binds, sin limite de jugadores del mapa, y no dejan entrar a nadie mas (salvo GMs).
// Todo corre en el hilo del mundo, salvo IsMatchInstance (protegido: lo consultan hooks de mapas).
class EventWowMatchMgr
{
public:
    static EventWowMatchMgr& Instance();

    void Update(Milliseconds diff);

    // Cola. Devuelve el codigo de ERROR si no se pudo (nullptr si ok)
    char const* Enqueue(Player* player, EventWowGameInfo const& game);
    void Dequeue(Player* player);
    void SendQueueStatus(Player* player) const;

    EventWowMatch* GetMatch(Player* player) const;
    // Saca al jugador de la partida (y del bind de la instancia). teleport: llevarlo al lobby si esta dentro
    void RemovePlayer(EventWowMatch& match, ObjectGuid guid, bool teleport);

    // Eventos de jugador (EventWow_MatchPlayerScript)
    void OnPlayerMapChanged(Player* player);
    void OnPlayerLogout(Player* player);
    void OnPlayerConnected(Player* player);
    bool GetDestinationInstance(Player* player, uint32 mapId, uint32& instanceId) const;
    bool CanEnterInstance(Player* player, uint32 mapId, uint32 instanceId, bool& allow) const;

private:
    struct QueueEntry
    {
        ObjectGuid Guid;
        Seconds Since;
    };

    void UpdateQueues();
    void CreateMatch(EventWowGameInfo const& game, GuidVector players);
    void CloseMatch(uint32 matchId);
    bool IsMatchInstance(uint32 instanceId) const;

    // id juego -> cola (por orden de llegada)
    std::map<std::string, std::vector<QueueEntry>, std::less<>> _queues;
    std::map<uint32, std::unique_ptr<EventWowMatch>> _matches;
    uint32 _nextMatchId = 1;
    Milliseconds _queueTimer = 0ms;

    mutable std::mutex _instancesLock;
    std::unordered_set<uint32> _instances;
};

#define sEventWowMatchMgr EventWowMatchMgr::Instance()

#endif
