# Despliegue de EventWow

Checklist para montar un entorno (local o produccion). La configuracion se divide en tres tipos:

| Tipo | Donde vive | Versionado |
|---|---|---|
| **Juego** (igual en todos los entornos) | `modules/mod-eventwow/conf/mod_eventwow.conf.dist` (pisa `worldserver.conf`) | Si |
| **Datos de BD** | `modules/mod-eventwow/data/sql/db-*/` (los aplica el updater de AzerothCore al arrancar) | Si |
| **Infraestructura** (cambia por entorno) | `worldserver.conf`, `authserver.conf`, tabla `acore_auth.realmlist` | No (solo esta lista) |

## 1. Compilar

- AzerothCore con `mod-eventwow` dentro de `azerothcore-wotlk/modules/` (junction a `EventWow/modules/mod-eventwow`).
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
| `DataDir` | carpeta con dbc/maps/vmaps/mmaps | | |
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

- Copiar `configs/modules/mod_eventwow.conf.dist` a `configs/modules/mod_eventwow.conf`.
- Al arrancar, el log debe mostrar `Using modules configuration: > mod_eventwow.conf`.

## 4. Auditoria antes de produccion

```powershell
.\tools\Diff-Config.ps1 -Conf <ruta>\worldserver.conf -Dist <ruta>\worldserver.conf.dist `
    -Overrides .\modules\mod-eventwow\conf\mod_eventwow.conf.dist
```

Toda clave CAMBIADA/ANADIDA debe ser de infraestructura (estar en la tabla de arriba) o estar pisada por el modulo.
Si no, moverla a `mod_eventwow.conf.dist` o documentarla aqui.

## 5. Cliente

- `Config.wtf`: `SET locale "esES"`, `SET realmList "<host>"`.
- Copiar `client/patches/patch-4.MPQ` a `Data\` (generar con `tools/Build-Patch.ps1`).
- `Wow.exe` parcheado para aceptar interfaz modificada.
