# MiWow (repo EventWow)

Servidor WoW 3.3.5a (build 12340) + AzerothCore: **servidor normal blizzlike (razas, clases, niveles, mazmorras...) +
sistema de eventos** (minijuegos en instancias propias) + temporadas de hermandad + cliente web/movil.

- **Solo se trabaja en la rama `tradicional`** (decision del usuario 2026-11-21); `main` (plataforma de minijuegos con
  lobby, personaje contenedor, disfraces y heroes) queda parada: su diseno e historial estan en el `CLAUDE.md` de `main`.
- En `tradicional` se entra a los eventos con el personaje y equipo propios. **Regla de oro: nunca tocar de forma
  destructiva el personaje real** (objetos, oro, nivel, talentos, auras pasivas); lo que se cambie y se guarde en BD
  necesita foto + restauracion en el login.
- Nombre: el servidor es **MiWow** (renombrado 2026-11-21): modulo `mod-miwow`, `MiWow*`, `MIWOW_*`, config `MiWow.*`,
  comandos `.miwow` / `/miwow`, prefijo de protocolo `MIWOW`. Conservan el nombre antiguo A PROPOSITO: carpeta/repo
  `EventWow`, rama `eventwow` del core y prefijo `[EventWow]` de sus commits, directorios de mapas `EventWow*`,
  texturas `eventwow_*.blp`, BD `eventwow_*`, IDs.

## Donde esta cada cosa

Cada area tiene su `CLAUDE.md` (se carga al trabajar en esa carpeta) y su estado detallado en `docs/`:

| Area | Guia | Estado / detalle |
|---|---|---|
| Servidor (modulo C++, eventos, SQL) | `modules/mod-miwow/CLAUDE.md` | `docs/protocolo.md`, `docs/core-changes.md` |
| Carrera de motos | | `docs/carrera-estado.md` |
| Parkour (PAUSADO) | | `docs/parkour-estado.md` |
| Defensa del castillo | | `docs/castillo-estado.md` |
| Temporadas de hermandad | | `docs/hermandad.md` |
| Cliente (Lua, parche, DBC) | `client/CLAUDE.md` | |
| Cliente web/movil, VPS, Cloudflare, HUD tactil | `web/CLAUDE.md` | `docs/cliente-web.md`, `docs/despliegue-vps-pruebas.md` |
| Mapas propios (WC3, circuitos) | | `docs/mapas.md` |
| Hechizos propios (`tools/spellgen`) | | `docs/hechizos.md` |
| Voz de grupo/cerca (WebRTC, LiveKit) | | `docs/voz.md` |
| Infraestructura por entorno | | `docs/despliegue.md` |

Al terminar un trabajo, actualizar el `CLAUDE.md` o el doc de SU area (no este) salvo que cambie algo general.

## Estructura

```
EventWow/
  azerothcore-wotlk/     fork de AzerothCore (repo git aparte, rama tradicional) - ver docs/core-changes.md
  server/                build de CMake/Visual Studio (no versionado)
  client/                interface-original (solo lectura), src (lo nuestro), patches (generado)
  modules/mod-miwow/     modulo C++ (azerothcore-wotlk/modules/mod-miwow es un JUNCTION a esta carpeta)
  web/                   cliente web/movil (wasm de Last Havens) + server.js + deploy (Worker, R2, VPS)
  Maps/                  maps.json, Planos/ (circuitos JSON), Warcraft/ (mapas de WC3 del usuario)
  docs/
  tools/                 Build-Patch, Build-Dbc, mpqpack, mpqcompact, Merge-Interface, Diff-Config, mapgen/,
                         spellgen/, touchui/
```

## Reglas generales
- El usuario compila, prueba y decide; Claude prepara. **No compilar ni correr CMake. No lanzar el cliente.**
- Commit solo despues de que el usuario lo pruebe.
- **Versionado**: dos repos. `EventWow` (este; ignorados `azerothcore-wotlk/`, `server/`, `client/interface-original/`,
  `client/patches/`, `*.conf`) y `azerothcore-wotlk/` (core: `upstream` = AzerothCore oficial con push deshabilitado,
  `master` = espejo que nunca se commitea, trabajo en `tradicional` / `eventwow`, actualizar = `rebase` sobre `master`).
  Remotos GitHub: `black7in/miwow` y `black7in/miwow-azerothcore`. Commits con el trailer de atribucion de Claude.
- **Configuracion reproducible**: lo de juego (igual en todos los entornos) en `mod_miwow.conf.dist`; las claves del
  core en su seccion "OVERRIDES DEL CORE" con su motivo (AC carga `configs/modules/*.conf` despues de `worldserver.conf`
  y la ultima clave gana; no afecta a authserver ni a lo leido antes: BD, logs, DataDir). Infraestructura (BD, IPs,
  puertos, rutas, realmlist) nunca en el modulo: `docs/despliegue.md`. Nunca pedir editar `worldserver.conf` para algo
  de juego; auditar con `tools/Diff-Config.ps1`.

## Decisiones vigentes
- Interfaz = nativa en FrameXML (en `patch-4.MPQ`, no addon desactivable) + protocolo propio por addon messages manejado
  en C++. Panel generico guiado por datos del servidor: anadir/cambiar un evento no toca el cliente.
- Eventos en C++; partidas = una instancia por partida en mapas propios 750-799.
- Stats = formulas NATIVAS de AzerothCore (bonificaciones como objetos; el motor deriva el resto).
- Chat, susurros, amigos y grupo = los nativos (el panel es solo de juegos). Grupos nativos de AzerothCore.
- Mapas: los disena el usuario (y un amigo) en el World Editor de WC3 1.26 y se convierten; diseno PROPIO, no se replican
  mapas de terceros. Circuitos de carrera desde planos JSON.
- Descartados (2026-11-21): heroes, disfraz, fase de eleccion, login por launcher/solo nombre (se queda cuenta +
  contrasena), lobby definitivo.

## Siguiente
- **Proxima sesion**: tamano de las interfaces MiWow en movil (se ven mas grandes que la pantalla): panel, HUD de
  partida, ventanas de eleccion y tienda. Ver `web/CLAUDE.md`.
- Defensa del castillo: jugable y probada por el usuario; pendiente el minimapa (no sale) y ajustes de equilibrio.
  Ver `docs/castillo-estado.md`.
- Cliente web: congelones
  por espera de datos (dominio propio en Cloudflare / bundles) y `wowRenderScale` en movil. Ver `web/CLAUDE.md`.
- Hermandad: ventajas NO pasivas (resurreccion en masa, invocar al grupo, calderos/festines, vuelos mas rapidos).
- Carrera: arreglar las caidas (no vuelve a la pista). Ver `docs/carrera-estado.md`.
