# Protocolo cliente <-> servidor (addon messages)

Implementacion: servidor `modules/mod-miwow/src/MiWowProtocol.*`, cliente
`client/src/Interface/FrameXML/MiWowProtocol.lua`. Version actual: **13**
(`MiWowProtocol::Version` / `MIWOW_PROTOCOL.VERSION`; cambiarla en ambos lados a la vez).

## Transporte

- **Cliente -> servidor**: `SendAddonMessage("MIWOW", <flag><payload>, "WHISPER", UnitName("player"))`.
  El core lo procesa como whisper con `LANG_ADDON` a uno mismo; `Player::Whisper` llama a
  `OnPlayerCanUseChat(..., Player* receiver)`, el modulo lo consume y devuelve `false` (no se reenvia).
- **Servidor -> cliente**: paquete `SMSG_MESSAGECHAT` `CHAT_MSG_WHISPER` + `LANG_ADDON`, emisor = el propio jugador,
  texto `MIWOW\t<flag><payload>`. El cliente recibe `CHAT_MSG_ADDON("MIWOW", <flag><payload>, "WHISPER", <su nombre>)`.
- **Seguridad**: el modulo descarta cualquier addon message `MIWOW` en whisper, grupo, banda, BG y hermandad, asi que
  nunca llega uno de otro jugador. El cliente ademas solo acepta `WHISPER` con emisor = el mismo.
  El servidor valida todo lo recibido.
- Requiere `AddonChannel = 1` (fijado en `mod_miwow.conf.dist`).

## Fragmentacion

El core descarta mensajes de mas de 255 caracteres (`ChatHandler.cpp`). Cada paquete lleva un flag:

| Flag | Significado |
|---|---|
| `=` | mensaje completo |
| `+` | fragmento, siguen mas |
| `.` | ultimo fragmento |

Trozos de hasta 240 bytes, sin partir caracteres UTF-8. Los paquetes llegan en orden (un solo TCP por jugador).
El servidor limita un mensaje reensamblado del cliente a 2048 bytes (buffer en `Player::CustomData`).

## Payload

`<OP>\t<campo>\t<campo>...` - los campos no pueden contener `\t` (se sustituye por espacio al enviar).
Texto en UTF-8.

## Mensajes

### Conexion

`HELLO` lo gestiona el propio protocolo: si la version coincide, el jugador queda "conectado" (recibe los broadcasts)
y se llama a los `RegisterConnectListener` (catalogo, estado de cola). Cualquier otro
opcode recibido antes de `HELLO` se ignora. Al hacer logout se avisa a los `RegisterDisconnectListener`.

### Cliente -> servidor

| OP | Campos | Cuando | Respuesta |
|---|---|---|---|
| `HELLO` | version | primer `PLAYER_ENTERING_WORLD` de cada carga del Lua (login, `/reload`) | `WELCOME` + listeners, o `ERROR VERSION` |
| `LIST` | - | pedir el catalogo de nuevo | `GAMES` |
| `QUEUE` | id juego | "Buscar partida" (solo, o el lider por todo su grupo) | `QUEUE_STATUS` a todos los apuntados, o `ERROR` (ver "Grupos") |
| `LEAVE` | - | "Cancelar" la cola (sale todo el grupo) | `QUEUE_STATUS NONE` a todos; los demas, `ERROR QUEUE_GROUP_CANCELLED <nombre>` |
| `ABANDON` | - | "Abandonar" / "Salir" en partida | vuelta a donde estaba (entry point) y `MATCH_STATE NONE` |
| `ACCEPT` | id propuesta | "Aceptar" la partida encontrada | `MATCH_FOUND_STATUS` a todos; si es el ultimo, `MATCH_FOUND_END ACCEPTED` + partida |
| `DECLINE` | id propuesta | "Rechazar" (tambien `LEAVE`, logout o cambio de grupo con propuesta pendiente) | `MATCH_FOUND_END` a todos (ver "Partida encontrada") |
| `PARKOUR_RESTART` | - | "Reiniciar" en el parkour | vuelta a la salida, cronometro a cero: `PARKOUR_EVENT RESTART` + `PARKOUR`. v12 |
| `GUILD_INFO` | - | abrir la ventana de hermandad, o `GUILD_DIRTY` con ella abierta (como mucho 1/s) | los 8 `GUILD_*` de "Hermandad", o `ERROR GUILD_DISABLED`. v13 |
| `GUILD_BUY` | objeto | comprar en la tienda de la hermandad (como mucho 2/s). El servidor comprueba hermandad, intendente a menos de 10 m, objeto de la temporada, rango, oro y hueco | el objeto (nativo, como un vendedor) o el error (chat / error nativo de compra) + `GUILD_DIRTY`. v13 |
| `GUILD_BOARD_REOPEN` | - | al cerrar la ventana de misiones abierta desde el tablon (el core cierra el gossip al aceptar/entregar; como mucho 2/s) | si sigue a menos de 10 m de un tablon: `GUILD_BOARD_OPEN` + la info + el gossip, como al hacer clic. v13 |

### Servidor -> cliente

| OP | Campos | Significado |
|---|---|---|
| `WELCOME` | version, rango (0 jugador, 1 GM) | handshake correcto |
| `ERROR` | codigo, detalle... | textos en `MIWOW_ERROR_TEXTS` (MiWowProtocol.lua); `UNKNOWN_OP <op>` |
| `GAMES` | n, luego n x (id, icono, min, max, nombre, descripcion, jugable 0/1, grupo max, casillas, sesion abierta 0/1) | catalogo de minijuegos (no jugable = maqueta, "Proximamente"; casillas: campo de la rama main, aqui siempre 0 y el cliente lo ignora; v6. v12: sesion abierta = sin cola, el panel dice "Entrar" y se entra directo en una partida en marcha con hueco) |
| `QUEUE_STATUS` | `QUEUED` id segundos jugadores-de-la-entrada / `NONE` | estado de la cola (tambien al conectar) |
| `MATCH_FOUND` | id, id juego, segundos para aceptar, total, aceptados, tu 0/1 | partida encontrada: aceptar o rechazar (tambien al conectar si sigue pendiente) |
| `MATCH_FOUND_STATUS` | id, aceptados, total | alguien ha aceptado |
| `MATCH_FOUND_END` | id, `ACCEPTED`/`REQUEUED`/`REMOVED` | fin de la confirmacion: a la partida / de vuelta a la cola / fuera de la cola |
| `MATCH_STATE` | `NONE` / estado, id juego, segundos | partida del jugador (al conectar, en cada cambio y al salir). Estados: `LOADING` (en camino, sigue en modo mundo), `WAITING` (dentro, esperando al resto), `COUNTDOWN`, `RUNNING`, `ENDED` (resultado; luego vuelta a donde estaba). segundos = lo que queda del estado, 0 = sin tiempo |
| `MATCH_HUD` | texto | objetivo que muestra el HUD (vacio = nada) |
| `MATCH_END` | `WIN`/`LOSE`/`NONE`, texto | resultado del jugador y resumen |
| `MATCH_RESPAWN` | segundos | has muerto: reapareces en N s (0 = ya has reaparecido). Morir nunca saca de la partida |
| `RACE_INFO` | vueltas | empieza una carrera (`MiWowGameRace`, juegos `carrera` / `carrera_estelar`): al llegar a la instancia. v9 |
| `RACE` | vuelta, vueltas, posicion, corredores, ms carrera, ms vuelta actual, ms mejor vuelta, contraria 0/1, terminado 0/1 | marcador de la carrera, cada 500 ms a cada corredor; el cliente hace avanzar el reloj entre mensajes. v9 |
| `RACE_EVENT` | `LAP` vuelta ms / `FINAL_LAP` / `FELL` / `FINISH` posicion ms / `WINNER` nombre segundos / `ITEM` hechizo hueco / `HIT` hechizo / `BLOCK` / `MOUNT` | avisos: nueva vuelta, ultima vuelta, caida (vuelve al ultimo punto bueno, quieto 2 s), has llegado, alguien ha ganado (quedan N s). v9. v10: poder recogido (hasta 5 acumulados, huecos 1-5 de la barra de la moto), golpe recibido (derrape/frenado), el escudo ha parado un golpe. v11: "¡Todos a sus motos!" (cuenta atras: llegan a pie y se montan a la vez) |
| `RACE_RESULTS` | final 0/1, n, luego n x (posicion, nombre, ms total / 0 = sin terminar, ms mejor vuelta) | clasificacion: provisional cada vez que alguien llega (el cliente la muestra si ya has llegado), final al acabar (con boton "Salir" = `ABANDON`). v9 |
| `PARKOUR_INFO` | n, nombres de las n secciones | empieza el parkour (`MiWowGameParkour`, juego `parkour`, sesion abierta): al llegar a la instancia. v12 |
| `PARKOUR` | seccion 1..n, caidas, ms, estado (0 en la salida, 1 corriendo, 2 en la meta), ms mejor (0 = ninguno) | marcador personal: al cambiar algo y cada 10 s; el cliente hace avanzar el reloj si estado = 1. v12 |
| `PARKOUR_EVENT` | `CHECKPOINT` seccion / `FALL` / `FINISH` ms record 0/1 / `PLAYER_FINISH` nombre ms / `RESTART` | avisos: punto de control, caida (vuelta al ultimo punto de control), has llegado a la cima, otro jugador de la sesion ha llegado, reinicio. v12 |
| `PARKOUR_RANK` | n, luego n x (nombre, ms) | mejores tiempos de la sesion (hasta 10; se pierden al cerrarse la sesion). v12 |
| `DEV_MODE` | 0/1 | modo dev (`.gm on` o `.dev on`; se comprueba cada 250 ms). Al conectar y en cada cambio. En modo dev el cliente permite ocultar el panel (solo cliente) |

## Hermandad (temporadas, v13)

Servidor `modules/mod-miwow/src/guild/` (`MiWowGuildSeason`, `MiWowGuildScripts`, `MiWowGuildProtocol`), cliente
`MiWowGuild.lua`. La hermandad, su chat y su lista son los nativos; esto solo anade la temporada. Respuesta a
`GUILD_INFO` (en este orden; tambien se manda sola al usar el tablon o el intendente):

| OP | Campos | Significado |
|---|---|---|
| `GUILD_STATE` | en hermandad 0/1, temporada, nombre, segundos que quedan (0 = sin fin), puntos, puesto (0 = sin puntos), puntos de la siguiente ventaja (0 = ninguna), reputacion, rango, reputacion del rango, siguiente rango ("" = maximo), reputacion del siguiente, contribucion, puntos hoy, limite diario (0 = sin), segundos desde el inicio de la temporada | resumen |
| `GUILD_RANKS` | n, n x (rango, nombre, reputacion) | rangos de reputacion |
| `GUILD_PERKS` | n, n x (puntos, hechizo, desbloqueada 0/1) | ventajas (el cliente saca nombre e icono de `GetSpellInfo`) |
| `GUILD_PRIZES` | n, n x (puesto, objeto, cantidad) | premios del podio de la temporada actual |
| `GUILD_BOARD` | segundos para la rotacion diaria, semanal, n, n x (mision, tablon 0 diaria/1 semanal, titulo, puntos, reputacion, miembros, reclamada 0/1, estado 0 disponible/1 en curso/2 para entregar/3 hecha/4 bloqueada: no se completo en grupo, hay que abandonarla, nivel (-1 = el del personaje), tipo 0 individual/1 grupo/2 banda) | tablon (diarias primero) |
| `GUILD_RANKING` | puesto propio, n, n x (hermandad, puntos) | 10 primeras hermandades |
| `GUILD_MEMBERS` | n, n x (personaje, contribucion, rango) | 10 miembros que mas han aportado |
| `GUILD_VENDOR` | n, n x (objeto, nombre, rango minimo, precio en cobre, cantidad) | tienda de la hermandad esta temporada |

Avisos sin peticion: `GUILD_DIRTY` (cambiaron puntos, tablon, temporada, miembros, una mision de hermandad del
personaje o una compra; a los de esa hermandad, al personaje o a todos), `GUILD_BOARD_OPEN` (justo antes del gossip
del tablon: el cliente muestra su tablon en lugar de la lista nativa; los botones eligen las misiones del gossip con
`SelectGossipAvailableQuest/ActiveQuest` y la ventana de misiones nativa hace el resto) y `GUILD_SHOP_OPEN` (el
intendente: abrir la tienda con las compras activas).

## Chat, susurros, canales y amigos (fuera del protocolo)

Todo nativo de WoW: el panel no tiene chat ni lista de amigos (desde 2026-11-21, rama `tradicional`).

## Grupos

Grupos **nativos** del core (no van por el protocolo), con su interfaz nativa (grupo y banda). El panel solo mira
el grupo para el boton de buscar (lider, tamano: `GetNumPartyMembers`/`GetNumRaidMembers`).

Reglas (`MiWowGroups.cpp`, no en modo dev): no se invita ni se acepta en partida (`ERROR GROUP_IN_MATCH`,
`GROUP_TARGET_IN_MATCH <nombre>`); el tamano de cola lo limita `MaxPartySize` de cada juego.

Cola en grupo (`MiWowMatchMgr`): `QUEUE` del lider apunta al grupo entero como una entrada (nunca se separa).
- Requisitos: ser el lider (`QUEUE_NOT_LEADER`), juego con `MaxPartySize` > 1 (`QUEUE_SOLO_ONLY <max>`) y grupo que
  quepa (`QUEUE_GROUP_TOO_BIG <max>`), todos conectados al protocolo (`QUEUE_GROUP_OFFLINE <nombre>`), sin partida y en condiciones de
  entrar (`QUEUE_GROUP_BUSY <nombre>`; para uno mismo: `QUEUE_DEAD`, `QUEUE_IN_COMBAT`, `QUEUE_IN_FLIGHT`,
  `QUEUE_IN_INSTANCE`, `QUEUE_IN_BG_QUEUE`, ver `MiWowLobby::CanJoinFrom`; se vuelve a comprobar al teleportar).
- Sale entera de la cola si: cualquiera cancela (`QUEUE_GROUP_CANCELLED <nombre>` a los demas), se desconecta
  (`QUEUE_GROUP_LOGOUT <nombre>`) o el grupo cambia (entra/sale alguien, se disuelve: `QUEUE_GROUP_CHANGED`).
- Emparejamiento: por orden de llegada, entradas enteras que quepan en `MaxPlayers` (puede saltarse una entrada
  grande para llenar con otras mas pequenas).

### Partida encontrada (confirmacion tipo Dota 2)

Lo emparejado no va directo a la partida: es una propuesta (`MATCH_FOUND`, popup `MiWowMatchFound.lua` con
Aceptar/Rechazar y cuenta atras de `MiWow.Queue.AcceptTimeout`, 20 s).
- Todos aceptan -> `MATCH_FOUND_END ACCEPTED` y se crea la partida (`MATCH_STATE LOADING`...).
- Alguien rechaza (`DECLINE`, `LEAVE`, logout, cambio de grupo) o no acepta a tiempo -> se cancela. Las entradas
  con algun culpable salen de la cola (`REMOVED`; sus companeros de grupo reciben `ERROR QUEUE_GROUP_DECLINED <nombre>`
  / `QUEUE_GROUP_NOT_ACCEPTED` / el motivo de `LEAVE`, logout o cambio de grupo). El resto vuelve a la cola
  automaticamente con su antiguedad (`REQUEUED`) y puede emparejarse de nuevo en el siguiente segundo.
- Durante la propuesta los jugadores siguen "en cola" (`QUEUE_STATUS QUEUED`) y no pueden apuntarse a otra.
- Instancias: el core liga tambien al lider de quien entra (aunque no este en la partida); al cerrar la partida se
  quitan todos los binds de su InstanceSave (`UnbindAllFor`).

## Partidas (paso 6-7)

Servidor: `MiWowMatchMgr.*` (colas, emparejamiento, instancias), `MiWowMatch.*` (clase base de minijuego),
`games/` (minijuegos). Cliente: `MiWowMatch.lua` (HUD) + `MiWow_SetMode("world"|"match")` en `MiWow.lua`.

```
QUEUE -> QUEUE_STATUS QUEUED ... -> (emparejado) QUEUE_STATUS NONE + MATCH_STATE LOADING -> teleport
      -> (llega) MATCH_STATE WAITING -> COUNTDOWN n -> RUNNING [t] (+ MATCH_HUD) -> MATCH_END + ENDED n
      -> vuelta a donde estaba (TeleportToEntryPoint) -> MATCH_STATE NONE
```

- Errores nuevos: `QUEUE_GAME_UNAVAILABLE`, `QUEUE_IN_MATCH`, `MATCH_CREATE_FAILED`, `MATCH_TELEPORT_FAILED`.
- Salir de la instancia por otra via (liberar espiritu, teleport de GM) o hacer logout saca de la partida.
