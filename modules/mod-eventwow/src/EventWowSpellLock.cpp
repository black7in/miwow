#include "EventWowSpellLock.h"
#include "DataMap.h"
#include "EventWowDevMode.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Spell.h"

namespace
{
    std::string const SpellLockKey = "EventWowSpellLock";

    struct SpellLockSlot : public DataMap::Base
    {
    };
}

void EventWowSpellLock::Set(Player* player)
{
    player->CustomData.GetDefault<SpellLockSlot>(SpellLockKey);
}

void EventWowSpellLock::Clear(Player* player)
{
    player->CustomData.Erase(SpellLockKey);
}

bool EventWowSpellLock::IsLocked(Player const* player)
{
    return player->CustomData.Get<SpellLockSlot>(SpellLockKey) != nullptr;
}

class EventWow_SpellLockScript : public AllSpellScript
{
public:
    EventWow_SpellLockScript() : AllSpellScript("EventWow_SpellLockScript", {
        ALLSPELLHOOK_ON_SPELL_CHECK_CAST
    }) { }

    void OnSpellCheckCast(Spell* spell, bool /*strict*/, SpellCastResult& res) override
    {
        // Desencadenados y los de objetos (pociones...) siempre se permiten
        if (res != SPELL_CAST_OK || spell->IsTriggered() || spell->m_castItemGUID)
            return;

        Player const* player = spell->GetCaster() ? spell->GetCaster()->ToPlayer() : nullptr;
        if (player && EventWowSpellLock::IsLocked(player) && !EventWowDevMode::IsActive(player))
            res = SPELL_FAILED_SPELL_UNAVAILABLE;
    }
};

void AddSC_eventwow_spell_lock()
{
    new EventWow_SpellLockScript();
}
