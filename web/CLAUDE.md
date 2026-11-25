# Cliente web y movil (`web/`)

Cliente 3.3.5a en wasm de Last Havens (permiso verbal, SIN fuentes) + nuestro backend. Decision del usuario
(2026-11-21): integrado en el proyecto. Documentacion completa: `docs/cliente-web.md`; VPS: `docs/despliegue-vps-pruebas.md`.

## Reglas
- **El cliente web = el de PC.** Glue ORIGINAL en ambos y nada de Last Havens a la vista; lo nuestro (login propio
  futuro incluido) va en `patch-4.MPQ`, que cargan los dos. `parchear.js` desactiva su login, seleccion/creacion
  tactiles, catalogo de addons, FAQ, encuestas, creadores, "Go in now", canal world, Discord (`do return end` en la
  primera sentencia del tramo).
- `D:\EmulacionWow\ExplorandoCliente` ya NO se usa; su `token-cloudflareR2.txt` NUNCA se lee ni se copia.
- `web/cliente/` (binarios suyos) y `web/referencia/` (APK, Lua extraido con `extraer-lua.js` en
  `referencia/lua-lasthavens/`) no versionados. Para entender su HUD tactil: `lua-lasthavens/18_WebTouchSecure.lua`.
- Solo lee MPQ EMPAQUETADOS (la carpeta `patch-4.MPQ` no). `Build-Patch` deja el empaquetado en
  `client/patches/web/patch-4.MPQ`. El tamano del MPQ debe cambiar en cada version (cache por tamano; `publicar-vps.ps1`
  se niega si coincide). El wasm carga interfaz modificada (`signature check OFF`).

## Despliegue
- **VPS de pruebas** (`ssh MiWow`, sudo). COMPARTIDO con `wow-arcano.com` y SU AzerothCore (3724/8085): no tocarlos.
  Apache + certbot, web Astro en `miwow.duckdns.org`, cliente en `https://juego.miwow.duckdns.org/play`
  (`miwow-juego.service`, `/opt/miwow-juego`).
- Publicar: `powershell -ExecutionPolicy Bypass -File web\deploy\publicar-vps.ps1` (pagina/servidor/wasm) y
  `... -Parche client\patches\web\patch-4.MPQ -SoloParche` (solo el parche). Sube a R2 desde el VPS
  (`deploy/vps-pruebas/subir-r2.sh`) y reinicia `miwow-juego`.
- **Por Cloudflare** (PROBADO 2026-11-23/24): Worker `wotlk-web` (`ORIGIN` = el VPS):
  `https://wotlk-web.<cuenta>.workers.dev/play`; `/blocks` desde R2; el tunel `/tcp/` tambien pasa por el Worker.
  Motivo: del usuario al VPS 60 % de paquetes perdidos y 300 ms; a Cloudflare 0 %.
- Nuestro core en el VPS (seccion 8 del doc): `/opt/miwow-core`, `miwow-auth`/`miwow-world` en 3725/8086, BD
  `miwow_auth/characters/world` (usuario `miwow_web`), SOAP 127.0.0.1:7879 (cuenta GM `black`), realmlist PC
  `144.126.158.141:3725`, cliente Frostbound esES COMPACTADO (`tools/mpqcompact.py`, 14,1 -> 10,1 GB).
- Repos GitHub publicos: `black7in/miwow` y `black7in/miwow-azerothcore` (rama `tradicional`).

## Estado
- Carga: solo baja lo que el juego toca (bloques de 64 KB, cache OPFS). En movil el arranque con cache llena tarda
  ~3 min por PROCESADO, no por descarga.
- **Congelones en partida = ESPERAS DE DATOS** (el circulito gira): el cliente pide bloques de uno en uno (XHR sincrono),
  ~0,3-1 s cada uno por R2 sin cache cerca. **Siguiente**: (1) dominio propio en Cloudflare para cachear `/blocks` en el
  borde (la Cache API no funciona en `workers.dev`) y/o (2) investigar los bundles (`bundle-<crc>.bin`, hoy 404).
  Despues: `wowRenderScale` en movil (fluidez).
- 2026-11-24 probado (`play.html`): sin "Descargando" falso en cargas siguientes (`wowLoadedOnce`,
  Resource Timing del wasm, `phaseLoad`, `#dl` oculto en la pantalla de carga) + receptor `wowPresentChannel` para que
  se vea la pantalla de carga del mundo (trazas `present: inicio/fin` con `?carga=1`; si no llegan, el C++ no lo usa ahi).
- Pendiente: mmaps v19 -> regenerar con el generador actual; arreglo clang de `MiWowGuildSeason.cpp` sin commitear
  (copiado a mano al VPS); pagina `/[lang]/play` de Astro; Warden.

## Voz (`docs/voz.md`)
`voice.js` (hub, dentro de server.js: enlace con el worldserver en 127.0.0.1:8091, `/voice-ws`, proxy `/livekit/*`,
liga sesion <-> personaje viendo `VOICE_TOKEN` en el tunel) + `public/voice/voice.js` (navegador, `livekit-client`
2.23.0 de `node_modules`). LiveKit aparte (`tools/livekit` en local; `deploy/vps-pruebas/livekit.yaml` +
`miwow-livekit.service` en el VPS, SIN instalar). El dictado por voz de Last Havens (boton de micro tactil) esta desactivado en `parchear.js` (tramo 30).

## HUD tactil (`client/src/Interface/FrameXML/MiWowTouchSkin.lua`)
Decision del usuario (2026-11-22): su logica intacta, marcos de vida nativos, solo texturas e iconos "modernos" dorados.
Solo actua con `webTouch`; captura `LasthavensEditApi` con una metatabla de `_G` (su trozo 15 lo borra). Texturas de
`tools/touchui/gen_touchui.py` en `client/src/Interface/TouchUI`. Maqueta de referencia: artefacto "HUD tactil MiWoW".
- Probado: anillo, saltar dorado y (2026-11-24) lo siguiente:
- iconos del boton inteligente, menu (retrato con nuestro anillo, cajon y micro
  botones), chat (ventana grande, canales/pestanas en pastilla, caja, botones redondos), ventana de bolsas; mochila y
  libro de hechizos con su icono ORIGINAL recortado en circulo dentro de nuestro anillo (`MiWowTouch_RoundIcon`), en
  columna bajo el boton Menu junto al minimapa; su engranaje `hud.setup` (abria el libro) oculto; vista previa del chat
  (`hud.preview`) centrada abajo y 26 px mas arriba; experiencia = `MiWowTouchXpBar` abajo-centro con texto
  (actual / siguiente, %, lo que falta, descanso) y su linea de 3 px con alfa 0.
- 2026-11-24: ventanas MiWow que caben en movil. Su HUD pone `UIParent:SetScale(768 / alto)` (~844x390 de
  UI apaisado); `MIWOW_TOUCH_FIT` (`MiWow.lua`) escala panel, hermandad, tienda, eleccion, partida encontrada, texto
  grande y HUD de partida/carrera (estos con tope de ancho) para caber con margen; tienda (50 % ancho / 62 % alto) y
  eleccion (45 % / 70 %) con tope (el usuario: la tienda aun era muy grande solo con caber); al abrirse y cada 0,5 s, solo con
  `webTouch`. El panel en tactil: margen 12 y minimo 640x340 (por debajo, escala).
- 2026-11-24 (SIN PROBAR): "mantener pulsado" (tooltip en vez de lanzar) de 0,45 a 0,70 s (`MIWOW_TOUCH_HOLD`, CVar
  `webTouchHold`, solo si sigue en su valor por defecto). Tooltips que se quedan pegados: pendiente (posible vigilante
  que los esconda a los ~3 s).
- Pendiente: adaptar `MiWow.lua` (modo partida) y las ventanas al modo tactil (su Lua toca `VehicleMenuBar`, barras,
  `UIParent:SetScale`...).
