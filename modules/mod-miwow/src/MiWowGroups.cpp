#include "MiWowConfig.h"
#include "MiWowDevMode.h"
#include "MiWowMatchMgr.h"
#include "MiWowProtocol.h"
#include "Group.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"

// Grupos: los nativos de AzerothCore (invitar, aceptar, lider, expulsar, salir, chat de grupo, marcos de grupo).
// El panel los maneja con la API de grupo del cliente (MiWowGroup.lua); aqui solo las reglas de MiWow:
//  - Bandas normales (servidor tradicional): un grupo o banda solo busca partida si cabe en MaxPartySize del juego
//    (MiWowMatchMgr::Enqueue, QUEUE_GROUP_TOO_BIG).
//  - No se invita ni se acepta estando en una partida (ni a alguien que este en una).
//  - Cualquier cambio en un grupo lo saca de la cola (MiWowMatchMgr::OnGroupChanged).
// En modo dev (.gm / .dev) no hay reglas: AzerothCore normal.
//
//   Servidor -> cliente: ERROR GROUP_IN_MATCH | GROUP_TARGET_IN_MATCH <nombre>
namespace
{
    bool HasRules(Player const* player)
    {
        return sMiWowConfig.Enabled && !MiWowDevMode::IsActive(player);
    }
}

class MiWow_GroupPlayerScript : public PlayerScript
{
public:
    MiWow_GroupPlayerScript() : PlayerScript("MiWow_GroupPlayerScript", {
        PLAYERHOOK_CAN_GROUP_INVITE,
        PLAYERHOOK_CAN_GROUP_ACCEPT
    }) { }

    bool OnPlayerCanGroupInvite(Player* player, std::string& memberName) override
    {
        if (!HasRules(player))
            return true;

        if (sMiWowMatchMgr.IsInMatch(player))
        {
            MiWowMessage("ERROR").Add("GROUP_IN_MATCH").Send(player);
            return false;
        }

        Player* invited = ObjectAccessor::FindPlayerByName(memberName, false);
        if (invited && sMiWowMatchMgr.IsInMatch(invited))
        {
            MiWowMessage("ERROR").Add("GROUP_TARGET_IN_MATCH").Add(invited->GetName()).Send(player);
            return false;
        }

        return true;
    }

    bool OnPlayerCanGroupAccept(Player* player, Group* /*group*/) override
    {
        if (!HasRules(player) || !sMiWowMatchMgr.IsInMatch(player))
            return true;

        MiWowMessage("ERROR").Add("GROUP_IN_MATCH").Send(player);
        return false;
    }
};

class MiWow_GroupScript : public GroupScript
{
public:
    MiWow_GroupScript() : GroupScript("MiWow_GroupScript", {
        GROUPHOOK_ON_ADD_MEMBER,
        GROUPHOOK_ON_REMOVE_MEMBER,
        GROUPHOOK_ON_DISBAND
    }) { }

    void OnAddMember(Group* group, ObjectGuid guid) override
    {
        if (sMiWowConfig.Enabled)
            sMiWowMatchMgr.OnGroupChanged(group, guid);
    }

    void OnRemoveMember(Group* group, ObjectGuid guid, RemoveMethod /*method*/, ObjectGuid /*kicker*/,
        char const* /*reason*/) override
    {
        if (sMiWowConfig.Enabled)
            sMiWowMatchMgr.OnGroupChanged(group, guid);
    }

    void OnDisband(Group* group) override
    {
        if (sMiWowConfig.Enabled)
            sMiWowMatchMgr.OnGroupChanged(group, ObjectGuid::Empty);
    }
};

void AddSC_miwow_groups()
{
    new MiWow_GroupPlayerScript();
    new MiWow_GroupScript();
}
