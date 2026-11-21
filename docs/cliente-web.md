# Cliente web y movil de MiWow

El cliente para PC, Android e iPhone es el **cliente 3.3.5a compilado a WebAssembly por Last Havens** (`Wow.wasm` +
`Wow.js`), servido por un backend nuestro (`web/`). El jugador no instala nada: abre `/play` en el navegador.

> **Permiso (2026-11-10)**: el equipo de Last Havens dijo que no tiene problema en que usemos su cliente en NUESTRO
> servidor. NO dan el codigo fuente (solo pagando). Pendiente: tenerlo **por escrito**, darles **creditos** y aclarar
> detalles (quitar su logo/botones, avisos de versiones nuevas, si se puede cobrar).
> Usamos una copia fija de su `Wow.wasm`: sus actualizaciones hay que bajarlas a mano y repasar `parchear.js`.

Origen: estudio hecho en `D:\EmulacionWow\ExplorandoCliente` (noviembre 2026). Todo lo necesario se trajo a `web/`
el 2026-11-21 y **esa carpeta ya no se usa** (el estudio original esta copiado en
`web/referencia/ESTUDIO-LastHavens-original.md`). Su `token-cloudflareR2.txt` **no se lee ni se copia nunca**.

---

## 1. Carpeta `web/`

```
web/
  README.md                 resumen y comandos
  cliente/                  NO VERSIONADO (binarios de Last Havens; copia de seguridad fuera de git)
    Wow.original.wasm       su cliente sin tocar (8,7 MB)
    Wow.wasm                el nuestro = original + parchear.js
    Wow.js                  "pegamento" de Emscripten (JS en texto plano, 208 KB)
    game-manifest.txt       su lista de archivos (solo para copiar las mayusculas de las rutas)
  servidor/                 backend Node (HTTP + proxy WebSocket->TCP). Dependencia: ws@8.18.0
    server.js               ver seccion 4
    play.html               pagina de arranque (canvas, Module, wowMemoryMB, wowTouch)
    config.example.json     plantilla para el VPS (rutas /srv/wow)
    config.local.example.json  plantilla para este PC (copiar a config.json; config.json no se versiona)
    game-index.txt          lista "tamano<TAB>ruta" del cliente subido a R2 (la genera subir-r2.ps1)
    public/                 manifest.webmanifest + icons/icon.svg ("Instalar app")
  herramientas/
    parchear.js             parches de texto sobre el Lua incrustado en el wasm (seccion 6)
    extraer-lua.js          vuelca su Lua incrustado a referencia/lua-lasthavens/ para leerlo (seccion 7)
  deploy/
    subir-r2.ps1            sube el cliente (MPQ) y Wow.js/wasm a R2 + genera game-index.txt
    arrancar-online.ps1     pruebas online gratis: server.js + tunel cloudflared + Worker
    empaquetar.ps1          arma web/paquete/ (no versionado) con lo que va al VPS Linux
    Caddyfile, wow-web.service   HTTPS automatico y servicio systemd del VPS
    vps/config.json, vps/LEEME.md   config y pasos del VPS (van dentro del paquete)
    worker/                 Worker de Cloudflare (wrangler.toml + src/index.js)
  referencia/               NO VERSIONADO salvo el estudio
    ESTUDIO-LastHavens-original.md   estudio completo original (historia, capturas, decisiones)
    lasthavens.apk          su app Android (solo una TWA; seccion 9)
    lua-lasthavens/         su Lua extraido (31 tramos + indice.txt)
```

No versionado (ver `.gitignore`): `web/cliente/`, `web/referencia/lasthavens.apk` y `lua-lasthavens/`,
`web/servidor/{node_modules,userdata,.cookie-secret,config.json}`, `web/paquete/`, `web/deploy/logs/`, `.wrangler/`,
`token*.txt`. **Hacer copia de seguridad de `web/cliente/` aparte**: no se puede volver a bajar (su web cambia).

No se trajo de ExplorandoCliente (no hace falta): `server.v1.js` (version vieja), `lh.js` (pagina de error 502),
el `.har` vacio, `APK/x/` (APK descomprimido), `paquete-web/` (salida generada), `userdata/` y `.cookie-secret` de
las pruebas, logs, y el token.

Herramientas instaladas en el PC (fuera del repo): rclone `%LOCALAPPDATA%\rclone\rclone.exe` (remote `r2`, token
de cuenta solo para el bucket; `rclone lsd r2:` da 403 y es normal: usar `rclone ls r2:wotlk-cliente`), cloudflared
`%LOCALAPPDATA%\cloudflared\cloudflared.exe`, wrangler con `npx wrangler@4`. Node >= 18.

---

## 2. Que es su cliente

Firma: `client  Waystone 1645 (eb6f2aa), 3.3.5 (12340)` ("Waystone" = su port, 1645 = build, eb6f2aa = commit).
Es el **cliente original** (codigo reconstruido del `Wow.exe` 12340: `SFile.cpp`, `CGxDeviceOpenGl.cpp`,
`NetClient.cpp`...) compilado con Emscripten, mas una capa propia (`Os/Web`, `Storm/Web`, `Ui/Web`).

| Pieza | Solucion |
|---|---|
| Compilacion / hilos | Emscripten + pthreads (Web Workers + `SharedArrayBuffer`) -> cabeceras **COOP same-origin + COEP require-corp** obligatorias, y HTTPS fuera de `localhost` |
| Graficos | backend OpenGL del cliente -> WebGL2 / GLES 3.0 |
| Audio | FMOD Ex a wasm con salida WebAudio |
| Red | `NetClient` por **WebSocket** `wss://host/tcp/<IP>/<puerto>?ticket=..&rx=<bytes>` (`rx` = reanudar tras cortes) |
| Archivos | **WebVfs**: MPQ por bloques HTTP + cache OPFS (seccion 3) |
| Configuracion | carpeta `WTF` sincronizada con `PUT/DELETE /userdata/...` (cabecera `X-Wow-Client: 1`) |
| Memoria | hasta 4 GB; se limita con `window.wowMemoryMB` (play.html: 2048) |
| Movil | controles tactiles + mando (seccion 8) |
| Login | SRP6 normal dentro del WebSocket (`ticket=null`): contra AzerothCore funciona sin tocar nada |
| Interfaz modificada | el wasm lleva `signature check OFF (modified MPQ files and interface files load)`: carga nuestro FrameXML de `patch-4.MPQ` |

Endpoints que pide el cliente: `GET /game-manifest.txt`, `GET /game/<ruta>` (Range), `GET /blocks/<ruta>/<tamano>-<i>-<N>k.bin`,
`GET /blocks/<carpeta>/bundle-<crc>.bin` (formato no investigado: 404 y cae a bloques), `/userdata/*`, `/account/*`
(su servicio de cuentas: no se usa), `/addons/library.txt`, `/polls/*`, `/stats/*`, `/server-alert.txt`, `/sw.js`.

**IP fija**: su cliente reescribe `realmList` a la IP de Last Havens. `server.js` **ignora la IP pedida** y solo mira
el puerto (`tcpRoutes`): nada sale nunca a su servidor.

Parametros de URL del cliente: `?touch=1|0` (play.html), `?debug=1`, `?texbudget=<MB>`, `?nodxt`, `?ps` (iconos de
PlayStation), `?padpreview`.

---

## 3. WebVfs: los archivos del juego

No reempaquetan nada: el servidor tiene los MPQ originales.

```
el cliente quiere un archivo de patch.MPQ
  -> SFile (lector MPQ original) lee cabecera/hash/block table -> offset
     -> WebVfs: bloque en cache OPFS? si -> local | no -> GET /blocks/Data/patch.MPQ/<tamano>-<i>-<N>k.bin
```

- Solo se descarga lo que el juego toca (~50 MB hasta el login). Cache persistente en OPFS (`blocks.bin` + `blocks.idx`),
  XHR sincrono dentro de workers (el C++ espera `read()` bloqueante). Prefetch con `window.wowPrefetch`;
  `wowCacheBlocks` (256) sugiere un limite.
- **El tamano del archivo va en la URL del bloque**: si un MPQ cambia de tamano, cambian las URL y la cache (navegador,
  OPFS y Cloudflare) se invalida sola. **Si cambia pero queda del MISMO tamano, se siguen usando los bloques viejos.**
- **Solo MPQ empaquetados**: la "carpeta como MPQ" que usamos en PC (`Build-Patch`) **NO funciona** en el cliente web
  (comprobado por el usuario 2026-11-21).
- El manifest lo genera `server.js`: todos los `.MPQ` de `Data/`, `Data/<locale>/`, `Interface/` y el `WTF/` + `realmlist.wtf`
  del jugador. Parches propios: `Data/patch-?.MPQ` y `Data/<locale>/patch-<locale>-?.MPQ` (el wasm busca los mismos nombres
  que el `Wow.exe`).

---

## 4. `server.js`

Configuracion: `config.json` junto a `server.js` (o `CONFIG=/ruta`); variables `WOW_PORT`, `WOW_HOST`, `WOW_CLIENTDIR`,
`WOW_LOCALE`, `WOW_BASICAUTH`, `WOW_TRUSTPROXY`, `WOW_MAXWSPERIP`, `WOW_GAMEINDEX` pisan el archivo.

| Que | Como |
|---|---|
| Aislamiento | COOP/COEP/CORP en todas las respuestas |
| Sesion | `/play` da la cookie `wsid` (id aleatorio firmado HMAC, secreto en `.cookie-secret`). Sin ella: 403 en manifest/bloques/userdata/WebSocket |
| Userdata por jugador | `userdata/<sid>/WTF/...`, tope `maxUserdataMB`, escritura atomica. Primer `Config.wtf` con locale, realmlist, sin cinematica |
| Manifest | del disco (`clientDir`) o de `gameIndex` (VPS sin MPQ: los bloques que no estan en disco dan 404 y los sirve R2). MPQ re-escaneados cada 30 s |
| Cache | bloques `immutable` 1 ano (si el tamano pedido coincide); Wow.js/wasm con ETag; manifest y userdata `no-store` |
| Proxy WS->TCP | lista blanca `tcpRoutes` puerto->host, max. conexiones por IP, cierre por inactividad, contrapresion |
| Acceso en pruebas | `basicAuth: "usuario:clave"` (`""` = abierto) |
| Otros | `/healthz`, `/server-alert.txt` (opcional en `public/`), `clientIp` con `CF-Connecting-IP` detras de Cloudflare |

### Arrancar en local
```powershell
cd web\servidor
npm ci                                   # una vez
copy config.local.example.json config.json   # una vez; ajustar clientDir
node server.js
```
1. authserver + worldserver encendidos; en `acore_auth.realmlist`: `address = 127.0.0.1`.
2. Abrir **http://localhost:8080/play** (Chrome; Firefox puede dar "out of memory" tras varias recargas: cerrar la pestana).
3. Cliente base: **`D:\Wow`** (original). NO usar `D:\Clientes de Wow\Wow3.3.5a-Limpio` (intento de compactarlo, puede estar roto).
4. Si desconecta al entrar al mundo: Warden (su modulo nativo no corre en wasm) -> `Warden.Enabled = 0` (sin decidir
   donde: si va en `mod_miwow.conf.dist` afecta tambien al cliente de PC).

Probado (2026-11-10/11): MPQ esES, login, SRP6 contra el authserver, lista de reinos, manifest, bloques, Range, ETag/304,
userdata, traversal bloqueado, reglas del proxy.

---

## 5. Parche de MiWow en el cliente web (sincronizacion)

**Un solo parche para PC y web.** La fuente sigue siendo `client/src` + `tools/Build-Patch.ps1` (interfaz FrameXML,
`DBFilesClient`, mapas 750-799). Diferencia: la web necesita el **MPQ empaquetado** (lo convierte el usuario a mano;
el empaquetado automatico queda pendiente). El MPQ empaquetado tambien sirve en PC, asi que lo ideal es usar el mismo
archivo en los dos.

Flujo al cambiar algo de cliente:
1. `tools\Build-Patch.ps1` -> `client\patches\patch-4.MPQ` (carpeta) -> el usuario lo empaqueta como MPQ.
2. **Asegurar que el tamano cambia** respecto a cualquier version publicada antes (si no, los jugadores se quedan con los
   bloques viejos): comparar con la linea de `patch-4.MPQ` en `web\servidor\game-index.txt`; si coincide, anadir un
   archivo de relleno/version al MPQ (o, como plan B, renombrar a `patch-5.MPQ`).
3. Copiarlo a `D:\Wow\Data\patch-4.MPQ` (el `clientDir`: de ahi sale el manifest y el respaldo del Worker).
4. Si se usa R2: `web\deploy\subir-r2.ps1 -Solo patch-4` y `web\deploy\subir-r2.ps1 -SoloIndice`; en el VPS copiar
   `game-index.txt` a `/srv/wow/servidor/` (se relee solo cada 30 s).
5. Los jugadores solo recargan la pagina. Si R2 aun tiene otro tamano, el Worker manda el bloque al origen (mas lento, nunca
   datos viejos).

Pendiente: probar en el navegador que nuestro FrameXML carga con el MPQ empaquetado (panel, hermandad, carrera) y que
los DBC/mapas propios se leen.

---

## 6. Parches al wasm (`herramientas/parchear.js`)

Su Glue (login, seleccion de personaje) y su interfaz tactil son Lua incrustado como texto en el wasm. `parchear.js`
sustituye texto por otro de **igual o menor longitud** (relleno con espacios), comprueba que cada original aparece una
sola vez y valida el wasm (`new WebAssembly.Module`).

```
node web\herramientas\parchear.js     # cliente\Wow.original.wasm -> cliente\Wow.wasm
```

**Regla (decision del usuario 2026-11-21): el cliente web es IGUAL que el de PC.** Nada de Last Havens a la vista y
Glue ORIGINAL de Blizzard en los dos; lo propio de MiWow (un login personalizado futuro incluido) va en NUESTRO
`patch-4.MPQ`, que cargan ambos (el wasm carga `Interface\GlueXML\GlueXML.toc` y `FrameXML.toc` de los MPQ). Asi un cambio
nuestro sale igual en PC, web y movil. Solo se conserva lo que es del cliente web en si (tactil, mando, voz, pantalla completa).

Tecnica para desactivar un tramo entero: su primera sentencia (completa, de una linea) se cambia por `do return end`
(mismo largo, con espacios): el wasm lo sigue ejecutando pero sale enseguida, y el resto solo tiene que compilar.
`contexto` elige entre varias apariciones del mismo texto (el guard tactil sale dos veces).

| Parche | Que quita |
|---|---|
| `04_WebLoginLayout` desactivado | SU pantalla de login entera: logo/texto "Lasthavens", Discord, crear/gestionar cuenta, cuentas guardadas (guardaba contrasenas en el navegador), version tactil. Sustituye a los 9 parches sueltos de antes |
| `p_7060721` | apertura automatica de su dialogo de registro |
| `p_7061044` (parte) | cambio de los enlaces de Blizzard por su Discord en los textos `LOGIN_`/`AUTH_`/`RESPONSE_`/`REALM_LIST_`; enganche de su embudo de estadisticas (`WebCharacterCreated`) |
| `01`, `03` desactivados (desde su guard) | seleccion y creacion de personaje tactiles/mando (en movil queda la original, que se toca como con el raton) |
| `05` desactivado | su catalogo de addons en el boton AddOns de la seleccion de personaje |
| `09`, `10`, `16`, `17` desactivados | "Go in now" del buscador de mazmorras, su FAQ en la ayuda, programa de creadores, encuestas |
| `31` (parte) | unirse solo al canal "world" al conectar |
| cabecera de teclas | `BINDING_HEADER_LASTHAVENS` = "Web" (cabecera de "Interactuar con lo mas cercano") |
| `29` traducido | aviso "version nueva" en espanol y sin la marca (el aviso se queda: es del cliente web) |

Se quedan (cliente web, no Last Havens): HUD tactil y de mando (`06-08`, `11-15`, `18-28`), voz (`30`), compatibilidad (`02`,
`p_7148482`), `/bugreport`, resolucion, boton de pantalla completa del menu, vista previa de mando de `?padpreview` (`07`,
`p_7156686`: solo con ese parametro). Sus textos siguen en ingles (traducirlos: pendiente).
Lo que queda con "Lasthavens" en el wasm esta dentro de los tramos desactivados o es nombre interno de marco.
Sin Lua instalado no se pudo pasar `luac`; los reemplazos son sentencias completas de una linea.
Revertir un parche = quitarlo de `PARCHES` y volver a ejecutar. Sirve para QUITAR o cambiar textos; para anadir: nuestro
parche, `Wow.js` o `play.html`. PENDIENTE: probarlo en el navegador (login, seleccion/creacion, ayuda, buscador de
mazmorras, chat) en PC y con `?touch=1`; en movil, que el teclado del telefono sale al tocar las cajas del login original.

---

## 7. Su interfaz Lua y la nuestra

`node web\herramientas\extraer-lua.js [wasm]` vuelca su Lua a `web/referencia/lua-lasthavens/` (31 tramos `NN_*.lua`,
~960 KB, + 9 piezas cortas `p_<offset>_*.lua`, `indice.txt`; los nombres se adivinan por sus globales). Son copias para
LEER: el cliente ejecuta el Lua del wasm. Para ver el resultado de `parchear.js`: `extraer-lua.js cliente\Wow.wasm <carpeta>`. En el wasm aparecen los nombres de chunk:
`WebTouch.lua`, `WebTouchCompactFrames.lua`, `WebTouchBigBags.lua`, `WebTouchBigSpellBook.lua`, `WebTouchWorldMap.lua`,
`WebTouchPanels.lua`, `WebTouchFullPanel.lua`, `WebTouchForeverRing.lua`, `WebTouchPetCluster.lua`, `WebPadClusters.lua`,
`WebPadPreview.lua`, `WebGamepad.lua`, `WebInteract.lua`, `WebEditMode.lua`, `WebDragonUI.lua`, `WebCharSelect.lua`,
`WebCharCreate.lua`, `WebAccount.lua`, `WebAddOns.lua`, `WebPolls.lua`, `WebFaq.lua`, `WebCreators.lua`, `WebQuickChat.lua`,
`WebVoiceChat.lua`, `WebWorldChat.lua`, `WebDungeonFinder.lua`, `WebResolution.lua`, `WebVersion.lua`,
`WebGameMenuFullscreen.lua`, `compat.lua`.

Como conviven:
- **Su Lua lo ejecuta su C++ desde el wasm, no sale de `FrameXML.toc`**: nuestro `FrameXML.toc` (en `patch-4.MPQ`) no lo
  quita ni el lo pisa. Cargan los dos.
- Casi todo lo tactil empieza con `if GetCVar("webTouch") ~= "1" and not WebPadLayout() then return end`: **en PC con raton
  no hace nada**; solo actua en tactil (`window.wowTouch`, que pone `play.html`) o con mando.
- En tactil (`18_WebTouchSecure.lua`, el HUD principal) toca lo mismo que nosotros: `UIParent:SetScale`, reparenta a un
  marco oculto `ShapeshiftBarFrame`, `ExhaustionTick` y, con mando, `ActionButton1-12`/`MultiBarBottom*`/`BonusActionBarFrame`;
  `MainMenuBar`/`BonusActionBarFrame` sin raton; **`VehicleMenuBar` con alfa 0 y sin raton** (sus botones propios
  sustituyen a la barra de vehiculo y tiene boton de salir con `VehicleExit`); mueve `ChatFrame1`, `CastingBarFrame`,
  `UIErrorsFrame`, escala `MinimapCluster`; 59 `hooksecurefunc` y 28 `SetOverrideBinding`.
- Choques esperables con `MiWow.lua` en modo `"match"`: reparentamos marcos a `MiWowHiddenParent` y los devolvemos a su
  padre guardado (puede deshacer lo suyo), las teclas 1-6 de vehiculo miran `VehicleMenuBar:IsVisible()` (en tactil no se
  pulsa con teclas sino con sus botones), la carrera depende de los poderes en la barra de vehiculo. Paneles 860x560
  (minijuegos) y 720x560 (hermandad) no pensados para pantalla tactil.
- Plan: detectar el modo tactil en nuestro Lua (`GetCVar("webTouch") == "1"`; en PC la CVar no deberia existir: comprobarlo) y en ese caso no
  ocultar/reparentar sus marcos ni forzar teclas, y adaptar el tamano de las ventanas. Sin hacer todavia.

---

## 8. Movil

Cuatro capas: captura de toques y mando (Gamepad API) en `Wow.js` (texto plano); logica (joystick, camara, pinza,
interactuar, modo edicion, voz) en C++ del wasm (`WebTouch.cpp`, `WebInteract.cpp`...; solo parcheando binario, aunque
muchos valores son opciones); interfaz en su Lua (`LasthavensTouch*`, `LasthavensPad*`, `WebTouch*`, `WebPad*`:
modificable con nuestro FrameXML via hooks); texturas `Interface/TouchUI/*.tga` (56) que estan en SU servidor: **nos
faltan**, hay que hacer las nuestras con los mismos nombres (en el parche).

- `play.html` pone `window.wowTouch`: automatico en pantallas tactiles, `?touch=1` fuerza (sirve en PC), `?touch=0` desactiva.
  `wowTouch` tambien activa `wowHalfTextures` (texturas a media resolucion). Mando: automatico si `navigator.getGamepads()` lo ve.
- Movil necesita HTTPS (sin el no hay `SharedArrayBuffer`): VPS con Caddy, o el Worker `*.workers.dev`, o en pruebas
  `adb reverse tcp:8080 tcp:8080` / `chrome://flags/#unsafely-treat-insecure-origin-as-secure`.
- Ejemplo de ajuste desde Lua: `LasthavensTouchJump:SetSize(90, 90)`, `hooksecurefunc("WebTouchLayout", function() LasthavensTouchSit:Hide() end)`.

---

## 9. App de Android

Su APK (3,3 MB, `web/referencia/lasthavens.apk`) es solo una **TWA** (`androidbrowserhelper`, plantilla Bubblewrap/PWABuilder)
que abre `https://lasthavens.com/play?app=android` en Chrome a pantalla completa (WebView de respaldo), verificada con
Digital Asset Links (`/.well-known/assetlinks.json`). No aporta nada tecnico: un solo `Wow.wasm` sirve para todo.
La nuestra: "Instalar app" desde Chrome (`public/manifest.webmanifest` ya esta) o TWA propia con Bubblewrap/PWABuilder
(requiere dominio con HTTPS).

---

## 10. Pruebas online gratis (R2 + Worker + tunel)

```
Navegador -> Worker wotlk-web.<cuenta>.workers.dev
               |- /Wow.js, /Wow.wasm, /game/*, /blocks/*  -> R2 bucket "wotlk-cliente"
               '- resto (/play, manifest, /userdata, /tcp WS) -> tunel cloudflared -> server.js (este PC) -> AzerothCore
```
- Claves en R2: `game/<ruta en minuscula>`, `web/Wow.js`, `web/Wow.wasm`. Se sube de `D:\Wow`: `Data\*.MPQ`, `Data\esES\**`
  (menos `realmlist.wtf`, que es por jugador) e `Interface\AddOns\Blizzard_*`.
- `web\deploy\subir-r2.ps1 [-BwLimit 2M] [-Solo <texto>] [-Simular] [-SoloIndice]` (re-ejecutable: se salta lo subido).
- Una vez: `cd web\deploy\worker; npx wrangler@4 login; npx wrangler@4 secret put BASIC_AUTH` (usuario:clave).
- Arrancar: `web\deploy\arrancar-online.ps1 -Auth "usuario:clave"` (server.js con `WOW_MAXWSPERIP=30`, tunel, y `wrangler deploy
  --var ORIGIN:<url del tunel>`). Entrar por `https://wotlk-web.<cuenta>.workers.dev/play`. La URL del tunel cambia en cada
  arranque y no se comparte.
- Worker: si un archivo no esta en R2 o tiene otro tamano, lo pide al origen. Pide la misma basicAuth.
- Coste: R2 ~0,10 $/mes (~17 GB), salida gratis, Workers gratis (100k peticiones/dia) para pocos testers.
- Estado (2026-11-20): Worker probado con `wrangler dev`; subida a R2 lanzada por el usuario.

---

## 10b. VPS de pruebas (sin R2)

Montado el 2026-11-21 en `ssh MiWow` (`https://juego.miwow.duckdns.org/play`, junto a la web de Astro): ver
**`docs/despliegue-vps-pruebas.md`** (Apache, servicio, puertos 3725/8086, `publicar-vps.ps1`).

## 11. Produccion (~500 jugadores, plan acordado 2026-11-18)

```
Jugadores --HTTPS/WSS--> Cloudflare (CDN + anti-DDoS, oculta IPs)
   |- /blocks/*  -> Worker -> R2                          (todas las descargas)
   '- resto      -> maquina WEB (Caddy + server.js: web, wasm, manifest, userdata, proxy /tcp/*)
                        | red privada, mismo datacenter
                        v
                   maquina CORE (authserver + worldserver + MySQL), sin puertos de juego publicos
```

| | CORE | WEB |
|---|---|---|
| Tipo | dedicado | VPS |
| CPU / RAM | Ryzen 8+ nucleos / 32 GB | 2-4 vCPU / 4 GB |
| Disco | 2x NVMe RAID1 | 40-80 GB NVMe |
| Red | 1 Gbps + red privada | 1 Gbps, ilimitado o >= 20 TB/mes |
| EUR/mes | 50-100 | 8-15 |

- **Jugadores de Latinoamerica** (Bolivia, Peru, Mexico) -> **Miami recomendado** (OVH no tiene Miami; candidatos Gcore,
  DataPacket, Hivelocity; Vultr Miami para la WEB). Comprobar red privada entre maquinas y que jugadores de BO/PE/MX
  hagan ping a los looking glass antes de contratar. Firewall de la WEB solo para rangos de Cloudflare; no publicar la IP.
  Espana descartada (ademas, bloqueos de IPs de Cloudflare en partidos de LaLiga).
- Trafico de juego ~10 KB/s por jugador -> 500 = ~40 Mbps, 6-13 TB/mes de salida en la WEB. worldserver: `MapUpdate.Threads` 4-6.
- Reglas de cache: `/blocks/*` 1 ano; `Wow.wasm`/`Wow.js` con `?v=`; manifest 1-5 min; `/userdata/*`, `/account/*`, `/tcp/*` sin
  cache. Tiered Cache y precalentar (login + zonas de inicio). Evitar `/game/` con Range en produccion (MPQ > 512 MB no se
  cachean en el plan gratis). Workers Paid 5 $/mes en la apertura.
- Paquete del VPS: `web\deploy\subir-r2.ps1 -SoloIndice` y `web\deploy\empaquetar.ps1` -> `web\paquete\` (~8,6 MB: `servidor/`
  -> `/srv/wow/servidor`, `web/` -> `/srv/wow/web`, `deploy/`). Pasos en `web/deploy/vps/LEEME.md` (va dentro del paquete).
  Antes de usar `vps/config.json`: cambiar `basicAuth` y `tcpRoutes`; en `acore_auth.realmlist.address` la IP que alcanza el proxy.
- A resolver: con el Worker los bloques son publicos (server.js los protege con la cookie `wsid`): validar la cookie HMAC en el
  Worker o aceptarlo. Medir bytes reales por sesion.

---

## 12. Cliente propio (futuro, sin fecha)

Con su wasm no hay hooks de memoria (WarcraftXL, DLL, MinHook, D3D9: imposible en el navegador) ni opcodes nuevos con logica
en el cliente. Opciones: (a) portar **wowdecomp** (decompilacion C++ del 12340, ~90 %) a Emscripten + WebGL2 + WebVfs +
nuestro proxy (riesgos: 64 -> 32 bits, render a WebGL2, FMOD); (b) **comprarles el codigo**. Alternativas valoradas: Whoa
(solo llega a la seleccion de personaje), Wowee (Vulkan). Su Lua y su diseno son trabajo suyo: para publicar una version
propia, pedir permiso o reescribirlo. Ingenieria inversa del wasm: Ghidra + ghidra-wasm-plugin, WABT; el binario no tiene
nombres de funciones. Descartado (2026-11-20): "cliente web universal para cualquier servidor" (proxy abierto, Warden,
permiso solo para nuestro servidor, DMCA).
