# Cliente (`client/`)

- Idioma base: **esES**. Cliente de pruebas: `D:\Clientes de Wow\Wow - copia` (`Config.wtf` con `SET locale "esES"`).
  `Wow.exe` ya parcheado para aceptar interfaz modificada.
- `interface-original/` = Interface esES consolidada (`tools/Merge-Interface.ps1`, `manifest.csv` dice de que MPQ sale
  cada archivo). SOLO LECTURA, nunca editar. Para modificar: copiar a `src/` con la misma ruta y editar ahi.
- Archivos propios en `src/Interface/FrameXML/` (anadidos al final de `FrameXML.toc`):
  `MiWowProtocol.lua` (protocolo, `docs/protocolo.md`), `MiWow.lua` (modos `"world"` = interfaz nativa intacta |
  `"match"` = en partida: HUD del juego y la interfaz nativa SIN CAMBIOS (`MIWOW_MATCH_RESTRICT_UI = false`,
  2026-11-24; con true vuelve la interfaz restringida de main: marcos ocultos, ventanas/acciones bloqueadas)),
  `MiWowPanel.lua` (panel de eventos 860x560 arrastrable; boton en el minimapa, `/miwow`, `/eventos`),
  `MiWowMatchFound.lua`, `MiWowMatch.lua`, `MiWowRace.lua`, `MiWowParkour.lua`, `MiWowGuild.lua` (`docs/hermandad.md`),
  `MiWowTouchSkin.lua` (HUD tactil del cliente web: ver `web/CLAUDE.md`). Glue y `GlobalStrings.lua` ORIGINALES.
- Los originales usan **CRLF**: normalizar tras editar uno copiado (`sed -i 's/\r$//; s/$/\r/' archivo`).
- Preferir ganchos en Lua sobre editar XML. Toda linea anadida a una funcion original lleva `-- MiWow`; la logica propia
  va en un bloque `MiWow` al final. Para interceptar funciones globales de otros archivos, envolverlas desde un archivo
  que cargue despues segun el `.toc`, en vez de copiar el original.
- No hay interprete Lua instalado: revisar sintaxis a mano (cuidado con `local` declarados mas abajo del uso). Errores en
  cliente: `SET scriptErrors "1"`.

## Parche
- `powershell -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1` -> `patches/patch-4.MPQ` (carpeta, PC) y
  `patches/web/patch-4.MPQ` (empaquetado, cliente web). `-Rapido` (~16 s): solo `src` encima del parche anterior (cambios
  de Lua/texturas; si cambian DBC, mapas o se borran archivos de `src`: generacion completa). `-SkipDbc` sin la BD.
- **Claude SIEMPRE regenera el parche tras cambios de cliente.** El usuario copia `patches/patch-4.MPQ` a `Data\` y
  prueba a mano con `patches/Instalar-Parche.ps1` (SOLO lo ejecuta el usuario). No lanzar el cliente.
- `Data\patch-4.MPQ` (carpeta) tiene prioridad sobre los MPQ de locale; no usar `patch-esES-N`.

## DBC
- Fuente de verdad = tablas `*_dbc` de AzerothCore en la BD world (SQL del modulo). El servidor las fusiona con sus DBC
  al arrancar (sus archivos DBC, ingles, NO se tocan). El cliente recibe el DBC original de `DBCs/DBCesES` (no
  versionado; `DBCenEN` = ingles) + nuestras filas (ID >= 9500000) en `patch-4.MPQ/DBFilesClient`: lo hace `Build-Patch`
  (necesita la BD arrancada).
- Si cambia SQL del modulo que afecta a DBC, Claude lo aplica a la BD de desarrollo ANTES de `Build-Patch` (el updater lo
  reaplica al arrancar: SQL idempotente). Nunca pedir al usuario que aplique SQL a mano.
- Objetos: `item_dbc` se rellena DESDE `item_template` en el SQL (con `DBC.EnforceItemAttributes = 1` deben coincidir).
- `tools/Build-Dbc.ps1` exporta `map_dbc` en el rango 750-799.
