# Voz (chat de voz estilo juegos moviles)

Decision del usuario (2026-11-24): voz propia por **WebRTC** para todos (no la voz nativa del 3.3.5, que va por UDP a un
servidor aparte, no funciona en navegador/movil, no tiene proximidad ni autenticacion; ver issue AC #5063 y PR #28180).
Canales: **grupo** y **cerca** (mundo abierto). Fuera: banda (de momento) y susurro.

## Fases
1. **Grupo en el cliente web** (HECHO, sin probar en juego): sala por grupo nativo (no banda), botones de micro y
   altavoz, quien habla en los marcos de grupo.
2. Cerca: posiciones del worldserver, suscripcion por distancia (tope 5-6 voces mas cercanas hablando, radio que encoge
   con mucha gente), volumen por distancia; pulsar para hablar por defecto en "Cerca".
3. Silenciar/volumen por jugador, pulsar para hablar (tecla y boton), elegir micro.
4. Cliente de PC: pagina de voz en el navegador enlazada con un codigo que da el juego (el PC no pasa por el tunel).

## Arquitectura

```
 Juego (Lua MiWowVoice.lua) --MIWOW--> worldserver (MiWowVoice.cpp) --TCP 127.0.0.1:8091--> server.js (voice.js, hub)
                                         autoridad: personaje, grupo                         tokens LiveKit, salas
 Navegador (public/voice/voice.js) --WS /voice-ws--> hub          Navegador --WebRTC (UDP 7882 / TCP 7881)--> LiveKit
                                   --/livekit/* (senalizacion)--> server.js --> LiveKit 127.0.0.1:7880
```

- **LiveKit** (SFU, `livekit-server` v1.13.10; cliente `livekit-client` 2.23.0 servido por server.js en
  `/voice/livekit-client.js`, sin CDN por el COEP de `/play`). Solo reenvia audio (Opus, preset `speech` 24 kbps, DTX:
  en silencio casi no envia). Token JWT HS256 hecho en `voice.js`: identidad `p<guid>`, sala, solo `microphone`.
- **Quien es quien** (sin que nadie pueda hacerse pasar por otro): al conectarse al protocolo MIWOW el modulo crea un
  nonce de un solo uso, se lo manda al hub (`TICKET`) y al jugador (`VOICE_TOKEN`). El mensaje del jugador pasa en
  claro por el tunel `/tcp/` de server.js (en 3.3.5 solo se cifra la cabecera de cada paquete; el chat no se
  comprime): el hub lo ve y liga la sesion del navegador (cookie `wsid`) a ese personaje. Un nonce que llega por el
  tunel antes que su `TICKET` se guarda 30 s. El cliente de PC no pasa por el tunel: no queda ligado (sin voz).
- **Sala** = `g<id del grupo>` si esta en un grupo que no es banda; el modulo la recalcula cada segundo (cubre
  unirse, salir, disolver, pasar a banda) y manda `ROOM`. LiveKit cierra la sala vacia al minuto.
- El Lua no puede hablar con el JavaScript del wasm: los botones van Lua -> MIWOW -> modulo -> hub -> navegador
  (`CMD`) y el estado vuelve igual (`STATE` -> `VOICE_STATE`). "Hablando" lo detecta cada navegador de si mismo
  (`IsSpeakingChanged` de LiveKit, tope 10/s) -> `SPEAK` -> `VOICE_SPEAK` a los de su grupo en su sala.

### Enlace modulo <-> hub (lineas de texto, campos separados por tabulador)
| Sentido | Linea |
|---|---|
| -> hub | `HELLO <clave>` (primera; mal = se cierra), `TICKET <nonce> <guid> <nombre>`, `ROOM <guid> <sala o vacio>`, `CMD <guid> mic/speaker 0/1`, `GONE <guid>` |
| <- hub | `WELCOME`, `STATE <guid> <voz> <en sala> <mic> <altavoz> <error>`, `SPEAK <guid> 0/1` |

El modulo reconecta cada 5 s; tras cada `WELCOME` vuelve a dar nonce a todos los conectados (el hub empieza de cero).
Si se cae el enlace, el hub saca a todos de sus salas.

### Protocolo MIWOW (ver `docs/protocolo.md`)
`VOICE_TOKEN`, `VOICE_STATE`, `VOICE_SPEAK` (servidor -> cliente), `VOICE_MIC`, `VOICE_SPEAKER` (cliente -> servidor).

### Interfaz (`MiWowVoice.lua`)
Dos botones redondos junto al minimapa (abajo a la izquierda): microfono (gris tachado = apagado, blanco = encendido,
verde = hablando) y altavoz (tachado = silenciado). Sin grupo, medio transparentes y un aviso al tocar. Quien habla:
el altavoz animado NATIVO de los marcos (`PlayerSpeakerFrame`, `PartyMemberFrameNSpeakerFrame`). `/voz` (micro) y
`/voz altavoz`. Solo se ve si el cliente tiene voz (el web con el hub conectado). Preferencias (micro/altavoz) en el
`localStorage` del navegador. Errores: `mic_denied`, `mic_error`, `connect`, `load` (`MIWOW_VOICE_ERRORS`).

## Configuracion (infraestructura: NO va en mod_miwow.conf.dist)
- `worldserver.conf`: `MiWow.Voice.Enable = 1`, `MiWow.Voice.LinkHost = "127.0.0.1"`, `MiWow.Voice.LinkPort = 8091`,
  `MiWow.Voice.LinkSecret = "<clave>"` (el enlace se abre al arrancar: cambiar algo pide reiniciar).
- `web/servidor/config.json`: seccion `voice` (ver `config.example.json`): `enabled`, `linkPort`, `linkSecret` (la misma),
  `livekitHost/Port`, `livekitUrl` (`''` = la misma web + `/livekit`), `apiKey/apiSecret` (las de LiveKit).

## Probar en local
1. `tools\livekit\livekit-server.exe --dev --bind 127.0.0.1` (claves de desarrollo `devkey` / `secret`; binario no
   versionado, release oficial de github.com/livekit/livekit).
2. server.js y worldserver con la voz configurada (2026-11-24 ya puesto en el `config.json` local y en
   `server/bin/RelWithDebInfo/configs/worldserver.conf`; copia previa en `worldserver.conf.antes-voz`).
3. Dos navegadores (o uno normal y otro de incognito) en `http://127.0.0.1:8080/play`, dos personajes en el mismo
   grupo. Botones junto al minimapa. `?voz=1` saca trazas `[voz]` en la consola del navegador.
- Comprobado sin el juego (2026-11-24): enlace y clave, nonce partido en dos trozos y llegado antes que el TICKET,
  sala + token, estado, hablando, botones, logout; LiveKit real acepta el token (`/rtc/validate` success, tambien por
  `/livekit/` de server.js) y rechaza uno falsificado; WebSocket de senalizacion por server.js abierto.

## VPS (SIN HACER: lo decide el usuario; el VPS es compartido con wow-arcano, no tocar lo suyo)
1. Binario `livekit_1.13.10_linux_amd64.tar.gz` en `/opt/miwow-livekit/`, `livekit.yaml` y `miwow-livekit.service`
   de `web/deploy/vps-pruebas/` (claves propias largas y aleatorias, las mismas en `config.json`).
2. Firewall: abrir **UDP 7882** y **TCP 7881**; el 7880 NO (solo local, entra por server.js). Comprobar antes que no los
   usa nadie.
3. Apache (`juego.conf`): `a2enmod rewrite`, reglas de `/voice-ws` y `/livekit/*`; `apachectl configtest` antes de
   recargar.
4. `worldserver.conf` del VPS (`/opt/miwow-core`) y `config.json` con la seccion `voice`; `publicar-vps.ps1` ya sube
   `voice.js` y `public/voice/`.
- Cloudflare no pasa UDP: el audio va directo a la IP del VPS (la senalizacion si puede ir por el Worker). OJO: desde
  la red del usuario al VPS se midio 60 % de perdida (por eso el juego va por Cloudflare); si la voz va mal por eso,
  alternativas: TURN en otro sitio o el SFU de Cloudflare (Realtime).
- Consumo: ver la conversacion de diseno: ~24 kbps por voz oida; tope de voces en la fase 2.
