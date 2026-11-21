# Cambios al core (AzerothCore)

Repositorio del core: `azerothcore-wotlk/` (fork local, luego remoto privado).

- `upstream` -> https://github.com/azerothcore/azerothcore-wotlk.git (solo fetch; push deshabilitado)
- `master`   -> espejo exacto de `upstream/master`, nunca se commitea en ella
- `eventwow` -> `master` + nuestros commits `[EventWow]`

`git log --oneline master..eventwow` es en todo momento la lista real de cambios; este archivo explica el porque.

- `tradicional` -> `eventwow` sin los cambios que solo usaban los heroes (`ab105ded2`, `04ab628c7`, `b88f7bc5d`,
  revertidos en `cc3c9300d`, 2026-11-21, probado). Es la del servidor tradicional (rama
  `tradicional` del repo EventWow): solo quedan `4fc546e73` (login) y `71970693a` (instancias).

## Version base probada

| Fecha | upstream/master | eventwow | Notas |
|---|---|---|---|
| 2026-11-12 | `2948c203f` (chore(DB): import pending files) | `2948c203f` | Inicio: sin cambios al core |
| 2026-11-13 | `2948c203f` | `4fc546e73` | Hook OnPlayerOverrideLoginLocation compilado y probado (lobby) |
| 2026-11-13 | `2948c203f` | `71970693a` | Hooks de instancia (partidas) compilados y probados |
| 2026-11-16 | `2948c203f` | `ab105ded2` | Hook OnPlayerCanAttackSwing (ataque basico de los heroes) compilado y probado |
| 2026-11-16 | `2948c203f` | `04ab628c7` | SpellInfo::IsAutoShot (disparos propios con las reglas del 75) compilado y probado |

> Actualizar esta tabla cada vez que se haga rebase sobre un upstream nuevo.

## Reglas

1. Prioridad: hook existente > hook nuevo > edicion directa del core (ultimo recurso).
2. Un commit por cambio logico, mensaje `[EventWow] <que>` + cuerpo con el motivo.
3. Hooks nuevos genericos (sin logica de EventWow), siguiendo el patron de AC:
   enum `XXXHOOK_*` en `ScriptDefines/XxxScript.h` -> metodo virtual con default -> declaracion en `ScriptMgr.h`
   -> implementacion con `CALL_ENABLED_HOOKS` / `CALL_ENABLED_BOOLEAN_HOOKS` en `ScriptDefines/XxxScript.cpp`
   -> llamada en el punto del core. La logica va en `mod-miwow`.
4. Ediciones directas: minimas y marcadas con `// EventWow: <motivo>`.
5. Registrar cada commit en la tabla de abajo. Marcar si es candidato a PR upstream (hooks genericos).

## Actualizar a un upstream nuevo

```bash
cd azerothcore-wotlk
git tag eventwow-<fecha>                      # punto de retorno
git fetch upstream
git checkout master && git merge --ff-only upstream/master
git checkout eventwow && git rebase master    # resolver conflictos commit a commit
# compilar + probar; actualizar "Version base probada"
```

## Registro de cambios

| Commit | Tipo | Archivos | Motivo | Usado por (modulo) | Upstreamable |
|---|---|---|---|---|---|
| `4fc546e73` | Hook nuevo `PlayerScript::OnPlayerOverrideLoginLocation(Player*, WorldLocation&) -> bool` | `ScriptDefines/PlayerScript.h/.cpp`, `ScriptMgr.h`, `Entities/Player/PlayerStorage.cpp` (`Player::LoadFromDB`, tras `_LoadEntryPointData`) | Elegir donde aparece el jugador al hacer login ANTES de que el core valide la posicion guardada. Si un script lo sobrescribe, se descartan transporte, ruta de taxi e instance id. Sin el, un jugador desconectado dentro de una instancia reaparece en la entrada de la mazmorra/homebind | `EventWowLobby.cpp` (todo login -> lobby) | Si (generico) |
| `71970693a` | Hooks nuevos `PlayerScript::OnPlayerOverrideInstanceDestination(Player*, uint32 mapId, Difficulty, uint32& instanceId) -> bool` y `PlayerScript::OnPlayerOverrideInstanceEnter(Player*, InstanceMap*, bool loginCheck, bool& allow) -> bool` | `ScriptDefines/PlayerScript.h/.cpp`, `ScriptMgr.h`, `Instances/InstanceSaveMgr.cpp` (`PlayerGetDestinationInstanceId`, al principio), `Maps/Map.cpp` (`InstanceMap::CannotEnter`, tras la comprobacion de "ya en el mapa") | Cada partida es una instancia propia de un mapa de mazmorra elegida por el modulo: el primero manda a los jugadores a esa instancia sin grupos ni binds (el modulo crea antes el `InstanceSave`); el segundo les deja entrar sin limite de jugadores del mapa ni comprobaciones de grupo/bind, y deniega la entrada a otros. Se teleporta con `TELE_TO_GM_MODE` para saltar `MapMgr::PlayerCannotEnter` (banda sin grupo, requisitos, instancias por hora) | `EventWowMatchMgr.cpp` | Si (generico) |
| `ab105ded2` | Hook nuevo `PlayerScript::OnPlayerCanAttackSwing(Player*, Unit* victim) -> bool` | `ScriptDefines/PlayerScript.h/.cpp`, `ScriptMgr.h`, `Handlers/CombatHandler.cpp` (`HandleAttackSwingOpcode`, antes de `Attack`) | Decidir que pasa con el ataque automatico que pide el cliente (clic derecho / "Atacar"). Si un script devuelve false no se ataca cuerpo a cuerpo (se manda `SMSG_ATTACKSTOP`) y el script hace otra cosa | `EventWowDisguise.cpp` (heroes a distancia: el clic derecho lanza su disparo automatico) | Si (generico) |
| `04ab628c7` | API nueva `SpellInfo::IsAutoShot()` (campo `AutoShot`, true para 75) + `SpellMgr::SetSpellAutoShot(uint32) -> bool`; las 10 comprobaciones fijas `Id == 75` / `HUNTER_AUTOSHOOT` pasan a usarla | `Spells/SpellInfo.h/.cpp`, `Spells/SpellMgr.h/.cpp`, `Entities/Unit/Unit.cpp` (`_UpdateAutoRepeatSpell`, `SetCurrentCastedSpell`), `Spells/Spell.cpp` (`prepare`), `Entities/Player/Player.cpp` (cooldown de disparos) | El core solo da al Disparo automatico (75) sus reglas: lanzar/canalizar/moverse lo pausa (a los demas los corta) y empezar no interrumpe otros hechizos (los demas cortan el canalizado). Un disparo automatico propio a alta velocidad cortaba las habilidades (probado: con 75 no pasa). Sin cambio de comportamiento si nadie llama a `SetSpellAutoShot` | `EventWowCharacters.cpp` (ataque basico de las fichas, todos los rangos) | Si (generico) |
| `b88f7bc5d` | Hook nuevo `UnitScript::ModifySpellCastTime(Unit const* caster, SpellInfo const*, int32 baseCastTime, int32& castTime)` | `ScriptDefines/UnitScript.h/.cpp`, `ScriptMgr.h`, `Entities/Object/Object.cpp` (`WorldObject::ModSpellCastTime`, al final; `baseCastTime` = valor de entrada) | Cambiar el tiempo de lanzamiento final (tras modificadores de hechizo y celeridad). No habia ningun hook que lo permitiera | `EventWowDisguise.cpp` (suelo de lanzamiento de los heroes, `EventWow.Hero.SpellCastMinTime`) | Si (generico) |
