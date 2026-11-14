# Mapas propios (desde Warcraft 3)

Los mapas de los minijuegos se disenan en el **World Editor de Warcraft 3 (1.26)** y `tools/mapgen` los convierte
al formato de WoW 3.3.5: terreno del cliente (ADT/WDT en `patch-4.MPQ`) y del servidor (`.map`).

```
Maps/<carpeta>/<mapa>.w3m|.w3x  --(Maps/maps.json)-->  tools/mapgen  -->  cliente: World\Maps\<Directory>\
                                                                      -->  servidor: <DataDir>\maps\<id>3232.map
SQL del modulo (map_dbc, mapdifficulty_dbc, instance_template) --> Build-Dbc --> Map.dbc / MapDifficulty.dbc del cliente
                                                                      -->  servidor: <DataDir>\vmaps\<id>.vmtree/.vmtile + .vmo
mmaps_generator <id> (a mano, tras .map y vmaps) --> <DataDir>\mmaps (caminos de los PNJ)
```

## Anadir un mapa

1. Guardar el mapa de WC3 (sin proteger) en `Maps/<carpeta>/`.
2. Entrada en `Maps/maps.json`:
   - `id`: rango reservado **750-799** (los de WotLK llegan a 724; `TC9Sidecar.h` limita a 800 y el cliente y el
     core dimensionan tablas por el ID mas alto, por eso no se usa el rango 9500000).
   - `directory`: nombre de la carpeta en `World\Maps` (ASCII, sin espacios).
   - `source`: ruta del mapa de WC3 relativa a `Maps/`.
   - Opcionales: `yardsPerTile` (4), `cliffYards` (8), `wallHeight` (auto = parte mas alta + `wallExtra` 15),
     `textures` (sobrescribe la tabla `TEXTURES` de `mapgen.py`: tipo de casilla de WC3 -> BLP de WoW),
     `regionNames` (nombre de region de WC3 -> nombre propio, para no tener que editar el mapa; mapgen imprime
     ambos), `wallLayer` (nivel de acantilado que es muro construido, ver Conversion; texturas `wallTop`/`wallFace`),
     `wallModels` (modelos M2 sobre esos muros: `model`, `box`, `scale`, `offset`, `terrainHeight`, `simplify`),
     `areaId` (zona de `AreaTable`, ver paso 3; 0 = sin zona).
3. SQL del modulo (copiar `2026_11_13_10_eventwow_map_test.sql`): `map_dbc` (mazmorra, `InstanceType = 1`; nombre en
   las 16 columnas de idioma), `mapdifficulty_dbc` (ID propio 9500000+, sin reinicio) e `instance_template`.
   Zona (copiar `2026_11_13_12_eventwow_map_areas.sql`): fila de `areatable_dbc` (ID **5000-5099**: el cliente llega
   a 4987; `AreaBit` **3700-3799**: el cliente llega a 3617 y el limite de exploracion es 4095; `ContinentID` = mapa;
   nombre en las 16 columnas) + `map_dbc.AreaTableID` + `areaId` en `maps.json`. Un solo nombre para todo el mapa.
4. `Build-Patch` (BD arrancada y con el SQL aplicado): genera el parche con Map.dbc + el mapa, y el `.map` y los
   vmaps en `server\bin\RelWithDebInfo\data` (`-ServerDataDir` para otra ruta; vmaps con `-WowDataDir` = `Data\` del
   cliente, por defecto el de pruebas: de ahi se lee la colision de los modelos).
5. mmaps (despues de los vmaps: el navmesh incluye la colision de los modelos): herramientas de AC compiladas con
   `TOOLS_BUILD` = `maps-only` (deja `mmaps_generator.exe` y `mmaps-config.yaml` en `server\bin\RelWithDebInfo`).
   Desde el DataDir: `..\mmaps_generator.exe --config ..\mmaps-config.yaml <id>` (al acabar espera una tecla;
   desde un script, `< nul`). Unos segundos por mapa. Hay que repetirlo cada vez que
   cambie el mapa (terreno o muros). Sin mmaps los jugadores van bien, pero los PNJ van en linea recta (atraviesan
   muros). Tras regenerar `.map`/vmaps/mmaps: reiniciar el worldserver.
6. Juego: `MapId` = id y `Start` = punto que imprime mapgen (inicio del jugador 1 o una region).

## Conversion

- Colocacion: el mapa de WC3 se centra en un bloque de n x n ADT empezando por el `32_32` (esquina noroeste del
  bloque en X = 0, Y = 0; el mapa ocupa X e Y negativas). Norte de WC3 = norte de WoW (+X), este = -Y.
- Escala: 1 casilla de WC3 (128 unidades) = `yardsPerTile` yardas; el relieve suave se escala igual.
- Acantilados: cada nivel = `cliffYards` (a escala real serian 4 yardas, que en WoW se suben andando). Rampas como
  en WC3: 3 filas marcadas (bajo, bajo, alto) y la del medio a media altura (2 casillas por nivel: ~45 grados con
  los valores por defecto); sin textura de acantilado.
- Muros construidos (`wallLayer`, p. ej. 4 en el 751): los puntos de ese nivel (y el borde exterior) no se
  interpolan con el suelo: cada vertice es suelo o muro, asi la cara queda casi vertical (lo que permite la malla de
  WoW, ~2-4 yardas). Suelo bajo el muro = el suelo vecino mas alto. Texturas `wallTop` (arriba) y `wallFace` (cara).
- Modelos de muro (`wallModels`, requiere `wallLayer`): un M2 de tramo de muro (por defecto `SC_Wall_01.M2`, muralla
  de la Plaga) a lo largo de las caras de los muros. `scale` es uniforme (el MDDF solo tiene una escala): no se puede
  dar mas alto sin dar tambien mas grueso y largo. 751: escala 2 (24 x 18.6 x 12.8 yardas; muros de WC3 de 12).
  - Contorno de la mascara de muro (cada vertice de WC3 = una casilla) simplificado con Douglas-Peucker
    (`simplify`, 1 casilla): los escalones de WC3 pasan a ser diagonales.
  - Por cada lado del contorno, modelos con los extremos alineados (se solapan en el medio si el largo no cuadra).
    Primero los lados "canonicos" (normal hacia +X, o +Y) y los largos.
  - Muro mas fino que el modelo: modelo centrado en el muro (sale por las dos caras). Mas grueso: cara del modelo en
    el borde de WC3 + `offset`. Grosor medido hacia dentro desde la cara (el exterior no jugable cuenta como muro).
  - Un modelo se salta si su cara ya queda dentro de otro (cara opuesta de un muro fino, extremos, esquinas); asi
    solo se rellenan los huecos (cruces). Los de relleno centrados se desplazan 0.3 para no coincidir en el plano.
  - Relleno: todo vertice del INTERIOR del muro de WC3 (muro o exterior a los 4 lados) debe quedar bajo un modelo
    (caja menos `COVER_SIDE` 3 yardas de grosor / `COVER_END` 1 de largo: la colision tiene talud, a los pies ocupa
    ~0.9 menos que la caja y a media altura ~3). Por caras quedaban sin tapar el centro de los cruces en "+" y "T"
    (las caras acaban en las esquinas interiores) y los muros que en WC3 solo se tocan en diagonal (cuello): se podia
    pasar de una sala a otra (probado). En cada hueco, un modelo a 0/90 grados centrado, o desplazado hasta 6 yardas
    si centrado pisaria un punto de region o de inicio (aviso si no se puede evitar).
  - Comprobado en el 751 (script de un solo uso): que regiones se comunican andando con los modelos = las mismas que
    en WC3, tambien con el muro 2 yardas mas fino por lado; ningun punto de region dentro de un muro.
  - Solo en caras que dan a suelo con sitio (al menos un bloque de 3x3 vertices): las franjas residuales entre el muro
    y el borde no llevan modelos. No se mira si se llega andando (salas cerradas con teletransportes/puertas).
  - Z = suelo exterior mas bajo del tramo. Se apilan modelos solo si no sobresaldria ni 2 yardas del suelo mas alto
    (estanque); una plaza elevada se queda con parapeto.
  - Muro de terreno = huella de los modelos encogida `terrainInset` (3 yardas; la union, no cada modelo: sin rendijas
    entre tramos) a suelo + `terrainHeight` (751: 5, con `terrainInset` 5;
    siempre por debajo del alto del modelo): la colision del terreno del servidor es lo que se ve y el terreno no
    asoma. Lo que era muro en WC3 y no cubre ningun modelo pasa a ser suelo (textura del suelo vecino). El cliente
    choca ademas con la colision del M2. Borde exterior (`wallHeight` auto) = suelo del perimetro + alto del modelo
    - 1 (no asoma roca por detras).
  - Por que el margen: la malla de WoW tiene un vertice cada ~2 yardas (y uno central por cuadro), asi que el borde de
    un muro de terreno no es vertical: baja en triangulos de hasta ~2.1 yardas hacia fuera. Con 1 yarda de margen
    asomaban por las caras como "dientes" de roca (probado). Comprobacion: ningun vertice elevado a menos de 2.08
    yardas del borde de la union de modelos.
  - ADT: MMDX/MMID/MDDF + MCRF en cada MCNK que toca el modelo (por su radio); un modelo entre dos ADT va en los dos
    con el mismo uniqueId. Colocacion MDDF = (ZERO - Y, Z, ZERO - X); el +X del M2 apunta a `rot.y + 180` grados
    (comprobado con las esquinas `SC_Wall_02_Cap` de `Northrend_28_20` y el extractor de vmaps). Escala 1024 = 1.0.
  - `box` = caja del M2 (offset 0xA0 del archivo: 6 floats), X = largo, Y = grosor. Para otro modelo de muro,
    leerla del M2 (`tools/mapgen/mpq.py` sobre los MPQ del cliente). SC_Wall_01: 12.0 x 9.3 x 6.4 yardas.
- Borde no jugable del mapa de WC3 (solo el conectado con el perimetro: marcas sueltas dentro se ignoran) y todo lo
  de fuera: muro de `wallHeight`.
- Texturas: por casilla de WC3 (mezcla bilineal, hasta 4 por chunk); casillas de acantilado con la textura de su
  acantilado; plaga = `blight`; muro = `wall`. Alfa de 4 bits.
- Agua: casillas de WC3 con agua -> MH2O (cliente) / MLIQ (servidor), tipo 5 (agua lenta). Nivel de WC3 a escala
  del relieve: "poco profunda" (sobre el suelo, nivel 8704) = 1.2 yardas, se anda; "profunda" (un nivel abajo,
  8192) = 5.2 yardas, se nada. Si el agua quedara bajo su fondo (agua en niveles altos), se conserva la profundidad.
- Tilesets con tabla de texturas: Lordaeron verano (L), Rasganorte (N), Glaciar de Corona de Hielo (I).
- Puntos: mapgen imprime los puntos de inicio (`sloc`) y el centro de cada region en coordenadas de WoW (con Z del
  terreno y orientacion). Nombrar las regiones en WC3 (`Inicio`, `Oleada1`, `Tienda`...).
- Se ignoran a proposito: unidades (salvo puntos de inicio, que se imprimen), decoracion y objetos de WC3 (`war3map.doo`;
  puertas etc. se pondran como objetos del juego). Si no se pueden leer (otra version del editor) solo se avisa.
- Zona: `areaId` va en el campo de area de cada MCNK (cliente: nombre de zona, `ZoneTextFrame` al entrar, minimapa)
  y como area unica de cada `.map` del servidor (`GridTerrainData::getArea` devuelve el area de la cuadricula si no
  hay mapa de areas). Entrar marca el bit de exploracion (`Player::CheckAreaExploreAndOutdoor`; nivel 80, sin XP).
- Minimapa: una textura de 256x256 por ADT (BLP2 DXT1 sin mipmaps, como las del cliente): color medio de cada
  textura del terreno (`MINIMAP_COLORS`, medido de sus BLP) mezclado con los mismos pesos, sombreado del relieve (luz
  del noroeste), agua y la huella de los modelos de muro. Archivos `eventwow_<id>_<tx>_<ty>.blp`, traducidos por
  `Textures\Minimap\md5translate.trs`. El `.trs` del parche SUSTITUYE al del cliente, asi que se genera con el
  original + nuestros mapas: el original (no versionado) va en `client\Minimap\md5translate.trs`, extraido de
  `patch-3.MPQ` del cliente (`tools/mapgen/mpq.py`). Sin el, `Build-Patch` avisa y no genera minimapas.
  En la interfaz: `MinimapCluster` visible en partida, sin sus botones (`EVENTWOW_MINIMAP_HIDDEN_BUTTONS`, EventWow.lua).
- vmaps (`tools/mapgen/vmaps.py`): la colision de los modelos para el servidor (linea de vision de hechizos y PNJ,
  altura sobre modelos, navmesh). `vmap4_extractor` no sirve: lee los MPQ y nuestro parche es una carpeta. Se escribe
  lo mismo que extractor + assembler (VMAP_4.8): `<id>.vmtree` (BIH de los limites de los modelos), `<id>_<tx>_<ty>.vmtile`
  (orden del ADT; comprobado contra los datos oficiales: vmtile `A_B` <-> `.map` `BA`) y `Sc_Wall_01.m2.vmo` (malla de
  colision del M2 = bounding vertices/triangles + BIH). El BIH es un port literal de `BoundingIntervalHierarchy.cpp`
  en float32: el `.vmo` de `SC_Wall_01_Cap.M2` sale **identico byte a byte** al oficial. Comprobado ademas con un
  trazado de rayos sobre los archivos generados: hay vision dentro de una sala y no a traves de los muros.
  Sin modelos (750) no se escribe nada (y se borran los de una version anterior): el servidor no aplica vmaps.
- Sin convertir todavia: sombras, sonidos y musica de zona (`ZoneMusic`/`AmbienceID` de `areatable_dbc` = 0).

## Formato (comprobado)

- ADT comparado con `Azeroth_32_48.adt` y `PVPZone01_32_32.adt` del cliente (`tools/mapgen/inspect_adt.py`):
  orden de chunks, MCNR con 13 bytes de relleno fuera de su tamano, offsets del MCNK relativos al inicio del chunk,
  posicion del MCNK = (X, Y, altura base).
- `.map` comprobado reconstruyendo las alturas desde el ADT como hace `map_extractor` (diferencia < 1e-6).
- `tools/mapgen/mpq.py` lee los MPQ de WC3 y los del cliente (zlib/bzip2; sin PKWARE implode).
