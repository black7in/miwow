# Protocolo cliente <-> servidor (addon messages)

Implementacion: servidor `modules/mod-eventwow/src/EventWowProtocol.*`, cliente
`client/src/Interface/FrameXML/EventWowProtocol.lua`. Version actual: **3**
(`EventWowProtocol::Version` / `EVENTWOW_PROTOCOL.VERSION`; cambiarla en ambos lados a la vez).

## Transporte

- **Cliente -> servidor**: `SendAddonMessage("EWOW", <flag><payload>, "WHISPER", UnitName("player"))`.
  El core lo procesa como whisper con `LANG_ADDON` a uno mismo; `Player::Whisper` llama a
  `OnPlayerCanUseChat(..., Player* receiver)`, el modulo lo consume y devuelve `false` (no se reenvia).
- **Servidor -> cliente**: paquete `SMSG_MESSAGECHAT` `CHAT_MSG_WHISPER` + `LANG_ADDON`, emisor = el propio jugador,
  texto `EWOW\t<flag><payload>`. El cliente recibe `CHAT_MSG_ADDON("EWOW", <flag><payload>, "WHISPER", <su nombre>)`.
- **Seguridad**: el modulo descarta cualquier addon message `EWOW` en whisper, grupo, banda, BG y hermandad, asi que
  nunca llega uno de otro jugador. El cliente ademas solo acepta `WHISPER` con emisor = el mismo.
  El servidor valida todo lo recibido.
- Requiere `AddonChannel = 1` (fijado en `mod_eventwow.conf.dist`).

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
y se llama a los `RegisterConnectListener` (catalogo, historial de chat, `ONLINE`, estado de cola). Cualquier otro
opcode recibido antes de `HELLO` se ignora. Al hacer logout se avisa a los `RegisterDisconnectListener`.

### Cliente -> servidor

| OP | Campos | Cuando | Respuesta |
|---|---|---|---|
| `HELLO` | version | primer `PLAYER_ENTERING_WORLD` de cada carga del Lua (login, `/reload`) | `WELCOME` + listeners, o `ERROR VERSION` |
| `LIST` | - | pedir el catalogo de nuevo | `GAMES` |
| `CHAT` | texto | chat global (max 200 caracteres; rafaga 3, luego 1 por segundo) | `CHAT` a todos, o `ERROR MUTED/CHAT_RATE/CHAT_TOO_LONG` |
| `QUEUE` | id juego | "Buscar partida" (solo, o el lider por todo su grupo) | `QUEUE_STATUS` a todos los apuntados, o `ERROR` (ver "Grupos") |
| `LEAVE` | - | "Cancelar" la cola (sale todo el grupo) | `QUEUE_STATUS NONE` a todos; los demas, `ERROR QUEUE_GROUP_CANCELLED <nombre>` |
| `ABANDON` | - | "Abandonar" / "Volver al lobby" en partida | vuelta al lobby y `MATCH_STATE NONE` |
| `ACCEPT` | id propuesta | "Aceptar" la partida encontrada | `MATCH_FOUND_STATUS` a todos; si es el ultimo, `MATCH_FOUND_END ACCEPTED` + partida |
| `DECLINE` | id propuesta | "Rechazar" (tambien `LEAVE`, logout o cambio de grupo con propuesta pendiente) | `MATCH_FOUND_END` a todos (ver "Partida encontrada") |

### Servidor -> cliente

| OP | Campos | Significado |
|---|---|---|
| `WELCOME` | version, rango (0 jugador, 1 GM) | handshake correcto |
| `ERROR` | codigo, detalle... | textos en `EVENTWOW_ERROR_TEXTS` (EventWowProtocol.lua); `UNKNOWN_OP <op>` |
| `GAMES` | n, luego n x (id, icono, min, max, nombre, descripcion, jugable 0/1, grupo max) | catalogo de minijuegos (no jugable = maqueta, "Proximamente") |
| `CHAT` | unix time, rango, nombre, texto | chat global; al conectar llegan los ultimos 50 (historial) |
| `ONLINE` | n | jugadores conectados (cada vez que alguien conecta/desconecta) |
| `QUEUE_STATUS` | `QUEUED` id segundos jugadores-de-la-entrada / `NONE` | estado de la cola (tambien al conectar) |
| `MATCH_FOUND` | id, id juego, segundos para aceptar, total, aceptados, tu 0/1 | partida encontrada: aceptar o rechazar (tambien al conectar si sigue pendiente) |
| `MATCH_FOUND_STATUS` | id, aceptados, total | alguien ha aceptado |
| `MATCH_FOUND_END` | id, `ACCEPTED`/`REQUEUED`/`REMOVED` | fin de la confirmacion: a la partida / de vuelta a la cola / fuera de la cola |
| `MATCH_STATE` | `NONE` / estado, id juego, segundos | partida del jugador (al conectar, en cada cambio y al volver al lobby). Estados: `LOADING` (en camino, sigue en modo lobby), `WAITING` (dentro, esperando al resto), `COUNTDOWN`, `RUNNING`, `ENDED` (resultado; luego vuelta al lobby). segundos = lo que queda del estado, 0 = sin tiempo |
| `MATCH_HUD` | texto | objetivo que muestra el HUD (vacio = nada) |
| `MATCH_END` | `WIN`/`LOSE`/`NONE`, texto | resultado del jugador y resumen |
| `MATCH_RESPAWN` | segundos | has muerto: reapareces en N s (0 = ya has reaparecido). Morir nunca saca de la partida |
| `DEV_MODE` | 0/1 | modo dev (`.gm on` o `.dev on`; se comprueba cada 250 ms). Al conectar y en cada cambio. En modo dev el cliente permite ocultar el panel (solo cliente) |

## Susurros y canales (fuera del protocolo)

- Los susurros son los nativos del core (`SendChatMessage(..., "WHISPER")`, eventos `CHAT_MSG_WHISPER/_INFORM/AFK/DND`):
  el cliente los muestra en una pestana por conversacion del chat del panel (filtrados del chat nativo).
- Canales (General, Comercio...): no existen. `EventWowChat.cpp` descarta `CMSG_JOIN_CHANNEL` salvo en modo dev
  y al salir del modo dev se abandonan todos (`CleanupChannels`). El cliente filtra `CHAT_MSG_CHANNEL*`.

## Grupos

Grupos **nativos** del core (no van por el protocolo): el panel (`EventWowGroup.lua`) usa `InviteUnit`, `UninviteUnit`,
`PromoteToLeader`, `LeaveParty` y los eventos `PARTY_*`; la invitacion es el dialogo nativo. Alt+clic en un nombre
del chat invita. El chat de grupo va a la pestana "Grupo" del chat (fija mientras estas en grupo; escribir ahi = `/p`).

Reglas (`EventWowGroups.cpp`, no en modo dev): maximo 5 (se descarta `CMSG_GROUP_RAID_CONVERT`); no se invita ni se
acepta en partida (`ERROR GROUP_IN_MATCH`, `GROUP_TARGET_IN_MATCH <nombre>`).

Cola en grupo (`EventWowMatchMgr`): `QUEUE` del lider apunta al grupo entero como una entrada (nunca se separa).
- Requisitos: ser el lider (`QUEUE_NOT_LEADER`), juego con `MaxPartySize` > 1 (`QUEUE_SOLO_ONLY <max>`) y grupo que
  quepa (`QUEUE_GROUP_TOO_BIG <max>`), todos conectados al protocolo (`QUEUE_GROUP_OFFLINE <nombre>`), en el lobby y
  sin partida (`QUEUE_GROUP_BUSY <nombre>`).
- Sale entera de la cola si: cualquiera cancela (`QUEUE_GROUP_CANCELLED <nombre>` a los demas), se desconecta
  (`QUEUE_GROUP_LOGOUT <nombre>`) o el grupo cambia (entra/sale alguien, se disuelve: `QUEUE_GROUP_CHANGED`).
- Emparejamiento: por orden de llegada, entradas enteras que quepan en `MaxPlayers` (puede saltarse una entrada
  grande para llenar con otras mas pequenas).

### Partida encontrada (confirmacion tipo Dota 2)

Lo emparejado no va directo a la partida: es una propuesta (`MATCH_FOUND`, popup `EventWowMatchFound.lua` con
Aceptar/Rechazar y cuenta atras de `EventWow.Queue.AcceptTimeout`, 20 s).
- Todos aceptan -> `MATCH_FOUND_END ACCEPTED` y se crea la partida (`MATCH_STATE LOADING`...).
- Alguien rechaza (`DECLINE`, `LEAVE`, logout, cambio de grupo) o no acepta a tiempo -> se cancela. Las entradas
  con algun culpable salen de la cola (`REMOVED`; sus companeros de grupo reciben `ERROR QUEUE_GROUP_DECLINED <nombre>`
  / `QUEUE_GROUP_NOT_ACCEPTED` / el motivo de `LEAVE`, logout o cambio de grupo). El resto vuelve a la cola
  automaticamente con su antiguedad (`REQUEUED`) y puede emparejarse de nuevo en el siguiente segundo.
- Durante la propuesta los jugadores siguen "en cola" (`QUEUE_STATUS QUEUED`) y no pueden apuntarse a otra.
- Instancias: el core liga tambien al lider de quien entra (aunque no este en la partida); al cerrar la partida se
  quitan todos los binds de su InstanceSave (`UnbindAllFor`).

## Pendiente

- `ONLINE` se difunde en cada login/logout: agrupar si hay muchos jugadores.
- Chat: filtro de palabras, registro en BD (de momento log `module.eventwow.chat`).

## Partidas (paso 6-7)

Servidor: `EventWowMatchMgr.*` (colas, emparejamiento, instancias), `EventWowMatch.*` (clase base de minijuego),
`games/` (minijuegos). Cliente: `EventWowMatch.lua` (HUD) + `EventWow_SetMode("lobby"|"match")` en `EventWow.lua`.

```
QUEUE -> QUEUE_STATUS QUEUED ... -> (emparejado) QUEUE_STATUS NONE + MATCH_STATE LOADING -> teleport
      -> (llega) MATCH_STATE WAITING -> COUNTDOWN n -> RUNNING [t] (+ MATCH_HUD) -> MATCH_END + ENDED n
      -> teleport al lobby -> MATCH_STATE NONE
```

- Errores nuevos: `QUEUE_GAME_UNAVAILABLE`, `QUEUE_IN_MATCH`, `MATCH_CREATE_FAILED`, `MATCH_TELEPORT_FAILED`.
- Salir de la instancia por otra via (liberar espiritu, teleport de GM) o hacer logout saca de la partida.
