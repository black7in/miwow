# Protocolo cliente <-> servidor (addon messages)

Implementacion: servidor `modules/mod-eventwow/src/EventWowProtocol.*`, cliente
`client/src/Interface/FrameXML/EventWowProtocol.lua`. Version actual: **1**
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
| `QUEUE` | id juego | "Buscar partida" (provisional: no empareja) | `QUEUE_STATUS`, o `ERROR QUEUE_UNKNOWN_GAME/QUEUE_NOT_IN_LOBBY` |
| `LEAVE` | - | "Cancelar" la cola | `QUEUE_STATUS NONE` |

### Servidor -> cliente

| OP | Campos | Significado |
|---|---|---|
| `WELCOME` | version, rango (0 jugador, 1 GM) | handshake correcto |
| `ERROR` | codigo, detalle... | textos en `EVENTWOW_ERROR_TEXTS` (EventWowProtocol.lua); `UNKNOWN_OP <op>` |
| `GAMES` | n, luego n x (id, icono, min, max, nombre, descripcion) | catalogo de minijuegos |
| `CHAT` | unix time, rango, nombre, texto | chat global; al conectar llegan los ultimos 50 (historial) |
| `ONLINE` | n | jugadores conectados (cada vez que alguien conecta/desconecta) |
| `QUEUE_STATUS` | `QUEUED` id segundos / `NONE` | estado de la cola (tambien al conectar) |

## Pendiente

- Cola real (emparejamiento), inicio/fin de partida (paso 6).
- `ONLINE` se difunde en cada login/logout: agrupar si hay muchos jugadores.
- Chat: filtro de palabras, registro en BD (de momento log `module.eventwow.chat`).
