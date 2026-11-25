# Despliegue en el VPS de pruebas (`ssh MiWow`)

Entorno de PRUEBAS (decision del usuario 2026-11-21): web de Astro + cliente web en un solo VPS, dominio gratis de
DuckDNS, **sin R2**: los MPQ del juego estan en el disco del VPS y los sirve `server.js`. Produccion (R2 + Worker,
dos maquinas) en `docs/cliente-web.md` seccion 11. Que es el cliente web y como funciona: `docs/cliente-web.md`.

## 1. El VPS tal como esta (revisado 2026-11-21)

| | |
|---|---|
| Acceso | `ssh MiWow` (usuario `miwow`, con sudo). Debian 12, 8 nucleos, 23 GB RAM, 394 GB de disco (350 libres) |
| Proxy / HTTPS | **Apache 2.4.71** (no Caddy) + certbot (`certbot.timer` renueva solo). Modulos: proxy, proxy_http, headers, rewrite, ssl, deflate |
| Dominio | `miwow.duckdns.org`; los subdominios (`juego.miwow.duckdns.org`) ya resuelven a la misma IP (DuckDNS lo hace solo) |
| Web Astro | `/opt/miwow-web/app` (sin git: se copia el build), servicio `miwow-web.service` (usuario `miwow`, `127.0.0.1:4321`, `.env` en la carpeta), vhost `miwow.conf` + `miwow-le-ssl.conf` |
| Node | 22.23.5 en `/usr/local/bin` (+ pnpm) |
| **NO ES NUESTRO** | `wow-arcano.com` (FusionCMS en `/var/www/html`, vhosts `fusioncms*.conf`) y su **AzerothCore** (authserver/worldserver como root, puertos **3724** y **8085**), MySQL en 3306/33060 |

> **Regla: no tocar nada de wow-arcano** (sus vhosts, su core, sus BD). Antes de recargar Apache, siempre
> `sudo apache2ctl configtest` (un error tira tambien su web).
> Nota de seguridad (no es nuestro, avisar al dueno): MySQL escucha en todas las interfaces (3306/33060).

## 2. Lo que se anade

```
/opt/miwow-juego/                     (usuario miwow)
  servidor/       server.js, play.html, package.json, public/, config.json  <- web/servidor + web/deploy/vps-pruebas/config.json
  cliente-web/    Wow.js, Wow.wasm (parcheado), game-manifest.txt          <- web/cliente
  cliente/        Data/*.MPQ, Data/esES/**, Interface/AddOns/Blizzard_*    <- cliente 3.3.5a (~17 GB) + nuestro patch-4.MPQ
  userdata/       WTF de cada jugador (lo crea server.js)
/etc/systemd/system/miwow-juego.service    <- web/deploy/vps-pruebas/miwow-juego.service
/etc/apache2/sites-available/juego.conf    <- web/deploy/vps-pruebas/juego.conf (+ juego-le-ssl.conf que genera certbot)
```

Resultado: `https://miwow.duckdns.org/es/play` (Astro, pagina de entrada con el boton "Jugar") ->
`https://juego.miwow.duckdns.org/play` (el juego a pantalla completa). Por que no un iframe: `docs/cliente-web.md` y
decision 2026-11-21 (las cabeceras COOP/COEP romperian las imagenes externas de la web; en movil el juego necesita la
pantalla entera).

## 3. Puertos (el core de wow-arcano ocupa 3724/8085)

Nuestro AzerothCore (cuando se compile) va en puertos propios, solo en `127.0.0.1` si se puede:

| | wow-arcano (no tocar) | MiWow |
|---|---|---|
| authserver | 3724 | **3725** (`authserver.conf`: `RealmServerPort = 3725`) |
| worldserver | 8085 | **8086** (`worldserver.conf`: `WorldServerPort = 8086`; `acore_auth.realmlist.port = 8086`) |
| BD | las suyas | **propias** (`miwow_auth`, `miwow_characters`, `miwow_world`: nunca las de wow-arcano) |

El cliente web siempre pide el authserver en el **3724** (trae fija la IP de Last Havens y el puerto por defecto), asi que
`server.js` traduce: `tcpRoutes` = `{ "3724": "127.0.0.1:3725", "8086": "127.0.0.1" }` (puerto pedido -> host[:puerto]).
`acore_auth.realmlist.address` = `127.0.0.1` (lo alcanza `server.js`; el cliente web ignora la IP y el proxy decide).
Mientras nuestro core no exista, el cliente web carga y llega al login, pero "no se puede conectar".
**Nunca** apuntar `tcpRoutes` al core de wow-arcano.

La web de Astro: su `.env` del VPS apunta hoy a las BD que haya en ese MySQL; al tener nuestro core, `DB_AUTH_NAME`,
`DB_CHARACTERS_NAME`, `DB_WORLD_NAME` a las nuestras y `REALM_ID` a nuestro reino.

## 4. Cliente del juego en el VPS

- INSTALADO 2026-11-21: repack "Frostbound" (esES, contenido revisado por el usuario) en
  `/home/miwow/wow-client/World of Warcraft Frostbound`. En `/opt/miwow-juego/cliente/Data` solo sus MPQ de Blizzard
  (`Data/*.MPQ` y `Data/esES/*.MPQ`) como ENLACES DUROS (`ln -f`, mismo disco: no ocupan otra vez) + nuestro
  `patch-4.MPQ`. Fuera su launcher, addons (MultiBot), videos y `realmlist.wtf`. Sus tamanos NO coinciden con `D:\Wow`
  (otro empaquetado): `game-index.txt` no sirve para compararlos.
- Al extraerlo, dejar en `/opt/miwow-juego/cliente/` SOLO lo original de Blizzard:
  `Data/common.MPQ`, `common-2.MPQ`, `expansion.MPQ`, `lichking.MPQ`, `patch.MPQ`, `patch-2.MPQ`, `patch-3.MPQ`,
  `Data/esES/**` (menos `realmlist.wtf`) e `Interface/AddOns/Blizzard_*`. **Fuera** cualquier otro `patch-*.MPQ` /
  `patch-esES-4+.MPQ` o carpeta propia del repack (son de otro servidor: cambiarian la interfaz o los datos).
- **Locale `esES`** obligatorio (nuestro parche, `config.locale` y el `Config.wtf` que crea `server.js`). Si el repack es
  `enUS` (sin `Data/esES`), subir `Data\esES\` desde `D:\Wow` (scp/rsync) o cambiar de cliente.
- Comprobar que es el mismo cliente que `D:\Wow`: `web/servidor/game-index.txt` tiene los tamanos de cada archivo de `D:\Wow`
  (p. ej. `Data/patch.MPQ` = 4005207470). Comando en el paso 6.
- `patch-4.MPQ` de MiWow (empaquetado, ver `docs/cliente-web.md` seccion 5) en `cliente/Data/`.
- **Frostbound vs `D:\Wow`** (comparado 2026-11-23 por tabla de archivos): `common`, `common-2`, `expansion`, `lichking`,
  `locale-esES`, `patch-esES-2` = mismo contenido (otro empaquetado); `patch-3`, `patch-esES-3` identicos. En `patch.MPQ`,
  `patch-2.MPQ` y `patch-esES.MPQ` le faltan ~1600 entradas de 0 bytes y ~125 archivos (animaciones, texturas, piezas del
  mapa del mundo de Rasganorte) que SI estan en versiones anteriores de los MPQ base: no falta nada, carga la version vieja.
- **COMPACTADO 2026-11-23** (`tools/mpqcompact.py`, 14,1 -> 10,1 GB): de `common`..`patch-2` se quitaron los archivos que
  sustituye un MPQ posterior (orden `common < common-2 < expansion < lichking < patch < patch-2 < patch-3`; ni `esES` ni
  `patch-4` cuentan ni se tocan). Comprobado: los 177.796 archivos ganadores identicos byte a byte. Los de `Data/` ya NO son
  enlaces duros; los originales siguen en la carpeta del Frostbound. Volver atras:
  `cd /opt/miwow-juego/cliente/Data && for f in common common-2 expansion lichking patch patch-2; do ln -f "/home/miwow/wow-client/World of Warcraft Frostbound/Data/$f.MPQ" $f.MPQ; done`
  (despues, `subir-r2.sh` para que R2 vuelva a coincidir).
- **Descargas por Cloudflare (2026-11-23)**: Worker `wotlk-web` (`web/deploy/worker`, `ORIGIN = https://juego.miwow.duckdns.org`,
  sin `BASIC_AUTH`) -> entrar por **`https://wotlk-web.<cuenta>.workers.dev/play`**. Wow.js/wasm y bloques de los MPQ salen
  de R2 (`wotlk-cliente`); lo demas (play, manifest, userdata, tunel `/tcp/`) lo reenvia al VPS. Motivo: del usuario al VPS
  ~60 % de paquetes perdidos (0,1 MB/s); a Cloudflare 0 % (wasm medido a ~390 KB/s). Desplegar: `cd web\deploy\worker;
  npx wrangler@4 deploy` (sesion de wrangler en el PC del usuario).
- **R2 se sube DESDE EL VPS** (`deploy/subir-r2.sh`, rclone en `~/bin/rclone` del usuario `miwow`, remote `r2` en
  `~/.config/rclone/rclone.conf` 600 copiado del PC): `bash subir-r2.sh` = `sync` de `cliente/` a `game/` (R2 queda igual que
  el disco) + `web/`; `parche` / `web` / `simular`. `publicar-vps.ps1` lo llama solo (web en cada publicacion, `parche` con
  `-Parche`). Si R2 se queda atras, el Worker ve otro tamano y pide el bloque al VPS (lento pero correcto).

## 5. Primera instalacion (una vez) — HECHA el 2026-11-21

Estado: `miwow-juego.service` activo, vhost `juego.conf` + `juego-le-ssl.conf` (certbot, redireccion a https),
`proxy_wstunnel` activado. Comprobado desde fuera: 401 sin clave, COOP/COEP/CORP, cookie `wsid` Secure, `Wow.wasm`
(8.730.355 bytes, `application/wasm`), manifest, iconos, WebSocket 101 en `/tcp/.../3724` -> `127.0.0.1:3725`
(rechazado: nuestro core aun no existe) y `/tcp/.../8085` (wow-arcano) rechazado con 403. Webs de Astro y wow-arcano
intactas (el 403 de `wow-arcano.com` con curl es el reto anti-bots de su Cloudflare; su origen da 200).
`basicAuth` QUITADA el 2026-11-21 (decision del usuario: nadie conoce el servidor); para volver a cerrarlo, "usuario:clave" en `/opt/miwow-juego/servidor/config.json` y reiniciar `miwow-juego`.
Falta: el cliente del juego en `cliente/` (paso 4) y nuestro core.

Desde el PC (PowerShell, en la raiz del repo). `web\deploy\publicar-vps.ps1` hace los pasos 1-2 y reinicia el servicio:
```powershell
web\deploy\publicar-vps.ps1            # servidor + cliente-web (Wow.js/wasm/manifest); -Parche <ruta> sube tambien patch-4.MPQ
```
En el VPS (`ssh MiWow`):
```bash
# 1) carpetas
sudo mkdir -p /opt/miwow-juego/{servidor,cliente-web,cliente,userdata} && sudo chown -R miwow:miwow /opt/miwow-juego
# 2) (lo hace publicar-vps.ps1) dependencias: cd /opt/miwow-juego/servidor && npm ci --omit=dev
# 3) config: editar /opt/miwow-juego/servidor/config.json -> basicAuth (usuario:clave de pruebas) y tcpRoutes
# 4) servicio
sudo cp /opt/miwow-juego/servidor/deploy/miwow-juego.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now miwow-juego
journalctl -u miwow-juego -n 20      # "juego: N archivos" y "Listo: http://127.0.0.1:8080/play"
# 5) Apache: modulo de WebSocket y vhost (SOLO el nuestro)
sudo a2enmod proxy_wstunnel
sudo cp /opt/miwow-juego/servidor/deploy/juego.conf /etc/apache2/sites-available/juego.conf
sudo a2ensite juego && sudo apache2ctl configtest && sudo systemctl reload apache2
# 6) HTTPS: certbot crea juego-le-ssl.conf con el mismo contenido + certificado, y la redireccion a https
sudo certbot --apache -d juego.miwow.duckdns.org
sudo apache2ctl configtest && sudo systemctl reload apache2
```
Comprobar: `curl -sI https://juego.miwow.duckdns.org/healthz` (200) y abrir `https://juego.miwow.duckdns.org/play`
(en la consola del navegador `crossOriginIsolated` = true).

## 6. Comprobaciones utiles

```bash
# el cliente subido coincide con D:\Wow (tamanos de game-index.txt)
cd /opt/miwow-juego/cliente && while IFS=$'\t' read -r sz rel; do
  [ -f "$rel" ] || { echo "FALTA $rel"; continue; }
  [ "$(stat -c %s "$rel")" = "$sz" ] || echo "DISTINTO $rel"; done < /opt/miwow-juego/servidor/game-index.txt
ls /opt/miwow-juego/cliente/Data/                     # solo los MPQ de Blizzard + patch-4.MPQ
journalctl -u miwow-juego -f                          # peticiones raras, WS abiertos/cerrados, 404 de bloques
```

## 7. Actualizar

| Cambio | Que hacer |
|---|---|
| Parche de MiWow | empaquetarlo (con tamano distinto al anterior), `web\deploy\publicar-vps.ps1 -Parche <ruta>`; los jugadores recargan |
| `server.js` / `play.html` / config de ejemplo | `web\deploy\publicar-vps.ps1` (copia y reinicia `miwow-juego`) |
| `Wow.wasm` (nuevos parches con `parchear.js`) | `node web\herramientas\parchear.js` y `web\deploy\publicar-vps.ps1` |
| Web de Astro | como hasta ahora (build y copia a `/opt/miwow-web/app`, `sudo systemctl restart miwow-web`) |

`publicar-vps.ps1` NUNCA sube `config.json` (el del VPS tiene la clave real) ni toca `userdata/`.

## 8. Core de MiWow en el VPS (DESPLEGADO el 2026-11-21)

Decisiones del usuario: respetar el servidor de wow-arcano (otros puertos, nada suyo se modifica) y usar en MySQL
**solo el usuario de la web, `miwow_web`** (su contrasena sale de `/opt/miwow-web/app/.env` `DB_PASSWORD`; no se crean usuarios).

### Repos (GitHub, publicos)
| Repo | Rama | En el VPS |
|---|---|---|
| `https://github.com/black7in/miwow-azerothcore` (fork del core) | `tradicional` | `/opt/miwow-core/src` (clon de AzerothCore oficial + remoto `miwow` con nuestra rama) |
| `https://github.com/black7in/miwow` (este repo) | `tradicional` | `/opt/miwow-core/miwow`; `src/modules/mod-miwow` = enlace simbolico a `miwow/modules/mod-miwow` |

### Carpetas
```
/opt/miwow-core/
  src/      core (git)            build/   CMake (no versionado)
  miwow/    este repo (git)       server/  instalacion: bin/ (authserver, worldserver), etc/ (*.conf, modules/)
  data/     dbc, maps, vmaps, mmaps, Cameras        logs/
```
`data/` = copia de `/home/azeroth-server/data` (wow-arcano: misma extraccion, se comprobaron tamanos; su carpeta solo
se LEYO) + nuestros archivos: mapas 750-754 (maps/vmaps/mmaps), modelos de colision de los circuitos, `Cameras` y 9 teselas
de mmaps del mapa 562 que difieren por version del generador (88 archivos, ~12 MB, subidos desde
`server\bin\RelWithDebInfo\data`). Tras regenerar mapas propios: volver a subir sus archivos `75x*`.

### Compilar (dependencias ya instaladas: cmake 3.25, clang 14, boost 1.74, libmysqlclient 8.4)
```bash
cd /opt/miwow-core/src && git fetch miwow && git checkout tradicional && git reset --hard miwow/tradicional
cd /opt/miwow-core/miwow && git pull
mkdir -p /opt/miwow-core/build && cd /opt/miwow-core/build
cmake ../src -DCMAKE_INSTALL_PREFIX=/opt/miwow-core/server -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
      -DWITH_WARNINGS=1 -DTOOLS_BUILD=none -DSCRIPTS=static -DMODULES=static -DCMAKE_CXX_FLAGS="-include utility"
nice -n 15 make -j6 install > build.log 2>&1     # -j6 + nice: no quitar CPU al worldserver de wow-arcano
```
`-include utility`: a `MySQLConnection.cpp` de AzerothCore (base 2948c203f) le falta `#include <utility>` para
`std::exchange`; MSVC lo trae de rebote, clang 14 + libstdc++ 12 no. Se arregla sin tocar el core.

Primera compilacion (2026-11-21): mientras el push del core a GitHub seguia en marcha, `src` = AzerothCore oficial en
`2948c203f` + nuestros 6 commits con `git format-patch`/`git am`. Terminado el push, `src` sigue a `miwow/tradicional`
(remoto `miwow` = `black7in/miwow-azerothcore`; mismo arbol `dff44864`, sin recompilar). Actualizar:
`git fetch miwow && git reset --hard miwow/tradicional`.

### Base de datos (MySQL 8.4 compartido)
- BD propias `miwow_auth`, `miwow_characters`, `miwow_world` (utf8mb4; CREADAS el 2026-11-21 con `sudo mysql`) con
  `GRANT ALL` SOLO a `miwow_web` sobre esas tres. No se toca ninguna BD ni usuario de wow-arcano (`acore_*`, `acore`, `root`).
- HECHO 2026-11-21: la web de Astro (`/opt/miwow-web/app/.env`) apunta a `miwow_auth/characters/world` (antes leia las
  `acore_*` de wow-arcano y su registro creaba cuentas en SU `acore_auth.account`; copia en `.env.bak-acore-20261121`).
  Las variables son `astro:env` secretas: se leen al arrancar (`systemctl restart miwow-web`, sin recompilar).
  A `miwow_web` se le quitaron TODOS los permisos sobre `acore_*`: solo tiene `miwow_web`, `miwow_auth`,
  `miwow_characters`, `miwow_world`.

### Configuracion (`/opt/miwow-core/server/etc`, no versionada, `chmod 600`)
| Clave | Valor |
|---|---|
| `LoginDatabaseInfo` / `WorldDatabaseInfo` / `CharacterDatabaseInfo` | `"127.0.0.1;3306;miwow_web;<clave>;miwow_auth"` / `..._world` / `..._characters` |
| `RealmServerPort` (authserver) | `3725` |
| `WorldServerPort` (worldserver) | `8086` |
| `DataDir` / `LogsDir` | `"/opt/miwow-core/data"` / `"/opt/miwow-core/logs"` |
| `Console.Enable` | `0` (servicio systemd sin consola) |
| `modules/mod_miwow.conf` | copia de `mod_miwow.conf.dist` (juego: igual en todos los entornos) |

`miwow_auth.realmlist`: `address` = IP publica del VPS (clientes de PC), `localAddress = 127.0.0.1`,
`localSubnetMask = 255.255.255.255` (el proxy del cliente web llega desde 127.0.0.1), `port = 8086`.
Servicios `miwow-auth` / `miwow-world` (usuario `miwow`, plantillas en `web/deploy/vps-pruebas/`): INSTALADOS y
habilitados. Los `.conf` se generaron desde los `.dist` con un script (claves de la tabla de arriba + `SourceDirectory`
= `/opt/miwow-core/src` para el updater, `TempDir`, `SOAP`); `mod_miwow.conf` = copia del `.dist`.

### Comandos GM sin consola: SOAP
`Console.Enable = 0` (systemd) -> los comandos van por SOAP, SOLO en `127.0.0.1:7879` (7878 es el de por defecto;
comprobado cerrado desde fuera). Se autentica con una cuenta GM 3:
```bash
curl -s -u USUARIO:CLAVE -H 'Content-Type: text/xml' http://127.0.0.1:7879/ -d '<?xml version="1.0"?><SOAP-ENV:Envelope
 xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:AC"><SOAP-ENV:Body><ns1:executeCommand>
 <command>account create nombre clave</command></ns1:executeCommand></SOAP-ENV:Body></SOAP-ENV:Envelope>'
```
Primera cuenta GM (`BLACK`, nivel 3, todos los reinos) creada directamente en `miwow_auth` con SRP6 (mismo calculo que
`AccountMgr`: g = 7, N del core, x = SHA1(sal | SHA1(USUARIO:CLAVE)) little-endian), porque SOAP necesita ya una cuenta GM.

### Estado del arranque (2026-11-21)
- auth en 3725 y world en 8086 abiertos a Internet (clientes de PC: `set realmlist 144.126.158.141:3725`; el puerto en
  el realmlist del cliente es obligatorio, 3724 es de wow-arcano). Cliente web: `tcpRoutes` 3724 -> 127.0.0.1:3725.
- `realmlist` id 1 `MiWow`: `address 144.126.158.141`, `localAddress 127.0.0.1/255.255.255.255`, `port 8086`.
- El updater creo las tres BD y aplico el SQL del modulo; cargan carrera (752/753) y parkour (754).
- Aviso NO fatal: 66 teselas de mmaps `built with generator v19, expected v20` (los mmaps de `data/` son anteriores al
  core actual; en esas teselas no hay navegacion de PNJ). Regenerarlos con `mmaps_generator` del core actual (pendiente).
- Arreglo de compilacion en clang 14: `MiWowGuildSeason.cpp` capturaba un structured binding en una lambda (lo permite
  C++20/MSVC, clang < 16 no). Corregido en el repo; en el VPS se copio el archivo a mano hasta el siguiente commit.
- 2026-11-25: desplegado `7b808a4` (auto-aprendizaje, defensa del castillo, voz desactivada): compila en clang 14
  sin errores; `mod_miwow.conf` sustituido por el `.dist` nuevo (copia `mod_miwow.conf.bak-20261125`); subidos los
  archivos del mapa 755 (`maps`, `vmaps`, `mmaps`, `755_castillo.txt`). Avisos `Missing property MiWow.Voice.*` al
  arrancar: normales mientras no haya voz en el VPS.

## 9. Pendiente

- Nuestro AzerothCore en el VPS (compilar, BD propias, puertos 3725/8086, `Warden.Enabled` segun la prueba).
- Pagina `/[lang]/play` de Astro con el boton "Jugar" (URL del cliente web en los ajustes de la web).
- Trafico: sin R2 todas las descargas salen del VPS (~50 MB por jugador hasta el login, mas al viajar por el mundo).
