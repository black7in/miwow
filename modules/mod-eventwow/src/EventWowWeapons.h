#ifndef MOD_EVENTWOW_WEAPONS_H
#define MOD_EVENTWOW_WEAPONS_H

#include "Define.h"
#include "ObjectGuid.h"
#include <array>
#include <vector>

class Player;
struct ItemTemplate;

// Armas de los heroes.
//
// Equip/Unequip (el disfraz, EventWowDisguise): las armas de la ficha se EQUIPAN de verdad mientras dura el disfraz.
// El cliente decide de forma nativa la animacion segun el arma equipada: el Disparo automatico (SPELL_ATTR0_USES_
// RANGED_SLOT) anima y saca el arco/escopeta de la ranura de distancia, y los golpes salen segun el tipo de arma
// y la mano. Solo con el arma visible (SetVisible) un disparo sin arma de distancia no se animaba.
//  - Las equipa el servidor (Player::EquipNewItem): sin las comprobaciones de equipar (clase, habilidad, nivel).
//  - Combate: el core no mira la habilidad para atacar con lo equipado, pero el valor de la habilidad de arma entra
//    en la tabla de golpe (con 0 falla casi siempre): se da la que le falte al druida, al maximo de su nivel, y
//    la competencia al cliente (SMSG_SET_PROFICIENCY, como un instructor). No hace falta SkillRaceClassInfo: al
//    hacer login el core borra las habilidades que no son de su raza/clase (red de seguridad si no se quitaron).
//  - Mano izquierda con arma: doble empunadura; arco/escopeta/ballesta: aura 46699 "No necesita municion"
//    (proyectil de flecha en el SPELL_GO; nuestros disparos hacen dano de hechizo y no piden municion).
//  - Se quitan (se destruyen) en Unequip. Nunca pisan un arma del jugador: si la ranura esta ocupada no se equipa.
//
// SetVisible: solo el aspecto (PLAYER_VISIBLE_ITEM_<ranura>_ENTRYID, como la transfiguracion), para el comando de
// pruebas .eventwow weapon. Un arma con sheath = 0 (arcos de PNJ) no se ve envainada: copias propias (SQL).
namespace EventWowWeapons
{
    struct EquipState
    {
        // Objetos equipados por Equip en mano derecha, izquierda y distancia (vacio = no se equipo nada)
        std::array<ObjectGuid, 3> Items;
        std::vector<uint32> AddedSkills;
        bool AddedDualWield = false;
        bool AddedNoAmmo = false;
    };

    // true si el objeto se puede equipar en esa ranura (EQUIPMENT_SLOT_MAINHAND / OFFHAND / RANGED)
    bool FitsSlot(ItemTemplate const* proto, uint8 slot);

    // Equipa las que falten (repetible: Update del disfraz la usa para reponer un arma destruida). No toca una
    // ranura ocupada por otro objeto (GM con su equipo en modo dev). true si equipo algo.
    bool Equip(Player* player, uint32 mainHand, uint32 offHand, uint32 ranged, EquipState& state);
    // Destruye lo equipado por Equip y quita habilidades, doble empunadura y aura que anadio
    void Unequip(Player* player, EquipState& state);
    // Habilidades anadidas al maximo del nivel actual (al subir de nivel)
    void UpdateSkills(Player* player, EquipState const& state);
    // true si el objeto de esa ranura es el que equipo Equip
    bool IsEquippedBy(Player const* player, EquipState const& state, uint8 slot);

    // slot = EQUIPMENT_SLOT_MAINHAND / OFFHAND / RANGED; entry 0 = vacia
    void SetVisible(Player* player, uint8 slot, uint32 entry);
    // Vuelve a mostrar lo que lleva equipado de verdad en las ranuras de armas
    void RestoreEquipped(Player* player);
}

#endif
