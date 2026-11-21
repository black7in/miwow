# Despliegue de MiWow

Checklist para montar un entorno (local o produccion). La configuracion se divide en tres tipos:

| Tipo | Donde vive | Versionado |
|---|---|---|
| **Juego** (igual en todos los entornos) | `modules/mod-miwow/conf/mod_miwow.conf.dist` (pisa `worldserver.conf`) | Si |
| **Datos de BD** | `modules/mod-miwow/data/sql/db-*/` (los aplica el updater de AzerothCore al arrancar) | Si |
| **Infraestructura** (cambia por entorno) | `worldserver.conf`, `authserver.conf`, tabla `acore_auth.realmlist` | No (solo esta lista) |

## 1. Compilar

- AzerothCore con `mod-miwow` dentro de `azerothcore-wotlk/modules/` (junction a `MiWow/modules/mod-miwow`).
- Tras anadir/quitar archivos del modulo: volver a correr CMake.

## 2. Configuracion de infraestructura

Partir de los `.conf.dist` limpios y tocar SOLO estas claves (o definirlas como variables de entorno `AC_<CLAVE>`,
p.ej. `AC_LOGIN_DATABASE_INFO`):

### worldserver.conf
| Clave | Para que | Local | Produccion |
|---|---|---|---|
| `LoginDatabaseInfo` | conexion a acore_auth | | |
| `WorldDatabaseInfo` | conexion a acore_world | | |
| `CharacterDatabaseInfo` | conexion a acore_characters | | |
| `DataDir` | carpeta con dbc/maps/vmaps/mmaps (+ los de los mapas propios 750-799: `Build-Patch` + `mmaps_generator`, ver `docs/mapas.md`) | | |
| `LogsDir` | carpeta de logs | | |
| `RealmID` | id del reino en acore_auth.realmlist | | |
| `WorldServerPort` | puerto del mundo (8085) | | |
| `BindIP` | IP de escucha | | |

### authserver.conf
| Clave | Para que | Local | Produccion |
|---|---|---|---|
| `LoginDatabaseInfo` | conexion a acore_auth | | |
| `RealmServerPort` | puerto de login (3724) | | |
| `BindIP` | IP de escucha | | |

### acore_auth.realmlist
| Columna | Para que |
|---|---|
| `name` | nombre del reino (debe coincidir con `SET realmName` del cliente si se usa) |
| `address` / `localAddress` | IP publica / local que reciben los clientes |
| `port` | `WorldServerPort` |

> Si se toca cualquier otra clave de infraestructura, anadirla aqui.

## 3. Configuracion del juego

- Copiar `configs/modules/mod_miwow.conf.dist` a `configs/modules/mod_miwow.conf`.
- Al arrancar, el log debe mostrar `Using modules configuration: > mod_miwow.conf`.

## 4. Auditoria antes de produccion

```powershell
.\tools\Diff-Config.ps1 -Conf <ruta>\worldserver.conf -Dist <ruta>\worldserver.conf.dist `
    -Overrides .\modules\mod-miwow\conf\mod_miwow.conf.dist
```

Toda clave CAMBIADA/ANADIDA debe ser de infraestructura (estar en la tabla de arriba) o estar pisada por el modulo.
Si no, moverla a `mod_miwow.conf.dist` o documentarla aqui.

## 5. Cliente

- `Config.wtf`: `SET locale "esES"`, `SET realmList "<host>"`.
- Copiar `client/patches/patch-4.MPQ` a `Data\` (generar con `tools/Build-Patch.ps1`).
- `Wow.exe` parcheado para aceptar interfaz modificada.

## 6. Migraciones de BD (una vez por entorno)

### Renombrado EventWow -> MiWow (2026-11-21)

Los SQL del modulo pasaron de `*_eventwow_*` a `*_miwow_*` y el script de los hechizos de `spell_eventwow_*` a
`spell_miwow_*`. En una BD donde ya se aplicaron con el nombre antiguo, ANTES de arrancar el worldserver nuevo
(si no, el updater ve los antiguos como borrados: "Cleanup is disabled!"):

```sql
-- BD world y BD auth
UPDATE `updates` SET `name` = REPLACE(`name`, 'eventwow', 'miwow') WHERE `name` LIKE '%eventwow%';
```

Al arrancar, el updater reaplica los que cambiaron de contenido (son idempotentes). Tambien: el modulo se llama
`mod-miwow` (volver a pasar CMake) y su config `configs/modules/mod_miwow.conf` (borrar `mod_eventwow.conf*`).
