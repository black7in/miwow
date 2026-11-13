#include "EventWowConfig.h"
#include "EventWowDevMode.h"
#include "EventWowMatchMgr.h"
#include "EventWowProtocol.h"
#include "Group.h"
#include "ObjectAccessor.h"
#include "Opcodes.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldPacket.h"
#include "WorldSession.h"

// Grupos: los nativos de AzerothCore (invitar, aceptar, lider, expulsar, salir, chat de grupo, marcos de grupo).
// El panel los maneja con la API de grupo del cliente (EventWowGroup.lua); aqui solo las reglas de EventWow:
//  - Maximo 5 (grupo, nunca banda): se descarta CMSG_GROUP_RAID_CONVERT.
//  - No se invita ni se acepta estando en una partida (ni a alguien que este en una).
//  - Cualquier cambio en un grupo lo saca de la cola (EventWowMatchMgr::OnGroupChanged).
// En modo dev (.gm / .dev) no hay reglas: AzerothCore normal.
//
//   Servidor -> cliente: ERROR GROUP_IN_MATCH | GROUP_TARGET_IN_MATCH <nombre>
namespace
{
    bool HasRules(Player const* player)
    {
        return sEventWowConfig.Enabled && !EventWowDevMode::IsActive(player);
    }
}

class EventWow_GroupPlayerScript : public PlayerScript
{
public:
    EventWow_GroupPlayerScript() : PlayerScript("EventWow_GroupPlayerScript", {
        PLAYERHOOK_CAN_GROUP_INVITE,
        PLAYERHOOK_CAN_GROUP_ACCEPT
    }) { }

    bool OnPlayerCanGroupInvite(Player* player, std::string& memberName) override
    {
        if (!HasRules(player))
            return true;

        if (sEventWowMatchMgr.IsInMatch(player))
        {
            EventWowMessage("ERROR").Add("GROUP_IN_MATCH").Send(player);
            return false;
        }

        Player* invited = ObjectAccessor::FindPlayerByName(memberName, false);
        if (invited && sEventWowMatchMgr.IsInMatch(invited))
        {
            EventWowMessage("ERROR").Add("GROUP_TARGET_IN_MATCH").Add(invited->GetName()).Send(player);
            return false;
        }

        return true;
    }

    bool OnPlayerCanGroupAccept(Player* player, Group* /*group*/) override
    {
        if (!HasRules(player) || !sEventWowMatchMgr.IsInMatch(player))
            return true;

        EventWowMessage("ERROR").Add("GROUP_IN_MATCH").Send(player);
        return false;
    }
};

class EventWow_GroupScript : public GroupScript
{
public:
    EventWow_GroupScript() : GroupScript("EventWow_GroupScript", {
        GROUPHOOK_ON_ADD_MEMBER,
        GROUPHOOK_ON_REMOVE_MEMBER,
        GROUPHOOK_ON_DISBAND
    }) { }

    void OnAddMember(Group* group, ObjectGuid guid) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnGroupChanged(group, guid);
    }

    void OnRemoveMember(Group* group, ObjectGuid guid, RemoveMethod /*method*/, ObjectGuid /*kicker*/,
        char const* /*reason*/) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnGroupChanged(group, guid);
    }

    void OnDisband(Group* group) override
    {
        if (sEventWowConfig.Enabled)
            sEventWowMatchMgr.OnGroupChanged(group, ObjectGuid::Empty);
    }
};

// Grupo -> banda: no existe (CanPacketReceive llega desde el hilo de red: solo se leen flags del jugador)
class EventWow_GroupServerScript : public ServerScript
{
public:
    EventWow_GroupServerScript() : ServerScript("EventWow_GroupServerScript", {
        SERVERHOOK_CAN_PACKET_RECEIVE
    }) { }

    bool CanPacketReceive(WorldSession* session, WorldPacket const& packet) override
    {
        if (packet.GetOpcode() != CMSG_GROUP_RAID_CONVERT || !sEventWowConfig.Enabled)
            return true;

        Player* player = session->GetPlayer();
        return player && EventWowDevMode::IsActive(player);
    }
};

void AddSC_eventwow_groups()
{
    new EventWow_GroupPlayerScript();
    new EventWow_GroupScript();
    new EventWow_GroupServerScript();
}
