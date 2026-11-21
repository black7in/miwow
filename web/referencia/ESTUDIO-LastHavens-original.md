# Estudio: cómo Last Havens corre WoW 3.3.5a en el navegador

> Estudio personal (noviembre 2026). Objetivo: entender la técnica.
> Todo lo de este documento se ejecuta solo en local, contra un servidor propio.

---

## 1. Resumen en una frase

Last Havens **compiló el cliente 3.3.5a (código reconstruido del `Wow.exe`) a WebAssembly con Emscripten**, y le añadió una capa web propia: los MPQ originales se leen **por bloques vía HTTP** (con caché en el navegador) y la red del juego viaja por **WebSocket** hasta un proxy que la reenvía por TCP al authserver/worldserver.

---

## 2. Archivos de esta carpeta

| Archivo / carpeta | Qué es |
|---|---|
| `Wow.original.wasm` | Su cliente (binario WebAssembly, 8.7 MB) **sin tocar**. Copia de seguridad. |
| `Wow.wasm` | Su cliente **parcheado** por nosotros (lo genera `parchear.js`). |
| `Wow.js` | "Pegamento" de Emscripten (JS en texto plano, 208 KB). Carga el wasm y le da acceso al navegador. |
| `game-manifest.txt` | Su lista de archivos del juego (1147 archivos, 18.6 GB). |
| `apk/lasthavens.apk` | Su app de Android (resultó ser solo una TWA). |
| `servidor-local/` | **Nuestro servidor** que imita su backend (ver sección 5). |
| `lh.js` | Inútil: es una página de error 502 de Cloudflare (su web estaba caída al bajarla). |
| `lasthavens.com_Archive [...].har` | Vacío (0 bytes), intento fallido de exportar HAR. |

### Cómo se capturaron los archivos
- La web tiene **Cloudflare** (bloquea `curl`) y **bloquea la tecla F12**.
- Solución: abrir DevTools **antes** de entrar (menú → Más herramientas), o usar Firefox.
- Firefox **no guarda respuestas > 1 MB** en el panel Red (`devtools.netmonitor.responseBodyLimit`), por eso "Guardar respuesta" y el HAR salían en 0 bytes.
- Lo que funcionó: **doble clic en la petición** en la pestaña Red → se descarga el archivo completo.

---

## 3. Qué hay dentro de su cliente (`Wow.wasm` + `Wow.js`)

### Firma
```
client  Waystone 1645 (eb6f2aa), 3.3.5 (12340)
```
"Waystone" = nombre de su port · 1645 = número de build · `eb6f2aa` = commit de git.

### Es el cliente original, no una reimplementación
Dentro del binario aparecen las rutas y clases del código del cliente de Blizzard:
`Engine/Source/BlizzardCore/.../Mopaq/SFile.cpp`, `Gx/CGxDeviceOpenGL/CGxDeviceOpenGl.cpp`, `Storm/`, `Frame/CSimpleFrame.cpp`, `WoW/Source/Net/NetClient/NetClient.cpp`, clases `CGGameObject_C`, `CWorldOccluder`, `ClientServices`…
Más una capa propia: `Engine/Source/Os/Web/`, `Storm/Source/Web/`, `WoW/Source/Ui/Web/`.

### Cómo resolvieron cada pieza

| Problema | Solución |
|---|---|
| Compilación | **Emscripten** con **pthreads** (Web Workers + `SharedArrayBuffer`) |
| Hilos | Requiere cabeceras `COOP: same-origin` + `COEP: require-corp` |
| Gráficos | Backend OpenGL del cliente (el del Mac) → **WebGL2 / GLES 3.0** |
| Audio | **FMOD Ex** compilado a wasm con salida propia a **WebAudio** |
| Red | `NetClient` usa **WebSocket** en vez de TCP |
| Archivos | Sistema propio **WebVfs** (ver abajo) |
| Login/cuentas | HTTP `/account/*` (registro, login, challenge, email, password) |
| Configuración | Carpeta `WTF` sincronizada con el servidor (`PUT /userdata/...`) |
| Memoria | Hasta 4 GB por defecto; se limita con `window.wowMemoryMB` |
| Móvil | Controles táctiles + mando (ver sección 7) |
| Extras | DragonUI preinstalado, UI táctil, voz a texto, catálogo de addons, encuestas, telemetría (`/stats/freeze`, `/stats/gpu`) |

### Endpoints que usa el cliente

| Endpoint | Uso |
|---|---|
| `GET /game-manifest.txt` | Lista de archivos: `tamaño<TAB>ruta` por línea |
| `GET /game/<ruta>` + `Range: bytes=` | Leer un trozo de un archivo |
| `GET /blocks/<ruta>/<tamaño>-<índice>-<N>k.bin` | Un bloque fijo de N KB de un archivo |
| `GET /blocks/<carpeta>/bundle-<crc>.bin` | Paquete con muchos archivos pequeños (formato no investigado; no hizo falta) |
| `PUT/DELETE /userdata/<ruta>` | Guardar WTF, addons, etc. (cabecera `X-Wow-Client: 1`) |
| `POST /account/login`, `/register`, `/challenge`, `/info`, `/poll-token`, `/email`, `/password` | Servicio de cuentas |
| `GET /addons/library.txt` | Catálogo de addons |
| `/polls/status`, `/polls/vote` | Encuestas |
| `POST /stats/freeze`, `/stats/gpu` | Telemetría |
| `GET /server-alert.txt`, `/sw.js` | Aviso del servidor, service worker |
| WebSocket `wss://host/tcp/<IP>/<puerto>?ticket=…&rx=<bytes>` | Túnel TCP al auth/world. `rx` permite **reanudar** tras cortes ("Reconnecting…") |

---

## 4. WebVfs: el truco de los assets (lo más elegante)

**No reempaquetaron nada.** El servidor tiene los **MPQ originales intactos** (18.6 GB, incluido enUS y ruRU).

```
El cliente quiere un modelo dentro de patch.MPQ
  → SFile (lector MPQ original) lee cabecera / hash table / block table → offset X
     → WebVfs: ¿bloque en caché OPFS?  sí → leer local
                                       no → GET /blocks/Data/patch.MPQ/<tamaño>-<i>-<N>k.bin
  → SFile lee solo los sectores del archivo pedido → más bloques
```

- Solo se descarga **lo que el juego toca** (~50 MB para llegar al login).
- Caché persistente en **OPFS** (`navigator.storage.getDirectory()` → `blocks.bin` + `blocks.idx`) con acceso síncrono desde un worker.
- Usan **XHR síncrono dentro de workers**, para que el C++ original (que espera `read()` bloqueante) funcione sin reescribirlo.
- El **tamaño del archivo va en la URL** del bloque → si cambia un MPQ, cambian las URL → la caché se invalida sola y Cloudflare puede cachear los bloques para siempre.
- Hay **prefetch** (`window.wowPrefetch`) para adelantar bloques que se van a necesitar.
- **Nunca se descarga el cliente completo**: idiomas no usados, cinemáticas, versiones viejas de archivos pisadas por parches y zonas no visitadas no se piden. `wowCacheBlocks` (256 por defecto) sugiere además un límite de caché.

---

## 5. Nuestro servidor local (`servidor-local/`)

Imita su backend para que **su cliente funcione en nuestro PC, con nuestros MPQ y nuestro servidor**.

### Archivos
| Archivo | Qué hace |
|---|---|
| `server.js` | Servidor Node (HTTP + WebSocket). Dependencia: `ws@8.18.0` |
| `play.html` | Página de arranque (canvas, `wow-text`, config de `Module`, `wowMemoryMB = 2048`) |
| `parchear.js` | Genera `Wow.wasm` parcheado a partir de `Wow.original.wasm` |
| `userdata/WTF/` | Config.wtf y datos que guarda el cliente |
| `server.log` | Log (cuando se arranca en segundo plano) |

### Qué implementa `server.js`
- Cabeceras **COOP/COEP/CORP** en todo (necesarias para hilos).
- `/game-manifest.txt` **generado al vuelo** desde el cliente local: todos los `.MPQ` de `Data/`, `Data/<locale>/`, `Interface/` y `WTF/` (de `userdata`). Usa las mayúsculas de su manifest cuando coincide el nombre.
- `/game/` con `Range`, `/blocks/` calculando el trozo al vuelo, `/userdata/` en disco local.
- `bundle-*.bin` → 404 (el cliente cae a lectura por bloques sin problema).
- `/account/*` → solo se registra en el log (no hizo falta: el login funciona sin ticket).
- **Proxy WebSocket → TCP** en `/tcp/<IP>/<puerto>`.

### Configuración (arriba de `server.js`)
```js
clientDir: 'D:/Clientes de Wow/Wow3.3.5a-Limpio',  // cliente 3.3.5a
locale: 'esES',
realmlist: '127.0.0.1',
forceAuthHost: '127.0.0.1',
```

### ⚠️ IP fija en su cliente
Su cliente **reescribe `realmList` a `144.217.162.68`** (el authserver de Last Havens) aunque le pongamos otra.
Por eso el proxy **redirige SIEMPRE a `127.0.0.1`** cualquier IP que no sea local: nada sale nunca a su servidor real.

### Uso
```
cd D:\EmulacionWow\ExplorandoCliente\servidor-local
node server.js
```
1. Encender **authserver** (y worldserver si se quiere entrar al mundo).
2. En la BD `auth`, tabla `realmlist`: `address = 127.0.0.1`.
3. Abrir **http://localhost:8080/play** (Chrome recomendado; Firefox puede dar "out of memory" tras recargas → cerrar la pestaña y abrir otra).

### Resultado comprobado
✅ Carga tus MPQ esES · ✅ pantalla de login · ✅ login SRP6 contra tu authserver · ✅ lista de reinos.
(El login va por SRP6 normal dentro del WebSocket: `ticket=null`, sin usar `/account/*`.)

---

## 6. Parches al binario (`parchear.js`)

Su interfaz de login/selección de personaje es **Lua incrustado como texto dentro del `.wasm`**. Se puede parchear sustituyendo texto por otro **de igual o menor longitud** (se rellena con espacios, que en Lua no afectan).

Parches aplicados:
| Parche | Efecto |
|---|---|
| logo login / logo selección de personaje | Quita el texto "Lasthavens" (la imagen `Interface/Glues/LasthavensLogo.tga` ya no existía: está en su servidor, no en el nuestro) |
| Create Account (PC), New here?/Register (táctil), menú móvil, apertura automática | Quita todo lo de crear cuenta |
| Manage Account (PC + menú móvil) | Quita su gestor de cuentas (dependía de su servicio) |
| Saved Accounts + botón Manage | Quita el desplegable de cuentas guardadas (¡guardaba también **contraseñas** en el navegador!) |

```
node servidor-local/parchear.js      # regenera Wow.wasm desde Wow.original.wasm y valida el wasm
```
Para revertir un parche: borrar su entrada de la lista `PARCHES` y volver a ejecutar.
Limitación: sirve para **quitar/ocultar**; para **añadir** código hace falta otra técnica (addon, MPQ de parche o editar `Wow.js`).

---

## 7. Controles móviles

Están **en el cliente web**, no en el APK. Cuatro capas:

| Capa | Dónde | ¿Modificable? |
|---|---|---|
| Captura de toques y mando (Gamepad API) | `Wow.js` | ✅ texto plano |
| Lógica: joystick, cámara, pinch, interactuar, edit mode, voz | C++ en el wasm: `WebTouch.cpp`, `WebInteract.cpp`, `WebTouchCompactFrames.cpp`, `WebTouchWorldMap.cpp`, `WebEditMode.cpp`, `WebVoiceChat.cpp`, `WebFace.cpp` | ⚠️ solo parcheando binario (muchos valores ya son opciones: zona muerta, velocidad, tamaño) |
| Interfaz: HUD, botones, anillo radial, teclado virtual, objetivo por tanque/healer… | Lua incrustado: `LasthavensTouch*`, `LasthavensPad*`, `WebTouch*`, `WebPad*` | ✅ con **addon** propio (hooks/sobrescribir globales) o parches |
| Texturas: joystick, botones, glifos de mando | `Interface/TouchUI/*.tga` en **su servidor** (56 archivos) | ✅ basta crear archivos con el mismo nombre |

- El modo táctil se activa con `window.wowTouch`, que lo pone **su página `/play`** (no la tenemos; habría que ponerlo en nuestra `play.html`).
- En nuestra copia la lógica está completa pero **faltan las texturas TouchUI**.
- Para probar en móvil hace falta **HTTPS** (fuera de `localhost` no hay `SharedArrayBuffer`): p. ej. `mkcert` en la red local.

Ejemplo de addon para ajustar su UI táctil:
```lua
LasthavensTouchJump:SetSize(90, 90)
hooksecurefunc("WebTouchLayout", function() LasthavensTouchSit:Hide() end)
```

---

## 8. La app de Android

- 3.3 MB, sin `.so`, sin wasm: es una **TWA (Trusted Web Activity)** hecha con `androidbrowserhelper` (plantilla Bubblewrap/PWABuilder).
- Abre `https://lasthavens.com/play?app=android` en **Chrome a pantalla completa**; si no hay Chrome, usa un WebView de respaldo.
- La verificación es por Digital Asset Links (`/.well-known/assetlinks.json`).
- **No aporta nada técnico**: un solo cliente (`Wow.wasm`) sirve para PC, Android e iPhone.
- Hacer una propia: "Añadir a pantalla de inicio" + `manifest.webmanifest` (lo más fácil), Bubblewrap/PWABuilder (requiere HTTPS con dominio real), o WebView propio (más delicado por `SharedArrayBuffer`).

---

## 9. Conceptos aclarados

- **`.wasm` es un binario**, como `Wow.exe`, pero compilado para la máquina virtual del navegador (funciona igual en cualquier sistema). `Wow.js` es el pegamento.
- **Tenemos el binario, no el código fuente** ("el pastel, no la receta"). Es la misma situación que con el `Wow.exe` de Blizzard en la escena de emulación: se usa y se parchea sin fuentes.
- **Programa ≠ datos**: el wasm es el programa (lo que hizo Last Havens); los MPQ son los datos (iguales a los de cualquier cliente 3.3.5a).
- **La data solo hace falta en el servidor**: el jugador no necesita tener WoW instalado; el navegador pide los bloques al servidor.
- **Parches MPQ propios** funcionan igual que en el original: `Data/patch-?.MPQ` (p. ej. `patch-4.MPQ`, `patch-A.MPQ`) y `Data/esES/patch-esES-?.MPQ`. Nuestro manifest los incluye solos; no hace falta reiniciar el servidor.
- **Publicarlo** sería redistribuir su trabajo (y los MPQ de Blizzard). Para uso personal no hay problema práctico.

---

## 10. Si algún día queremos nuestro propio cliente web

Lo único realmente difícil es **el cliente compilable a wasm**. Lo demás (proxy WS→TCP, servidor de bloques, manifest, caché OPFS) ya lo tenemos hecho o entendido.

| Base | Qué es | Pros | Contras |
|---|---|---|---|
| **[wowdecomp](https://github.com/Terrorblade/wowdecomp)** ⭐ | Decompilación C++ del `Wow.exe` 12340 (~90% funciones, "100% jugable") | Cliente original completo; ya corre en Linux con SDL2 y tiene respaldo OpenGL | Solo 64 bits (wasm es 32 → revisar), proyecto pequeño (verificar), sin licencia, audio probablemente FMOD |
| [Whoa](https://github.com/whoahq/whoa) | Reimplementación fiel (dominio público) | Arquitectura original | Solo llega a login/selección de personaje |
| [Wowee](https://github.com/Kelsidavis/wowee) | Cliente nuevo moderno (MIT + restricción comercial) | Muy completo | Render Vulkan → habría que reescribir para WebGPU |

**Plan si se retoma (con wowdecomp):**
1. Clonar y analizar: capa SDL2, backend OpenGL (¿moderno o fijo?), lectura de MPQ, sockets, por qué exige 64 bits.
2. Compilarlo en Windows y comprobar que entra al mundo en AzerothCore.
3. Emscripten + pthreads + WebGL2; enchufar WebVfs (bloques HTTP + OPFS) y WebSocket a nuestro proxy; audio abierto → WebAudio.

---

## 11. Activación de controles móviles (resuelto)
- El C++ pregunta `window.wowTouch ? 1 : 0`; **lo pone su página `/play`**, no `Wow.js`.
- Nuestra `play.html` ya lo pone: automático en pantallas táctiles, `?touch=1` para forzar (sirve en PC con ratón), `?touch=0` para desactivar.
- Modo mando: automático si `navigator.getGamepads()` detecta uno (o `wowPadSeen`). `?ps` fuerza iconos PlayStation, `?padpreview` vista previa.
- Otros parámetros URL del cliente: `?debug=1`, `?texbudget=<MB>`, `?nodxt`.
- `wowTouch` también activa `wowHalfTextures` (texturas a media resolución).

## 12. Ingeniería inversa del wasm
- **Decompilar ≠ código fuente**: da pseudocódigo para **entender**, no para recompilar.
- Herramientas: **Ghidra + [ghidra-wasm-plugin](https://github.com/nneonneo/ghidra-wasm-plugin)** (recomendado), WABT (`wasm-decompile`, `wasm2wat`/`wat2wasm`), Chrome DevTools (depurar en vivo).
- **[REA](https://github.com/morluto/rea)** (`npx rea-agents setup`): MCP que conecta agentes de IA con Ghidra/IDA/Hopper/WABT. **No reconstruye** código; para wasm solo valida, lista secciones/imports/exports y da WAT (WABT 1.0.42). Ghidra en Windows: experimental. Requiere Node 22.23.4+/24.22.1+.
- El binario **no tiene nombres de funciones** (sin sección `name`). Pistas para nombrarlas: imports/exports, strings de asserts con archivo fuente, RTTI de clases, y comparar con wowdecomp.
- Añadir funcionalidades sin fuente: addons Lua, `Wow.js`, MPQ de parche, parches de texto en el wasm, o editar WAT (difícil).

## 13. Cliente propio: el plan completo (para el futuro)
**Trabajo A — portar wowdecomp al navegador** (no se reescribe el juego, se adaptan los bordes con el SO):
| Parte | Dificultad |
|---|---|
| CMake + Emscripten; **64 → 32 bits** (primer riesgo a investigar) | 🟢–🔴 |
| **Render `CGxDevice` → WebGL2** (¿su OpenGL es moderno o de función fija?), shaders → GLSL ES 3.0, texturas DXT en móvil | 🔴 |
| Archivos → WebVfs (bloques HTTP + OPFS; lectura bloqueante vía XHR síncrono en workers / Asyncify / JSPI) | 🟡 |
| Red → WebSocket al proxy que ya tenemos | 🟢 |
| Hilos → pthreads; bucle principal → `emscripten_set_main_loop` o worker | 🟡 |
| Audio (FMOD cerrado) → miniaudio/OpenAL → WebAudio | 🟡 |
| Funciones del SO (portapapeles, URLs, hora, WTF) → `Os/Web` | 🟢 |

**Trabajo B — sus extras (táctil) encima del cliente portado:**
1. Ghidra + plugin → decompilar su `Wow.wasm`.
2. Localizar sus funciones `WebTouch*`, `WebPad*`, `WebInteract`… (~80 expuestas a Lua; archivos `WebTouch.cpp`, `WebInteract.cpp`, `WebTouchCompactFrames.cpp`, `WebTouchWorldMap.cpp`, `WebEditMode.cpp`, `WebVoiceChat.cpp`, `WebFace.cpp`).
3. Reescribirlas en C++ (copiar el **comportamiento**, guiado por el decompilado).
4. Extraer su Lua táctil y ponerlo encima (el Lua define el "contrato" de funciones).
5. Texturas TouchUI propias. Compilar.

Orden: compilar wowdecomp en Windows y verificar que entra al mundo (días) → login en navegador → mundo en navegador → táctil.
⚠️ Su Lua y su diseño son trabajo suyo: uso personal OK; para publicar, pedirles permiso o escribir versión propia.

---

## 14. 📌 PRÓXIMA SESIÓN (acordado 2026-11-10)

> ✅ **PERMISO (2026-11-10):** el equipo de Last Havens dijo que **no tienen problema en que usemos su cliente** en nuestro servidor.
> ❌ **No dan el código fuente**, salvo **pagando**.
> Pendiente: tenerlo **por escrito**, darles **créditos**, aclarar detalles (¿quitar su logo/botones OK?, ¿avisan de versiones nuevas?, ¿restricciones como no cobrar?).
> Nota técnica: usamos una copia fija de `Wow.wasm`/`Wow.js` → las actualizaciones suyas hay que bajarlas a mano y repasar `parchear.js`.
> Opciones a futuro para cliente propio: (a) portar wowdecomp, (b) **comprarles el código** si hay apoyo/presupuesto.

### 1) Mejorar `servidor-local` para producción y pruebas en un VPS — ✅ código hecho (ver §15), falta desplegar
- **HTTPS** obligatorio (fuera de `localhost` no hay `SharedArrayBuffer`): Caddy o nginx delante del Node, con dominio + certificado (Let's Encrypt).
- Configuración por archivo / variables de entorno (rutas, puertos, IP del auth/world) en vez de constantes en el código.
- Servir MPQ eficientemente: bloques **inmutables con caché larga** (`Cache-Control: immutable`), no `no-store`; streams en vez de leer a memoria; opcional CDN (Cloudflare) delante.
- Proxy WS→TCP: lista blanca de destinos (solo nuestro auth/world), límites de conexiones por IP, timeouts, logs.
- `/userdata/` **por usuario** (ahora es una sola carpeta compartida: en un VPS todos pisarían el mismo WTF).
- Servicio del sistema (systemd / pm2), reinicio automático, logs rotados.
- `manifest.webmanifest` + iconos (para "Instalar app" en Android).
- ~~Acceso restringido mientras usemos su `Wow.wasm`~~ → **ya hay permiso de Last Havens** (ver arriba). Para la fase de pruebas, opcionalmente igual proteger con contraseña (basic auth) hasta abrir oficialmente.

### 2) Probar en Android
- Con el VPS en HTTPS: abrir la URL en Chrome → "Instalar app" (equivale a su APK/TWA).
- Probar modo táctil (`wowTouch`), rendimiento, memoria, caché OPFS.
- Texturas `Interface/TouchUI` propias (joystick, botones) si salen vacías.
- Alternativas sin VPS: flag `chrome://flags/#unsafely-treat-insecure-origin-as-secure` o `adb reverse tcp:8080 tcp:8080`.

### 3) Futuro: cliente propio
**Por qué merece la pena — WarcraftXL ([repo](https://github.com/WarcraftXL/core)):**
- WarcraftXL = DLL dentro de `Wow.exe` (Win32) + MinHook sobre direcciones x86 fijas de la build 12340 (`src/offsets/`) + `Native<Fn>(addr)` + Dear ImGui sobre D3D9 (`OnEndScene`). GPL-3.0.
- **Con su `Wow.wasm`: no se puede** (no hay DLLs, ni direcciones x86, ni MinHook, ni D3D9 en el navegador). Solo cosas parecidas desde fuera: interceptar `gl*` y el WebSocket en JS, addons Lua. Nuevos opcodes con lógica en el cliente: imposible sin fuentes.
- **Con cliente propio (wowdecomp): sí, y más fácil que en el original**: sin hooks, se edita el código. Opcode nuevo = handler en `NetClient`; función Lua nueva = registrarla; ImGui con backend WebGL.
- **Puente**: las direcciones de `src/offsets/` de WarcraftXL == los `// OFFSET:` de wowdecomp (mismo `Wow.exe` 12340). Para portar un módulo: buscar la dirección → función en wowdecomp → llamada directa. La lógica de los módulos se reutiliza casi entera.

- Seguir la sección 13 (wowdecomp → wasm, luego táctil).
- Primer paso: clonar wowdecomp y revisar **por qué exige 64 bits, qué OpenGL usa y cómo hace el audio** → estimación real (semanas vs meses).

### Otras ideas sueltas
- Encender el worldserver y probar el juego completo con su cliente.
- Panel de tráfico en vivo (qué bloques de qué MPQ se piden).
- Extraer todo su Lua incrustado a archivos legibles (útil para addons ya y para el cliente propio después).
- Reintentar descargar su página `/play` (dio 502) para ver su configuración real (`wowTouch`, `wowPrefetch`…).

---

## 15. Servidor v2 para VPS (hecho 2026-11-11)

`server.js` reescrito (la versión anterior queda en `server.v1.js`). Probado en local: manifest, bloques, Range, ETag/304, userdata, traversal bloqueado, reglas del proxy WS.

| Mejora | Cómo |
|---|---|
| Configuración | `config.json` (ver `config.example.json`) o `CONFIG=/ruta`; variables `WOW_PORT`, `WOW_HOST`, `WOW_CLIENTDIR`, `WOW_LOCALE`, `WOW_BASICAUTH`, `WOW_TRUSTPROXY` |
| **Sesión por navegador** | `/play` entrega cookie `wsid` (id aleatorio **firmado HMAC**, secreto en `.cookie-secret`). Sin cookie válida → 403 en manifest/bloques/userdata/WebSocket |
| **Userdata por jugador** | `userdata/<sid>/WTF/...`; tope `maxUserdataMB`; escritura atómica |
| Caché | bloques `immutable` 1 año (la URL lleva el tamaño); `Wow.js`/`Wow.wasm` con ETag (304); manifest y userdata `no-store`. MPQ re-escaneados cada 30 s |
| Rendimiento | todo en **streams** (antes leía a memoria) |
| **Proxy WS→TCP** | lista blanca `tcpRoutes` puerto→host (la IP pedida se ignora), máx. conexiones por IP, cierre por inactividad, contrapresión |
| Acceso en pruebas | `basicAuth: "usuario:clave"` (opcional) |
| Instalar app | `public/manifest.webmanifest` + `public/icons/icon.svg`; `play.html` los enlaza |
| Despliegue | `deploy/Caddyfile` (HTTPS automático) y `deploy/wow-web.service` (systemd) |
| Aviso del servidor | `public/server-alert.txt` (opcional) se sirve en `/server-alert.txt` |

⚠️ Si se **sustituye un MPQ por otro del mismo tamaño**, los navegadores seguirán usando los bloques viejos de caché (y del OPFS). Al cambiar un parche, mejor renombrarlo (p. ej. `patch-5.MPQ`).
⚠️ Al usar `realmlist` en el VPS: en la BD `auth.realmlist.address` poner la IP que el **proxy** puede alcanzar (127.0.0.1 si el world está en el mismo VPS); el puerto debe estar en `tcpRoutes`.

---

## 16. 📌 Plan de producción para ~500 jugadores (acordado 2026-11-18, pendiente)

### Arquitectura
```
Jugadores ──HTTPS/WSS──► Cloudflare (CDN + anti-DDoS, oculta IPs)
   ├─ /blocks/*  → Worker → R2 (bucket con los bloques)   ← TODAS las descargas
   └─ resto      → Máquina WEB (Caddy + server.js: web, wasm, manifest, userdata, proxy /tcp/*)
                        │ red privada (OVH vRack / Hetzner vSwitch), mismo datacenter
                        ▼
                   Máquina CORE (authserver + worldserver + MySQL), sin puertos de juego públicos
```

### Máquinas (precios orientativos)
| | CORE | WEB |
|---|---|---|
| Tipo | Dedicado (no VPS) | VPS |
| CPU | Ryzen 8+ núcleos, buen rendimiento por núcleo | 2–4 vCPU |
| RAM | 32 GB (worldserver 6–10 GB, MySQL 8–12 GB) | 4 GB |
| Disco | 2× NVMe RAID1 | 40–80 GB NVMe |
| Red | 1 Gbps + red privada | 1 Gbps, **ilimitado o ≥ 20 TB/mes** |
| Ejemplos | OVH Game (anti-DDoS de juegos) / Hetzner AX42-52 | OVH VPS-2/3 / Hetzner CPX21-31 |
| €/mes | 50–100 | 8–15 |

- Ambas **en el mismo proveedor y datacenter**, cerca de los jugadores (Europa: OVH Francia / Hetzner DE-FI; Latinoamérica: OVH Canadá-BHS, como Last Havens). **Decidido 2026-11-18: jugadores de Latinoamérica.** Candidatos: Miami (punto medio para Latinoamérica, buen equilibrio México↔Cono Sur), OVH BHS/US-East (anti-DDoS de juegos), São Paulo si la mayoría es del Cono Sur o Brasil. Países principales: **Bolivia, Perú, México** → **recomendado Miami** (Canadá BHS suma ~30–40 ms a todos porque el tráfico pasa por EE. UU. de todas formas). El anti-DDoS de OVH pesa menos porque todo el tráfico de jugadores entra por Cloudflare (WSS) y las IPs de origen quedan ocultas: firewall de la WEB solo para rangos IP de Cloudflare, y no publicar nunca la IP. OVH **no tiene datacenter en Miami** (en EE. UU. está en Virginia/Vint Hill y Oregón). Proveedores en Miami con DDoS incluido a evaluar: **Gcore** (dedicados desde ~65 $/mes, DDoS de serie), **DataPacket** (ColoHouse Miami), **Hivelocity**; Vultr Miami para la WEB. Comprobar que el proveedor ofrezca red privada entre las dos máquinas. Pendiente: que jugadores de BO/PE/MX hagan ping a las IPs de prueba (looking glass) de los proveedores candidatos de Miami y de BHS antes de contratar. (España descartada como base; además allí hay bloqueos de IPs de Cloudflare durante los partidos de LaLiga.)
- Tráfico de juego: ~10 KB/s por jugador → 500 ≈ 40 Mbps; al mes **6–13 TB** de salida en la WEB (por eso tráfico ilimitado).
- worldserver: `MapUpdate.Threads` 4–6, visibilidad dinámica.

### Descargas: R2 + Worker
- Los bloques (`/blocks/<ruta>/<tamaño>-<i>-<N>k.bin`) son inmutables → caché eterna en Cloudflare. **No hace falta balancear con varios servidores.**
- Se **pregeneran** desde el cliente en el PC y se suben a R2 (`rclone`/`wrangler`). ~18.6 GB, ~75k objetos.
- Worker en la ruta `tudominio.com/blocks/*` con binding R2 `BLOQUES`, usando `caches.default`. Mismo dominio → sin tocar `Wow.js` ni CORS.
- Coste: R2 ≈ 0,13 $/mes (almacenamiento), salida 0 $, lecturas dentro de lo gratis; Workers Paid 5 $/mes (el gratis son 100k peticiones/día, insuficiente en apertura). Alternativa: bucket público en `blocks.tudominio.com` (0 $, pero exige CORS + cambiar URL en Wow.js).
- Reglas de caché Cloudflare: `/blocks/*` 1 año; `Wow.wasm`/`Wow.js` con `?v=`; `game-manifest.txt` 1–5 min; `/userdata/*`, `/account/*`, `/tcp/*` bypass. Activar **Tiered Cache** y **precalentar** (login + zonas de inicio) antes de abrir.
- Evitar que en producción se use `/game/` con Range (MPQ > 512 MB no se cachean en el plan gratis).

### ⚠️ Cosas a resolver al implementarlo
- `server.js` v2 protege los bloques con la cookie `wsid` (403 sin ella). Con el Worker los bloques pasan a ser **públicos**. Valorar si el Worker debe validar la cookie HMAC (mismo secreto) o aceptar que sean públicos.
- Cambiar un MPQ por otro del mismo tamaño también rompe la caché de Cloudflare → renombrar parches (§15).

### Tareas pendientes (para "luego")
1. Script que genere los bloques desde el cliente con los nombres exactos que espera WebVfs (mirar tamaño N k en `Wow.js`/server.js).
2. Worker + `wrangler.toml` + subida a R2.
3. Medir bytes reales por sesión (contador en server.js) para confirmar estimaciones.
4. Probar gratis: dominio en Cloudflare + R2 + Worker con server.js local, antes de contratar máquinas.
5. Contratar CORE + WEB, red privada, `tcpRoutes` a la IP privada del core, firewall del core solo desde la WEB.

---

## 17. 🧪 Pruebas online gratis: R2 + Worker + túnel (en curso, 2026-11-20)

**Objetivo:** que ~3 testers jueguen online contra tu AzerothCore sin que los 17 GB del cliente salgan por tu conexión. Es el paso previo (tarea 4 de §16), sin dominio propio.

**Descartado ese día:** "cliente web universal para cualquier servidor". Problemas: proxy TCP abierto, Warden (el módulo nativo no corre en wasm), parches custom de cada server, el permiso de Last Havens solo cubre TU servidor y la exposición a DMCA.

### Arquitectura
```
Navegador ─► Worker wotlk-web.<cuenta>.workers.dev
               ├─ /Wow.js, /Wow.wasm, /game/*, /blocks/*  ─► R2 bucket "wotlk-cliente"
               └─ resto (/play, manifest, /userdata, /tcp WS, WTF, realmlist) ─► túnel rápido cloudflared ─► server.js (tu PC) ─► AzerothCore
```
- Si un archivo no está en R2, el Worker lo pide a tu PC (respaldo; sirve para parches nuevos).
- Seguridad: el Worker pide la misma basicAuth (secreto `BASIC_AUTH`), y `server.js` también.
- Coste: R2 con ~17 GB ≈ 0,10 $/mes (10 GB gratis); salida gratis; Workers gratis con 100k peticiones/día (sobra para 3 personas).

### Cliente que se sube
- **`D:\Wow`** (original, sin tocar). ⚠️ NO usar `D:\Clientes de Wow\Wow3.3.5a-Limpio`: fue un intento de compactarlo y puede estar roto.
- Se sube: `Data\*.MPQ`, `Data\esES\**` (menos `realmlist.wtf`) e `Interface\AddOns\Blizzard_*` (las firmas).
- **NO** se sube el `patch-4.MPQ` custom (pendiente de revisar qué contiene) ni tus addons personales.
- Claves en R2: `game/<ruta en minúscula>`, `web/Wow.js`, `web/Wow.wasm`.

### Herramientas (sin winget en este PC; instaladas a mano)
- rclone: `%LOCALAPPDATA%\rclone\rclone.exe`, remote `r2` (token de cuenta, solo para el bucket). `rclone lsd r2:` da 403: es **normal**, usa `rclone ls r2:wotlk-cliente`.
- cloudflared: `%LOCALAPPDATA%\cloudflared\cloudflared.exe`.
- wrangler: con `npx wrangler@4`.

### Archivos (`servidor-local\deploy\`)
| Archivo | Para qué |
|---|---|
| `subir-r2.ps1` | Sube el cliente a R2. Se puede re-ejecutar (se salta lo ya subido). Opciones: `-BwLimit 2M`, `-Solo <texto>`, `-Simular` |
| `worker\` | Worker `wotlk-web` (lo único que va a Cloudflare). Probado en local con `wrangler dev` (401, R2, Range, bloques idénticos, respaldo a origen, 304, WebSocket) ✅ |
| `arrancar-online.ps1 -Auth "usuario:clave"` | Arranca `server.js` (`WOW_CLIENTDIR=D:\Wow`, `WOW_MAXWSPERIP=30`), el túnel, y hace `wrangler deploy --var ORIGIN:<url del túnel>` |
| `Caddyfile`, systemd | Del plan VPS (§15); ahora no se usan |

`server.js`: se añadió la variable de entorno `WOW_MAXWSPERIP` (detrás del Worker los testers pueden llegar con la misma IP).

### Estado / pendiente
1. ⏳ Subida a R2 en marcha (la lanzó el usuario).
2. Una sola vez: `cd servidor-local\deploy\worker` → `npx wrangler@4 login` → `npx wrangler@4 secret put BASIC_AUTH`.
3. Con AzerothCore encendido (realmlist `address = 127.0.0.1`): ejecutar `arrancar-online.ps1` y entrar a `https://wotlk-web.<cuenta>.workers.dev/play`.
4. Si te desconecta al entrar al mundo: `Warden.Enabled = 0`.
5. Más adelante: revisar `patch-4.MPQ` y subirlo con `subir-r2.ps1 -ClientDir ... -Solo patch-4`.
6. Nota: la URL del túnel rápido cambia en cada arranque (el script vuelve a desplegar el Worker con la nueva). Para una fija hace falta un dominio en Cloudflare.

### Actualizar un parche (p. ej. cambiar un Lua dentro de `patch-4.MPQ`)
- El cliente lo detecta solo **si el tamaño del MPQ cambia**: el manifest (sin caché) da el tamaño nuevo, así que las URLs de los bloques cambian y se descargan de nuevo. Los testers solo recargan la página.
- Si el tamaño queda igual, se usan los bloques viejos (caché immutable + OPFS). Solución: meter un `version.txt` con la fecha en el MPQ para forzar un cambio de tamaño, o, como plan B, renombrar a `patch-5`.
- Siempre se actualizan **los dos sitios**: `D:\Wow\Data` (de ahí sale el manifest) y R2 (`subir-r2.ps1 -Solo patch-4`).
- Worker: si el tamaño que tiene R2 no coincide con el pedido, el bloque lo sirve tu PC (respaldo). Así un olvido no da bytes viejos, solo va más lento.

### Paquete para el VPS Linux (2026-11-20)
- `servidor-local\deploy\empaquetar.ps1` genera **`D:\EmulacionWow\ExplorandoCliente\paquete-web\`** (unos 8,6 MB, 16 archivos): `servidor/` → `/srv/wow/servidor`, `web/` → `/srv/wow/web`, `deploy/` (Caddyfile, systemd, worker). Instrucciones en `paquete-web\LEEME.md`.
- Ahí **no** van los MPQ: `server.js` tiene la opción `gameIndex` (`WOW_GAMEINDEX`), que arma el manifest desde `game-index.txt` (lo genera `subir-r2.ps1`, o `-SoloIndice` para solo eso). Los bloques que no están en disco dan 404 y los sirve R2 a través del Worker.
- El manifest siempre incluye el `realmlist.wtf` del jugador con su tamaño real.
- `clientIp` usa `CF-Connecting-IP` (detrás de Cloudflare + Caddy).
- Worker: `ORIGIN` vacío = modo ruta en tu dominio (pide al mismo host, que es el VPS).
- Plantilla de config para el VPS: `servidor-local\deploy\vps\config.json`. Antes de usarla, cambiar `basicAuth` y `tcpRoutes`.
- Probado: el paquete arrancó sin MPQ → manifest con 168 entradas, Wow.wasm OK, bloques 404 (van por R2), realmlist por jugador OK.
