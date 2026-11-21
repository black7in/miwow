#include "MiWowSpellLock.h"
#include "DataMap.h"
#include "MiWowDevMode.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Spell.h"

namespace
{
    std::string const SpellLockKey = "MiWowSpellLock";

    struct SpellLockSlot : public DataMap::Base
    {
    };
}

void MiWowSpellLock::Set(Player* player)
{
    player->CustomData.GetDefault<SpellLockSlot>(SpellLockKey);
}

void MiWowSpellLock::Clear(Player* player)
{
    player->CustomData.Erase(SpellLockKey);
}

bool MiWowSpellLock::IsLocked(Player const* player)
{
    return player->CustomData.Get<SpellLockSlot>(SpellLockKey) != nullptr;
}

class MiWow_SpellLockScript : public AllSpellScript
{
public:
    MiWow_SpellLockScript() : AllSpellScript("MiWow_SpellLockScript", {
        ALLSPELLHOOK_ON_SPELL_CHECK_CAST
    }) { }

    void OnSpellCheckCast(Spell* spell, bool /*strict*/, SpellCastResult& res) override
    {
        // Desencadenados y los de objetos (pociones...) siempre se permiten
        if (res != SPELL_CAST_OK || spell->IsTriggered() || spell->m_castItemGUID)
            return;

        Player const* player = spell->GetCaster() ? spell->GetCaster()->ToPlayer() : nullptr;
        if (player && MiWowSpellLock::IsLocked(player) && !MiWowDevMode::IsActive(player))
            res = SPELL_FAILED_SPELL_UNAVAILABLE;
    }
};

void AddSC_miwow_spell_lock()
{
    new MiWow_SpellLockScript();
}
