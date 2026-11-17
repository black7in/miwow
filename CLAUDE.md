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
    mapas.md                  mapas propios desde Warcraft 3: flujo, conversion, rango de IDs 750-799
  Maps/
    maps.json                 lista de mapas propios (id, carpeta, mapa de WC3 fuente, escala)
    Warcraft/                 mapas de Warcraft 3 (fuente, los hace el usuario en el World Editor 1.26)
  tools/
    Merge-Interface.ps1       consolida Interface de los MPQ extraidos respetando el orden de carga
    Build-Patch.ps1           copia client/src -> client/patches/patch-4.MPQ (+ DBC con Build-Dbc.ps1 + mapas con mapgen)
    Build-Dbc.ps1             DBC del cliente = client/DBCs/DBC<locale> + filas EventWow de las tablas *_dbc de la BD world
    Diff-Config.ps1           audita worldserver.conf vs .dist (cambios hechos a mano)
    mapgen/                   Python (py + numpy): WC3 -> ADT/WDT del cliente + .map del servidor (docs/mapas.md)
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
- **DBC** (objetos, hechizos... propios): fuente de verdad = tablas `*_dbc` de AzerothCore en la BD world (SQL del
  modulo). El servidor las fusiona con sus DBC al arrancar: sus archivos DBC (ingles) NO se tocan. El cliente recibe
  el DBC original de `client/DBCs/DBCesES` (no versionado; `DBCenEN` = ingles, para un parche futuro) + nuestras filas
  (ID >= 9500000) en `patch-4.MPQ/DBFilesClient`: lo hace `Build-Patch` (necesita la BD arrancada; `-SkipDbc` sin ella).
  Objetos: `item_dbc` se rellena DESDE `item_template` en el SQL (con `DBC.EnforceItemAttributes = 1` deben coincidir).

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
- Overrides: `CharactersPerRealm/Account = 1`, `HeroicCharactersPerRealm = 0`, RaceMask/ClassMask (solo la raza/clase del
  contenedor; desde 2026-11-13 elfo de la noche druida nivel 80), `SkipCinematics = 2`.

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
- Interfaz del lobby v1 (probada por el usuario 2026-11-13, incluida pantalla completa):
  - Disposicion: barra superior (titulo, nombre con distintivo GM, boton Menu) / lista de juegos (izq.) + detalle con
    "Buscar partida" o estado de cola (der.) / chat global abajo. Pantalla completa en cualquier resolucion
    (`EventWowPanel_Layout`: reparto proporcional, filas segun alto), estilo oscuro plano.
  - Cliente: `EventWowPanel.lua` (panel generico guiado por GAMES/QUEUE_STATUS), `EventWowChat.lua` (chat global; oculta
    el chat nativo y copia lo que llega a ChatFrame1; "/" -> comandos nativos, "." -> comandos GM; Intro enfoca la caja).
    `EventWowProtocol.lua`: `EventWow_RegisterListener` (CONNECTED, GAMES), textos de error `EVENTWOW_ERROR_TEXTS`.
  - Servidor: HELLO movido a `EventWowProtocol` (conectados + Connect/DisconnectListener, `Broadcast`);
    `EventWowChat.cpp` (CHAT/ONLINE, historial 50, limite 200 caracteres y frecuencia, silencio `CanSpeak`, rango GM =
    security > SEC_PLAYER, log `module.eventwow.chat`); `EventWowQueue.cpp` (QUEUE/LEAVE PROVISIONAL: solo estado);
    juegos de maqueta `race`/`invasion` en `EventWowGames.cpp` (quitar con el framework).
  - Chat v2 (probado por el usuario 2026-11-13): pestanas planas [Global] + una por conversacion privada (susurros nativos; se
    abre al recibir/enviar o al hacer clic en un nombre; contador de no leidos, sonido; "x" o clic derecho cierra y
    conserva el historial; max 8). Sin tutoriales: cliente (`EventWow_DisableTutorials`) + servidor (flags de tutorial
    todos vistos en cada login, `EventWowLobby.cpp`). Sin canales: el servidor descarta
    `CMSG_JOIN_CHANNEL` salvo en modo dev (`EventWow_ChatServerScript`) y `CleanupChannels` al salir del modo dev.
- Grupos + cola en grupo (probado por el usuario 2026-11-13). Ver "Grupos" en `docs/protocolo.md`.
  - Decision: grupos NATIVOS de AzerothCore (no propios). Servidor `EventWowGroups.cpp`: max 5 sin banda, no
    invitar/aceptar en partida, cambio de grupo -> fuera de la cola. `EventWowGameInfo::MaxPartySize` (1 = individual).
  - `EventWowMatchMgr`: entrada de cola = jugador o grupo entero (lo apunta el lider); `UnbindAllFor` al cerrar partida.
  - Cliente: `EventWowGroup.lua` (seccion GRUPO abajo a la derecha: miembros, lider, invitar, expulsar, salir),
    boton de buscar segun grupo, alt+clic invita, pestana "Grupo" en el chat (CHAT_MSG_PARTY*), marcos de grupo nativos visibles en partida. Protocolo v3.
  - Juego `test_group` (1-5 jugadores, grupo hasta 5) para probarlo.
- Partida encontrada con confirmacion tipo Dota 2 (probado por el usuario 2026-11-13): `EventWowMatchMgr` propuestas
  (`StartProposal/AcceptProposal/FailProposal`, `EventWow.Queue.AcceptTimeout` = 20 s); quien rechaza o no acepta sale
  de la cola con su grupo, el resto vuelve con su antiguedad. Cliente `EventWowMatchFound.lua` (popup Aceptar/Rechazar).
- Amigos v1 (probado por el usuario 2026-11-13; mejorable): seccion social con pestanas [Grupo] [Amigos] (`EventWowSocial.lua`,
  `EventWowFriends.lua`; lista nativa: conectados primero, estado, invitar, quitar, susurrar, anadir). Servidor:
  `OnPlayerNotVisibleGloballyFor` en `EventWowLobby.cpp` (sin el, los amigos del lobby salian desconectados).
- Personajes por juego ("disfraz") - ver decision 2026-11-13 abajo. Orden:
  1. HECHO (probado por el usuario 2026-11-13): contenedor = **elfo de la noche druida nivel 80**: `EventWow.Character.Race/Class`
     4/11, RaceMask 1783, ClassMask 511, override `StartPlayerLevel = 80`, `EVENTWOW_CONFIG` NIGHTELF/DRUID, SQL
     `2026_11_13_00_lobby_playercreateinfo_druid.sql` (druida al lobby, humano guerrero de vuelta a Villadorada).
     Personajes de prueba borrados de `eventwow_characters` (tablas por personaje vaciadas).
  2. Prototipo de disfraz (probado por el usuario 2026-11-13):
     - BD world (SQL del modulo): `eventwow_character` (Id, Name, Description, Icon, DisplayId, Scale, Health, PowerType,
       MaxPower), `eventwow_character_spell` (CharacterId, Slot, SpellId), `eventwow_game_character` (GameId,
       CharacterId, Sort). Prueba: personaje 1 "Piromano goblin" (modelo 7052, 5000 vida, 2000 mana, Bola de Fuego /
       Nova de Escarcha / Traslacion) en `test` y `test_group`. Se cargan al arrancar (sin comando de recarga aun).
     - `EventWowCharacters.*` (catalogo), `EventWowDisguise.*` (Apply/Remove: display nativo + display, escala, tipo de
       poder, vida/poder max por hooks, hechizos temporales; `OnSpellCheckCast` solo deja lanzar los del disfraz salvo
       modo dev). Estado en `CustomData` (se pierde con logout).
     - Framework: `EventWowMatch::GetAssignedCharacter` (virtual; por defecto el primero del juego) se aplica al llegar;
       `SetCharacter` para juegos con seleccion. Se quita en `EventWowMatchMgr::RemovePlayer` (fin, abandono, salir,
       logout; tambien modo dev) y en `RestoreBaseState`.
     - Cliente: `EventWowAbilities.lua` (barra propia abajo, botones seguros `CastSpellByID`, teclas 1..0 por override
       bindings, cooldown/coste/alcance). Protocolo v4: `MATCH_CHARACTER`. Oculta los mensajes de sistema
       `ERR_LEARN_SPELL_S` / `ERR_LEARN_ABILITY_S` / `ERR_SPELL_UNLEARNED_S` (salvo modo dev con panel oculto).
     - Comprobar: modelo/escala/vida/mana, lanzar con clic y teclas, que Rejuvenecimiento etc. del druida no se
       pueden lanzar, y que todo vuelve al acabar/abandonar/desconectar/morir.
     - Habilidades de armas/Defensa al maximo del nivel en cada login: override `AlwaysMaxSkillForLevel = 1`
       (opcion del core, sin probar a peticion del usuario). No suben jugando ni salen avisos.
     - Pendiente del disfraz: stats primarias/AP/velocidad, ajustes de dano por personaje, comando de recarga,
       fase `Picking`.
  3. Prototipo de vehiculo (probado por el usuario 2026-11-13; el goblin no hace la animacion de sentado: buscar modelo):
     - `eventwow_character.VehicleEntry` (SQL `_03` ALTER, `_04` datos): personaje 2 "Motorista goblin" (goblin en
       Salvaged Chopper 33062, moto de Ulduar; su script `npc_salvaged_chopper` solo cambia un boton con pasajero)
       en el juego nuevo `test_vehicle` (Sima Ignea, 60 s).
     - `EventWowDisguise`: invoca el vehiculo (TempSummon manual, faccion del jugador) y lo sube al asiento 0; al quitar
       lo baja y despawnea. `Update()` cada 1 s desde `EventWowMatch::Update`: si se baja, vuelve a subirlo; si el
       vehiculo murio o esta a > 10 m (reaparicion) invoca otro (no en modo dev / muerto). Caso limite: si sale del
       mapa sin pasar por `Remove` (teleport GM), el vehiculo queda en la instancia hasta que se descarga.
     - Cliente: `VehicleMenuBar` visible en partida, `VehicleMenuBarLeaveButton` oculto, teclas 1-6 permitidas en
       vehiculo (`EVENTWOW_VEHICLE_ACTION_FUNCTIONS` en EventWow.lua).
     - Nombres (en pruebas): solo los de jugadores. `EventWow_SetupUnitNames` (EventWow.lua) fuerza CVars
       (`UnitNameOwn = 1`, `UnitName*Pet/Guardian/TotemName = 0`). Comprobado: el vehiculo conducido NO cuenta como
       mascota para el cliente (sale como PNJ) y cambiar `UNITNAME_TITLE_*` desde Lua no tiene efecto: se edita
       `client/src/Interface/FrameXML/GlobalStrings.lua` (`UNITNAME_TITLE_CHARM/MINION` y `UNITNAME_SUMMON_TITLE3`
       = "%s": el subtitulo de un vehiculo sin nombre muestra solo el nombre del conductor, entre < > (lo pone el motor); probado y aceptado por ahora. Mejora posible: entrada de vehiculo por jugador con su nombre (fragil, descartada de momento)).
       Al conducir, el cliente muestra sobre el vehiculo el nombre de la CRIATURA y nunca el del conductor (probado),
       y el nombre es por entrada (no por jugador). Decision: **vehiculos propios de EventWow sin nombre**, rango de
       entradas reservado **9500000-9599999**, copias de vehiculos existentes sin script/heroico/clic/locale
       (SQL `_05`: 9500000 = Salvaged Chopper; probado: sin nombre encima; el retrato del vehiculo muestra "Entidad desconocida", aceptado). El nombre es un campo mas: un juego puede darle uno.
     - Personajes con vehiculo no deberian llevar hechizos de disfraz (las teclas 1.. chocarian con la barra propia).
  4. Stats, capa 1: modificadores (probado por el usuario 2026-11-13: 6000 vida, 3500 mana, como se esperaba). Herramientas para un futuro "Hero Siege".
     - `EventWowStats.*`: `Add/Get/Reset` por jugador (`CustomData`), 23 stats con clave estable (str, agi, sta, int,
       spi, health, mana, armor, ap, rap, sp, crit, haste, hit, expertise, dodge, parry, block, resilience, armorpen,
       spellpen, mp5, hp5). Se aplican IGUAL que `Player::_ApplyItemBonuses`: lo derivado lo calcula el motor.
       `Reset` en `RemovePlayer` y `RestoreBaseState` (despues de `EventWowDisguise::Remove`).
     - Ficha: `eventwow_character_stat` (SQL `_06`; prueba: Piromano +100 sta, +100 int, +300 sp). El disfraz las suma
       al aplicarse y las resta al quitarse. `Health`/`MaxPower` de la ficha pasan a ser BASE: hook = base + (maximo
       nativo actual - maximo nativo medido al disfrazarse), asi Aguante/Intelecto/libros/auras suben vida y mana.
     - Comando GM: `.eventwow stat add <stat> <valor>` | `reset` | `list` (seleccionado o uno mismo).
     - Siguiente: tienda (capa 3) con moneda propia de partida; libros = filas de catalogo en BD.
  5. Prototipo de tienda (probado por el usuario 2026-11-13, incluido Item.dbc en el cliente). Decisiones del usuario: todo
     nativo (PNJ vendedor en el mundo, ventana de vendedor, bolsas), **oro de WoW = moneda de partida** (0 fuera de ella),
     objetos propios ya. Item.dbc: filas en `item_dbc` (SQL `_08`) + `tools/Build-Dbc.ps1` (ver "DBC" en Reglas).
     - `EventWowShop.*`: tabla world `eventwow_item` (Entry, Flags; SQL `_07`). `INSTANT` (0x1) = al comprarlo se
       destruye y sus stats de `item_template` (stat_type/stat_value, armadura) x cantidad van a `EventWowStats`
       (hook `OnPlayerAfterStoreOrEquipNewItem`; necesita hueco en la mochila). Sin fila = objeto normal.
     - `EventWowLobby::ClearInventory` (equipo, bolsas, recompra, oro = 0): en `RestoreBaseState` (tambien al llegar
       a la partida) y en CADA login (antes solo el primero).
     - `EventWowGameInfo::Inventory` -> 9o campo de `GAMES` (protocolo v5): el cliente deja abrir las bolsas en
       partida (`EVENTWOW_INVENTORY_FUNCTIONS`, EventWow.lua). `OnSpellCheckCast` del disfraz deja lanzar hechizos de
       objetos (pociones).
     - SQL `_08`: libros 9500000-9500003 (Fuerza/Intelecto +20, Poder con hechizos +50, Aguante +20; 50 oro), vendedor
       9500100 "Mercader" (copia de Kixxle 8305, faccion 35) con los libros + Pocion de sanacion runica (33447).
       Arregla tambien los iconos de `eventwow_character` (`'\I'` en MySQL pierde la barra: escribir `\\`).
     - Juego `test_shop` (`EventWowGameTestShop`, 180 s, Piromano): 200 oro al empezar e invoca al vendedor junto al inicio.
  6. Inventario de partida + HUD inferior (compilado y probado por el usuario 2026-11-13: la interfaz se ve "decente pero
     mejorable"; COMMIT INCOMPLETO a peticion del usuario: se termina en otro commit). PENDIENTE de la prueba:
     - La pocion (33447) no se puede usar: falta el mensaje de error exacto. Sospechas: vida al maximo (las pociones de
       sanacion no se usan con vida llena), o "Accion bloqueada" por llamar a `UseContainerItem` desde el boton (pasar a
       botones seguros), o el filtro `OnSpellCheckCast` del disfraz.
     - La espada (9500004) no se puede comprar: el druida no tiene la habilidad de espadas. Opciones: aprender las
       habilidades de armas al contenedor (hechizos de habilidad + `skillraceclassinfo_dbc`, que el servidor fusiona
       con su DBC) o saltarse la comprobacion en la compra (los objetos nunca se equipan). Ver primero donde se rechaza.
     - Las casillas no muestran el tooltip del objeto al pasar el raton (en el vendedor si). Causa probable:
       `EventWowInventory.lua` OnEnter hace `if GameTooltip:SetBagItem(...) then Show() else Hide()`, pero en 3.3.5
       SetBagItem devuelve (hasCooldown, repairCost), no "hay objeto": casi siempre nil -> Hide. Comprobar con
       GetContainerItemLink y llamar Show() siempre.
     - En partida no se ven los errores del juego ("No tienes suficiente mana", "No puedes usar eso..."; los pinta
       `UIErrorsFrame` con UI_ERROR_MESSAGE). Revisado: nuestro codigo no oculta ni reparenta `UIErrorsFrame`, no le
       quita eventos y el HUD de partida no lo tapa (HUD de -24 a -108, errores en -122 con strata HIGH). Probar en partida
       `/run UIErrorsFrame:AddMessage("prueba", 1, 0, 0)`: si sale, el marco funciona y el problema es que el evento no
       llega o la accion no se envia. Puede estar ligado a la pocion: si `GetItemSpell(link)` devuelve nil, el clic
       no hace nada y tampoco hay error.
     - Al volver al lobby se ven en el chat los mensajes de objetos recibidos (CHAT_MSG_LOOT/MONEY de la partida):
       filtrarlos y valorar chat de grupo / decir (/say) dentro de las partidas.
  Decisiones del usuario (inventario):
     estilo Dota, 6 casillas, los objetos NO se equipan (llevarlos ya da sus efectos), panel de stats fijo y compacto,
     teclas para objetos: no por ahora (solo clic; quiza un panel de teclas configurable por jugador mas adelante).
     Interfaz del vendedor propia: mas adelante.
     - `EventWowInventory.*`: casillas = N primeras ranuras de la mochila (`EventWowGameInfo::InventorySlots`, sustituye a
       `Inventory`; GAMES envia el numero, protocolo v6). `Update` cada 250 ms desde `EventWowMatch::Update`: stats de
       item_template + hechizos "Equipar:" como aura (sin acumular el mismo hechizo; vuelve tras morir). "Uso:" nativo.
       Sin dano de arma. Compra bloqueada si no cabe en las casillas (`OnPlayerBeforeBuyItemFromVendor`, "Inventario
       lleno"); equipar bloqueado (`OnPlayerCanEquipItem`). `Clear` antes de `EventWowStats::Reset`.
       `EventWowStats::FromItemMod` (compartido con la tienda).
     - Cliente: `EventWowStats.lua` (panel 2x5 a la izquierda de la barra de habilidades, tooltip con todo; API nativa,
       sin protocolo; oculto en vehiculo) y `EventWowInventory.lua` (casillas 3x2 + oro a la derecha; clic = usar o
       vender con el vendedor abierto; arrastrar = mover/vender/destruir; API de contenedores directa). Bolsas nativas
       bloqueadas siempre en partida (tambien `OpenBackpack` del vendedor). Barra de habilidades bajada (offset 24).
       Avisos internos nuevos: `MATCH`, `CHARACTER`.
     - SQL `_09`: 9500004 "Espada de prueba" (copia de Grieving Spellblade 39200: Aguante, Intelecto, pasiva 48626).
  Despues: carrera con fases.
- Corte vertical pasos 6-7 (compilado y probado por el usuario 2026-11-13):
  - Core (commit `71970693a`): hooks `OnPlayerOverrideInstanceDestination` / `OnPlayerOverrideInstanceEnter`.
  - Servidor: `EventWowMatchMgr.*` (sustituye a `EventWowQueue.cpp`: cola por juego, emparejamiento con
    Max o Min + `EventWow.Queue.FillWait`, una instancia por partida con `InstanceSave` propio, teleport con
    `TELE_TO_GM_MODE`, bind temporal quitado al salir, logout/abandono/salir de la instancia -> fuera),
    `EventWowMatch.*` (framework: Loading -> Countdown -> Running -> Ended; `OnStart/OnUpdate/OnTimerExpired/
    OnPlayerArrived/OnPlayerLeft`, `SetTimer/SetHud/SetResult/End`), `EventWowLobby.h` (visibilidad, estado
    base, `ReturnToLobby`), `games/EventWowGameTest.cpp` (juego `test`: Sima Ignea 389, aguantar 30 s).
    `EventWowGameInfo` + `MapId/Start/Factory` (sin factoria = maqueta); `Validate()` al arrancar.
    Config: `EventWow.Queue.FillWait`, `EventWow.Match.LoadTimeout/ReturnDelay`; override `Instance.UnloadDelay = 60000`.
  - Cliente: protocolo v2 (`GAMES` + jugable, `MATCH_STATE/HUD/END`, `ABANDON`); `EventWowMatch.lua` (HUD,
    cuenta atras, resultado, Abandonar); `EventWow_SetMode("lobby"|"match")` (en partida: mundo + PlayerFrame/
    TargetFrame/BuffFrame/CastingBar; ventanas y acciones siguen bloqueadas; sin chat).
  - Muerte (probado por el usuario 2026-11-13): regla por defecto = reaparecer en el inicio a los 5 s (`OnPlayerDied`, `RespawnPlayer`,
    `GetRespawnPosition`; hooks `OnPlayerJustDied` + `OnPlayerCanRepopAtGraveyard`: nunca al cementerio; caer fuera
    del mapa -> punto de reaparicion). `IsInLobby` = mismo mapa Y a menos de 250 m del ancla (la Isla GM comparte
    Kalimdor con Orgrimmar). Login muerto -> resucita.
  - Pendiente: chat en partida, "disfraz".
- Modo dev (2026-11-13; probado con .dev/.gm; "Ocultar panel" y reglas de jugador en modo dev sin probar):
  - Activo con `.dev on` (`PLAYER_FLAGS_DEVELOPER`) o `.gm on`, SOLO por comando (quien puede: RBAC del core).
    El core no avisa del cambio de modo GM: `EventWowDevMode.cpp` lo comprueba cada 250 ms para los conectados y
    manda `DEV_MODE 0/1`. `.gm` y `.dev` iguales: los dos se quitan al hacer login (`.dev` en el modulo, `.gm` con el
    override `GM.LoginState = 0`).
  - Cliente: en modo dev se ve el panel igual; boton "Ocultar panel" (barra superior) o `/eventwow` ->
    `EventWow_SetPanelHidden` (EventWow.lua, solo cliente, no toca flags): todos los marcos, sin portada/panel,
    ventanas y acciones desbloqueadas, chat nativo (`EventWowChat_SetNativeVisible`); boton "Mostrar panel" arriba.
    Al salir del modo dev el panel vuelve. En partida el HUD sigue visible.
  - Regla general en servidor: `EventWowDevMode.h` `IsActive()`; `EventWowMatchMgr` no aplica muerte/salida/vuelta al
    lobby/estado base/cola-solo-lobby en modo dev (ver decision 2026-11-13).
  - Observacion pendiente: reinicios de instancia del core. Mazmorras 5 normal no tienen reinicio programado
    (seguro). Bandas (semanal) / heroicos (diario) si: una partida en esos mapas se cortaria a la hora del reinicio.
    Opcion propuesta: que `Validate()` rechace mapas con `MapDifficulty.resetTime` != 0. Sin decidir.
- **Mapa del asedio (751): modelos de muralla HECHOS y probados por el usuario (2026-11-13: "perfecto").** `wallModels` en `maps.json` (ver "Modelos de muro" en
  `docs/mapas.md`), `SC_Wall_01.M2` (muralla de la Plaga) por las caras de los muros (contorno simplificado: diagonales
  reales). v1 (escala 1, 993 modelos en las dos caras) probada por el usuario: los muros salen, pero pequenos/
  "chatos" y se notaba el relieve del terreno; pidio el doble de alto y ~50% mas de ancho. v2 (probada: tamano bien): escala 2
  (uniforme: 24 x 18.6 x 12.8), 378 modelos centrados en los muros finos (salta caras ya tapadas), muro de terreno = huella
  de los modelos a suelo + 8, borde exterior a 11.7 (sin roca detras); pero el muro de terreno asomaba en "dientes" de
  roca por las caras (triangulos de la malla). v3 (huella encogida 3 yardas, `terrainInset`): mucho mejor, aun asomaba
  algo. v4 (probada, "perfecto"): `terrainInset` 5 y `terrainHeight` 5 en maps.json. Despues el usuario encontro pasos
  entre salas: centro de los cruces en "+"/"T" sin modelo (Sala Sur 1 <-> otras) y cuellos diagonales (Sala Sur 2/3 <->
  Cruce_Punto_Suroeste/Sureste). v5 (el usuario: "satisfecho con el mapa, por el momento lo dejamos aqui"): pasada de relleno (39 modelos a 0/90 grados en cruces y cuellos, sin pisar
  puntos de region), 468 modelos; comunicacion entre regiones = WC3 (comprobado por script). Parche y `.map` regenerados.
  Vista previa (no versionada): `tools/mapgen/_work/muros_751*.png`. Familia por si hace falta: SC_Wall_01_Cap 5.0x9.4x6.4 (remate), SC_Wall_01_Ramp,
  SC_Wall_02..06, SC_Wall_Decoration_01/02 (carpeta `World\Expansion02\Doodads\Generic\Scourge`; ninguna esta suelta en
  los ADT de Rasganorte, solo dentro de WMO). Posibles mejoras: remates (Cap) en extremos libres.
  Zona + minimapa (el usuario: "perfecto", 2026-11-13; decision del usuario: un solo nombre de zona para todo el mapa, es una mazmorra de
  evento): SQL `_12` (`areatable_dbc` 5000 "Prueba WC3" / 5001 "Asedio", `map_dbc.AreaTableID`; aplicado a mano en la
  BD de desarrollo), `areaId` en maps.json (MCNK + `.map`), minimapas generados por mapgen + `md5translate.trs`
  (original en `client/Minimap/`, no versionado), `MinimapCluster` visible en partida sin botones. Ver `docs/mapas.md`.
  vmaps + mmaps (dados por buenos por el usuario 2026-11-13; LoS en el juego aun sin PNJ que lo pongan a prueba): `tools/mapgen/vmaps.py` escribe `751.vmtree`, `751_<tx>_<ty>.vmtile` y
  `Sc_Wall_01.m2.vmo` en `data\vmaps` (el extractor de AC no lee nuestro parche-carpeta). Validado: `.vmo` identico al
  oficial (probado con SC_Wall_01_Cap), nombres de tile como los oficiales, linea de vision simulada bloqueada por muros.
  Despues: funcion de cada region con el amigo (renombrar en `regionNames`), minijuego de oleadas.
  Logica del mapa de WC3 analizada (2026-11-13, `temp/Mi X Hero`, script ofuscado): ver `docs/asedio.md` (flujo, funcion
  de cada region, adaptacion a 1 personaje y plan por pasos; nombres/jefes/objetos propios, no los del mapa de terceros).
  Pendiente tambien: completar el paso 6 (inventario + HUD; commit incompleto), ver arriba.
  Asedio paso 1 (2026-11-14, compilado y probado por el usuario: "funciona el pick"): fase de eleccion `Picking` en el framework (Loading -> Picking ->
  Countdown; `GetPickTime()` > 0 y >= 2 personajes; eleccion definitiva, unica por defecto, al azar al acabar el tiempo o
  todos elegidos antes; protocolo v7 `PICK`/`MATCH_PICK`/`MATCH_PICKS`/estado `PICKING`; cliente `EventWowPick.lua`).
  Juego `asedio` (`games/EventWowGameSiege.cpp`, sustituye a `test_siege_map`; 1-5 jugadores, 6 casillas) con 4 heroes
  provisionales (SQL `_14_00`, Id 10-13). Durante la eleccion el jugador puede moverse (sin disfraz).
  Heroes (diseno decidido con el usuario 2026-11-14, SIN IMPLEMENTAR): ver `docs/heroes.md`. Nivel real de WoW 1 -> 30 en
  partida con la XP nativa de AC (tope y multiplicador con `OnPlayerGiveXP`), oleadas que suben de nivel, talentos y
  logros bloqueados, un hechizo propio por nivel de habilidad (tooltip correcto; `spell_dbc` + Spell.dbc), un punto por
  nivel con "+" en la barra, definitiva a nivel 6. Las puntuaciones (critico, celeridad...) valen mucho mas a nivel bajo:
  crecimiento con stats que no dependen del nivel + stats en porcentaje (`critpct`) convertidas segun el nivel.
  Esquema: 3 basicas x 4 rangos (rango max = (nivel+1)/2: niveles 1/3/5/7), definitiva x 3 (6/12/18), Atributos x 15
  (desde nivel 2, stats por rango) = 30 puntos. Agilidad -> velocidad de ataque e intelecto -> celeridad con hechizos
  (unicas reglas propias, 0,5 %/punto provisional, tope 1 golpe/0,3 s). Ataque basico para todos: cuerpo a cuerpo nativo
  con dano base por ficha; distancia y lanzadores con disparo automatico propio (sin arma).
  Hechizos propios (plan 2026-11-14, sin implementar): ver `docs/hechizos.md`. Fichas TOML por heroe -> `tools/spellgen`
  (copia una base del Spell.dbc del cliente, un hechizo por rango) -> SQL `spell_dbc` + `spell_ranks` +
  `spell_bonus_data` -> Build-Dbc. Spell Editor de Stoneharry solo como explorador. OJO: texto esES = hueco 6 de cada
  texto (columna `*_Lang_zhCN` en spell_dbc, los nombres de AC no siguen el orden de 3.3.5).
  Paso 1 hecho (2026-11-14, probado por el usuario: "hechizos funcionando"): `tools/spellgen/spellgen.py` (build/dump/find/icon), ficha
  `data/spells/prueba.toml` -> `eventwow_spells_prueba.sql` (Martillo de prueba 9500000-9500003), personaje 19
  "Probador de hechizos" en el Asedio (SQL `_14_01`). Ambos SQL aplicados a mano en la BD de desarrollo; parche regenerado.
  Paso 2 (2026-11-14, probado por el usuario: "funciona"): bateria de recetas en `prueba.toml` (9500010-9500027: lanzamiento 2 s, area, suelo,
  DoT, HoT, curacion 1,5 s, escudo, mejora de grupo, aura de grupo, aura de inmolacion (aura + hechizo disparado),
  nova/raiz, carga, empujar, cadena, canalizado, disparo automatico sin arma, pasiva). Personajes 20 "Probador ofensivo"
  y 21 "Probador de apoyo" (SQL `_14_02`). spellgen: claves `visual`, `type = "NONE"`, limpia `*AuraSpell`.
  Invocaciones 9500028 (lobo controlable: SummonProperties 1561, categoria PET -> barra de mascota) y 9500029 (2 arboles
  guardianes no controlables: SummonProperties 61). En modo partida la barra/retrato de mascota no se muestran (anadirlos
  si un heroe invoca). Pasiva: la base llevaba DO_NOT_DISPLAY (0x80), quitado.
  Enemigos para probar: `.dev on` + `/eventwow` (chat nativo) + `.npc add temp 28104` (Enraged Skeleton 80) / 31144 (muneco).
  **DONDE QUEDAMOS (2026-11-14)**: heroes del Asedio = jefes/personajes de WoW (Arthas, Rey Exanime, Thrall,
  Sylvanas...). Lista de modelos en `docs/heroes-modelos.md` (displays de la BD + arma de cada PNJ). El usuario los esta
  probando con `.morph` y pasara SU LISTA de heroes con el modelo elegido; despues: definir habilidades de cada uno
  (`docs/heroes.md`: 3 basicas x 4 + definitiva x 3 + atributos; fichas con spellgen) e investigar armas visibles sin
  equipar (las armas no son parte del modelo). Lista inicial de 15 heroes con modelo y armas HECHA (2026-11-14, tabla
  "Lista inicial" en `docs/heroes-modelos.md`). Armas sin equipar: prototipo `EventWowWeapons.cpp` (comando
  `.eventwow weapon set/sheath/clear`, escribe `PLAYER_VISIBLE_ITEM_*`), probado por el usuario: se ven sobre el modelo
  transformado, la Z envaina/desenvaina; `sheath` no hace nada (el cliente controla el envainado propio; quitarlo) y
  la ranura de distancia no se dibuja (arcos en la mano derecha; OJO: probado con un arco de PNJ de envainado 0, a
  revisar con las armas equipadas de 2026-11-16). Armas propias 9500200-9500299 (SQL
  `2026_11_14_03`, 9500200 = arco de Sylvanas visible envainado). Siguiente: armas en la ficha (`eventwow_character`)
  aplicadas por el disfraz.
  **Eleccion estilo Warcraft 3 (decidida con el usuario 2026-11-14, probada: "todo bien"; tamanos a ajustar por el usuario)**: en el Asedio los heroes son PNJ en
  circulo (radio 16) alrededor de la region Inicio (el jugador entra en el centro); se elige hablando con uno (dialogo + confirmacion, definitiva) y su
  PNJ desaparece. Tiempo 60 s; al acabar, al azar a quien no eligio. La ventana `EventWowPick.lua` se mantiene para otros
  juegos (`GetPickPositions()` vacio = ventana). Framework: `EventWowMatch::GetPickPositions/MakePickCircle/CanPick`,
  `UpdatePickCreatures` (aspecto de la ficha: modelo, escala, armas con `SetVirtualItem`); `EventWowPickCreature.cpp`
  (`npc_eventwow_pick`). Ficha: `WeaponMainHand/WeaponOffHand` (el disfraz las pone con `EventWowWeapons`, hook
  `OnPlayerAfterSetVisibleItemSlot` las repone) y `PickCreature` (SQL `_04`). SQL `_05`: 15 heroes (fichas 30-44, sin
  habilidades), PNJ 9500300-9500317 generados desde las fichas (+ `npc_text` mismo ID = descripcion), Asedio = heroes +
  probadores 19-21 (los 10-13 fuera). `_04`/`_05` aplicados a mano en la BD de desarrollo.
  Esquema de habilidades ampliado (2026-11-14): 4 basicas x 4 + definitiva x 3 + suprema (sola a nivel 30) + 11 de
  atributos (`docs/heroes.md`). `.eventwow hero <id>|off|list` (EventWowDisguise.cpp): probar un heroe sin partida.
  **Arthas caballero de la Muerte (ficha 31), probado por el usuario 2026-11-14 ("todos los hechizos probados")**: `data/spells/arthas.toml` (spellgen: clave nueva
  `script`), `EventWowHeroSpells.cpp` (Espiral de la Muerte, invocaciones), SQL `_06` (rango 1 de cada habilidad),
  barra de mascota nativa en partida (`EventWow_ApplyPetBar`, EventWow.lua). SQL aplicados a mano en la BD de desarrollo.
  Despues: base de niveles (paso 1 de `docs/heroes.md`, requiere compilar).
  **Niveles y puntos de habilidad (pasos 1-2 de `docs/heroes.md`, 2026-11-14, probado por el usuario: "funciona"; interfaz a mejorar mucho, afinar hechizos despues)**:
  `EventWowProgress.*` (nivel real 1 -> `EventWowGameInfo::MaxLevel`, XP nativa x `XpRate` con tope, un punto por
  nivel, rangos = cadena de spell_ranks, atributos de `eventwow_character_attribute`, suprema sola al maximo;
  talentos/logros/correo de nivel bloqueados; `Stop` desde `EventWowDisguise::Remove` = nivel base; login = nivel
  base). `EventWowMatch::SetCharacter`: con `MaxLevel` -> nivel 1 antes del disfraz (mide la vida nativa) +
  `Apply(..., true)` (solo fijas) + `Start`. Asedio `MaxLevel = 30`. SQL `_07` (columna `Kind` + atributos de
  Arthas; aplicado a mano en la BD de desarrollo). Protocolo v8 (`MATCH_ABILITIES`/`UPGRADE`). Cliente
  `EventWowAbilities.lua`: rango "n/m", gris sin aprender, "+" (no seguros), boton Atributos, barra de XP, nombre
  con nivel/puntos; lanza por NOMBRE (rango mas alto aprendido). `EventWow.lua`: barra nativa oculta con disfraz
  (tambien en modo dev), pet bar mas arriba (GAP 40). Comando `.eventwow hero <id> [nivel]` / `hero level <n>`.
  **Habilidades de los 14 heroes restantes (2026-11-14, SIN COMPILAR NI PROBAR; el usuario lo mandara a probar a
  otros)**: `docs/heroes-habilidades.md` (diseno, IDs, cambios al implementar). 14 fichas TOML + `comun.toml`
  (Poder de invocacion 9509000-001, Reencarnacion agotada 9509010), SQL `_08` (habilidades/Kind de las fichas 30 y
  32-44, atributos por papel, criaturas 9500400 serpiente / 9500401 fenix). `EventWowHeroSpells.cpp`:
  `spell_eventwow_black_arrow`, `spell_eventwow_reincarnation`; solo las invocaciones controlables sustituyen a la
  anterior. spellgen: clave `[spell.fields]` (columnas sueltas, p. ej. `ProcChance`). Todo aplicado a mano en la BD
  de desarrollo y parche regenerado.
  **Ataque basico de los heroes (2026-11-14, SIN COMPILAR NI PROBAR)**: `docs/heroes.md` seccion 6. Casilla 1 = ataque
  ("Atacar" con arma invisible de la ficha, o disparo automatico propio `data/spells/ataques.toml` 9509020-024) y
  clic derecho (hook nuevo del core `OnPlayerCanAttackSwing`, commit `ab105ded2`). Columnas
  `eventwow_character.AutoAttackSpell/AttackMin/AttackMax/AttackPerLevel/AttackSpeed` (SQL `_09`, aplicado a mano),
  spellgen `per_level`. Parche regenerado.
  Probado por el usuario (2026-11-14): disparo de Kel'Thuzad bien; Sylvanas disparaba sin animacion con el arco
  envainado (el cliente anima segun el arma EQUIPADA en la ranura de distancia). Un emote por disparo salia
  "interrumpido" (probado 2026-11-16, descartado). Tambien corregido `UNIT_MASK_CONTROLABLE_GUARDIAN` ->
  `IsControllableGuardian()` en `EventWowHeroSpells.cpp` (error de compilacion de `ca464c0`).
  **Decision del usuario (2026-11-16): las armas de los heroes se EQUIPAN de verdad durante el disfraz** (todas:
  derecha, izquierda y distancia; excepcion a "los objetos no se equipan", que sigue valiendo para los de la tienda).
  SIN COMPILAR NI PROBAR: `EventWowWeapons::Equip/Unequip` (EquipNewItem, habilidad de arma que falte + competencia,
  doble empunadura, aura 46699 sin municion; no se pueden quitar; Update las repone), `EventWowDisguise` (dano de la
  ficha escalado a la velocidad del arma, hook `OnPlayerApplyWeaponDamage`), columna `WeaponRanged`, armas propias
  9500200 + 9500210-9500222 sin stats, dano/velocidad normales de su tipo (SQL `2026_11_16_00`, aplicado a mano en la
  BD de desarrollo junto con `eventwow_spells_ataques.sql`; parche regenerado). 9509020 recupera `USES_RANGED_SLOT`.
  Detalle y "PROBAR" en `docs/heroes.md` sec. 6.
  Probado por el usuario (2026-11-16): armas equipadas BIEN en todos los heroes (Arthas ya a dos manos, Garrosh doble
  empunadura, Kel'Thuzad). Sylvanas NO: ni dispara con el arco ni lo desenvaina, tampoco tras devolver
  `USES_RANGED_SLOT` a Multidisparo/Flecha negra/Salva. Ademas sus disparos daban "fuera de rango" a cualquier
  distancia: causa = `RangedModRange` 0 del arco (copiado de PNJ; el CLIENTE lo usa como % del alcance) -> 100 (SQL
  `_16_00` aplicado; sin probar; hace falta borrar la carpeta Cache del cliente: datos de objeto cacheados).
  Pendiente de diagnostico (el usuario tuvo que salir): `.demorph` con el disfraz puesto y disparar: si el elfo saca
  el arco y anima, el problema es el modelo de criatura (28213) y hay que buscar otra via; mirar tambien con C (modo
  dev + /eventwow) que el arco esta en la ranura de distancia. Posible relacion con el alcance 0.
  RESUELTO (probado por el usuario 2026-11-16: "lo hicimos"): el druida tenia ranura de RELIQUIA (`ChrClasses.dbc`
  Flags bit 0x08) -> arco en rojo, sin envainar ni municion. SQL `_16_01` (TODAS las habilidades de armas al druida:
  `skillraceclassinfo_dbc` + `playercreateinfo_skills` + `playercreateinfo_spell_custom`, override
  `PlayerStart.CustomSpells = 1`) y `_16_02` (druida Flags 0x0A -> 0x02, Build-Dbc `ExtraRanges` chrclasses_dbc).
  Sylvanas dispara y anima. Probado tambien (2026-11-16, "todo esta bien"): icono del disparo (icono propio en
  `ataques.toml` + `EventWowAbilities.lua` refresca iconos con PLAYER_EQUIPMENT_CHANGED, el cliente da el del arma a
  los hechizos de ranura de distancia) y la casilla del ataque basico ya no se corta al pulsarla varias veces (boton
  "macro": `/startattack` para 6603, `/cast !<nombre>` para 9509020-9509039).
  Todo lo anterior COMMITEADO (2026-11-16).
  Velocidad de ataque (2026-11-16): SOLO la agilidad EXTRA (total - base del contenedor) sube la celeridad de
  todos los ataques automaticos: % = Max x agi / (agi + Half), suelo AttackMinInterval (config
  `EventWow.Hero.AgilityHaste.Max/Half` = 1770/1000, `EventWow.Hero.AttackMinInterval` = 150 ms;
  `EventWowDisguise::UpdateAgilityHaste` cada 250 ms, se deshace en `Remove`). PROBADO por el usuario 2026-11-16 ("funciona"). Comando de prueba
  `.eventwow attackspeed set <pct> | lineal <agi> | wc3 <agi> | off` (EventWowStats.cpp). Problema encontrado: a esa
  velocidad nuestro disparo automatico cortaba las habilidades (Salva...); con el 75 no (probado). Causa: el core da
  reglas propias solo al ID 75. Cambio al core `04ab628c7` (probado: Salva ya no se corta): `SpellInfo::IsAutoShot` + `SpellMgr::SetSpellAutoShot`
  (docs/core-changes.md); `EventWowCharacters::Load` marca los `AutoAttackSpell` de las fichas. Pendiente (lo hara el usuario sin prisa): el resto de "PROBAR" en
  `docs/heroes.md` sec. 6 y probar las habilidades de los 14 heroes.
  **SIGUIENTE (decidido por el usuario 2026-11-16)**: la logica del evento del Asedio (oleadas, regiones, flujo de
  partida; ver `docs/asedio.md`).
- Mapas propios desde Warcraft 3 (ver `docs/mapas.md`). Decision del usuario: los mapas los disena el (y un amigo) en
  el World Editor de WC3 1.26 (no usa Noggit) y se convierten. Diseno PROPIO: no se replican mapas de terceros
  (p. ej. X Hero Siege); el usuario y su amigo hicieron uno inspirado en el genero.
  - `tools/mapgen` (mpq.py, wc3.py, wowfiles.py, mapgen.py, inspect_adt.py): terreno, texturas por tileset (L, N, I),
    agua, rampas, borde = muro, puntos de inicio y regiones -> coordenadas de WoW. Integrado en `Build-Patch` (escribe
    tambien el `.map` y los vmaps (vmaps.py) en `server\bin\RelWithDebInfo\data`; tras regenerar: reiniciar el
    worldserver y copiar el parche). Unidades, decoracion y objetos de WC3 se ignoran a proposito (puertas etc. iran
    como objetos del juego). Falta: sombras, musica de zona.
  - IDs de mapa 750-799 (`Build-Dbc` exporta `map_dbc` en ese rango). SQL `_10` (750) y `_11` (751) aplicados a mano en
    la BD de desarrollo para generar Map.dbc (el updater los reaplica, son idempotentes).
  - 750 `EventWowTest` (`Maps/Warcraft/test.w3m`, juego `test_map`): probado, COMMIT `28f1693`.
  - 751 `EventWowAsedio` (`Maps/Warcraft/Mi_Mapa_XHero.w3x`, tileset Corona de Hielo, 96x224 casillas -> 2x2 ADT, juego
    `asedio` (antes `test_siege_map`), inicio = punto del jugador 1). Probado por el usuario: estructura igual a su mapa. Pero los muros
    (nivel 4) parecian relieve de tierra blanca ("es una ciudad, las divisiones deberian ser muros"): anadido
    `wallLayer: 4` (caras verticales + texturas `wallTop` IC_Vrykul_PaverRubbleB / `wallFace` IG_DarkRockA) y despues
    modelos de muro (ver "Mapa del asedio" arriba).
    48 regiones renombradas por POSICION en `maps.json` `regionNames` (plano: `tools/mapgen/_work/regiones_751.png`,
    regenerable); su funcion real (oleadas, teletransportes...) la sabe el amigo.
  - Mapa 751 completo (muros, zona, minimapa, vmaps): COMMIT `e3cea56`.
  - mmaps 750/751 GENERADOS (2026-11-13; herramientas compiladas por el usuario con `TOOLS_BUILD`): desde `data\`,
    `..\mmaps_generator.exe --config ..\mmaps-config.yaml <id> < nul` (al final espera una tecla). Comprobado leyendo
    los .mmtile: las zonas comunicadas andando en el navmesh = las 16 de WC3. Repetir tras cada cambio del mapa.
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

### Decisiones tomadas (2026-11-13)
- **Muerte en partida = mecanismo en el framework, regla en cada minijuego.**
  - Sistema (`EventWowMatch`/`EventWowMatchMgr`): morir nunca saca de la partida (cortar el cementerio exterior);
    aviso `OnPlayerDied(player, killer)`; herramientas: resucitar en un punto / tras N s, bloquear "Liberar
    espiritu", espectador, eliminar (LOSE); mensajes al HUD; regla por defecto si el juego no define nada
    (reaparecer en el inicio a los ~5 s).
  - Cada juego sobrescribe `OnPlayerDied` y elige (checkpoint, sin liberar hasta fin de oleada, eliminado...).
  - Hooks del core que ya existen (verificar al implementar): `OnPlayerJustDied`, `OnPlayerCanRepopAtGraveyard`,
    `OnPlayerReleasedGhost`, `CanResurrect` -> en principio sin tocar el core.
  - Las herramientas se disenan con el primer minijuego real que necesite muertes; antes, solo la regla por defecto.
- **Reglas de EventWow solo para jugadores; en modo dev (`.gm on` o `.dev on`) = AzerothCore normal** dentro del
  mundo: muerte (cementerio original), salir de la instancia (se queda donde este), fin/abandono de partida (no se
  le lleva al lobby), estado base al entrar, cola fuera del lobby, interfaz nativa. Comprobar con
  `EventWowDevMode::IsActive(player)` en toda regla nueva. Se decide por MODO, no por cuenta: un GM sin modo dev es
  un jugador (asi prueba el producto). NO afecta a login ni reglas de cuenta (todos entran al lobby/panel,
  un personaje, raza/clase fijas; modo dev desactivado en cada login).

- **Personajes por juego (decidido con el usuario; prototipo de disfraz hecho)**: cada juego declara sus personajes
  jugables (pocos hechizos cada uno, nunca los de clase).
  - **Personaje = disfraz + vehiculo opcional** (no dos modos excluyentes): p. ej. carrera = goblin (disfraz) en una
    moto (vehiculo, pone velocidad y habilidades); arena = heroes solo con disfraz, cada uno con stats y hechizos.
  - **Fichas en BD world** (tablas `eventwow_character*`), no en C++: ajustar sin compilar. Los juegos siguen en C++.
  - **Eleccion segun el juego**: asignado (carreras: todos iguales; `GetAssignedCharacter`) o fase de seleccion
    `Picking` dentro de la partida (arenas, estilo Dota; sin implementar). Elegir en el panel antes de buscar: descartado.
  Disfraz y vehiculo, ambos aceptados:
  - **Disfraz** (por defecto): el propio personaje con morph/escala, hechizos temporales (`learnSpell(id, true)`, no se
    guardan) y **barra de habilidades propia en el HUD** (la barra nativa se guarda en `character_action`: no usarla).
  - **Vehiculo**: subirlo a una criatura-vehiculo (`creature_template`: modelo, stats, hechizos 1-8, barra nativa de
    vehiculo); para juegos de montura/maquina (p. ej. la carrera).
  - Descartados: posesion (cuerpo abandonado en el mapa); aura OVERRIDE_SPELLS (293) sin probar en el cliente.
  - Contenedor = druida (mana nativo; ira/energia con `setPowerType`, como las formas).
  - **Stats exactas por personaje**: hooks del core al final del calculo, por referencia
    (`OnPlayerAfterUpdateMaxHealth`, `OnPlayerAfterUpdateMaxPower`, `OnPlayerAfterUpdateAttackPowerAndDamage`) ->
    se fuerza el valor del personaje mientras va disfrazado; stats primarias con `HandleStatFlatModifier`
    (diferencia hasta el objetivo, se deshace al quitar); velocidad con multiplicador; dano en los hechizos
    (`SpellScript`). Al quitar: `UpdateAllStats`. Nada se guarda (las stats se recalculan al cargar).
  - Ficha prevista `EventWowCharacterInfo` (Id, Name, Description, Icon, Mode, DisplayId, Scale, VehicleEntry, Health,
    PowerType, MaxPower, Stats[5], Speed, Spells); se envia al panel por el protocolo como los juegos.
  - Hechizos: primero existentes; propios = `spell_dbc` (servidor) + `Spell.dbc` parcheado en patch-4.MPQ (cliente).
  - **Stats = formulas NATIVAS de AzerothCore** (decidido con el usuario 2026-11-13): nada de reglas de conversion
    por juego (tipo WC3 Fuerza -> vida); las bonificaciones se aplican como objetos y el motor deriva el resto.
    La "stats exactas por personaje" de arriba queda sustituida por base + bonificaciones.

### Decisiones abiertas
- Login: cuenta+contrasena (actual) vs launcher/solo nombre.
- Lobby definitivo (mapa propio, se podria hacer con tools/mapgen) - de momento Isla de los GM.
