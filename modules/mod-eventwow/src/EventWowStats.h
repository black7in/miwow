#ifndef MOD_EVENTWOW_STATS_H
#define MOD_EVENTWOW_STATS_H

#include "Define.h"
#include <optional>
#include <string_view>

class Player;

// Bonificaciones de stats de una partida (libros de la tienda, base de un personaje, mejoras...).
// Se aplican EXACTAMENTE como las de un objeto equipado (Player::_ApplyItemBonuses), asi que todo lo derivado
// lo calcula el motor con sus formulas nativas (las del druida contenedor): Fuerza -> poder de ataque,
// Agilidad -> critico/esquiva/armadura, Aguante -> vida, Intelecto -> mana, etc.
// No se guardan en BD (el core no guarda modificadores) y se quitan al salir de la partida
// (EventWowMatchMgr::RemovePlayer, EventWowLobby::RestoreBaseState).
enum class EventWowStat : uint8
{
    Strength,
    Agility,
    Stamina,
    Intellect,
    Spirit,
    Health,           // vida maxima plana
    Mana,             // mana maximo plano
    Armor,
    AttackPower,      // cuerpo a cuerpo y a distancia
    RangedAttackPower,
    SpellPower,
    CritRating,       // indices: cuerpo a cuerpo, distancia y hechizos
    HasteRating,
    HitRating,
    ExpertiseRating,
    DodgeRating,
    ParryRating,
    BlockRating,
    ResilienceRating,
    ArmorPenRating,
    SpellPenetration,
    ManaRegen,        // mana cada 5 s
    HealthRegen,      // vida cada 5 s

    Count
};

namespace EventWowStats
{
    // Clave estable (SQL, comandos, protocolo): "str", "agi", "sp", "crit"...
    std::string_view GetKey(EventWowStat stat);
    std::optional<EventWowStat> FromKey(std::string_view key);

    // Suma (o resta, si es negativo) a la bonificacion acumulada del jugador
    void Add(Player* player, EventWowStat stat, int32 amount);
    int32 Get(Player const* player, EventWowStat stat);
    // Quita todas las bonificaciones
    void Reset(Player* player);
}

#endif
