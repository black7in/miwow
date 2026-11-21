# Paquete web MiWow (cliente WoW 3.3.5a en navegador) para el VPS Linux

> Lo genera `web/deploy/empaquetar.ps1` en `web/paquete/`. Documentacion completa: `docs/cliente-web.md`.

Este paquete trae **solo** lo que necesita el servidor web. Los 17 GB del cliente **no** van aquí: están en R2 (bucket `wotlk-cliente`) y los sirve el Worker.

```
paquete-web/
├─ servidor/   -> /srv/wow/servidor   (server.js, play.html, iconos, game-index.txt, config.json)
├─ web/        -> /srv/wow/web        (Wow.js, Wow.wasm, game-manifest.txt)
└─ deploy/                            (NO se copia tal cual: son plantillas)
   ├─ Caddyfile         -> /etc/caddy/Caddyfile
   ├─ wow-web.service   -> /etc/systemd/system/wow-web.service
   └─ worker/           -> se publica en Cloudflare con wrangler (desde tu PC)
```

En el VPS se crean solas: `/srv/wow/userdata` (datos de cada jugador) y `/srv/wow/servidor/.cookie-secret`.

## 1. Preparar el VPS (Debian/Ubuntu, una sola vez)
```bash
sudo apt update && sudo apt install -y nodejs npm     # Node 18 o más nuevo
sudo useradd -r -m -d /srv/wow -s /usr/sbin/nologin wow
sudo mkdir -p /srv/wow/servidor /srv/wow/web /srv/wow/userdata
```

## 2. Copiar el paquete (desde tu PC)
```bash
scp -r paquete-web/servidor/* usuario@IP-VPS:/tmp/servidor/
scp -r paquete-web/web/*      usuario@IP-VPS:/tmp/web/
```
y en el VPS:
```bash
sudo cp -r /tmp/servidor/* /srv/wow/servidor/ && sudo cp -r /tmp/web/* /srv/wow/web/
cd /srv/wow/servidor && sudo npm ci --omit=dev
sudo chown -R wow:wow /srv/wow
```

## 3. Configurar `/srv/wow/servidor/config.json`
- `basicAuth`: **cámbiala** (o `""` para abrirlo a todos).
- `tcpRoutes`: dónde está AzerothCore. `127.0.0.1` si está en el mismo VPS; si no, su IP (privada si se puede).
- En la BD de AzerothCore: `auth.realmlist.address` = la IP que **este VPS** alcanza (la misma de `tcpRoutes`).
- Si te desconecta al entrar al mundo: `Warden.Enabled = 0` en `worldserver.conf`.

## 4. Servicio + HTTPS
```bash
sudo cp deploy/wow-web.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now wow-web
journalctl -u wow-web -f          # debe decir "juego (gameIndex): 165 archivos" y "Listo"
```
Caddy (HTTPS automático): instalarlo (https://caddyserver.com/docs/install), poner tu dominio en `deploy/Caddyfile`, copiarlo a `/etc/caddy/Caddyfile` y hacer `sudo systemctl reload caddy`.

## 5. Worker (desde tu PC, en `deploy/worker`)
Con dominio en Cloudflare (proxy naranja activado para `wow.tudominio.com`), en `wrangler.toml`:
```toml
workers_dev = false
routes = [ { pattern = "wow.tudominio.com/*", zone_name = "tudominio.com" } ]
[vars]
ORIGIN = ""          # vacío: lo que no está en R2 va directo al VPS
LOCALE = "esES"
```
```powershell
npx wrangler@4 secret put BASIC_AUTH     # el mismo usuario:clave del config.json ("" si está abierto)
npx wrangler@4 deploy
```
Para muchos jugadores puedes limitar las rutas a `/blocks/*`, `/game/*`, `/Wow.js` y `/Wow.wasm` (docs/cliente-web.md del repo MiWow, "Produccion").

## Actualizar
- **Parche nuevo o cambiado:** súbelo a R2 (`subir-r2.ps1 -Solo patch-4`), vuelve a generar el índice (`subir-r2.ps1 -SoloIndice`), copia `game-index.txt` a `/srv/wow/servidor/` (se relee solo cada 30 s).
- **server.js / play.html:** cópialos y `sudo systemctl restart wow-web`.
- **Wow.wasm nuevo:** súbelo a R2 (`subir-r2.ps1 -Solo web/`) **y** cópialo a `/srv/wow/web/`.
