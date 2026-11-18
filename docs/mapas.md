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

## Circuitos (sin Warcraft 3)

Un mapa de `maps.json` cuyo `source` es un `.json` (en `Maps/Planos/`) es un **plano de circuito**: lo genera
`tools/mapgen/trackgen.py` en vez del conversor de WC3. Mismo resultado (ADT/WDT, `.map`, minimapa, vmaps, zona) y
ademas una vista previa (`tools/mapgen/_work/<Directory>_plano.png`) y la linea central de la pista para el
servidor (`<DataDir>/maps/<id>_pista.json`: `[s, X, Y, Z, media anchura]` cada 2 yardas desde la meta).

- **Pista** (`track`): puntos de control de una curva cerrada (Catmull-Rom centripeta) en yardas (x = este,
  y = norte, origen en el centro del mapa de `adts` x `adts` ADT). Por punto: `z`, ancho `w`, ambiente `biome` y el
  borde de cada lado (`left`/`right`, segun el sentido de la marcha) para el tramo hasta el siguiente punto:
  `berm` (muro de tierra de 6 yardas, cara > 60 grados: no se sube), `cut` (el relieve natural sube pegado: canon),
  `drop` (cae pegado: precipicio), `open`. `start: true` = meta. La pista queda llana a su altura (suavizada) con un
  arcen (`shoulder`) a cada lado.
- **Relieve natural** (`baseNoise` + `features`): `mountain` (elipse con crestas), `mesa` (poligono, `terraces`
  = estratos), `lake` (agua a `level`), `rim` (montanas en el borde del mapa), `flat`.
- **Ambientes** (`biomes`): texturas de pista (`road`), arcen (`verge`), suelo (`ground` + `ground2` en manchas),
  roca (pendiente > ~30 grados), cota de nieve (`snowLine`) y decoracion aleatoria (`scatter`: `density` por 1000
  yardas cuadradas, `lining` = mas densidad junto a la pista, modelos con peso, escala y pendiente maxima). El
  ambiente de cada punto del mapa = el del tramo de pista mas cercano, difuminado (`biomeBlend`).
- **Adornos** (`props`): un modelo cada `every` yardas a lo largo de la pista (`from`/`to` desde la meta, lado,
  distancia al arcen). Decoracion con colision -> vmaps (un `.vmo` por modelo; los que no tienen colision no van).
- **Efectos de suelo** (`effects`): textura -> `GroundEffectTexture` (hierba, flores, piedrecitas que pinta el
  cliente). Valores sacados de los ADT oficiales (la zona de cada textura; `MCLY` campo 4).
- Texturas y modelos: solo rutas que existen en el cliente (se sacaron de los ADT oficiales por zona). Los colores
  del minimapa se calculan del BLP de cada textura.
- Puntos que imprime: meta, parrilla de 8 (2 columnas escalonadas) y puntos de control repartidos por la vuelta.
- Sin mmaps: no hacen falta mientras no haya PNJ que anden por el circuito.
- 752 `EventWowCarrera` = `Planos/circuito_cuatro_tierras.json` (SQL `2026_11_17_00_eventwow_map_carrera.sql`,
  zona 5002): pradera (salida) -> bosque (Colinas Pardas) -> puerto nevado (Dun Morogh, con precipicio al lago) ->
  canon (Tierras Inhospitas) -> pradera. 2682 yardas por vuelta, ancho 22-26, 2x2 ADT.

## Formato (comprobado)

- ADT comparado con `Azeroth_32_48.adt` y `PVPZone01_32_32.adt` del cliente (`tools/mapgen/inspect_adt.py`):
  orden de chunks, MCNR con 13 bytes de relleno fuera de su tamano, offsets del MCNK relativos al inicio del chunk,
  posicion del MCNK = (X, Y, altura base).
- `.map` comprobado reconstruyendo las alturas desde el ADT como hace `map_extractor` (diferencia < 1e-6).
- `tools/mapgen/mpq.py` lee los MPQ de WC3 y los del cliente (zlib/bzip2; sin PKWARE implode).

## Pistas de plataformas en el espacio (sin terreno)

`tools/mapgen/platformgen.py`, plano JSON con `"type": "platforms"` (mapgen lo detecta). Ejemplo: 753
`Maps/Planos/circuito_estelar.json`.

- Sin terreno: los ADT existen (llevan la decoracion) pero todos sus MCNK son agujeros (`holes = 0xFFFF`), y el `.map`
  del servidor lleva los mismos agujeros (`GridTerrainData::isHole` -> sin suelo). El unico suelo son las piezas.
- Pista = piezas M2 encadenadas por la linea central (decoracion MDDF, colision en el cliente y en los vmaps).
  `pieces`: `model`, `scale`, `kind` (`rect`: alargada en su +X; `disc`: redonda, solapada), `overlap`, `maxTurn`,
  `zigzag` (desnivel alterno contra el parpadeo de caras coplanarias). La pieza necesita colision con una cara superior
  plana (se mide del M2: centro, altura, tamano). En subidas se inclina (MDDF rot[0] = -cabeceo, rot[2] = alabeo;
  convencion del extractor de vmaps). Probadas 2026-11-17: solo `SC_Platform2` (Plaga) convencio; muchos suelos
  "espaciales" (Ojo de la Eternidad, Algalon, El Castillo de la Tempestad) NO tienen colision propia.
- `paths`: abierta (`start`, `heading`, `segments` rectas/arcos) o circuito cerrado (`points` como trackgen). La
  primera cerrada es la carrera: meta, parrilla, controles y `<id>_pista.json` (Z = superficie). Pueden cruzarse por
  encima/debajo; el resumen avisa si la altura libre entre superficies baja de 18 yardas.
- `decor`: rocas flotantes a distancia de la pista. Cielo: fila de `light_dbc` (2600-2699) en el SQL del mapa.
- Caer al vacio: el core mata por debajo de z -500 (`MIN_HEIGHT`, sin planos de altura minima): pistas cerca de -400.

## Recorridos de parkour (sin terreno)

`tools/mapgen/parkourgen.py`, plano JSON con `"type": "parkour"` (mapgen lo detecta). Ejemplo: 754
`Maps/Planos/parkour_ascenso.json` (juego `parkour`, `EventWowGameParkour.cpp`).

- Sin terreno, como `platformgen` (ADT todo agujeros + `.map` con agujeros). La ruta son modelos M2 cualesquiera
  (mesas, barriles, estanterias, maquinas, columnas...) colocados como decoracion del ADT (colision en cliente y vmaps).
- **Cara pisable** de cada modelo: el nivel plano MAS ALTO con al menos el 40 % del area del mayor (una mesa da el
  tablero, no el suelo de las patas; un barril, la tapa). Se coloca el centro de esa cara en el punto de la ruta.
- **Catalogo** de candidatos: `tools/mapgen/catalog.py --wow-data <Data> --filter "chair|table" --out cat.csv`
  (colision, cara pisable mas alta, area, medidas; los modelos sin colision se atraviesan). Ojo con modelos
  "gigantes": `Karazahn_Rubble_Floating.m2` es todo el escombro de Karazhan (480 yardas).
- **Saltos** (fisica del cliente): impulso 7,9555 yd/s, gravedad 19,2911 (`Movement::gravity` del core), carrera
  7 yd/s -> altura maxima 1,64 yd, alcance en llano 5,8 yd. Cada salto: hueco borde a borde = `gap` (fraccion del
  alcance para ese desnivel `dz`). El resumen avisa de los saltos > 80 % (dificiles) y > 92 % (casi imposibles).
- **Secciones**: `jumps`, `gap`, `dz`, `turn` y `pieces` (modelo, escala, peso, `align`); la ruta se genera con
  semilla, girando hacia el centro cerca del borde (`bounds`), separada de los tramos lejanos 20 yd en 2D si estan a
  menos de 30 yd de altura (sin atajos entre secciones) y con vuelta atras si se encierra. Cada seccion empieza en
  una plataforma `rest` = punto de control (la 1a en `start`); al final, `finish`.
- Salida para el servidor: `<DataDir>/maps/<id>_parkour.txt` (`checkpoint X Y Z O radio caida nombre` /
  `finish X Y Z O radio`; caida = cara mas baja de la seccion - 8 yd). Vista previa: planta + perfil de altura.
- **Islas** (plantilla `isla` del plano): roca flotante de Nagrand `Nagrand_RockFloating_Huge01.m2` (500 yd a escala
  1, cupula con la cima en z 37,2 sobre el centro; colision tosca de 350 triangulos). Su cara se da a mano (`walk`) y
  con `surface: true` el borde de cada salto se MIDE en la colision (desde el centro hasta que el suelo se acaba o cae
  mas de 4 yd): el hueco del salto se cuenta desde donde de verdad termina la isla y desde su altura (el borde esta
  ~3 yd por debajo del centro). `dress`: arboles, matas, mariposas y un haz de luz encima, sobre la superficie real.
- **Decoracion**: M2 por distancia a la ruta (borde a borde, con el radio del modelo), WMO (`wmo: true`: islas de
  Nagrand con cascadas `World\wmo\Outland\FloatingRocks\Nagrand_RockFloating_*.wmo`; MODF + MWMO en el ADT, sin
  escala; SOLO cliente: los vmaps no incluyen WMO, asi que solo como decoracion inalcanzable) y efectos cada N
  piezas de la ruta (`every`: luciernagas).
- **Tramos** (`segments` de cada seccion): `run` (camino), `climb` (subida escalon a escalon casi al maximo del
  salto, p. ej. sillas), `descent` (caidas de 2-4 yd), `zigzag` (giros fuertes alternos) y `deadend` (callejon sin
  salida: un ramal de 4-8 saltos que sale hacia un lado de la pieza actual y se acaba; se genera al final, lejos del
  resto de la ruta para que no sea un atajo, y por encima de la altura de caida). Valores por tipo en `TRAMOS`.
- `align: "side"`: lo que sobresale de la cara (respaldo de una silla; se mide en la colision) queda a un lado del
  camino. Ojo: `DwarvenChair01` no sirve (su "cara" es el canto del respaldo); sillas buenas: `DwarvenChair02/03`,
  `ID_ChairMedium` a escala 3.
- Si la plataforma que cierra una seccion (siguiente punto de control o meta) no cabe, se deshacen saltos y se
  prueba otro camino (antes fallaba la generacion).
- 754 `EventWowParkour` "Ascenso" (SQL `2026_11_18_01_eventwow_map_parkour.sql`, zona 5004, luz 2601 = cielo de
  Nagrand, LightParams 396/491 de la luz 418): 3x3 ADT. Salida en una isla, una isla por punto de control: Taberna
  Flotante (muebles enanos x3), Biblioteca Arcana (estanterias y armarios), Taller Goblin (maquinas, carros,
  tuberias), Ruinas en el Vacio (columnas titanicas), La Cima; meta en una isla mayor. Cada seccion mezcla caminos,
  subidas de sillas, bajadas, zigzag y 2 callejones sin salida: 279 piezas + 56 en 10 callejones, z 56..152; 70
  islas WMO + 40 rocas de Nagrand + 150 rocas pequenas alrededor.
