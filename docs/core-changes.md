# Cambios al core (AzerothCore)

Repositorio del core: `azerothcore-wotlk/` (fork local, luego remoto privado).

- `upstream` -> https://github.com/azerothcore/azerothcore-wotlk.git (solo fetch; push deshabilitado)
- `master`   -> espejo exacto de `upstream/master`, nunca se commitea en ella
- `eventwow` -> `master` + nuestros commits `[EventWow]`

`git log --oneline master..eventwow` es en todo momento la lista real de cambios; este archivo explica el porque.

## Version base probada

| Fecha | upstream/master | eventwow | Notas |
|---|---|---|---|
| 2026-11-12 | `2948c203f` (chore(DB): import pending files) | `2948c203f` | Inicio: sin cambios al core |

> Actualizar esta tabla cada vez que se haga rebase sobre un upstream nuevo.

## Reglas

1. Prioridad: hook existente > hook nuevo > edicion directa del core (ultimo recurso).
2. Un commit por cambio logico, mensaje `[EventWow] <que>` + cuerpo con el motivo.
3. Hooks nuevos genericos (sin logica de EventWow), siguiendo el patron de AC:
   enum `XXXHOOK_*` en `ScriptDefines/XxxScript.h` -> metodo virtual con default -> declaracion en `ScriptMgr.h`
   -> implementacion con `CALL_ENABLED_HOOKS` / `CALL_ENABLED_BOOLEAN_HOOKS` en `ScriptDefines/XxxScript.cpp`
   -> llamada en el punto del core. La logica va en `mod-eventwow`.
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
| - | - | - | (sin cambios todavia) | - | - |
