#include "EventWowConfig.h"
#include "Log.h"
#include "ScriptMgr.h"

// Creacion de personaje: solo se permite la raza/clase configurada.
// Complementa CharacterCreating.Disabled.RaceMask/ClassMask, que los GMs pueden saltarse por RBAC.
class EventWow_AccountScript : public AccountScript
{
public:
    EventWow_AccountScript() : AccountScript("EventWow_AccountScript", {
        ACCOUNTHOOK_CAN_ACCOUNT_CREATE_CHARACTER
    }) { }

    bool CanAccountCreateCharacter(uint32 accountId, uint8 charRace, uint8 charClass) override
    {
        if (!sEventWowConfig.Enabled)
            return true;

        if (charRace == sEventWowConfig.CharacterRace && charClass == sEventWowConfig.CharacterClass)
            return true;

        LOG_WARN("module.eventwow", "Cuenta {} intento crear personaje con raza {} / clase {} (permitido: {} / {})",
            accountId, charRace, charClass, sEventWowConfig.CharacterRace, sEventWowConfig.CharacterClass);
        return false;
    }
};

void AddSC_eventwow_character()
{
    new EventWow_AccountScript();
}
