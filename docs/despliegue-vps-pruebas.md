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

- Lo esta bajando el usuario (2026-11-21) a `~/wow-client/` (un `.rar` de un repack 3.3.5a de terceros).
- Al extraerlo, dejar en `/opt/miwow-juego/cliente/` SOLO lo original de Blizzard:
  `Data/common.MPQ`, `common-2.MPQ`, `expansion.MPQ`, `lichking.MPQ`, `patch.MPQ`, `patch-2.MPQ`, `patch-3.MPQ`,
  `Data/esES/**` (menos `realmlist.wtf`) e `Interface/AddOns/Blizzard_*`. **Fuera** cualquier otro `patch-*.MPQ` /
  `patch-esES-4+.MPQ` o carpeta propia del repack (son de otro servidor: cambiarian la interfaz o los datos).
- **Locale `esES`** obligatorio (nuestro parche, `config.locale` y el `Config.wtf` que crea `server.js`). Si el repack es
  `enUS` (sin `Data/esES`), subir `Data\esES\` desde `D:\Wow` (scp/rsync) o cambiar de cliente.
- Comprobar que es el mismo cliente que `D:\Wow`: `web/servidor/game-index.txt` tiene los tamanos de cada archivo de `D:\Wow`
  (p. ej. `Data/patch.MPQ` = 4005207470). Comando en el paso 6.
- `patch-4.MPQ` de MiWow (empaquetado, ver `docs/cliente-web.md` seccion 5) en `cliente/Data/`.

## 5. Primera instalacion (una vez) — HECHA el 2026-11-21

Estado: `miwow-juego.service` activo, vhost `juego.conf` + `juego-le-ssl.conf` (certbot, redireccion a https),
`proxy_wstunnel` activado. Comprobado desde fuera: 401 sin clave, COOP/COEP/CORP, cookie `wsid` Secure, `Wow.wasm`
(8.730.355 bytes, `application/wasm`), manifest, iconos, WebSocket 101 en `/tcp/.../3724` -> `127.0.0.1:3725`
(rechazado: nuestro core aun no existe) y `/tcp/.../8085` (wow-arcano) rechazado con 403. Webs de Astro y wow-arcano
intactas (el 403 de `wow-arcano.com` con curl es el reto anti-bots de su Cloudflare; su origen da 200).
La clave de pruebas (`basicAuth`) esta solo en `/opt/miwow-juego/servidor/config.json` del VPS (`chmod 600`).
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
(pide la basicAuth; en la consola del navegador `crossOriginIsolated` = true).

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

## 8. Pendiente

- Nuestro AzerothCore en el VPS (compilar, BD propias, puertos 3725/8086, `Warden.Enabled` segun la prueba).
- Pagina `/[lang]/play` de Astro con el boton "Jugar" (URL del cliente web en los ajustes de la web).
- Quitar la basicAuth cuando se abra a todo el mundo.
- Trafico: sin R2 todas las descargas salen del VPS (~50 MB por jugador hasta el login, mas al viajar por el mundo).
