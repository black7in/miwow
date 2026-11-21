# Cliente web y movil de MiWow

Backend y herramientas para jugar a MiWow desde el navegador (PC, Android, iPhone) con el cliente 3.3.5a en
WebAssembly de Last Havens (usado con su permiso). **Documentacion completa: [`docs/cliente-web.md`](../docs/cliente-web.md).**

| Carpeta | Que hay |
|---|---|
| `cliente/` | `Wow.wasm`, `Wow.original.wasm`, `Wow.js`, `game-manifest.txt` (de Last Havens, **no versionado**: guardar copia aparte) |
| `servidor/` | `server.js` (archivos por bloques + proxy WebSocket->TCP), `play.html`, configs de ejemplo, `public/` |
| `herramientas/` | `parchear.js` (deja el wasm igual que el cliente de PC: Glue original, sin nada de Last Havens), `extraer-lua.js` (vuelca su Lua para leerlo) |
| `deploy/` | R2 (`subir-r2.ps1`), pruebas online (`arrancar-online.ps1`), paquete del VPS (`empaquetar.ps1`), Worker, Caddy, systemd |
| `referencia/` | estudio original, su APK y su Lua extraido (solo el estudio se versiona) |

Comandos rapidos:
```powershell
node web\herramientas\parchear.js                # Wow.original.wasm -> Wow.wasm
node web\herramientas\extraer-lua.js             # su Lua -> referencia\lua-lasthavens\
cd web\servidor; npm ci; node server.js          # local: http://localhost:8080/play (config.json desde config.local.example.json)
web\deploy\arrancar-online.ps1 -Auth "usuario:clave"   # pruebas online por Cloudflare
web\deploy\empaquetar.ps1                        # web\paquete\ para el VPS
```

El parche de MiWow va como **MPQ empaquetado** en `D:\Wow\Data\patch-4.MPQ` (la carpeta no funciona en la web) y su
tamano debe cambiar en cada version: ver "Parche de MiWow" en la documentacion.
