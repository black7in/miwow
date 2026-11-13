# Mapas propios (desde Warcraft 3)

Los mapas de los minijuegos se disenan en el **World Editor de Warcraft 3 (1.26)** y `tools/mapgen` los convierte
al formato de WoW 3.3.5: terreno del cliente (ADT/WDT en `patch-4.MPQ`) y del servidor (`.map`).

```
Maps/<carpeta>/<mapa>.w3m|.w3x  --(Maps/maps.json)-->  tools/mapgen  -->  cliente: World\Maps\<Directory>\
                                                                      -->  servidor: <DataDir>\maps\<id>3232.map
SQL del modulo (map_dbc, mapdifficulty_dbc, instance_template) --> Build-Dbc --> Map.dbc / MapDifficulty.dbc del cliente
mmaps_generator <id> (a mano, tras generar el .map) --> <DataDir>\mmaps (caminos de los PNJ)
```

## Anadir un mapa

1. Guardar el mapa de WC3 (sin proteger) en `Maps/<carpeta>/`.
2. Entrada en `Maps/maps.json`:
   - `id`: rango reservado **750-799** (los de WotLK llegan a 724; `TC9Sidecar.h` limita a 800 y el cliente y el
     core dimensionan tablas por el ID mas alto, por eso no se usa el rango 9500000).
   - `directory`: nombre de la carpeta en `World\Maps` (ASCII, sin espacios).
   - `source`: ruta del mapa de WC3 relativa a `Maps/`.
   - Opcionales: `yardsPerTile` (4), `cliffYards` (8), `wallHeight` (auto = parte mas alta + `wallExtra` 15),
     `textures` (sobrescribe la tabla `TEXTURES` de `mapgen.py`: tipo de casilla de WC3 -> BLP de WoW).
3. SQL del modulo (copiar `2026_11_13_10_eventwow_map_test.sql`): `map_dbc` (mazmorra, `InstanceType = 1`; nombre en
   las 16 columnas de idioma), `mapdifficulty_dbc` (ID propio 9500000+, sin reinicio) e `instance_template`.
4. `Build-Patch` (BD arrancada y con el SQL aplicado): genera el parche con Map.dbc + el mapa, y el `.map` en
   `server\bin\RelWithDebInfo\data\maps` (`-ServerDataDir` para otra ruta).
5. mmaps: `mmaps_generator <id>` desde el DataDir (necesita `mmaps-config.yaml`; herramientas de AC compiladas con
   `TOOLS_BUILD`). Sin mmaps los jugadores van bien, pero los PNJ no encuentran caminos.
6. Juego: `MapId` = id y `Start` = punto que imprime mapgen (inicio del jugador 1 o una region).

## Conversion

- Colocacion: el mapa de WC3 se centra en un bloque de n x n ADT empezando por el `32_32` (esquina noroeste del
  bloque en X = 0, Y = 0; el mapa ocupa X e Y negativas). Norte de WC3 = norte de WoW (+X), este = -Y.
- Escala: 1 casilla de WC3 (128 unidades) = `yardsPerTile` yardas; el relieve suave se escala igual.
- Acantilados: cada nivel = `cliffYards` (a escala real serian 4 yardas, que en WoW se suben andando). Las rampas
  de WC3 se aproximan (nivel = media de los vecinos).
- Borde no jugable del mapa de WC3 y todo lo de fuera: muro de `wallHeight`.
- Texturas: por casilla de WC3 (mezcla bilineal, hasta 4 por chunk); casillas de acantilado con la textura de su
  acantilado; plaga = `blight`; muro = `wall`. Alfa de 4 bits.
- Agua: casillas de WC3 con agua -> MH2O (cliente) / MLIQ (servidor), tipo 5 (agua lenta), nivel de WC3.
- Puntos: mapgen imprime los puntos de inicio (`sloc`) y el centro de cada region en coordenadas de WoW (con Z del
  terreno y orientacion). Nombrar las regiones en WC3 (`Inicio`, `Oleada1`, `Tienda`...).
- Sin convertir todavia: decoracion (`war3map.doo`), unidades (salvo puntos de inicio), vmaps (sin objetos no hacen
  falta: el servidor solo deja un mensaje de depuracion), sombras, sonidos, zona (`AreaTable` = 0).

## Formato (comprobado)

- ADT comparado con `Azeroth_32_48.adt` y `PVPZone01_32_32.adt` del cliente (`tools/mapgen/inspect_adt.py`):
  orden de chunks, MCNR con 13 bytes de relleno fuera de su tamano, offsets del MCNK relativos al inicio del chunk,
  posicion del MCNK = (X, Y, altura base).
- `.map` comprobado reconstruyendo las alturas desde el ADT como hace `map_extractor` (diferencia < 1e-6).
- `tools/mapgen/mpq.py` lee los MPQ de WC3 y los del cliente (zlib/bzip2; sin PKWARE implode).
