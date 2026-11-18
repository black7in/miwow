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

class Group;

// Colas de minijuegos, emparejamiento e instancias de partida (EventWowMatchMgr.cpp).
//  - Una cola por juego; un jugador solo puede estar en una cola o en una partida.
//  - Cada entrada de la cola es un jugador solo o un grupo nativo entero (lo apunta el lider, hasta
//    MaxPartySize del juego). Un grupo nunca se separa; si cambia (entra/sale alguien, se disuelve) o
//    cualquiera de sus miembros cancela o se desconecta, sale de la cola entero.
//  - Emparejamiento: por orden de llegada, metiendo entradas enteras que quepan, con MaxPlayers ya o con
//    MinPlayers tras EventWow.Queue.FillWait.
//  - Confirmacion (tipo Dota 2): lo emparejado es una "propuesta"; todos deben aceptar en
//    EventWow.Queue.AcceptTimeout. Si todos aceptan se crea la partida. Si alguien rechaza (o cancela, se
//    desconecta, cambia su grupo) o no acepta a tiempo, se cancela: su entrada sale de la cola y el resto
//    vuelve a ella automaticamente con su antiguedad.
//  - Juegos de sesion abierta (EventWowGameInfo::OpenSession, p. ej. el parkour): sin cola ni confirmacion, se entra
//    directamente en una partida en marcha con hueco (el grupo entero en la misma) o en una nueva.
//  - Cada partida tiene su propia instancia de un mapa de mazmorra: el modulo crea el InstanceSave y los
//    hooks del core OnPlayerOverrideInstanceDestination / OnPlayerOverrideInstanceEnter mandan ahi a sus
//    jugadores sin grupos ni binds, sin limite de jugadores del mapa, y no dejan entrar a nadie mas (salvo GMs).
// Todo corre en el hilo del mundo, salvo IsMatchInstance (protegido: lo consultan hooks de mapas).
class EventWowMatchMgr
{
public:
    static EventWowMatchMgr& Instance();

    void Update(Milliseconds diff);

    // Cola: el jugador solo, o su grupo entero si esta en uno (debe ser el lider). Si no se puede, manda
    // ERROR al jugador y devuelve false. Manda QUEUE_STATUS a todos los apuntados.
    bool Enqueue(Player* player, EventWowGameInfo const& game);
    // Saca de la cola la entrada del jugador (con todo su grupo) y manda QUEUE_STATUS a todos.
    // reason: ERROR que reciben los demas miembros de la entrada (<reason> <nombre del jugador>), o nullptr
    void Dequeue(Player* player, char const* reason = nullptr);
    void SendQueueStatus(Player* player) const;
    // El grupo ha cambiado (miembro nuevo/fuera, disuelto): fuera de la cola sus miembros y guid
    void OnGroupChanged(Group* group, ObjectGuid guid);
    // Respuesta a una partida encontrada (ACCEPT / DECLINE)
    void AcceptProposal(Player* player, uint32 proposalId);
    void DeclineProposal(Player* player, uint32 proposalId);
    bool IsInMatch(Player const* player) const;

    EventWowMatch* GetMatch(Player* player) const;
    // Saca al jugador de la partida (y del bind de la instancia). teleport: llevarlo al lobby si esta dentro
    void RemovePlayer(EventWowMatch& match, ObjectGuid guid, bool teleport);

    // Eventos de jugador (EventWow_MatchPlayerScript)
    void OnPlayerMapChanged(Player* player);
    void OnPlayerLogout(Player* player);
    // Hooks de muerte (pueden llegar desde el hilo del mapa de la instancia)
    void OnPlayerDied(Player* player);
    bool CanRepopAtGraveyard(Player* player);
    void OnPlayerConnected(Player* player);
    bool GetDestinationInstance(Player* player, uint32 mapId, uint32& instanceId) const;
    bool CanEnterInstance(Player* player, uint32 mapId, uint32 instanceId, bool& allow) const;

private:
    // Un jugador solo o un grupo entero
    struct QueueEntry
    {
        GuidVector Players;
        Seconds Since;
    };

    // Partida encontrada esperando a que todos acepten
    struct Proposal
    {
        uint32 Id = 0;
        std::string GameId;
        std::vector<QueueEntry> Entries;
        GuidSet Accepted;
        Seconds Deadline = 0s;  // GameTime

        std::size_t GetPlayerCount() const;
        bool Contains(ObjectGuid guid) const;
    };

    void UpdateQueues();
    void UpdateProposals();
    void StartProposal(EventWowGameInfo const& game, std::vector<QueueEntry> entries);
    void SendProposal(Player* player, Proposal const& proposal) const;
    // Cancela la propuesta: las entradas con algun jugador de failed salen de la cola (reason a sus demas
    // miembros, con el nombre de culprit); el resto vuelve a la cola
    void FailProposal(uint32 proposalId, GuidSet const& failed, char const* reason, std::string const& culprit);
    Proposal* GetProposal(Player const* player);
    // Crea la partida y manda a sus jugadores. Devuelve la partida (nullptr si no se pudo crear)
    EventWowMatch* CreateMatch(EventWowGameInfo const& game, GuidVector players);
    // Prepara al jugador (sale de la cola, MatchSlot) y lo teleporta a la instancia de la partida
    void SendToMatch(EventWowMatch& match, Player* player);
    // Sesion abierta (EventWowGameInfo::OpenSession): a una partida en marcha con hueco, o a una nueva
    void JoinOpenSession(EventWowGameInfo const& game, std::vector<Player*> const& members);
    void CloseMatch(uint32 matchId);
    bool IsMatchInstance(uint32 instanceId) const;

    // id juego -> cola (por orden de llegada)
    std::map<std::string, std::vector<QueueEntry>, std::less<>> _queues;
    std::map<uint32, Proposal> _proposals;
    uint32 _nextProposalId = 1;
    std::map<uint32, std::unique_ptr<EventWowMatch>> _matches;
    uint32 _nextMatchId = 1;
    Milliseconds _queueTimer = 0ms;

    mutable std::mutex _instancesLock;
    std::unordered_set<uint32> _instances;
};

#define sEventWowMatchMgr EventWowMatchMgr::Instance()

#endif
