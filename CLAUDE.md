# EventWow

Plataforma de minijuegos sobre WoW 3.3.5a (build 12340) + AzerothCore.
No hay flujo clasico (crear personaje, elegir raza/clase, mundo abierto):

```
Login -> "Tu nombre" -> Lobby -> Panel de minijuegos -> Cola (solo/grupo) -> Instancia -> Lobby
```

El personaje es solo un contenedor: nunca se ve en las pantallas previas al mundo;
en cada minijuego se le da modelo, hechizos y stats temporales.

## Estructura

```
EventWow/
  CLAUDE.md
  azerothcore-wotlk/          fork de AzerothCore (repo git aparte, rama eventwow) - ver docs/core-changes.md
  server/                     build de CMake/Visual Studio (no versionado)
  client/
    interface-original/       Interface esES consolidada del cliente. SOLO LECTURA, nunca editar.
      manifest.csv            de que MPQ sale cada archivo
    src/                      archivos de cliente que modificamos/anadimos (misma ruta relativa)
    patches/patch-4.MPQ/      salida generada por Build-Patch (carpeta, no MPQ empaquetado)
  modules/mod-eventwow/       nuestro modulo C++. azerothcore-wotlk/modules/mod-eventwow es un JUNCTION a esta carpeta
                              (no una copia): editar solo aqui. Recrear si falta:
                              New-Item -ItemType Junction -Path azerothcore-wotlk\modules\mod-eventwow -Target modules\mod-eventwow
    conf/mod_eventwow.conf.dist   opciones propias + OVERRIDES DEL CORE (pisan worldserver.conf)
    src/                          scripts (loader: Addmod_eventwowScripts)
    data/sql/db-{world,characters,auth}/   SQL que el updater de AC aplica al arrancar
  docs/
    despliegue.md             checklist de infraestructura por entorno
    core-changes.md           registro de cambios al core + procedimiento de rebase
    protocolo.md              protocolo cliente<->servidor (addon messages): transporte, fragmentacion, mensajes
  tools/
    Merge-Interface.ps1       consolida Interface de los MPQ extraidos respetando el orden de carga
    Build-Patch.ps1           copia client/src -> client/patches/patch-4.MPQ
    Diff-Config.ps1           audita worldserver.conf vs .dist (cambios hechos a mano)
```

## Reglas de trabajo

### Cliente
- Idioma base: **esES**. Cliente de pruebas: `D:\Clientes de Wow\Wow - copia` (`Config.wtf` debe tener `SET locale "esES"`).
- `Wow.exe` ya esta parcheado para aceptar interfaz modificada: no hace falta probar firmas.
- Para modificar un archivo: copiarlo de `client/interface-original/...` a `client/src/...` (misma ruta) y editar ahi.
- Generar parche: `powershell -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1`
  El usuario copia `client/patches/patch-4.MPQ` a `Data\` del cliente y **prueba manualmente**. No desplegar ni lanzar el cliente.
- `Data\patch-4.MPQ` (carpeta con ese nombre) tiene prioridad sobre los MPQ de locale; no usar `patch-esES-N`.
- Los archivos originales usan **CRLF**: normalizar tras editar (`sed -i 's/\r$//; s/$/\r/' archivo`).
- Preferir ganchos en Lua sobre editar XML. Toda linea anadida a una funcion original lleva `-- EventWow`;
  la logica propia va en un bloque `EventWow` al final del archivo.
- Para interceptar funciones globales de otros archivos, envolverlas (wrap) desde un archivo que cargue
  despues segun `GlueXML.toc` / `FrameXML.toc`, en vez de copiar el archivo original.
- No hay interprete Lua instalado: revisar sintaxis a mano. Errores en cliente: `SET scriptErrors "1"`.

### Servidor (AzerothCore)
- No modificar el core si se puede evitar: todo en modulos (`mod-eventwow`), hooks de ScriptMgr.
- Seguir `azerothcore-wotlk/AGENTS.md` y `.agents/docs/cpp-guidelines.md` / `sql-guidelines.md`
  (Allman, 4 espacios, LF, `LOG_*` con `{}`, `sConfigMgr->GetOption` solo al cargar config, guardar `ObjectGuid` no punteros).
- **No compilar ni correr CMake**: lo hace el usuario.
- El servidor es la fuente de verdad: validar/forzar todo lo que el cliente pueda falsear (raza, clase, nombre...).

### Versionado (git)
- **Dos repos**: `EventWow` (este: modulo, cliente, tools, docs; rama `main`) y `azerothcore-wotlk/` (fork del core).
  Ambos solo en local por ahora; el remoto privado se anade despues.
- Ignorados en EventWow: `azerothcore-wotlk/`, `server/` (build de CMake/VS), `client/interface-original/`
  (Blizzard, regenerable), `client/patches/` (generado), `*.conf` (solo se versionan `.conf.dist`).
- Core: remoto `upstream` = AzerothCore oficial (push deshabilitado). `master` = espejo de upstream, nunca se commitea.
  Trabajo en la rama **`eventwow`**; actualizar = `rebase` sobre `master`.
- Tocar el core: hook existente > hook nuevo (generico, patron de AC) > edicion directa marcada `// EventWow:`.
  Un commit por cambio, prefijo `[EventWow]`. Registrar cada uno en `docs/core-changes.md` (y la version base probada).
- Commits en ambos repos con el trailer de atribucion de Claude.

### Configuracion (para poder reproducir produccion)
- **Juego** (igual en todos los entornos): en `mod_eventwow.conf.dist`. Las claves del core van en la seccion
  "OVERRIDES DEL CORE", cada una con su motivo. Funciona porque AC carga `configs/modules/*.conf` despues de
  `worldserver.conf` y la ultima clave gana (`Config.cpp` AddKey; `Main.cpp` LoadAppConfigs -> LoadModulesConfigs ->
  SetInitialWorldSettings). No afecta a authserver ni a lo leido antes de cargar modulos (BD, logs, DataDir).
- **Infraestructura** (BD, IPs, puertos, rutas, `acore_auth.realmlist`): nunca en el modulo; documentar en `docs/despliegue.md`.
- **Datos de BD**: SQL en `modules/mod-eventwow/data/sql/db-*/` (nunca en `azerothcore-wotlk/data/sql/`),
  idempotente (DELETE antes de INSERT).
- Nunca pedir que se edite `worldserver.conf` para algo de juego. Auditar con `tools/Diff-Config.ps1`.

## Estado actual

### Hecho (Fase 0 - cliente, probado por el usuario)
`client/src/Interface/GlueXML/`:
- `CharacterSelect.lua`
  - `EVENTWOW_CONFIG` (raza, clase, sexo, fondo, retardo) y textos `EVENTWOW_STR_*`.
  - Pantalla oculta tras un fondo (`EventWow_CreateCover`); muestra solo "Conectando...".
  - 0 personajes -> `charcreate`; 1 personaje -> `EnterWorld()` automatico.
  - Al volver del mundo (logout) -> desconecta y vuelve al login. El cliente **recarga el Lua de Glue** al salir
    del mundo (comprobado), asi que se usa `EventWow_LoginPending`: true al pulsar Login (wrap de `AccountLogin_Login`),
    nil tras `EnterWorld`. Sin el flag, charselect manda al login. Un login automatico futuro debe poner el flag.
  - Envuelve `GlueDialog_OnEvent`: sustituye los dialogos de estado (`CHAR_LIST_*`, `CHAR_LOGIN_IN_PROGRESS`,
    `CHAR_CREATE_IN_PROGRESS/SUCCESS`) por texto propio; si el motor manda otro texto (error) se muestra el dialogo real.
- `CharacterCreate.lua`
  - Oculta raza/clase/personalizacion/logo/rotacion; tapa el modelo 3D con el fondo.
  - Solo caja de nombre centrada + Aceptar/Atras + etiqueta de estado. Atras -> login.
  - Raza/clase/sexo fijos resueltos por fileString (`EventWow_FindIndex`), no por indice fijo.

Datos clave de la API Glue:
- `CreateCharacter(nombre)` usa la raza/clase/sexo seleccionados (`SetSelectedRace/Class/Sex`).
- Los indices son posiciones en `GetAvailableRaces()` / `GetAvailableClasses()`, no IDs del servidor.

### Hecho (Fase 0 - servidor, sin compilar todavia)
`modules/mod-eventwow/`:
- `EventWowConfig` (WorldScript OnAfterConfigLoad): cachea `EventWow.Enable`, `EventWow.Character.Race/Class`.
- `EventWow_AccountScript::CanAccountCreateCharacter`: solo raza/clase configuradas (tambien GMs).
- Overrides: `CharactersPerRealm/Account = 1`, `HeroicCharactersPerRealm = 0`, RaceMask 1790 (solo humano),
  ClassMask 1534 (solo guerrero), `SkipCinematics = 2`.

### Hecho (corte vertical pasos 1-2, compilado y probado por el usuario 2026-11-13)
- Core (rama `eventwow`, commit `4fc546e73`): hook `OnPlayerOverrideLoginLocation` (ver `docs/core-changes.md`).
- `EventWowLobby.cpp`: todo login -> `EventWow.Lobby.*`; invisible en el lobby (no GMs); primer login sin objetos;
  `PLAYER_FLAGS_NO_XP_GAIN`. `EventWowConfig`: lee `EventWow.Lobby.*` y al arrancar avisa si `playercreateinfo` no coincide.
- SQL `data/sql/db-world/2026_11_12_00_lobby_playercreateinfo.sql`: humano guerrero nace en la Isla de los GM.
- Pendiente del "personaje neutro": hechizos/barra/stats -> los gestionara el sistema de "disfraz" de minijuegos.

### Pendiente
- Corte vertical paso 3 (ocultacion probada por el usuario 2026-11-13):
  - `client/src/Interface/FrameXML/EventWow.lua` (anadido al final de `FrameXML.toc`): `EventWow_SetLobbyMode(bool)`.
    Lobby = portada hija de `WorldFrame` (tapa el mundo y el raton, tambien con Alt+Z), marcos reparentados a
    `EventWowHiddenParent` (reversible), atajos de ventanas/acciones envueltos (no hacen nada), QuestLog/WorldMap
    se cierran al abrirse, Esc sin "Macros". De momento siempre en modo lobby; el chat se mantiene.
  - SQL `data/sql/db-auth/2026_11_13_00_rbac_instant_logout.sql`: RBAC 195 -> permiso 1 (logout sin 20 s).
  - Pendiente: el personaje sigue pudiendo moverse con el teclado (invisible); enraizar en servidor si molesta.
- Corte vertical paso 4 (compilado y probado por el usuario 2026-11-13): protocolo por addon messages, ver `docs/protocolo.md`.
  - Servidor: `EventWowProtocol.h/.cpp` (transporte, fragmentacion, `RegisterHandler`, `EventWowMessage`),
    `EventWowGames.h/.cpp` (catalogo `sEventWowGames` + handlers `HELLO`/`LIST`; juego provisional `test`).
  - Cliente: `FrameXML/EventWowProtocol.lua` (`EventWow_Send`, `EventWow_RegisterHandler`, `EventWow_Protocol.games`;
    `EVENTWOW_PROTOCOL.DEBUG` imprime en el chat). HELLO automatico al entrar al mundo.
- Subir ambos repos a un remoto privado.

## Hoja de ruta

**Fase 0 (HECHA):** login -> nombre -> mundo, validado en servidor (mod-eventwow).

**Siguiente: corte vertical** (acordado 2026-11-12). Antes de pulir cada fase, montar el recorrido completo
en version minima con UN minijuego trivial en solitario, para validar lo arriesgado (protocolo, instancias, retorno):

```
Lobby -> panel -> elegir juego -> cola -> instancia -> jugar -> fin -> lobby
```

1. Personaje neutro (servidor): sin equipo/hechizos de clase/XP/misiones, stats fijas; estado base restaurable.
2. Lobby minimo: punto fijo, zona segura sin combate (provisional).
3. Limpieza UI en el mundo (FrameXML): ocultar barras/bolsas/hechizos/talentos/misiones; Logout -> login.
4. Protocolo cliente<->servidor por addon messages (listar juegos, cola, salir, estado, inicio/fin).
5. Addon del panel de minijuegos.
6. Matchmaking + instancias (modulo): cola por juego, crear instancia, teleport, limpieza, retorno.
7. Framework de minijuego (clase base: inicio, tick, victoria, fin) + juego de prueba.

Despues: grupos/emparejamiento multijugador, minijuegos reales, lobby definitivo, launcher, remoto git.

### Decisiones tomadas (2026-11-12)
- **Lobby = "limbo" invisible**: el jugador nunca ve su personaje ni la zona, solo el panel. Es solo un punto ancla
  de entrada/retorno definido en config (`EventWow.Lobby.MapId/X/Y/Z/O`; provisional Isla GM: 1, 16226.2, 16257, 13.2022, 1.65).
  El modulo manda al lobby (y restaura estado base) en CADA login y al salir de un minijuego; no se usa `playercreateinfo`.
- **Lobby en mapa NO instanciado + jugadores invisibles entre si** (visibilidad server-side `SERVERSIDE_VISIBILITY_GM`
  = `SEC_MODERATOR`): evita el trafico de visibilidad sin instancias. Entrar a un mapa de mazmorra al hacer login
  sin bind valido expulsa a la entrada/homebind, por eso el lobby no va instanciado. Si al medir no aguanta:
  lobby instanciado de ~50 (requiere hook de destino de instancia + saltar validaciones de login).
- **Primer login directo al lobby**: `playercreateinfo` (SQL del modulo) apunta al lobby; logins posteriores via hook
  `OnPlayerOverrideLoginLocation` (nunca dos pantallas de carga).
- **Partidas = mapas de mazmorra instanciados** con instancia elegida por el modulo (hook de destino de instancia +
  hook de max jugadores, a crear en el paso de matchmaking). Continentes NO son instanciables: los minijuegos
  van en mapas de mazmorra/banda/BG/arena o mapas propios.
- **Personaje del minijuego = opcion A**: el mismo personaje "disfrazado" por el servidor (morph, hechizos, barra,
  stats, vehiculo) y restaurado al salir. NO se cambia a otro personaje de BD (sin relog).
- **Interfaz = nativa en FrameXML** (en `patch-4.MPQ`, anadida a `FrameXML.toc`, no addon desactivable) + protocolo
  propio por addon messages manejado en C++ en `mod-eventwow`. Panel **generico guiado por datos del servidor**
  (lista de juegos, textos, iconos, min/max jugadores, estado de cola): anadir/cambiar un minijuego no toca el cliente.
  Mensajes de addon: max 255 caracteres (`ChatHandler.cpp`) -> fragmentar. ALE/Eluna + AIO descartado por ahora.
- Minijuegos en C++ (Eluna solo si la iteracion se vuelve un problema).

### Decisiones abiertas
- Login: cuenta+contrasena (actual) vs launcher/solo nombre.
- Lobby definitivo (mapa propio) - de momento Isla de los GM.
