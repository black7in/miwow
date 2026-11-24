# Modulo del servidor (`mod-miwow`)

`azerothcore-wotlk/modules/mod-miwow` es un JUNCTION a esta carpeta (no una copia): editar solo aqui. Recrear si falta:
`New-Item -ItemType Junction -Path azerothcore-wotlk\modules\mod-miwow -Target modules\mod-miwow`.
Loader `Addmod_miwowScripts` (`src/mod_miwow_loader.cpp`). Log `module.miwow`. Comandos GM `.miwow ...`.

## Reglas
- No modificar el core si se puede evitar: hooks de ScriptMgr. Tocar el core: hook existente > hook nuevo (generico,
  patron de AC) > edicion directa marcada `// MiWow:`. Un commit por cambio, prefijo `[EventWow]`, registrado en
  `docs/core-changes.md`.
- Seguir `azerothcore-wotlk/AGENTS.md` y `.agents/docs/cpp-guidelines.md` / `sql-guidelines.md` (Allman, 4 espacios, LF,
  `LOG_*` con `{}`, `sConfigMgr->GetOption` solo al cargar config, guardar `ObjectGuid` no punteros).
- **No compilar ni correr CMake**: lo hace el usuario.
- El servidor es la fuente de verdad: validar todo lo que el cliente pueda falsear.
- **Regla de oro de `tradicional`**: nunca tocar de forma destructiva el personaje real (objetos, oro, nivel,
  talentos, auras pasivas); lo que se cambie y se guarde en BD necesita foto + restauracion en el login.
- Reglas de MiWow solo para jugadores; en modo dev (`.gm on` o `.dev on`) = AzerothCore normal. Comprobar con
  `MiWowDevMode::IsActive(player)` en toda regla nueva. Se decide por MODO, no por cuenta.
- SQL en `data/sql/db-{world,characters,auth}/` (nunca en `azerothcore-wotlk/data/sql/`), idempotente (DELETE antes de
  INSERT; ALTER con guarda). Si un SQL borrado ya estaba aplicado, quitar su registro de `updates` a mano en la BD de
  desarrollo (si no: "Cleanup is disabled!" al arrancar).
- Config de juego en `conf/mod_miwow.conf.dist` (claves del core en "OVERRIDES DEL CORE", cada una con su motivo).
- Rangos propios: entradas/objetos/hechizos >= 9500000 (vehiculos 9500000-9599999), mapas 750-799.

## Sistemas (rama `tradicional`)
- **Entrada/salida de eventos** (`MiWowLobby`): `CanJoinFrom` (vivo, sin combate, sin vuelo, fuera de instancias, sin
  cola de BG; errores `QUEUE_DEAD/IN_COMBAT/IN_FLIGHT/IN_INSTANCE/IN_BG_QUEUE`), `SaveReturnPoint` =
  `Player::SetEntryPoint`, `ReturnFromMatch` = estado base + `TeleportToEntryPoint`. Login dentro de un mapa de evento ->
  punto de vuelta (u hogar). Estado base: `RemoveArenaAuras` + montura + forma. Durabilidad: foto al llegar y se
  devuelve al reaparecer, al salir y antes del logout.
- **Cola y partidas** (`MiWowMatchMgr`, `MiWowMatch`): cola por juego (jugador o grupo entero, lo apunta el lider;
  limitada por `MaxPartySize`), propuesta con Aceptar/Rechazar (`MiWow.Queue.AcceptTimeout`), una instancia por
  partida en mapas propios 750-799 (`IsEventMap` = ese rango), estados Loading -> Countdown -> Running -> Ended,
  virtuales `OnStart/OnUpdate/OnTick/OnTimerExpired/OnPlayerArrived/OnPlayerLeft/OnPlayerDied/GetArrivalPosition/
  GetEndDelay/GetVehicleEntry/BlocksPlayerSpells`. Instancias cerradas se descargan solas (`UpdateClosedInstances`).
- Muerte: mecanismo en el framework, regla en cada juego (por defecto reaparecer en el inicio a los 5 s; nunca al
  cementerio).
- `MiWowVehicle` (invocar, montar, mantener montado, `Hold/Mount/DismissVehicle`), `MiWowSpellLock`
  (`OnSpellCheckCast`: sin hechizos propios ni monturas; objetos y desencadenados si), `MiWowStats` (stats temporales,
  `.miwow stat`; se quitan en `RemovePlayer` y `RestoreBaseState`), `MiWowRewards` (en mapas de evento: sin logros,
  XP ni reputacion), `MiWowGroups` (grupos nativos, bandas permitidas), `MiWowDevMode` (avisa `DEV_MODE`).
- Protocolo cliente<->servidor por addon messages (prefijo `MIWOW`): `docs/protocolo.md`.
- Juegos: `test`, `test_group`, `test_vehicle`, `test_map` (750), `carrera` (752), `carrera_estelar` (753), `parkour`
  (754, PAUSADO), `castillo` (755, defensa por oleadas, nivel 80). Mapa 751 (asedio) se queda sin juego (decision del
  usuario: para el futuro). `MiWowGameInfo::MinLevel` = nivel minimo (cola: `QUEUE_LEVEL` / `QUEUE_GROUP_LEVEL`).
  - Carrera: `docs/carrera-estado.md`. Parkour: `docs/parkour-estado.md`. Castillo: `docs/castillo-estado.md`.
- **Temporadas de hermandad** (`src/guild/`): `docs/hermandad.md`.
- Hechizos propios: `tools/spellgen` (`data/spells/*.toml` -> SQL), ver `docs/hechizos.md`.
- Mapas propios: `docs/mapas.md`. mmaps: desde `data\`, `..\mmaps_generator.exe --config ..\mmaps-config.yaml <id> < nul`.

## Pendiente
- Cola de evento + invitacion de BG/LFG (bloquear unas con otras), mascotas al entrar.
- Reinicios de instancia del core: bandas/heroicos se reinician a hora fija; propuesta sin decidir: que `Validate()`
  rechace mapas con `MapDifficulty.resetTime` != 0.
