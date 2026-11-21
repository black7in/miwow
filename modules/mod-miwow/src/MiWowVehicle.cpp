#include "MiWowVehicle.h"
#include "DataMap.h"
#include "MiWowDevMode.h"
#include "GameTime.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "TemporarySummon.h"
#include "VehicleDefines.h"

namespace
{
    std::string const VehicleKey = "MiWowVehicle";

    struct VehicleSlot : public DataMap::Base
    {
        uint32 Entry = 0;
        // Vehiculo invocado (en el mapa del jugador)
        ObjectGuid VehicleGuid;
        // No se pudo invocar: no se reintenta (evita repetirlo en cada Update)
        bool Failed = false;
        // No subir al vehiculo antes de esto (GameTime): ver VehicleEnterDelay
        Milliseconds ReadyAt = 0ms;
    };

    // Mas lejos que esto (reaparicion, teleport) se invoca otro vehiculo en vez de subir al antiguo
    constexpr float VehicleMaxDistance = 10.0f;

    // Hasta cuanto por debajo se busca el suelo al invocar el vehiculo (el jugador puede llegar algo por encima)
    constexpr float VehicleGroundSearch = 5.0f;

    // Al asignarse el vehiculo espera (lo invoca Update). Se asigna al llegar a la partida, en Map::AddPlayerToMap,
    // con el cliente aun cargando: al terminar el cliente reclama el control de su personaje (CMSG_SET_ACTIVE_MOVER)
    // y, si ya estaba en la moto, la consola avisa "HandleSetActiveMoverOpcode: incorrect mover guid".
    constexpr Milliseconds VehicleEnterDelay = 1500ms;

    VehicleSlot* GetSlot(Player const* player)
    {
        return player->CustomData.Get<VehicleSlot>(VehicleKey);
    }

    // Unit::EnterVehicle, pero con el resultado del hechizo de montar en el log si no llega a subirle
    void BoardVehicle(Player* player, Unit* vehicle)
    {
        SpellCastResult const result = player->CastCustomSpell(VEHICLE_SPELL_RIDE_HARDCODED, SPELLVALUE_BASE_POINT0, 1,
            vehicle, TRIGGERED_IGNORE_CASTER_MOUNTED_OR_ON_VEHICLE);
        sScriptMgr->AnticheatSetUnderACKmount(player);

        if (player->GetVehicleBase() == vehicle)
            LOG_INFO("module.miwow", "MiWow: {} sube al vehiculo {}", player->GetName(), vehicle->GetEntry());
        else
            LOG_ERROR("module.miwow", "MiWow: {} no ha subido al vehiculo {} (resultado del hechizo {}, distancia "
                "{:.1f}, vivo {}, en vehiculo {})", player->GetName(), vehicle->GetEntry(), uint32(result),
                player->GetExactDist(vehicle), vehicle->IsAlive() ? 1 : 0, player->GetVehicle() ? 1 : 0);
    }

    // Invoca el vehiculo en at (o junto al jugador) y le sube
    void SummonVehicle(Player* player, VehicleSlot* slot, Position const* at = nullptr)
    {
        // A ras de suelo (si lo hay cerca), no a la altura a la que llego el jugador
        Position pos = at ? *at : player->GetPosition();
        float const ground = player->GetMapHeight(pos.GetPositionX(), pos.GetPositionY(), pos.GetPositionZ() + 1.0f,
            true, VehicleGroundSearch + 1.0f);
        if (ground > INVALID_HEIGHT && ground <= pos.GetPositionZ() + 1.0f && pos.GetPositionZ() - ground <= VehicleGroundSearch)
            pos.m_positionZ = ground;

        TempSummon* vehicle = player->SummonCreature(slot->Entry, pos, TEMPSUMMON_MANUAL_DESPAWN);
        if (!vehicle || !vehicle->IsVehicle())
        {
            if (vehicle)
                vehicle->DespawnOrUnsummon();

            LOG_ERROR("module.miwow", "MiWow: no se pudo invocar el vehiculo {} para {}", slot->Entry, player->GetName());
            slot->VehicleGuid.Clear();
            slot->Failed = true;
            return;
        }

        // Amistoso para su conductor (y para su equipo cuando haya equipos)
        vehicle->SetFaction(player->GetFaction());
        slot->VehicleGuid = vehicle->GetGUID();
        BoardVehicle(player, vehicle);
    }

    // Baja al jugador y hace desaparecer el vehiculo (si sigue en su mapa)
    void DismissVehicleOf(Player* player, ObjectGuid vehicleGuid)
    {
        if (player->GetVehicle())
            player->ExitVehicle();

        if (!vehicleGuid)
            return;

        if (Creature* vehicle = ObjectAccessor::GetCreature(*player, vehicleGuid))
            vehicle->DespawnOrUnsummon();
    }
}

void MiWowVehicle::Assign(Player* player, uint32 entry)
{
    Remove(player);
    if (!entry)
        return;

    VehicleSlot* slot = player->CustomData.GetDefault<VehicleSlot>(VehicleKey);
    slot->Entry = entry;
    slot->ReadyAt = GameTime::GetGameTimeMS() + VehicleEnterDelay;
}

void MiWowVehicle::Remove(Player* player)
{
    VehicleSlot const* slot = GetSlot(player);
    if (!slot)
        return;

    ObjectGuid const vehicleGuid = slot->VehicleGuid;
    player->CustomData.Erase(VehicleKey);
    DismissVehicleOf(player, vehicleGuid);
}

bool MiWowVehicle::HasVehicle(Player const* player)
{
    return GetSlot(player) != nullptr;
}

void MiWowVehicle::Update(Player* player)
{
    VehicleSlot* slot = GetSlot(player);
    if (!slot || !player->IsInWorld() || !player->IsAlive() || player->IsBeingTeleported())
        return;

    if (slot->Failed || player->GetVehicle() || MiWowDevMode::IsActive(player)
        || GameTime::GetGameTimeMS() < slot->ReadyAt)
        return;

    Creature* vehicle = slot->VehicleGuid ? ObjectAccessor::GetCreature(*player, slot->VehicleGuid) : nullptr;
    if (vehicle && (!vehicle->IsAlive() || vehicle->GetExactDist(player) > VehicleMaxDistance))
    {
        vehicle->DespawnOrUnsummon();
        vehicle = nullptr;
    }

    if (vehicle)
        BoardVehicle(player, vehicle);
    else
        SummonVehicle(player, slot);
}

void MiWowVehicle::DismissVehicle(Player* player)
{
    VehicleSlot* slot = GetSlot(player);
    if (!slot)
        return;

    DismissVehicleOf(player, slot->VehicleGuid);
    slot->VehicleGuid.Clear();
}

void MiWowVehicle::HoldVehicle(Player* player)
{
    if (VehicleSlot* slot = GetSlot(player))
        slot->ReadyAt = Milliseconds::max();
}

bool MiWowVehicle::MountVehicle(Player* player, Position const* at)
{
    VehicleSlot* slot = GetSlot(player);
    if (!slot)
    {
        LOG_ERROR("module.miwow", "MiWow: no se puede montar a {}: sin vehiculo asignado", player->GetName());
        return false;
    }

    slot->ReadyAt = 0ms;     // desde aqui Update le mantiene montado
    if (player->GetVehicle())
        return true;

    if (!player->IsInWorld() || !player->IsAlive() || player->IsBeingTeleported())
    {
        LOG_ERROR("module.miwow", "MiWow: no se puede montar a {} (en el mundo {}, vivo {}, teletransportandose {})",
            player->GetName(), player->IsInWorld() ? 1 : 0, player->IsAlive() ? 1 : 0, player->IsBeingTeleported() ? 1 : 0);
        return false;
    }

    // El anterior (si lo hay) fuera: el nuevo se invoca donde toca
    DismissVehicleOf(player, slot->VehicleGuid);
    slot->VehicleGuid.Clear();
    slot->Failed = false;
    SummonVehicle(player, slot, at);
    return player->GetVehicle() != nullptr;
}

class MiWow_VehiclePlayerScript : public PlayerScript
{
public:
    MiWow_VehiclePlayerScript() : PlayerScript("MiWow_VehiclePlayerScript", {
        PLAYERHOOK_ON_BEFORE_LOGOUT
    }) { }

    // Antes de guardar el personaje: que no quede montado en una criatura que desaparece
    void OnPlayerBeforeLogout(Player* player) override
    {
        MiWowVehicle::Remove(player);
    }
};

void AddSC_miwow_vehicle()
{
    new MiWow_VehiclePlayerScript();
}
