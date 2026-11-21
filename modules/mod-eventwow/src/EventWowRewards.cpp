#include "EventWowConfig.h"
#include "EventWowLobby.h"
#include "Player.h"
#include "ScriptMgr.h"

// Servidor tradicional: un evento no cuenta para el progreso normal del personaje. Dentro del mapa de un evento
// (solo mapas propios, EventWowLobby::IsEventMap) no se avanza en logros ni en estadisticas (muertes, caidas, dano...),
// no se gana experiencia ni reputacion. Vale para todos (tambien modo dev): un mapa de evento no es contenido normal.
// Fuera de los mapas de evento, AzerothCore sin cambios.
//
// No hay hook para el honor ni para el botin: las criaturas de los eventos son propias (sin botin) y los mapas de
// evento no tienen zonas JcJ. Si un evento las necesita, decidir entonces.
// Logros propios de eventos (si llegan): permitirlos aqui por criterio.
namespace
{
    bool InEvent(Player const* player)
    {
        return sEventWowConfig.Enabled && EventWowLobby::IsEventMap(player->GetMapId());
    }
}

class EventWow_RewardsPlayerScript : public PlayerScript
{
public:
    EventWow_RewardsPlayerScript() : PlayerScript("EventWow_RewardsPlayerScript", {
        PLAYERHOOK_ON_GIVE_EXP,
        PLAYERHOOK_ON_REPUTATION_CHANGE,
        PLAYERHOOK_ON_BEFORE_CRITERIA_PROGRESS,
        PLAYERHOOK_ON_BEFORE_ACHI_COMPLETE
    }) { }

    void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
    {
        if (InEvent(player))
            amount = 0;
    }

    bool OnPlayerReputationChange(Player* player, uint32 /*factionID*/, int32& /*standing*/, bool /*incremental*/) override
    {
        return !InEvent(player);
    }

    bool OnPlayerBeforeCriteriaProgress(Player* player, AchievementCriteriaEntry const* /*criteria*/) override
    {
        return !InEvent(player);
    }

    bool OnPlayerBeforeAchievementComplete(Player* player, AchievementEntry const* /*achievement*/) override
    {
        return !InEvent(player);
    }
};

void AddSC_eventwow_rewards()
{
    new EventWow_RewardsPlayerScript();
}
