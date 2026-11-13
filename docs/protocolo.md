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

### Cliente -> servidor

| OP | Campos | Cuando | Respuesta |
|---|---|---|---|
| `HELLO` | version | primer `PLAYER_ENTERING_WORLD` de cada carga del Lua (login, `/reload`) | `WELCOME` + `GAMES`, o `ERROR VERSION` |
| `LIST` | - | pedir el catalogo de nuevo | `GAMES` |

### Servidor -> cliente

| OP | Campos | Significado |
|---|---|---|
| `WELCOME` | version | handshake correcto |
| `ERROR` | codigo, detalle... | `VERSION <version del servidor>`, `UNKNOWN_OP <op>` |
| `GAMES` | n, luego n x (id, icono, min, max, nombre, descripcion) | catalogo de minijuegos |

## Pendiente

- Cola: `QUEUE <id>` / `LEAVE`, estado `QUEUE_STATUS`, inicio/fin de partida (pasos 5-6).
- Limitar frecuencia de mensajes por jugador si hace falta.
