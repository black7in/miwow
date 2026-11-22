# MiWow (repo EventWow)

Plataforma de minijuegos sobre WoW 3.3.5a (build 12340) + AzerothCore.
No hay flujo clasico (crear personaje, elegir raza/clase, mundo abierto):

```
Login -> "Tu nombre" -> Lobby -> Panel de minijuegos -> Cola (solo/grupo) -> Instancia -> Lobby
```

El personaje es solo un contenedor: nunca se ve en las pantallas previas al mundo;
en cada minijuego se le da modelo, hechizos y stats temporales.

> **Renombrado EventWow -> MiWow (2026-11-21, rama `tradicional`, decision del usuario: el servidor se llama MiWow)**:
> modulo `mod-eventwow` -> `mod-miwow` (junction `azerothcore-wotlk/modules/mod-miwow`), clases/archivos `EventWow*` ->
> `MiWow*` (C++ y Lua), `EVENTWOW_*` -> `MIWOW_*`, config `EventWow.*` / `mod_eventwow.conf` -> `MiWow.*` / `mod_miwow.conf`,
> comandos `.eventwow` / `/eventwow` -> `.miwow` / `/miwow`, prefijo del protocolo `EWOW` -> `MIWOW`, log `module.miwow`,
> SQL `*_eventwow_*` -> `*_miwow_*` (registros de `updates` renombrados a mano en la BD de desarrollo, ver
> `docs/despliegue.md`), scripts `spell_eventwow_*` -> `spell_miwow_*`. NO cambian: carpeta/repo `EventWow`, rama
> `eventwow` del core y prefijo `[EventWow]` de sus commits, directorios de mapas (`EventWowTest`, `EventWowCarrera`...),
> texturas de minimapa `eventwow_*.blp`, BD `eventwow_*` (infraestructura), IDs. El diario de abajo usa los nombres de entonces.

> **Rama `tradicional` (desde 2026-11-18)**: servidor WoW normal (razas, clases, niveles, mazmorras...) + los
> eventos. Decision del usuario: rama propia SIN interruptor de configuracion. Lo de "contenedor/lobby" de este
> documento describe `main`. Regla de oro: **nunca tocar de forma destructiva el personaje real** (objetos, oro,
> nivel, talentos, auras pasivas); lo que se cambie y se guarde en BD necesita foto + restauracion en el login.
> Plan: 1) quitar lo destructivo y lo de plataforma (servidor) | 2) cliente: Glue original, panel que se abre y
> cierra sobre la interfaz normal, `GlobalStrings` restaurado, textos de error nuevos | 3) moneda propia de partida
> (la tienda usa el oro de WoW) | ~~4) heroes~~: DESCARTADO (2026-11-21, decision del usuario): en `tradicional` se
> entra a los eventos con el personaje y equipo propios; el aumento temporal de stats (`EventWowStats`) se queda.
> Paso 1 HECHO (compilado y probado por el usuario 2026-11-21):
> - Fuera: login/teletransporte al lobby, invisibilidad, `ClearInventory` (login y estado base), nivel forzado y
>   `PLAYER_FLAGS_NO_XP_GAIN`, tutoriales, bloqueo de canales, raza/clase fijas (`EventWowCharacter.cpp` borrado,
>   `EventWow.Character.*`/`EventWow.Lobby.*` fuera), overrides de plataforma (personajes por cuenta, mascaras,
>   `StartPlayerLevel`, `AlwaysMaxSkillForLevel`, `PlayerStart.CustomSpells`, `SkipCinematics`). Quedan
>   `AddonChannel`, `Instance.UnloadDelay`, `GM.LoginState = 0`. Talentos/correo de nivel: bloqueados solo con progresion.
> - SQL del contenedor borrado (playercreateinfo, druida con todas las armas, druida sin reliquia, logout instantaneo) y
>   SQL que lo deshace: `db-world/2026_11_18_02_eventwow_tradicional_revert.sql`, `db-auth/2026_11_18_00_..._rbac.sql`
>   (aplicados a la BD de desarrollo; parche regenerado sin ChrClasses/SkillRaceClassInfo).
> - `EventWowLobby` = entrada/salida de eventos: `CanJoinFrom` (vivo, sin combate, sin vuelo, fuera de instancias, sin
>   cola de BG; errores `QUEUE_DEAD/IN_COMBAT/IN_FLIGHT/IN_INSTANCE/IN_BG_QUEUE`, tambien al teleportar),
>   `SaveReturnPoint` = `Player::SetEntryPoint` (entry point nativo de los BG, se guarda en `character_entry_point`),
>   `ReturnFromMatch` = estado base + `TeleportToEntryPoint`. Login dentro de un mapa de evento -> punto de vuelta
>   (u hogar). Estado base: `RemoveArenaAuras` + montura + forma (antes `RemoveAllAuras`, que quita pasivas).
>   Salir de la instancia por otro medio (piedra de hogar...) -> se queda alli con el estado base.
> - Juegos con `MaxLevel` (progresion) o `InventorySlots` desactivados en `Validate` (asedio, test_shop) y
>   `.eventwow hero <id> <nivel>` / `level` rechazados, hasta los pasos 3-4.
> - `mod_eventwow.conf` desplegado actualizado; el de `main` guardado en `server/mod_eventwow.conf.main.bak`.
> Paso 2 HECHO (cliente, probado por el usuario 2026-11-21):
> - Glue original (borrados `GlueXML/CharacterSelect.lua` y `CharacterCreate.lua`) y `GlobalStrings.lua` original.
> - `EventWow.lua`: modos `"world"` (interfaz nativa intacta) | `"match"` (lo de antes: marcos ocultos, ventanas y
>   acciones bloqueadas). Fuera: portada del lobby, tutoriales desactivados, CVars de nombres forzadas, menu sin Macros.
>   Modo dev en partida: boton arriba / `/eventwow dev` = interfaz nativa (`EventWow_SetNativeUI`).
> - Panel = ventana centrada 960x640 (menos si no cabe), arrastrable, Esc/X la cierra; boton en el minimapa
>   (`EventWowMinimapButton`, borde verde en cola, tooltip con la cola) y `/eventwow` o `/eventos`. Cerrada en partida.
> - Chat: el nativo funciona normal (sin ocultar, sin filtros, Intro nativo). El del panel solo trae el Global de
>   EventWow + pestanas de susurros/grupo (duplican lo nativo) y ya no copia ChatFrame1.
> - Textos de error `QUEUE_DEAD/IN_COMBAT/IN_FLIGHT/IN_INSTANCE/IN_BG_QUEUE`; "Volver/Salir al lobby" -> "Salir".
> - Pendiente: cola de evento + invitacion de BG/LFG (bloquear unas con otras), mascotas al entrar. Personajes de prueba
>   druida 80 (Test, Bla, War) BORRADOS de la BD de desarrollo (2026-11-18, a peticion del usuario).

> Limpieza blizzlike (2026-11-21, compilada y probada por el usuario: "todo esta funcionando bien"):
> - Config: fuera `Instance.UnloadDelay` (global: afectaba a todas las mazmorras) y `EventWow.Hero.*`. Las instancias
>   de partidas cerradas se descargan solas al vaciarse (`EventWowMatchMgr::UpdateClosedInstances`, `InstanceMap::Reset`).
> - Bandas permitidas (fuera el bloqueo de `CMSG_GROUP_RAID_CONVERT`); la cola sigue limitada por `MaxPartySize`.
> - Partidas SOLO en mapas propios 750-799 (`EventWowFirstMapId/LastMapId`, `Validate`); `IsEventMap` = ese rango (antes
>   recorria el catalogo: la maqueta "invasion" con MapId 0 marcaba Reinos del Este como mapa de evento). `test`,
>   `test_group`, `test_vehicle` pasan de Sima Ignea (389) al 750.
> - `EventWowRewards.cpp`: en mapas de evento no avanzan logros/criterios (estadisticas), ni XP ni reputacion.
>   Sin hook de honor/botin: criaturas de evento sin botin y sin zonas JcJ.
> - Durabilidad: `EventWowLobby::Save/Restore/ClearDurability` (foto al llegar; se devuelve al reaparecer, al salir
>   y antes del logout).
> - Heroes BORRADOS: `EventWowProgress`, `EventWowWeapons`, `EventWowInventory`, `EventWowShop`, `EventWowHeroSpells`,
>   juego `asedio` y `test_shop`, comando `.eventwow attackspeed`; ficha sin armas/ataque/atributos/Kind; disfraz sin
>   armas, celeridad (agilidad/intelecto ya no dan velocidad de ataque/lanzamiento) ni progresion (solo cambia el tipo de
>   poder si la ficha fija `MaxPower`). Comando GM `.eventwow disfraz <id>|off|list` (antes `hero`).
>   GAMES sigue mandando el campo de casillas (siempre 0, el cliente lo ignora).
> - Datos de heroes PURGADOS: borrados sus SQL (`_13_07-09`, `_14_*`, `_16_00`) y los hechizos de spellgen salvo
>   `carrera`/`parkour` (toml + SQL). `2026_11_21_00_eventwow_tradicional_sin_heroes.sql` (aplicado a la BD de
>   desarrollo) borra fichas 10-44, objetos 9500000-9500299, mercader/PNJ de eleccion/invocaciones, hechizos
>   9500000-9509999 salvo 9502xxx/9503xxx, tablas `eventwow_item`/`eventwow_character_attribute` y columnas de
>   armas/ataque/`Kind`/`PickCreature`. Quedan fichas 1, 2, 3, 50. Registros de `updates` de los
>   SQL borrados quitados a mano en la BD de desarrollo (si no: "Cleanup is disabled!" al arrancar).
> - Cliente: fuera `EventWowInventory.lua` y `EventWowStats.lua`; `EventWowAbilities.lua` sin progresion/XP/atributos/
>   ataque basico. El filtro de "Has aprendido un nuevo hechizo" solo actua en partida o disfrazado (antes, siempre).
>   Parche regenerado. `docs/heroes*.md` y `docs/asedio*.md` borrados en esta rama (siguen en `main`).
> - Fase de eleccion BORRADA (decision del usuario: el asedio, si se hace, tendra sus propios heroes): estado `Picking`,
>   `PICK`/`MATCH_PICK(S)`, `EventWowPickCreature.cpp` (`npc_eventwow_pick`), `EventWowPick.lua`, columna `PickCreature`.
>   Los juegos solo usan `GetAssignedCharacter`/`SetCharacter`.
> - DISFRAZ BORRADO (decision del usuario 2026-11-21: cada uno va con su personaje; el morph ya lo tiene el core):
>   fuera `EventWowDisguise`, `EventWowCharacters`, tablas `eventwow_character*`/`eventwow_game_character` (DROP en
>   `_21_00`; SQL `_13_01-04/06` borrados y fichas quitadas de `_13_05`, `_17_02`, `_18_00`, `_18_01`), comando
>   `.eventwow disfraz`, `MATCH_CHARACTER`, `EventWowAbilities.lua` (barra propia y filtro de "Has aprendido...").
>   Lo que hacia y sigue haciendo falta, por juego (virtuales de `EventWowMatch`):
>   - `GetVehicleEntry()` -> `EventWowVehicle` (invocar, montar con retraso, mantener montado, `Hold/Mount/DismissVehicle`):
>     carrera = 9500001, `test_vehicle` = 9500000.
>   - `BlocksPlayerSpells()` -> `EventWowSpellLock` (`OnSpellCheckCast`: sin hechizos propios ni monturas; objetos y
>     desencadenados si; no en modo dev): carrera y parkour.
>   `EventWowStats` (stats temporales, `.eventwow stat`) se queda. Se quitan en `RemovePlayer` y `RestoreBaseState`.
> - Panel = solo juegos (decision del usuario 2026-11-21: chat, susurros, amigos y grupo son los nativos): ventana
>   860x560 arrastrable sobre la interfaz normal (lista + detalle + buscar/cola). Borrados `EventWowChat.lua`,
>   `EventWowGroup.lua`, `EventWowFriends.lua`, `EventWowSocial.lua` y el chat global del servidor (`EventWowChat.cpp`,
>   `CHAT`/`ONLINE`). El boton de buscar mira el grupo nativo (grupo o banda; solo el lider).
> - Mapa 751 (asedio) SE QUEDA (decision del usuario: para futuras implementaciones) aunque no lo use ningun juego.
> - Core: rama **`tradicional`** del core = `eventwow` sin `ab105ded2`/`04ab628c7`/`b88f7bc5d` (solo los usaban los
>   heroes), revertidos en el commit `cc3c9300d`. `main` sigue usando la rama `eventwow` del core.

> **Solo se trabaja en la rama `tradicional`** (decision del usuario 2026-11-21); `main` queda parada.

> **Siguiente sesion (pedido por el usuario 2026-11-21)**: ventajas de hermandad NO pasivas (las descartadas de
> Cataclysm: resurreccion en masa, invocar al grupo, calderos/festines, vuelos mas rapidos... = hechizos que se lanzan).

> **Temporadas de hermandad (2026-11-21, compilado y probado por el usuario)**: traido de `mod-guild-season` (repo
> `newserver-wotlk`, solo lectura) a `modules/mod-miwow/src/guild/`, decision del usuario: sin tocar esquemas ni el core.
> - Definiciones en world (`db-world/2026_11_21_01_miwow_guild.sql`): `miwow_guild_quest` (sustituye a las columnas de
>   `quest_template_addon` y al tipo de mision del core), `_perk`, `_rank`, `_vendor`, `_season`, `_prize`. Estado en
>   characters (`db-characters/2026_11_21_00`): `miwow_guild_state/progress/member/claim/board/vendor_active/history`
>   (sustituye a las columnas de `guild`/`guild_member`). Config `MiWow.Guild.*`.
> - Disenos del original (leerlos antes de tocar esto): `mod-guild-season/doc/GUILD_SEASON_SYSTEM.md`,
>   `AIO_FRONTEND_INSTRUCTIONS.md` (las 4 ventanas) y `QUEST_GUILD_TYPE.md` (misiones). Decisiones del usuario sobre ellos:
>   la ventana sigue las instrucciones (se puede mejorar); el TABLON es un objeto (no un PNJ) que da y recoge las misiones;
>   `QuestSortID = -400` solo pone las misiones en la categoria "Hermandad" del registro (`questsort_dbc` 400, al cliente
>   con `Build-Dbc`); la de hermandad la marca `miwow_guild_quest`. Puntos: individual = en cada entrega (pocos); de grupo
>   = solo la primera entrega de la hermandad mientras sigue en el tablon (mas); reputacion siempre, a cada uno.
> - Tablon = objeto 9500200 (`go_miwow_guild_board`, copia del "Wanted Board" 2713, `.gobject add`): relaciones de
>   misiones EN MEMORIA (`GetGOQuestRelationMap`; rotan con el reinicio diario/semanal del servidor), recoge todas las de
>   hermandad. Manda `GUILD_BOARD_OPEN` + la info y luego el gossip: el cliente pone su tablon en lugar de la lista nativa.
>   Intendente 9500201 (`npc_miwow_guild_vendor`, `.npc add`): abre la tienda PROPIA (`GUILD_BUY`, `Price` en cobre o el
>   del objeto; a menos de 10 m del intendente). Cambios a las listas del tablon solo en el hilo del mundo (`Update`; los
>   comandos dejan peticion). El heraldo PNJ 9500200 de antes se borra (su spawn de la BD de desarrollo pasado a objeto).
> - Decision del usuario: mision de hermandad = el requisito se mira al COMPLETARLA (objetivos cumplidos, p. ej. al morir
>   el jefe; NO al entregarla): hermandad y, si es de grupo (`RequiredMembers` N > 0), ir en grupo/banda con N miembros
>   de la hermandad conectados (contando al personaje; como el original, sin mirar el mapa). Si no, simplemente
>   no se completa (sin estado "Fallida"), via `OnPlayerBeforeQuestComplete`; queda bloqueada
>   (`miwow_guild_quest_block`) hasta abandonarla/reaceptarla, porque con los objetivos llenos el core no vuelve a
>   intentarlo salvo al entregar (y entonces bastaria con agruparse para entregarla). Ventajas = hechizos PASIVOS aprendidos (libro, como los raciales; sin icono de beneficio; decision del usuario
>   2026-11-21), revisados al conectar y cada 3 s (`RefreshPerks`; al conectar `RemoveStalePerkSpells` olvida los 9504000-9504099 que ya no estan en `miwow_guild_perk` o con el sistema desactivado), en TODAS partes (eventos y BG/arenas incluidos). Expulsado desconectado
>   -> se pone al dia en su login (`SyncMember`). Cerrojo `MiWowGuildSeason::GetLock()` (MapUpdate.Threads > 1).
> - Corregido respecto al original: `lock` sin comillas (palabra reservada), puntos de misiones fuera del tablon,
>   limite diario que se reiniciaba al reconectar, expulsion desconectado, ventajas pegadas a desconectados tras el cambio
>   de temporada, rango del vendedor sin aplicar.
> - Cliente `MiWowGuild.lua` (protocolo v13, `GUILD_*` en `docs/protocolo.md`): ventana 720x560 con las 4 superficies
>   de las instrucciones como pestanas: Tablon (diarias/semanales con su reinicio, RECLAMADA/DISPONIBLE, boton por
>   mision -> ventana de misiones nativa y vuelta al tablon), Hermandad (puntos, ventajas, premios del podio, ranking
>   interno + clasificacion), Reputacion (estrellas, progreso, cadena de tramos), Tienda (disponibles / con candado,
>   confirmacion). Sin hermandad no se abre. Pestana lateral en la ventana de hermandad nativa, `/temporada`,
>   `/miwow hermandad`. GM: `.miwow guild info|points|rep|rotate [daily|weekly]|endseason`.
> - Ventajas (decision del usuario: "disenalas tu", mas que las 5 del original, copiando a Cataclysm): 15 hechizos propios
>   `data/spells/hermandad.toml` (9504000-9504014, pasivos, se guardan en `character_spell`) + `miwow_guild_perk`
>   (`Effect` = grupo de rangos: solo se sabe el mas alto). Nativas por aura: montura
>   (172), experiencia (200 + 291), reputacion (156), honor (281). Del modulo (aura DUMMY, valor = efecto 1 del hechizo):
>   oro extra al banco de la hermandad (`OnPlayerBeforeLootMoney` + `Guild::ModifyBankMoney`), piedra de hogar -15 min
>   (`ModifySpellCooldown` cada 3 s), reparar -10 %, vendedores -5 %, +50 % al resucitar, correo instantaneo
>   (`MailScript`, hermandad de la cache de personajes), punto extra de profesion. Umbrales 2.500-150.000 PTH.
>   Descartadas de Cataclysm: resurreccion en masa, invocar al grupo, calderos/festines, vuelos mas rapidos.
> - CONTENIDO DE PRUEBA en el SQL world: misiones 9500000-9500003 (sin objetivos, QuestSortID -400),
>   premios (bolsas) y tienda (5 bolsas/tabardo).

> **Cliente web y movil (2026-11-21, decision del usuario: integrarlo en el proyecto)**: cliente 3.3.5a en wasm de Last
> Havens (permiso verbal, sin fuentes) + nuestro backend, todo traido de `D:\EmulacionWow\ExplorandoCliente` a `web/`
> (esa carpeta ya NO se usa; su `token-cloudflareR2.txt` NUNCA se lee ni se copia). Documentacion: `docs/cliente-web.md`.
> - `web/cliente/` (binarios suyos) y `web/referencia/` (APK, Lua extraido) no versionados. `extraer-lua.js` vuelca su Lua.
>   Deploy en `web/deploy/` (R2, tunel, VPS, Worker).
> - **Regla del usuario: el cliente web = el de PC.** Glue ORIGINAL en ambos y nada de Last Havens a la vista;
>   lo nuestro (login propio futuro incluido) va en `patch-4.MPQ`, que cargan los dos. `parchear.js` desactiva su login,
>   seleccion/creacion tactiles, catalogo de addons, FAQ, encuestas, creadores, "Go in now", canal world, Discord
>   (`do return end` en la primera sentencia del tramo). SIN PROBAR en el navegador (2026-11-21).
> - **VPS de pruebas** (`ssh MiWow`, sudo; `docs/despliegue-vps-pruebas.md`): Apache + certbot, web Astro en
>   `miwow.duckdns.org`, cliente web en `https://juego.miwow.duckdns.org/play` (`miwow-juego.service`, `/opt/miwow-juego`,
>   MPQ del disco, sin R2), publicar con `web\deploy\publicar-vps.ps1 [-Parche]`. COMPARTIDO con `wow-arcano.com` y SU
>   AzerothCore (3724/8085): no tocarlos. NUESTRO CORE DESPLEGADO (2026-11-21, seccion 8 del doc): `/opt/miwow-core`,
>   servicios `miwow-auth`/`miwow-world` en 3725/8086, BD `miwow_auth/characters/world` con el usuario de la web
>   `miwow_web` (sin permisos ya sobre `acore_*`; la web Astro lee nuestras BD), comandos GM por SOAP 127.0.0.1:7879
>   (cuenta GM `black`), realmlist PC `144.126.158.141:3725`, cliente Frostbound esES + nuestro `patch-4.MPQ`, sin
>   basicAuth. Repos GitHub publicos: `black7in/miwow` (este) y `black7in/miwow-azerothcore` (core, rama `tradicional`).
>   El usuario lo probo en el navegador: llega al reino; "hay mucho por mejorar en el cliente" (siguiente trabajo).
>   Pendiente: mmaps v19 -> regenerar con el generador actual; arreglo clang de `MiWowGuildSeason.cpp` sin commitear
>   (copiado a mano al VPS); pagina `/[lang]/play` de Astro.
> - El wasm carga interfaz modificada (`signature check OFF`). Solo lee MPQ EMPAQUETADOS (la carpeta `patch-4.MPQ` no:
>   comprobado por el usuario; lo empaqueta el a mano). El tamano del MPQ debe cambiar en cada version (cache por tamano).
> - Su Lua tactil va incrustado (no sale de `FrameXML.toc`: convive con el nuestro) y solo actua con `webTouch`/mando;
>   en tactil toca `VehicleMenuBar`, barras, `UIParent:SetScale`... -> pendiente adaptar `MiWow.lua` (modo partida) y
>   las ventanas al modo tactil. Pendiente: primera prueba de nuestro parche en el navegador, Warden, texturas TouchUI.

## Estructura

```
EventWow/                     repo (la carpeta conserva el nombre antiguo; el servidor es MiWow)
  CLAUDE.md
  azerothcore-wotlk/          fork de AzerothCore (repo git aparte, rama eventwow) - ver docs/core-changes.md
  server/                     build de CMake/Visual Studio (no versionado)
  client/
    interface-original/       Interface esES consolidada del cliente. SOLO LECTURA, nunca editar.
      manifest.csv            de que MPQ sale cada archivo
    src/                      archivos de cliente que modificamos/anadimos (misma ruta relativa)
    patches/patch-4.MPQ/      salida generada por Build-Patch (carpeta, no MPQ empaquetado)
  modules/mod-miwow/       nuestro modulo C++. azerothcore-wotlk/modules/mod-miwow es un JUNCTION a esta carpeta
                              (no una copia): editar solo aqui. Recrear si falta:
                              New-Item -ItemType Junction -Path azerothcore-wotlk\modules\mod-miwow -Target modules\mod-miwow
    conf/mod_miwow.conf.dist   opciones propias + OVERRIDES DEL CORE (pisan worldserver.conf)
    src/                          scripts (loader: Addmod_miwowScripts)
    data/sql/db-{world,characters,auth}/   SQL que el updater de AC aplica al arrancar
  docs/
    despliegue.md             checklist de infraestructura por entorno
    core-changes.md           registro de cambios al core + procedimiento de rebase
    protocolo.md              protocolo cliente<->servidor (addon messages): transporte, fragmentacion, mensajes
    mapas.md                  mapas propios desde Warcraft 3: flujo, conversion, rango de IDs 750-799
  Maps/
    maps.json                 lista de mapas propios (id, carpeta, mapa de WC3 fuente, escala)
    Warcraft/                 mapas de Warcraft 3 (fuente, los hace el usuario en el World Editor 1.26)
  web/                        cliente web/movil (wasm de Last Havens) + server.js + Worker/R2/VPS - ver docs/cliente-web.md
  tools/
    Merge-Interface.ps1       consolida Interface de los MPQ extraidos respetando el orden de carga
    Build-Patch.ps1           copia client/src -> client/patches/patch-4.MPQ (+ DBC con Build-Dbc.ps1 + mapas con mapgen)
                              y lo empaqueta (mpqpack.py) en client/patches/web/patch-4.MPQ para el cliente web
    mpqpack.py                carpeta -> MPQ v0 (zlib, listfile; el tamano cambia en cada version)
    Build-Dbc.ps1             DBC del cliente = client/DBCs/DBC<locale> + filas MiWow de las tablas *_dbc de la BD world
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
  Para eso usa `client/patches/Instalar-Parche.ps1` (copia el parche + borra `Cache`; no versionado): SOLO lo ejecuta el usuario.
- `Data\patch-4.MPQ` (carpeta con ese nombre) tiene prioridad sobre los MPQ de locale; no usar `patch-esES-N`.
- Los archivos originales usan **CRLF**: normalizar tras editar (`sed -i 's/\r$//; s/$/\r/' archivo`).
- Preferir ganchos en Lua sobre editar XML. Toda linea anadida a una funcion original lleva `-- MiWow`;
  la logica propia va en un bloque `MiWow` al final del archivo.
- Para interceptar funciones globales de otros archivos, envolverlas (wrap) desde un archivo que cargue
  despues segun `GlueXML.toc` / `FrameXML.toc`, en vez de copiar el archivo original.
- No hay interprete Lua instalado: revisar sintaxis a mano. Errores en cliente: `SET scriptErrors "1"`.
- **DBC** (objetos, hechizos... propios): fuente de verdad = tablas `*_dbc` de AzerothCore en la BD world (SQL del
  modulo). El servidor las fusiona con sus DBC al arrancar: sus archivos DBC (ingles) NO se tocan. El cliente recibe
  el DBC original de `client/DBCs/DBCesES` (no versionado; `DBCenEN` = ingles, para un parche futuro) + nuestras filas
  (ID >= 9500000) en `patch-4.MPQ/DBFilesClient`: lo hace `Build-Patch` (necesita la BD arrancada; `-SkipDbc` sin ella).
  Objetos: `item_dbc` se rellena DESDE `item_template` en el SQL (con `DBC.EnforceItemAttributes = 1` deben coincidir).
- **Parche listo ANTES de arrancar**: Claude SIEMPRE regenera el parche tras cambios de cliente. Si cambio SQL del
  modulo que afecta a DBC (`*_dbc`), Claude lo aplica el mismo a la BD de desarrollo antes de `Build-Patch` (el updater
  lo reaplica al arrancar: SQL idempotente). Nunca pedir al usuario que aplique SQL a mano.

### Servidor (AzerothCore)
- No modificar el core si se puede evitar: todo en modulos (`mod-miwow`), hooks de ScriptMgr.
- Seguir `azerothcore-wotlk/AGENTS.md` y `.agents/docs/cpp-guidelines.md` / `sql-guidelines.md`
  (Allman, 4 espacios, LF, `LOG_*` con `{}`, `sConfigMgr->GetOption` solo al cargar config, guardar `ObjectGuid` no punteros).
- **No compilar ni correr CMake**: lo hace el usuario.
- El servidor es la fuente de verdad: validar/forzar todo lo que el cliente pueda falsear (raza, clase, nombre...).

### Versionado (git)
- **Dos repos**: `EventWow` (este, carpeta con el nombre antiguo: modulo, cliente, tools, docs; rama `main`) y `azerothcore-wotlk/` (fork del core).
  Ambos solo en local por ahora; el remoto privado se anade despues.
- Ignorados en MiWow: `azerothcore-wotlk/`, `server/` (build de CMake/VS), `client/interface-original/`
  (Blizzard, regenerable), `client/patches/` (generado), `*.conf` (solo se versionan `.conf.dist`).
- Core: remoto `upstream` = AzerothCore oficial (push deshabilitado). `master` = espejo de upstream, nunca se commitea.
  Trabajo en la rama **`eventwow`**; actualizar = `rebase` sobre `master`.
- Tocar el core: hook existente > hook nuevo (generico, patron de AC) > edicion directa marcada `// MiWow:`.
  Un commit por cambio, prefijo `[EventWow]`. Registrar cada uno en `docs/core-changes.md` (y la version base probada).
- Commits en ambos repos con el trailer de atribucion de Claude.

### Configuracion (para poder reproducir produccion)
- **Juego** (igual en todos los entornos): en `mod_miwow.conf.dist`. Las claves del core van en la seccion
  "OVERRIDES DEL CORE", cada una con su motivo. Funciona porque AC carga `configs/modules/*.conf` despues de
  `worldserver.conf` y la ultima clave gana (`Config.cpp` AddKey; `Main.cpp` LoadAppConfigs -> LoadModulesConfigs ->
  SetInitialWorldSettings). No afecta a authserver ni a lo leido antes de cargar modulos (BD, logs, DataDir).
- **Infraestructura** (BD, IPs, puertos, rutas, `acore_auth.realmlist`): nunca en el modulo; documentar en `docs/despliegue.md`.
- **Datos de BD**: SQL en `modules/mod-miwow/data/sql/db-*/` (nunca en `azerothcore-wotlk/data/sql/`),
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
       = "%s": el subtitulo de un vehiculo sin nombre muestra solo el nombre del conductor, entre < > (lo pone el motor); probado y aceptado por ahora.
       2026-11-18 (SIN PROBAR): las tres cadenas = "" a peticion del usuario (el nombre del jugador ya se ve); comprobar
       que no sale "<>" vacio. Mejora posible: entrada de vehiculo por jugador con su nombre (fragil, descartada de momento)).
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
- Asedio (juego `asedio`): solo en `main` (pausado 2026-11-17, `docs/asedio-estado.md` de `main`). En
  `tradicional` borrado el juego; el mapa 751 se queda (sin juego). Queda tambien `tools/spellgen` (hechizos propios, `docs/hechizos.md`), que usan carrera y parkour.
- **Carrera (evento actual, desde 2026-11-17)**. Decisiones del usuario: circuito cerrado con vueltas (tipo Mario
  Kart, varios ambientes), en moto (vehiculo), 1-8 jugadores, objetos/poderes MAS ADELANTE. Mapas de circuito
  generados SIN Warcraft 3 desde un plano JSON (`tools/mapgen/trackgen.py`, ver "Circuitos" en `docs/mapas.md`; el
  usuario lo pidio tras comprobar que no existe un MCP para Noggit).
  - Mapa 752 "Circuito de las Cuatro Tierras" (`Maps/Planos/circuito_cuatro_tierras.json`, SQL `2026_11_17_00`,
    aplicado en la BD de desarrollo). PROBADO por el usuario 2026-11-17 ("esta super"; algunas rocas flotan un poco).
  - Mapa 753 "Circuito Estelar" (PROBADO por el usuario 2026-11-17; el usuario eligio la pieza de la Plaga
    `SC_Platform2`, "C es el unico decente"): pista en el espacio sin barandillas. Sin terreno (ADT todo agujeros,
    tambien en el `.map` del servidor) + piezas M2 encadenadas como decoracion del ADT (colision en cliente y vmaps;
    inclinadas en subidas con MDDF rot[0]/rot[2]) - `tools/mapgen/platformgen.py`, plano `"type": "platforms"`
    (`Maps/Planos/circuito_estelar.json`; cambiar de pieza = `model`/`scale`). Cielo = luz global propia (`light_dbc`
    2600-2699, copia de la del Ojo de la Eternidad: estrellas). 3516 yardas, ocho con CRUCE (el segundo paso va 21 yd
    por debajo del primero: el juego debe usar tambien la z para saber en que tramo esta el jugador). Caer: el core
    mata por debajo de z -500 (pista a -380..-326). SQL `2026_11_17_01`.
  - Juego de carreras FASE 1 (decisiones del usuario 2026-11-17: moto a 28 yd/s, al acabar resultados en pantalla +
    boton "Salir al lobby", nadie se mueve tras terminar). PRIMERA PRUEBA (2026-11-17, 753, 2 jugadores): la vuelta se
    quedaba en 1 y las posiciones no cambiaban. Arreglado y PROBADO por el usuario (2026-11-17, "ahora si funciona"):
    2 vueltas, cuenta atras 10 s, sin `TeleportVehicle` (baja al jugador y lo resube por clic y descoloca el control
    de la moto) -> `EventWowMatch::GetArrivalPosition` (cada piloto llega a su puesto y la moto se invoca alli), caidas
    = quitar moto (`EventWowDisguise::DismissVehicle`) + mover jugador + moto nueva; seguimiento con la posicion de la
    moto; raiz solo en la moto (al jugador montado el core no deja quitarsela).
    Descripcion original (3 vueltas,
    al acabar resultados en pantalla + boton "Salir al lobby", nadie se mueve tras terminar):
    - `games/EventWowGameRace.cpp`: juegos `carrera` (752) y `carrera_estelar` (753), 1-8 pilotos. Lee
      `<DataDir>/maps/<id>_pista.json` al arrancar (sin el, el juego sale "no disponible"). Seguimiento por ventana
      alrededor de la muestra anterior (3D: cruces) -> avance, vueltas, posiciones, direccion contraria. Parrilla de 8
      (ahora por GetArrivalPosition), motos con raiz (UNIT_STATE_ROOT en el vehiculo) en carga/cuenta atras (10 s)/
      tras llegar/resultado; con moto nueva la raiz se reenvia a los 500 ms. Caer (z < suelo - FallDepth) o salirse (borde +
      OffTrackMargin) -> ultimo punto bueno, quieto 2 s. Primero en llegar -> 30 s para el resto. Resultado 90 s
      (`GetEndDelay`). Framework: `EventWowMatch::OnTick` (todos los estados) y `GetEndDelay`.
    - SQL `2026_11_17_02`: moto 9500001 (Chopper a speed_run 4, sin hechizos), personaje 3 "Piloto". Protocolo v9
      (`RACE_INFO/RACE/RACE_EVENT/RACE_RESULTS`), cliente `EventWowRace.lua`. Maqueta "race" quitada del panel.
    - Meta decorada: 752 arco del Torneo Argenta x7 (colision solo en los pilares, abertura ~27 yd) + estandartes +
      banderines en los controles (props `at`/`side: center` en trackgen); 753 arco tecnologico draenei (sin
      colision) + pilones en los controles (props de platformgen).
    - FASE 2 poderes (PROBADA por el usuario 2026-11-18, incluido: `Powers` hasta 5 en los huecos 1-5 de la barra;
      cajas/manchas por el TRAMO recorrido entre dos posiciones (el cliente avisa ~cada 0,5 s yendo recto = ~14 yd de
      salto); Escudo sin mecanica (la base 17 tenia SHIELD y los vehiculos mecanicos son inmunes). Diseno: filas de 4
      cajas cada 180 yd (desde 150 yd hasta 80 yd antes de la meta; 752: 56 cajas, 753: 76), reaparecen a los 4 s.
      Poder al azar ponderado por posicion (`PowerWeights`) en `m_spells[0..4]` de la moto + `VehicleSpellInitialize`
      (teclas 1-5; con 5 la caja se queda); se conservan si la moto cambia (caida). Hechizos `data/spells/carrera.toml` (9502000-9502012):
      Cohete (al de delante, o al de detras si va primero; proyectil 9502010 UNIT_TARGET_ANY + script), Turbo (+60 %
      3 s), Mancha de aceite (criatura 9500011 detras, 40 s), Escudo (10 s, para el siguiente golpe), Rayo (frena -50 %
      4 s a todos los de delante). Golpes = la moto golpeada se lanza el efecto a si misma (Derrape 9502011 aturdir
      1,5 s / Electrocutado 9502012): sin hostilidad, alcanza tambien al mismo grupo. Scripts
      `spell_eventwow_race_power` / `_missile` en `EventWowGameRace.cpp`. Caja = criatura 9500010 (CrateCreatureBasic).
      SQL `2026_11_17_03` + `eventwow_spells_carrera.sql` (aplicados a la BD de desarrollo). Protocolo v10
      (`RACE_EVENT ITEM/HIT/BLOCK`). Para combates de verdad entre jugadores (otros eventos): zona con
      `AREA_FLAG_ARENA` (0x80) en `areatable_dbc` = todos contra todos nativo (salvo mismo grupo: el core lo comprueba antes).
    - Placas de aceleracion (2026-11-18; el efecto funciona, probado por el usuario): el juego las coloca solo
      (`FindBoostPads`): a la salida de cada curva que gire >= 50 grados, por el lado de dentro, lejos de las cajas y
      >= 100 yd entre si; tramos de > 500 yd sin placa se rellenan (una cada ~400 yd, lado alterno). Simulado: 752 = 10
      placas, 753 = 9. Hechizo 9502013 Aceleron (+40 % 1,5 s, base Turbo; la velocidad usa la mayor aura, no se suman).
      Sin mensaje de protocolo. Criatura 9500012: la runa G_RuneGroundBlue01 (27879) NO se veia (animaciones de goober);
      cambiada SIN PROBAR a la plataforma de teletransporte de Ulduar (31853, escala 1,8: a 0,6 se veia diminuta; radio de recogida 5 yd). SQL `2026_11_18_00`
      (aplicado a la BD de desarrollo). Mismo SQL: Piloto = gnomo (display 5436; probado) e icono arreglado.
    - Salida: la moto se invoca a ras de suelo (`SummonVehicle`, `GetMapHeight` hasta 5 yd por debajo): PROBADO, ya no
      queda en el aire. Aviso "HandleSetActiveMoverOpcode: incorrect mover guid": el disfraz montaba al jugador en
      `Map::AddPlayerToMap` con el cliente aun cargando (al terminar reclama el control de su personaje).
      Montarle 1,5 s despues desde `EventWowDisguise::Update` NO funciono (2 pruebas; en la segunda ni siquiera llego a
      intentarlo: ninguna linea de `BoardVehicle` en el log; causa sin averiguar -> el retraso por defecto de `Apply`
      (`VehicleEnterDelay`) puede dejar SIN vehiculo a otros juegos con vehiculo, p. ej. `test_vehicle`).
      Decision del usuario (2026-11-18, PROBADO: "mucho mejor"): por etapas. Llegan a pie a su puesto (`HoldVehicle` en
      `OnPlayerArrived`); a los 3 s de la cuenta atras `MountAll`: aviso "¡Todos a sus motos!" (protocolo v11,
      `RACE_EVENT MOUNT`, sonido) + `EventWowDisguise::MountVehicle` (invoca la moto en su puesto y le sube; log
      "a su moto (puesto N): montado/NO montado" y, si falla, el `SpellCastResult` de `BoardVehicle`). Si la cuenta
      atras no llega a ese momento, `OnStart` monta a todos.
    - PENDIENTE (proxima sesion, el usuario da el evento casi por terminado): caidas. Al caerse de la plataforma
      (visto en el 753) deberia volver a la pista a los pocos segundos y no lo hace. Logica actual: `Track` -> `Fell`
      si z < suelo de la muestra - `FallDepth` (753: 10 yd) o lateral > media anchura + `OffTrackMargin`; revisar
      con la moto cayendo (posicion del vehiculo, ventana de busqueda, `Frozen`).
    - Despues (sin fecha): placas con otro modelo (el usuario buscara uno, quiza flechas propias); fase 3 trampas;
      fase 4 modo "carrera de la muerte"; montaje con retraso desde `Update` sin resolver (ver arriba).
- **Parkour (juego `parkour`, mapa 754 "Ascenso"): PAUSADO el 2026-11-18**. Estado completo, decisiones, historial
  de pruebas y pendientes en **`docs/parkour-estado.md`** (leerlo al reanudar). Resumen: sesion siempre abierta
  (sin cola, "Entrar"; `EventWowGameInfo::OpenSession`), cielo e islas de Nagrand, ruta generada por
  `tools/mapgen/parkourgen.py` con tramos (subidas de sillas, bajadas, zigzag, callejones sin salida). El escenario
  gusta; la ruta la ultima vez fue "regular" (preguntar que mejorar). Falta: interactivos, efectos, ranking guardado.
  Herramientas reutilizables: `tools/mapgen/catalog.py` (cara pisable de los M2) y WMO en los ADT (MODF, solo cliente).
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
  - 751 `EventWowAsedio` (`Maps/Warcraft/Mi_Mapa_XHero.w3x`, Corona de Hielo, muros con modelos; detalle en
    `docs/asedio-estado.md` de `main`). En `tradicional` sin juego que lo use.
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
- Ninguna. DESCARTADAS por el usuario (2026-11-21): login por launcher/solo nombre (se queda cuenta+contrasena) y
  lobby definitivo (en `tradicional` no hay lobby).
