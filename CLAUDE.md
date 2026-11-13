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
  modules/mod-eventwow/       nuestro modulo C++ (junction -> azerothcore-wotlk/modules/mod-eventwow)
    conf/mod_eventwow.conf.dist   opciones propias + OVERRIDES DEL CORE (pisan worldserver.conf)
    src/                          scripts (loader: Addmod_eventwowScripts)
    data/sql/db-{world,characters,auth}/   SQL que el updater de AC aplica al arrancar
  docs/
    despliegue.md             checklist de infraestructura por entorno
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

### Pendiente
- Probar mod-eventwow en servidor (compila OK; prueba en curso por el usuario).
- Subir ambos repos a un remoto privado.
- Lobby: posicion (`playercreateinfo` humano guerrero) - por decidir; de momento inicio normal humano.
- `OnPlayerCreate`: personaje vacio (sin equipo/hechizos) o con ropa basica - por decidir.
- Decisiones abiertas: login (cuenta+contrasena vs solo nombre/launcher), C++ puro vs C++ + Eluna para minijuegos,
  base de matchmaking/instancias (sistema de Battlegrounds vs mapas de mazmorra vs phasing).

## Hoja de ruta
1. **Fase 0 - Servidor:** compilar AzerothCore; `CharactersPerRealm = 1`, nivel/arranque fijos, sin cinematicas;
   modulo que fuerce raza/clase en la creacion; `playercreateinfo` -> posicion del lobby.
2. **Fase 1 - Lobby y UI en el mundo (FrameXML):** ocultar UI no usada (bolsas, hechizos, talentos, misiones...),
   Logout del menu -> login; zona de lobby segura.
3. **Fase 2 - Protocolo cliente<->servidor:** addon messages; addon del panel de minijuegos.
4. **Fase 3 - Matchmaking e instancias:** colas solo/grupo, creacion/limpieza de instancias, retorno al lobby.
5. **Fase 4 - Framework de minijuegos:** clase base (inicio, ticks, victoria, recompensas) y normalizacion del jugador.
6. **Fase 5 - Minijuegos concretos.**
