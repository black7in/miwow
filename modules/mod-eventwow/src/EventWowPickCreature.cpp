// PNJ de eleccion en el mundo (estilo Warcraft 3, EventWowMatch::GetPickPositions): el jugador habla con el
// heroe y lo elige desde el dialogo, con confirmacion (la eleccion es definitiva).
// Las criaturas (EventWowCharacterInfo::PickCreature) llevan ScriptName = 'npc_eventwow_pick'; el texto del dialogo
// es el npc_text con el mismo ID que la criatura (descripcion del personaje, SQL del modulo).
#include "Creature.h"
#include "CreatureScript.h"
#include "EventWowCharacters.h"
#include "EventWowMatch.h"
#include "EventWowMatchMgr.h"
#include "Player.h"
#include "ScriptedGossip.h"
#include "StringFormat.h"

namespace
{
    // Partida del jugador si este PNJ es de un personaje que puede elegir ahora
    EventWowMatch* GetPickMatch(Player* player, Creature* creature, EventWowCharacterInfo const*& character)
    {
        character = sEventWowCharacters.GetByPickCreature(creature->GetEntry());
        EventWowMatch* match = sEventWowMatchMgr.GetMatch(player);
        if (!character || !match || match->GetInstanceId() != creature->GetInstanceId() || !match->CanPick(player, character->Id))
            return nullptr;

        return match;
    }
}

class npc_eventwow_pick : public CreatureScript
{
public:
    npc_eventwow_pick() : CreatureScript("npc_eventwow_pick") { }

    bool OnGossipHello(Player* player, Creature* creature) override
    {
        ClearGossipMenuFor(player);

        EventWowCharacterInfo const* character = nullptr;
        if (GetPickMatch(player, creature, character))
            AddGossipItemFor(player, GOSSIP_ICON_BATTLE, Acore::StringFormat("Elegir a {}", character->Name), GOSSIP_SENDER_MAIN,
                character->Id, Acore::StringFormat("¿Elegir a {}? La elección es definitiva.", character->Name), 0, false);

        SendGossipMenuFor(player, creature->GetEntry(), creature->GetGUID());
        return true;
    }

    bool OnGossipSelect(Player* player, Creature* creature, uint32 /*sender*/, uint32 action) override
    {
        CloseGossipMenuFor(player);

        EventWowCharacterInfo const* character = nullptr;
        if (EventWowMatch* match = GetPickMatch(player, creature, character))
            if (action == character->Id)
                match->HandlePick(player, character->Id);

        return true;
    }
};

void AddSC_eventwow_pick_creature()
{
    new npc_eventwow_pick();
}
