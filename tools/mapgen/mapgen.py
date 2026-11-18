"""Convierte mapas de Warcraft 3 (.w3m/.w3x 1.26) en mapas de WoW 3.3.5 para EventWow.

  py tools\\mapgen\\mapgen.py --client <carpeta del parche> [--server <DataDir del worldserver>] [--only <id>]

Lee Maps\\maps.json (lista de mapas). Por cada mapa genera:
  cliente:  <client>\\World\\Maps\\<Directory>\\<Directory>.wdt y <Directory>_<x>_<y>.adt
  servidor: <server>\\maps\\<id:03><y:02><x:02>.map   (las mmaps se generan despues con mmaps_generator <id>)
e imprime los puntos de inicio y las regiones del mapa de WC3 en coordenadas de WoW.

Conversion (ver docs\\mapas.md):
  - 1 casilla de WC3 = yardsPerTile yardas; el relieve suave se escala igual que el plano.
  - Cada nivel de acantilado = cliffYards yardas (mas alto que la escala real para que sea un muro).
  - Borde del mapa (zona no jugable) y fuera del mapa = muro de wallHeight yardas.
  - Texturas por tipo de casilla de WC3 (tabla TEXTURES, se puede sobrescribir en maps.json), acantilados con
    la textura de su acantilado, plaga con la textura "blight".
  - Agua: casillas de WC3 con agua -> agua de WoW a su nivel.
"""
import argparse
import json
import math
import os
import struct
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import parkourgen               # noqa: E402
import platformgen              # noqa: E402
import trackgen                 # noqa: E402
import vmaps                    # noqa: E402
import wc3                      # noqa: E402
import wowfiles as wow          # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

ROCK = r'Tileset\Elwynn\ElwynnRockBaseTest2.blp'
NR_ROCK = r'Tileset\Expansion02\DragonBlight\NorthRendRockBase.blp'
NR_ROCK_SNOW = r'Tileset\Expansion02\DragonBlight\NorthRendRockSnowScrape.blp'

# Tipo de casilla / acantilado de WC3 -> textura de WoW (rutas comprobadas en ADT del cliente 3.3.5)
TEXTURES = {
    # Lordaeron (verano)
    'Ldrt': r'Tileset\Elwynn\ElwynnDirtBase2.blp',
    'Ldro': r'Tileset\Aerie Peaks\AeriePeaksScrubBrushBase.blp',
    'Ldrg': r'Tileset\Elwynn\ElwynnDirtBase2.blp',
    'Lrok': ROCK,
    'Lgrs': r'Tileset\Elwynn\ElwynnGrassBase.blp',
    'Lgrd': r'Tileset\Elwynn\ElwynnFlowerBase.blp',
    'CLdi': ROCK,
    'CLgr': ROCK,
    # Rasganorte
    'Ndrt': NR_ROCK_SNOW,
    'Ndrd': NR_ROCK_SNOW,
    'Nrck': NR_ROCK,
    'Ngrs': r'Tileset\Expansion02\DragonBlight\DragonBlightSnowScrapeB.blp',
    'Nice': r'TILESET\Expansion02\StormPeaks\SP_SnowA.blp',
    'Nsnw': r'Tileset\Winterspring Grove\WinterspringSnowSolid.blp',
    'Nsnr': NR_ROCK_SNOW,
    'CNdi': NR_ROCK,
    'CNsn': NR_ROCK,
    # Glaciar de Corona de Hielo (texturas de Corona de Hielo de Rasganorte)
    'Idrt': r'TILESET\Expansion02\IceCrown\IG_DirtySnowE.blp',
    'Idtr': r'TILESET\Expansion02\IceCrown\IG_DirtySnowD.blp',
    'Idki': r'TILESET\Expansion02\IceCrown\IG_DirtyIceD.blp',
    'Ibkb': r'TILESET\Expansion02\IceCrown\IC_Vrykul_PaverRubbleB.blp',
    'Irbk': r'TILESET\Expansion02\IceCrown\IG_Vrykul_PaverB.blp',
    'Itbk': r'TILESET\Expansion02\IceCrown\IG_Vrykul_PaverB.blp',
    'Iice': r'TILESET\Expansion02\IceCrown\IG_GrayIceB.blp',
    'Ibsq': r'TILESET\Expansion02\IceCrown\IC_Vrykul_PaverRubbleA.blp',
    'Isnw': r'TILESET\Expansion02\IceCrown\IG_HardSnowA.blp',
    'CIsn': r'TILESET\Expansion02\IceCrown\IG_RockA.blp',
    'CIrb': r'TILESET\Expansion02\IceCrown\IC_Vrykul_PaverRubbleB.blp',
    # Especiales
    'blight': r'Tileset\Expansion01\BoneWastes\BoneWastesDirtShadow.blp',
    'wall': ROCK,
    'wallTop': ROCK,            # parte de arriba de los muros (con wallLayer)
    'wallFace': ROCK,           # caras de los muros (con wallLayer)
    'default': r'Tileset\Elwynn\ElwynnDirtBase2.blp',
}

# Minimapa: color medio de cada textura (mipmap de 4x4 de su BLP en los MPQ del cliente 3.3.5). Sin entrada = gris.
MINIMAP_COLORS = {
    r'TILESET\Expansion02\DragonBlight\IG_DarkRockA.blp': (21, 27, 33),
    r'TILESET\Expansion02\IceCrown\IC_Vrykul_PaverRubbleA.blp': (173, 178, 177),
    r'TILESET\Expansion02\IceCrown\IC_Vrykul_PaverRubbleB.blp': (132, 144, 149),
    r'TILESET\Expansion02\IceCrown\IG_DirtyIceD.blp': (0, 41, 46),
    r'TILESET\Expansion02\IceCrown\IG_DirtySnowD.blp': (78, 98, 98),
    r'TILESET\Expansion02\IceCrown\IG_DirtySnowE.blp': (94, 130, 130),
    r'TILESET\Expansion02\IceCrown\IG_GrayIceB.blp': (35, 54, 52),
    r'TILESET\Expansion02\IceCrown\IG_HardSnowA.blp': (126, 145, 143),
    r'TILESET\Expansion02\IceCrown\IG_RockA.blp': (46, 43, 46),
    r'TILESET\Expansion02\IceCrown\IG_Vrykul_PaverB.blp': (140, 148, 148),
    r'TILESET\Expansion02\StormPeaks\SP_SnowA.blp': (232, 248, 252),
    r'Tileset\Aerie Peaks\AeriePeaksScrubBrushBase.blp': (58, 71, 13),
    r'Tileset\Elwynn\ElwynnDirtBase2.blp': (126, 86, 27),
    r'Tileset\Elwynn\ElwynnFlowerBase.blp': (114, 119, 20),
    r'Tileset\Elwynn\ElwynnGrassBase.blp': (95, 105, 4),
    r'Tileset\Elwynn\ElwynnRockBaseTest2.blp': (149, 135, 105),
    r'Tileset\Expansion01\BoneWastes\BoneWastesDirtShadow.blp': (41, 46, 38),
    r'Tileset\Expansion02\DragonBlight\DragonBlightSnowScrapeB.blp': (133, 127, 137),
    r'Tileset\Expansion02\DragonBlight\NorthRendRockBase.blp': (21, 24, 19),
    r'Tileset\Expansion02\DragonBlight\NorthRendRockSnowScrape.blp': (93, 102, 106),
    r'Tileset\Winterspring Grove\WinterspringSnowSolid.blp': (235, 245, 247),
}
MINIMAP_WALL = (70, 66, 80)         # muros con modelo (vistos desde arriba)
MINIMAP_WALL_EDGE = (25, 23, 30)    # contorno de los muros
MINIMAP_WATER = (38, 78, 120)
MINIMAP_SIZE = 256

DEFAULTS = {
    'yardsPerTile': 4.0,
    'cliffYards': 8.0,
    'wallHeight': None,         # None = la parte mas alta del mapa + wallExtra
    'wallExtra': 15.0,
    'wallLayer': None,          # nivel de acantilado que es "muro construido": caras verticales + texturas de muro
    'wallModels': None,         # modelos M2 sobre los muros de wallLayer (ver WALL_MODEL_DEFAULTS)
    'areaId': 0,                # zona (AreaTable, rango 5000-5099, SQL *_eventwow_map_areas) de todo el mapa
}

# wallModels en maps.json: el M2 de un tramo de muro y como repartirlo. "box" = caja del M2 en yardas
# (minX, minY, minZ, maxX, maxY, maxZ; X = largo, Y = grosor), se lee del M2 (offset 0xA0).
WALL_MODEL_DEFAULTS = {
    'model': r'World\Expansion02\Doodads\Generic\Scourge\SC_Wall_01.M2',
    'box': [-6.00, -4.71, 0.01, 5.97, 4.64, 6.38],
    'scale': 1.0,
    'offset': 0.5,              # en muros mas gruesos que el modelo, su cara sale esto (yardas) del borde de WC3:
                                # tapa la base del muro de terreno (su cara no es del todo vertical)
    'terrainHeight': 4.0,       # altura del muro de terreno (colision del servidor) sobre el suelo; < alto del modelo
    'simplify': 1.0,            # tolerancia (casillas) al simplificar el contorno: escalones de 1 -> diagonal
    'terrainInset': 3.0,        # el muro de terreno queda esto (yardas) dentro de los modelos: su borde baja en
                                # triangulos de hasta ~2 yardas (malla de WoW) que si no asoman por la cara
}
MODEL_GRID = 0.5                # resolucion (yardas) de la huella de los modelos ya colocados
# Lo que un modelo cuenta como tapado: su caja menos este margen. La colision de SC_Wall_01 tiene talud: a 1 yarda
# de altura ocupa ~0.9 yardas menos que la caja por cada lado, a 3-5 yardas ~3 menos (a escala 2). Con margenes
# pequenos, dos tramos que solo se rozan dejaban rendijas visibles (y en esquinas, pasos).
COVER_SIDE = 3.0
COVER_END = 1.0


def wall_outline(mask, model_side):
    """Contorno de la mascara de muro (cada vertice de WC3 ocupa una casilla centrada en el) como polilineas con
    caras de muro: [(puntos [(u, v), ...], cerrada)]. u = columna, v = fila, en casillas. El muro queda a la
    izquierda del sentido de avance. Solo se incluyen los lados cuyo vecino cumple model_side(fila, columna)
    (p. ej. suelo jugable: no se ponen modelos contra el muro exterior)."""
    h, w = mask.shape
    edges = {}                      # inicio (doble de la coordenada, para trabajar con enteros) -> [(fin, con modelo)]
    for y, x in zip(*np.nonzero(mask)):
        X, Y = 2 * x, 2 * y
        for dy, dx, a, b in ((0, 1, (X + 1, Y - 1), (X + 1, Y + 1)), (1, 0, (X + 1, Y + 1), (X - 1, Y + 1)),
                             (0, -1, (X - 1, Y + 1), (X - 1, Y - 1)), (-1, 0, (X - 1, Y - 1), (X + 1, Y - 1))):
            ny, nx = y + dy, x + dx
            inside = 0 <= ny < h and 0 <= nx < w
            if inside and mask[ny, nx]:
                continue
            edges.setdefault(a, []).append((b, bool(inside and model_side(ny, nx))))

    def turn(prev, cur, nxt):
        d1 = (cur[0] - prev[0], cur[1] - prev[1])
        d2 = (nxt[0] - cur[0], nxt[1] - cur[1])
        return d1[0] * d2[1] - d1[1] * d2[0]        # > 0 = izquierda

    loops = []
    while edges:
        start = next(iter(edges))
        loop = [start]
        flags = []
        prev, cur = None, start
        while True:
            options = edges[cur]
            if prev is not None and len(options) > 1:
                options.sort(key=lambda e: -turn(prev, cur, e[0]))   # en un pellizco, girar a la izquierda
            nxt, flag = options.pop(0)
            if not options:
                del edges[cur]
            flags.append(flag)
            prev, cur = cur, nxt
            if cur == start:
                break
            loop.append(cur)
        loops.append((loop, flags))

    out = []
    for loop, flags in loops:
        pts = [(p[0] / 2.0, p[1] / 2.0) for p in loop]
        n = len(pts)
        if all(flags):
            out.append((simplify_closed(pts), True))
            continue
        if not any(flags):
            continue
        # Tramos abiertos: secuencias de lados con modelo (flags[i] = lado pts[i] -> pts[i + 1])
        first = next(i for i in range(n) if not flags[i])
        run = []
        for k in range(1, n + 1):
            i = (first + k) % n
            if flags[i]:
                if not run:
                    run.append(pts[i])
                run.append(pts[(i + 1) % n])
            elif run:
                out.append((run, False))
                run = []
        if run:
            out.append((run, False))
    return out


def douglas_peucker(pts, tol):
    if len(pts) < 3:
        return list(pts)
    a, b = np.array(pts[0]), np.array(pts[-1])
    d = b - a
    norm = math.hypot(d[0], d[1])
    best, index = -1.0, 0
    for i in range(1, len(pts) - 1):
        p = np.array(pts[i]) - a
        dist = abs(d[0] * p[1] - d[1] * p[0]) / norm if norm > 0 else math.hypot(p[0], p[1])
        if dist > best:
            best, index = dist, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return douglas_peucker(pts[:index + 1], tol)[:-1] + douglas_peucker(pts[index:], tol)


def simplify_closed(pts):
    """Polilinea cerrada sin puntos alineados (la simplificacion se hace despues, con la tolerancia del mapa)."""
    out = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]
        if (p1[0] - p0[0]) * (p2[1] - p1[1]) - (p1[1] - p0[1]) * (p2[0] - p1[0]) != 0:
            out.append(p1)
    return out


def ramp_layers(t):
    """Nivel efectivo por vertice. Una rampa de WC3 son 3 filas marcadas (nivel bajo, bajo, alto): el vertice del
    medio queda a media altura entre sus dos vecinos de rampa en la direccion de la rampa."""
    layer = t.layer.astype(np.float64)
    ramp = (t.flags & wc3.FLAG_RAMP) != 0
    out = layer.copy()
    h, w = layer.shape
    for y, x in zip(*np.nonzero(ramp)):
        for dy, dx in ((1, 0), (0, 1)):
            y1, x1, y2, x2 = y + dy, x + dx, y - dy, x - dx
            if 0 <= y1 < h and 0 <= x1 < w and 0 <= y2 < h and 0 <= x2 < w and ramp[y1, x1] and ramp[y2, x2] \
                    and layer[y1, x1] != layer[y2, x2]:
                out[y, x] = (layer[y1, x1] + layer[y2, x2]) / 2.0
                break
    return out


def outer_boundary(boundary):
    """Solo cuenta como borde (muro) el conectado con el perimetro: marcas de borde sueltas dentro del mapa se ignoran."""
    reach = np.zeros_like(boundary)
    reach[[0, -1], :] = boundary[[0, -1], :]
    reach[:, [0, -1]] |= boundary[:, [0, -1]]
    while True:
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= boundary
        if (grown == reach).all():
            return reach
        reach = grown


class Converter:
    def __init__(self, info, w3map):
        self.info = info
        self.map = w3map
        t = w3map.terrain
        self.t = t
        self.textures_cfg = dict(TEXTURES)
        self.textures_cfg.update(info.get('textures', {}))
        self.s = info['yardsPerTile'] / wc3.TILE_UNITS          # yardas por unidad de WC3

        # Alturas por vertice de WC3 (yardas)
        layer = t.layer.astype(np.float64)
        layer = ramp_layers(t)
        self.playable = ~outer_boundary(t.boundary)
        ground = (t.ground_height - 0x2000) / 4.0 * self.s
        heights = ground + (layer - 2.0) * info['cliffYards']
        relief = self.playable
        if info['wallModels'] is not None and info['wallLayer'] is not None:
            relief = relief & (t.layer < info['wallLayer'])      # los muros con modelo son bajos: no cuentan
        top = heights[relief].max() if relief.any() else 0.0
        self.wall_height = info['wallHeight'] if info['wallHeight'] is not None else top + info['wallExtra']
        heights[~self.playable] = self.wall_height
        self.heights = heights

        # Muros construidos (wallLayer): puntos del nivel de muro y el borde exterior. La altura deja de interpolarse
        # entre suelo y muro: cada vertice es suelo o muro (cara casi vertical a mitad de camino entre los dos puntos).
        self.walls = None
        if info['wallLayer'] is not None:
            walls = ((t.layer >= info['wallLayer']) & self.playable) | ~self.playable
            floor = np.where(walls, -np.inf, heights)
            while np.isinf(floor).any():
                padded = np.pad(floor, 1, mode='constant', constant_values=-np.inf)
                neighbours = np.max([padded[1 + dy:1 + dy + floor.shape[0], 1 + dx:1 + dx + floor.shape[1]]
                                     for dy in (-1, 0, 1) for dx in (-1, 0, 1)], axis=0)
                fill = np.isinf(floor) & ~np.isinf(neighbours)
                if not fill.any():
                    floor[np.isinf(floor)] = 0.0
                    break
                floor = np.where(fill, neighbours, floor)
            self.walls = walls.astype(np.float64)
            self.floor = floor
            self.inner_walls = walls & self.playable
        self.models = []
        self.model_top = None
        self.wall_model_cfg = None
        if info['wallModels'] is not None:
            if info['wallLayer'] is None:
                raise ValueError('mapa %s: wallModels necesita wallLayer' % info['directory'])
            cfg = dict(WALL_MODEL_DEFAULTS)
            cfg.update(info['wallModels'])
            self.wall_model_cfg = cfg
            # Muro de terreno bajo (queda dentro de los modelos): suelo + terrainHeight
            heights[self.inner_walls] = floor[self.inner_walls] + float(cfg['terrainHeight'])
            if info['wallHeight'] is None:
                # Exterior justo por debajo de lo alto de los modelos del perimetro: no asoma roca por detras
                outer = ~self.playable
                padded = np.pad(outer, 1, mode='constant', constant_values=True)
                touch = np.any([padded[1 + dy:1 + dy + outer.shape[0], 1 + dx:1 + dx + outer.shape[1]]
                                for dy in (-1, 0, 1) for dx in (-1, 0, 1)], axis=0) & self.inner_walls
                model_h = (cfg['box'][5] - cfg['box'][2]) * float(cfg['scale'])
                ring = floor[touch].max() if touch.any() else top
                self.wall_height = float(ring + model_h - 1.0)
                heights[outer] = self.wall_height
        self.water = ((t.flags & wc3.FLAG_WATER) != 0) & self.playable
        # Agua: nivel de WC3 a escala del relieve (respeta "poco profunda" sobre el suelo y "profunda" en un nivel
        # inferior). Si quedara por debajo de su fondo (agua en niveles altos, escalados por cliffYards), se conserva
        # la profundidad de WC3 sobre el fondo convertido.
        surface_units = (t.water_level - 0x2000) / 4.0 - wc3.WATER_OFFSET
        level = surface_units * self.s
        bed_units = (t.ground_height - 0x2000) / 4.0 + (t.layer - 2.0) * wc3.TILE_UNITS
        keep_depth = heights + np.maximum((surface_units - bed_units) * self.s, 0.5)
        self.water_level = np.where(level < heights + 0.3, keep_depth, level)

        # Colocacion: el mapa de WC3 centrado en un bloque de n x n ADT empezando en el 32_32
        size = max(t.width - 1, t.height - 1) * info['yardsPerTile']
        self.n = max(1, math.ceil(size / wow.TILE))
        self.tiles = [(32 + i, 32 + j) for j in range(self.n) for i in range(self.n)]
        self.xc = wow.ZERO - 32 * wow.TILE - self.n * wow.TILE / 2
        self.yc = self.xc
        self.cx, self.cy = t.center()

        if info['wallModels'] is not None:
            self._place_wall_models()
        # Modelos: lista de rutas + indice por colocacion (igual que trackgen)
        self.model_names = [self.wall_model_cfg['model']] if self.models else []
        for m in self.models:
            m['model'] = 0
        self._build_texture_grid()

    # --- Modelos de muro ---------------------------------------------------------------------------------------

    def _place_wall_models(self):
        """Modelos de muro a lo largo de las caras de los muros (contorno de WC3 simplificado: los escalones pasan
        a ser diagonales). Muro mas fino que el modelo: modelo centrado en el muro (tapa las dos caras). Muro mas
        grueso: la cara del modelo en el borde de WC3 (+ offset). Cada modelo se salta si su cara ya queda dentro de
        otro (cara opuesta, extremos, esquinas). El muro de terreno (colision del servidor) sigue la forma de WC3 pero
        bajo, dentro de los modelos. Si el suelo de un lado esta mas bajo (estanque), se apilan modelos."""
        cfg = self.wall_model_cfg
        bx0, by0, bz0, bx1, by1, bz1 = cfg['box']
        s = float(cfg['scale'])
        length, thick, height = (bx1 - bx0) * s, (by1 - by0) * s, (bz1 - bz0) * s
        mcx, mcy = (bx0 + bx1) / 2.0 * s, (by0 + by1) / 2.0 * s     # centro de la caja respecto al origen del M2
        offset = float(cfg['offset'])
        radius = math.hypot(length, thick) / 2 + math.hypot(mcx, mcy)

        reachable = self._reachable_floor()

        def floor_side(r, c):
            return reachable[r, c]

        def to_world(u, v):
            return np.array(self.to_wow(self.t.offset_x + u * wc3.TILE_UNITS, self.t.offset_y + v * wc3.TILE_UNITS))

        # Lados del contorno. Primero los "canonicos" (normal hacia +X, o +Y si es paralela a Y) y los largos: en un
        # muro mas fino que el modelo, el modelo va centrado y tapa tambien la cara opuesta, que se salta.
        faces = []
        for pts, closed in wall_outline(self.inner_walls, floor_side):
            pts = self._simplify(pts, closed, float(cfg['simplify']))
            ends = pts[1:] + ([pts[0]] if closed else [])
            for (u0, v0), (u1, v1) in zip(pts, ends):
                p0, p1 = to_world(u0, v0), to_world(u1, v1)
                seg = float(np.linalg.norm(p1 - p0))
                if seg < 1e-3:
                    continue
                u = (p1 - p0) / seg
                out = np.array([u[1], -u[0]])           # hacia el suelo (el muro queda a la izquierda)
                canonical = out[0] > 1e-6 or (abs(out[0]) <= 1e-6 and out[1] > 0)
                faces.append((not canonical, -seg, p0, u, out, seg))
        faces.sort(key=lambda f: (f[0], f[1]))

        solid = (self.inner_walls | ~self.playable).astype(np.float64)
        depths = np.arange(0.25, 80.0, 0.5)

        def thickness(p, out):
            """Grosor del muro desde el punto p de una cara, hacia dentro (hasta volver a salir a suelo)."""
            # La cara simplificada no sigue exactamente los escalones de WC3: se cuenta desde el primer punto de
            # muro (en las primeras yardas) hasta volver a salir
            pts = p[None, :] - out[None, :] * depths[:, None]
            inside = self.nearest(solid, pts[:, 0], pts[:, 1], 1.0) > 0.5
            first = int(np.argmax(inside))
            if not inside[first] or depths[first] > 4.0:
                return 0.0
            rest = inside[first:]
            return float(depths[first + int(np.argmin(rest))]) if not rest.all() else float(depths[-1])

        X0, Y0 = wow.tile_origin(*self.tiles[0])
        covered = np.zeros((int(math.ceil(self.n * wow.TILE / MODEL_GRID)) + 1,) * 2, dtype=bool)

        def is_covered(points):
            i = np.rint((X0 - points[:, 0]) / MODEL_GRID).astype(int)
            j = np.rint((Y0 - points[:, 1]) / MODEL_GRID).astype(int)
            ok = (i >= 0) & (j >= 0) & (i < covered.shape[0]) & (j < covered.shape[1])
            return bool(ok.all() and covered[i, j].all())

        def mark(center, u, hl, ht):
            r = hl + ht
            i0 = max(int((X0 - center[0] - r) / MODEL_GRID), 0)
            i1 = min(int(math.ceil((X0 - center[0] + r) / MODEL_GRID)), covered.shape[0] - 1)
            j0 = max(int((Y0 - center[1] - r) / MODEL_GRID), 0)
            j1 = min(int(math.ceil((Y0 - center[1] + r) / MODEL_GRID)), covered.shape[1] - 1)
            ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1), indexing='ij')
            dx, dy = X0 - ii * MODEL_GRID - center[0], Y0 - jj * MODEL_GRID - center[1]
            inside = (np.abs(dx * u[0] + dy * u[1]) <= hl) & (np.abs(-dx * u[1] + dy * u[0]) <= ht)
            covered[i0:i1 + 1, j0:j1 + 1] |= inside

        footprints = []
        for filler, _, p0, u, out, seg in faces:
            left = np.array([-u[1], u[0]])              # +Y del M2
            angle = math.atan2(u[1], u[0])
            nl = max(1, math.ceil(seg / length - 0.05))
            for i in range(nl):
                a = seg / 2 if nl == 1 else length / 2 + i * (seg - length) / (nl - 1)
                face = p0 + u * a
                reach = min(length / 2, seg / 2) - 0.5
                # Ya tapado por otro modelo (cara opuesta de un muro fino, extremo de muro, esquina): se salta
                line = np.array([face + u * d - out * 1.0 for d in np.arange(-reach, reach + 0.01, 1.0)])
                if is_covered(line):
                    continue
                along = [face + u * d for d in (-reach, 0.0, reach)]
                wall = min(thickness(p, out) for p in along)
                depth = thick / 2 - offset                  # cara del modelo en el borde + offset
                if wall / 2 < depth:
                    depth = wall / 2 - (0.3 if filler else 0.0)   # muro fino: centrado (relleno algo desplazado)
                center = face - out * depth
                far = depth + thick / 2                     # hasta donde llega el modelo hacia dentro
                outside = np.array([p + out * 2.5 for p in along]
                                   + ([p - out * (wall + 2.5) for p in along] if far >= wall else []))
                inside = np.array([p - out * max(wall / 2, 1.0) for p in along])
                base = float(self.bilinear(self.floor, outside[:, 0], outside[:, 1], self.wall_height).min())
                # Muro de terreno: suelo vecino mas alto (relleno bajo el muro) + terrainHeight
                high = float(self.bilinear(self.floor, inside[:, 0], inside[:, 1], base).max())
                need = high + float(cfg['terrainHeight']) + 0.2
                origin = center - u * mcx - left * mcy
                # Apilar solo si el modelo no sobresale ni 2 yardas del suelo mas alto (p. ej. junto al estanque);
                # una plaza elevada se queda con un parapeto
                stack = max(1, math.ceil((high + 2.0 - base) / height - 0.05))
                for k in range(stack):
                    self.models.append({'x': float(origin[0]), 'y': float(origin[1]),
                                        'z': base - bz0 * s + k * height - 0.1, 'angle': angle, 'scale': s,
                                        'radius': radius})
                mark(center, u, length / 2 - COVER_END, thick / 2 - COVER_SIDE)
                footprints.append((center, u, min(need - 0.2, base + stack * height - 1.0)))

        # Relleno: todo vertice de muro de WC3 debe quedar bajo algun modelo. Por caras quedan huecos donde ninguna
        # cara pasa por encima: el centro de los cruces en "+" y "T" (las caras acaban en las esquinas interiores) y
        # los muros que en WC3 solo se tocan en diagonal (cuello estrecho). En cada hueco, un modelo centrado con el
        # giro que mas muro tapa y menos suelo pisa.
        # Solo el interior del muro (vertices con muro o exterior a los 4 lados): los del borde dan al suelo y ya
        # los tapan los modelos de las caras
        sol = self.inner_walls | ~self.playable
        pad = np.pad(sol, 1, mode='constant', constant_values=True)
        core = self.inner_walls & pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
        wy_, wx_ = np.nonzero(core)
        wall_pts = np.array([self.to_wow(self.t.offset_x + x * wc3.TILE_UNITS, self.t.offset_y + y * wc3.TILE_UNITS)
                             for y, x in zip(wy_, wx_)])
        ring = [(0.0, 0.0)]
        marks = np.array([self.to_wow(*r.center()) for r in self.map.regions]
                         + [self.to_wow(u_.x, u_.y) for u_ in self.map.start_locations()]).reshape(-1, 2)
        padb = np.pad(sol, 1, mode='constant', constant_values=True)
        beside = np.any([padb[1 + dy:1 + dy + sol.shape[0], 1 + dx:1 + dx + sol.shape[1]]
                         for dy in (-1, 0, 1) for dx in (-1, 0, 1)], axis=0).astype(np.float64)
        gx, gy = np.meshgrid(np.arange(-length / 2 + 1, length / 2 - 0.9, 1.0),
                             np.arange(-thick / 2 + 1, thick / 2 - 0.9, 1.0))
        gx, gy = gx.ravel(), gy.ravel()
        skip = np.zeros(len(wall_pts), dtype=bool)
        tried = set()
        for _ in range(500):
            hole = np.zeros(len(wall_pts), dtype=bool)
            for dx, dy in ring:
                pts = wall_pts + np.array([dx, dy])
                i = np.rint((X0 - pts[:, 0]) / MODEL_GRID).astype(int)
                j = np.rint((Y0 - pts[:, 1]) / MODEL_GRID).astype(int)
                hole |= ~covered[np.clip(i, 0, covered.shape[0] - 1), np.clip(j, 0, covered.shape[1] - 1)]
            hole &= ~skip
            if not hole.any():
                break
            # El primer vertice de hueco y sus vecinos de hueco cercanos (un modelo por hueco)
            first = int(np.argmax(hole))
            if first in tried:
                skip[first] = True         # no se puede tapar mejor: no repetir modelos
                continue
            tried.add(first)
            near = hole & (np.linalg.norm(wall_pts - wall_pts[first], axis=1) <= thick / 2)
            hole_center = wall_pts[near].mean(axis=0)
            target = wall_pts[first]
            best = None
            for deg in (0, 90):                      # alineado con los tramos del cruce
                a = math.radians(deg)
                u = np.array([math.cos(a), math.sin(a)])
                left = np.array([-u[1], u[0]])
                # Centrado en el hueco o desplazado hasta 6 yardas (para no pisar un punto de region), siempre
                # tapando el vertice del hueco con el margen de COVER_*
                for da in (0.0, -2.0, 2.0, -4.0, 4.0, -6.0, 6.0):
                    for db in (0.0, -2.0, 2.0, -4.0, 4.0, -6.0, 6.0):
                        center = hole_center + u * da + left * db
                        rel = target - center
                        if abs(rel @ u) > length / 2 - COVER_END or abs(rel @ left) > thick / 2 - COVER_SIDE:
                            continue
                        px = center[0] + gx * u[0] + gy * left[0]
                        py = center[1] + gx * u[1] + gy * left[1]
                        wall = self.nearest(solid, px, py, 1.0) > 0.5
                        # Solo castiga el suelo a mas de una casilla de un muro: lo que sobresalen todos los modelos
                        # de escala 2 (~3.3 yardas) no cuenta
                        far = self.nearest(beside, px, py, 1.0) < 0.5
                        # Desplazarse solo si centrado pisaria un punto de region
                        score = int(wall.sum()) - 3 * int(far.sum()) - 1000 * int(abs(da) + abs(db))
                        # Nunca encima de un punto de region (apariciones, teletransportes...) si se puede evitar
                        relm = marks - center
                        on = (np.abs(relm @ u) <= length / 2 + 1.0) & (np.abs(relm @ left) <= thick / 2 + 1.0)
                        score -= 100000 * int(on.sum())
                        if best is None or score > best[0]:
                            best = (score, a, u, left, center)
            _, angle, u, left, center = best
            if best[0] < -50000:
                print('  AVISO: un relleno de muro tapa un punto de region cerca de (%.1f, %.1f)' % tuple(center))
            base = float(self.floor[wy_[near], wx_[near]].min())
            origin = center - u * mcx - left * mcy
            self.models.append({'x': float(origin[0]), 'y': float(origin[1]), 'z': base - bz0 * s - 0.1,
                                'angle': angle, 'scale': s, 'radius': radius})
            mark(center, u, length / 2 - COVER_END, thick / 2 - COVER_SIDE)
            footprints.append((center, u, base + min(float(cfg['terrainHeight']), height - 1.0)))
        if skip.any():
            print('  AVISO: %d vertices de muro sin modelo encima' % int(skip.sum()))
        self.filler_models = len(tried)

        # Muro de terreno = huella de los modelos (algo mas estrecha que ellos): lo que se ve es lo que choca en el
        # servidor y el terreno nunca asoma fuera del modelo. Lo que en WC3 era muro y no cubre ningun modelo
        # pasa a ser suelo.
        top = np.full(covered.shape, -np.inf)
        for center, u, wall_top in footprints:
            hl, ht = length / 2, thick / 2
            r = hl + ht
            i0 = max(int((X0 - center[0] - r) / MODEL_GRID), 0)
            i1 = min(int(math.ceil((X0 - center[0] + r) / MODEL_GRID)), top.shape[0] - 1)
            j0 = max(int((Y0 - center[1] - r) / MODEL_GRID), 0)
            j1 = min(int(math.ceil((Y0 - center[1] + r) / MODEL_GRID)), top.shape[1] - 1)
            ii, jj = np.meshgrid(np.arange(i0, i1 + 1), np.arange(j0, j1 + 1), indexing='ij')
            dx, dy = X0 - ii * MODEL_GRID - center[0], Y0 - jj * MODEL_GRID - center[1]
            inside = (np.abs(dx * u[0] + dy * u[1]) <= hl) & (np.abs(-dx * u[1] + dy * u[0]) <= ht)
            block = top[i0:i1 + 1, j0:j1 + 1]
            block[inside] = np.maximum(block[inside], wall_top)
        # Encoger la huella entera (no cada modelo: no se abren rendijas entre tramos) terrainInset yardas,
        # alternando vecindad de 4 y de 8 (aprox. octogonal)
        solid_top = np.isfinite(top)
        for step in range(int(round(float(cfg['terrainInset']) / MODEL_GRID))):
            padded = np.pad(solid_top, 1, mode='constant', constant_values=False)
            near = ((-1, 0), (1, 0), (0, -1), (0, 1)) + (((-1, -1), (-1, 1), (1, -1), (1, 1)) if step % 2 else ())
            for dy, dx in near:
                solid_top = solid_top & padded[1 + dy:1 + dy + top.shape[0], 1 + dx:1 + dx + top.shape[1]]
        top = np.where(solid_top, top, -np.inf)
        self.model_top = top
        self.model_origin = (X0, Y0)
        self.heights[self.inner_walls] = self.floor[self.inner_walls]
        self.walls = (~self.playable).astype(np.float64)

    def model_height(self, X, Y):
        """Altura del muro de terreno bajo los modelos (-inf fuera de su huella)."""
        X0, Y0 = self.model_origin
        i = np.rint((X0 - X) / MODEL_GRID).astype(int)
        j = np.rint((Y0 - Y) / MODEL_GRID).astype(int)
        n = self.model_top.shape[0]
        inside = (i >= 0) & (j >= 0) & (i < n) & (j < n)
        return np.where(inside, self.model_top[np.clip(i, 0, n - 1), np.clip(j, 0, n - 1)], -np.inf)

    def _reachable_floor(self):
        """Zonas de suelo donde cabe un jugador: las que tienen al menos un bloque de 3x3 vertices de suelo. Las
        franjas residuales (p. ej. 1 vertice entre el muro y el borde del mapa) no llevan modelos en sus caras.
        No se mira si se llega andando: las salas pueden estar cerradas (teletransportes, puertas)."""
        floor = self.playable & ~self.inner_walls
        h, w = floor.shape
        padded = np.pad(floor, 1, mode='constant', constant_values=False)
        core = np.all([padded[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] for dy in (-1, 0, 1) for dx in (-1, 0, 1)],
                      axis=0)
        # Crecer desde los centros de 3x3 dentro del suelo: queda cada zona con sitio
        reach = core.copy()
        while True:
            grown = reach.copy()
            grown[1:, :] |= reach[:-1, :]
            grown[:-1, :] |= reach[1:, :]
            grown[:, 1:] |= reach[:, :-1]
            grown[:, :-1] |= reach[:, 1:]
            grown &= floor
            if (grown == reach).all():
                return reach
            reach = grown

    @staticmethod
    def _simplify(pts, closed, tol):
        if not closed:
            return douglas_peucker(pts, tol)
        # Cerrada: se parte por el punto mas lejano al primero y se simplifica cada mitad
        p0 = np.array(pts[0])
        far = max(range(len(pts)), key=lambda i: float(np.linalg.norm(np.array(pts[i]) - p0)))
        a = douglas_peucker(pts[:far + 1], tol)
        b = douglas_peucker(pts[far:] + [pts[0]], tol)
        return a[:-1] + b[:-1]

    def tile_doodads(self, tx, ty):
        """Modelos que tocan el ADT (por su radio): [(indice global, modelo)]."""
        x0, y0 = wow.tile_origin(tx, ty)
        out = []
        for k, m in enumerate(self.models):
            r = m['radius']
            if x0 - wow.TILE - r <= m['x'] <= x0 + r and y0 - wow.TILE - r <= m['y'] <= y0 + r:
                out.append((k, m))
        return out

    # --- Coordenadas -------------------------------------------------------------------------------------------

    def to_wow(self, wx, wy):
        return self.xc + (wy - self.cy) * self.s, self.yc - (wx - self.cx) * self.s

    def to_grid(self, X, Y):
        """WoW (X, Y) -> coordenadas continuas en la rejilla de vertices de WC3 (px = columna, py = fila)."""
        wx = self.cx - (Y - self.yc) / self.s
        wy = self.cy + (X - self.xc) / self.s
        return (wx - self.t.offset_x) / wc3.TILE_UNITS, (wy - self.t.offset_y) / wc3.TILE_UNITS

    def bilinear(self, grid, X, Y, outside):
        px, py = self.to_grid(X, Y)
        h, w = grid.shape
        inside = (px >= 0) & (py >= 0) & (px <= w - 1) & (py <= h - 1)
        px = np.clip(px, 0, w - 1)
        py = np.clip(py, 0, h - 1)
        x0 = np.minimum(np.floor(px).astype(int), w - 2)
        y0 = np.minimum(np.floor(py).astype(int), h - 2)
        fx, fy = px - x0, py - y0
        value = (grid[y0, x0] * (1 - fx) * (1 - fy) + grid[y0, x0 + 1] * fx * (1 - fy)
                 + grid[y0 + 1, x0] * (1 - fx) * fy + grid[y0 + 1, x0 + 1] * fx * fy)
        return np.where(inside, value, outside)

    def nearest(self, grid, X, Y, outside):
        px, py = self.to_grid(X, Y)
        h, w = grid.shape
        ix, iy = np.rint(px).astype(int), np.rint(py).astype(int)
        inside = (ix >= 0) & (iy >= 0) & (ix < w) & (iy < h)
        return np.where(inside, grid[np.clip(iy, 0, h - 1), np.clip(ix, 0, w - 1)], outside)

    def height(self, X, Y):
        if self.walls is None:
            return self.bilinear(self.heights, X, Y, self.wall_height)
        wall = self.bilinear(self.walls, X, Y, 1.0)
        floor = self.bilinear(self.floor, X, Y, self.wall_height)
        weighted = self.bilinear(self.heights * self.walls, X, Y, self.wall_height)
        top = weighted / np.maximum(wall, 1e-6)
        result = np.where(wall >= 0.5, top, floor)
        if self.model_top is not None:
            result = np.maximum(result, self.model_height(X, Y))
        return result

    def normals(self, X, Y):
        e = wow.UNIT / 2.0
        dx = (self.height(X + e, Y) - self.height(X - e, Y)) / (2 * e)
        dy = (self.height(X, Y + e) - self.height(X, Y - e)) / (2 * e)
        n = np.stack([-dx, -dy, np.ones_like(dx)], axis=-1)
        return n / np.linalg.norm(n, axis=-1, keepdims=True)

    # --- Texturas ----------------------------------------------------------------------------------------------

    def texture_path(self, key):
        if key not in self.textures_cfg:
            if key not in self.unknown:
                self.unknown.add(key)
            return self.textures_cfg['default']
        return self.textures_cfg[key]

    def _build_texture_grid(self):
        t = self.t
        self.unknown = set()
        names = []
        index = {}

        def tex_id(path):
            if path not in index:
                index[path] = len(names)
                names.append(path)
            return index[path]

        ground_ids = [tex_id(self.texture_path(g)) for g in t.ground]
        point = np.array(ground_ids)[np.clip(t.texture, 0, len(ground_ids) - 1)]
        point = np.where((t.flags & wc3.FLAG_BLIGHT) != 0, tex_id(self.texture_path('blight')), point)
        self.wall_tex = tex_id(self.texture_path('wall'))
        point = np.where(self.playable, point, self.wall_tex)
        if self.model_top is not None:
            # Con modelos, lo que era muro de WC3 es suelo bajo el modelo: textura del suelo vecino mas cercano
            fill = np.where(self.inner_walls, -1, point)
            while (fill < 0).any():
                padded = np.pad(fill, 1, mode='edge')
                grown = fill.copy()
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    nb = padded[1 + dy:1 + dy + fill.shape[0], 1 + dx:1 + dx + fill.shape[1]]
                    grown = np.where((grown < 0) & (nb >= 0), nb, grown)
                if (grown == fill).all():
                    grown[grown < 0] = self.wall_tex
                fill = grown
            point = fill
        self.point_tex = point

        # Celdas con acantilado: niveles distintos en sus 4 esquinas -> textura del acantilado de la esquina mas alta
        lay = t.layer
        corners = np.stack([lay[:-1, :-1], lay[:-1, 1:], lay[1:, :-1], lay[1:, 1:]])
        ramp = (t.flags & wc3.FLAG_RAMP) != 0
        ramp_cell = ramp[:-1, :-1] | ramp[:-1, 1:] | ramp[1:, :-1] | ramp[1:, 1:]
        self.cliff_cell = (corners.max(axis=0) != corners.min(axis=0)) & ~ramp_cell
        if self.model_top is not None:
            iw = self.inner_walls
            self.cliff_cell &= ~(iw[:-1, :-1] | iw[:-1, 1:] | iw[1:, :-1] | iw[1:, 1:])
        cliff_ids = [tex_id(self.texture_path(c)) for c in t.cliffs] or [self.wall_tex]
        ctex = np.stack([t.cliff_texture[:-1, :-1], t.cliff_texture[:-1, 1:], t.cliff_texture[1:, :-1],
                         t.cliff_texture[1:, 1:]])
        top = np.take_along_axis(ctex, corners.argmax(axis=0)[None], axis=0)[0]
        self.cell_cliff_tex = np.array(cliff_ids)[np.where(top < len(cliff_ids), top, 0)]
        if self.info['wallLayer'] is not None:
            self.wall_top_tex = tex_id(self.texture_path('wallTop'))
            self.wall_face_tex = tex_id(self.texture_path('wallFace'))
        self.texture_names = names

    def texture_weights(self, X, Y):
        """Pesos [K, ...] de cada textura en los puntos (X, Y)."""
        k = len(self.texture_names)
        px, py = self.to_grid(X, Y)
        h, w = self.point_tex.shape
        inside = (px >= 0) & (py >= 0) & (px <= w - 1) & (py <= h - 1)
        pxc, pyc = np.clip(px, 0, w - 1), np.clip(py, 0, h - 1)
        x0 = np.minimum(np.floor(pxc).astype(int), w - 2)
        y0 = np.minimum(np.floor(pyc).astype(int), h - 2)
        fx, fy = pxc - x0, pyc - y0
        weights = np.zeros((k,) + X.shape)
        for (oy, ox, wgt) in ((0, 0, (1 - fx) * (1 - fy)), (0, 1, fx * (1 - fy)), (1, 0, (1 - fx) * fy),
                              (1, 1, fx * fy)):
            ids = self.point_tex[y0 + oy, x0 + ox]
            for tid in range(k):
                weights[tid] += np.where(ids == tid, wgt, 0.0)
        cliff = self.cliff_cell[y0, x0] & inside
        cliff_ids = self.cell_cliff_tex[y0, x0]
        for tid in range(k):
            weights[tid] = np.where(cliff, (cliff_ids == tid).astype(float), weights[tid])
            weights[tid] = np.where(inside, weights[tid], 1.0 if tid == self.wall_tex else 0.0)
        if self.walls is not None:
            # Cara del muro (franja donde salta la altura, con un poco de margen) y parte de arriba
            wall = self.bilinear(self.walls, X, Y, 1.0)
            face = (wall > 0.3) & (wall < 0.7)
            top = wall >= 0.7
            for tid in range(k):
                weights[tid] = np.where(face, float(tid == self.wall_face_tex), weights[tid])
                weights[tid] = np.where(top, float(tid == self.wall_top_tex), weights[tid])
        if self.model_top is not None:
            # Bajo los modelos y su borde (por si asoma el terreno): cara de muro
            near = np.zeros(X.shape, dtype=bool)
            for dx, dy in ((0, 0), (1.5, 0), (-1.5, 0), (0, 1.5), (0, -1.5)):
                near |= np.isfinite(self.model_height(X + dx, Y + dy))
            for tid in range(k):
                weights[tid] = np.where(near, float(tid == self.wall_face_tex), weights[tid])
        return weights

    # --- ADT ---------------------------------------------------------------------------------------------------

    def build_tile(self, tx, ty):
        tile = wow.TileData(tx, ty)
        tile.area_id = int(self.info['areaId'])
        x0, y0 = wow.tile_origin(tx, ty)
        r = np.arange(129)
        Xo, Yo = np.meshgrid(x0 - r * wow.UNIT, y0 - r * wow.UNIT, indexing='ij')
        ri = np.arange(128) + 0.5
        Xi, Yi = np.meshgrid(x0 - ri * wow.UNIT, y0 - ri * wow.UNIT, indexing='ij')
        tile.heights_outer = self.height(Xo, Yo)
        tile.heights_inner = self.height(Xi, Yi)
        tile.normals_outer = self.normals(Xo, Yo)
        tile.normals_inner = self.normals(Xi, Yi)

        # Agua por celda (centro de la celda) y nivel por vertice
        tile.water = self.nearest(self.water, Xi, Yi, False).astype(bool)
        tile.water_height = self.nearest(self.water_level, Xo, Yo, 0.0)

        # Texturas: alfa de 64x64 por MCNK (1024x1024 por ADT)
        pa = (np.arange(1024) + 0.5) * (wow.TILE / 1024.0)
        Xa, Ya = np.meshgrid(x0 - pa, y0 - pa, indexing='ij')
        weights = self.texture_weights(Xa, Ya)
        used = []
        for cr in range(16):
            for cc in range(16):
                wch = weights[:, cr * 64:(cr + 1) * 64, cc * 64:(cc + 1) * 64]
                totals = wch.reshape(wch.shape[0], -1).sum(axis=1)
                order = [int(i) for i in np.argsort(-totals) if totals[i] > 0][:4] or [self.wall_tex]
                sel = wch[order]
                total = sel.sum(axis=0)
                sel = np.where(total > 0, sel / np.where(total > 0, total, 1), 0)
                sel[0] = np.where(total > 0, sel[0], 1.0)
                layers = []
                acc = sel[0].copy()
                for li, tid in enumerate(order):
                    if tid not in used:
                        used.append(tid)
                    local = used.index(tid)
                    if li == 0:
                        layers.append((local, None))
                        continue
                    acc = acc + sel[li]
                    alpha = np.where(acc > 0, sel[li] / np.where(acc > 0, acc, 1), 0)
                    layers.append((local, alpha))
                tile.layers[(cr, cc)] = layers
        tile.textures = [self.texture_names[i] for i in used]

        # Modelos: cada uno en todos los ADT que toca, con el mismo uniqueId (el cliente no lo duplica)
        add_tile_doodads(tile, self, tx, ty)
        return tile

    # --- Minimapa ----------------------------------------------------------------------------------------------

    def minimap(self, tx, ty):
        """Vista cenital del ADT para el minimapa: [256, 256, 3] en 0..1 (fila 0 = norte, columna 0 = oeste).
        Color medio de las texturas mezcladas como en el terreno, sombreado por el relieve, agua y muros."""
        x0, y0 = wow.tile_origin(tx, ty)
        p = (np.arange(MINIMAP_SIZE) + 0.5) * (wow.TILE / MINIMAP_SIZE)
        X, Y = np.meshgrid(x0 - p, y0 - p, indexing='ij')
        weights = self.texture_weights(X, Y)
        palette = np.array([MINIMAP_COLORS.get(name, (128, 128, 128)) for name in self.texture_names]) / 255.0
        color = np.tensordot(weights.transpose(1, 2, 0), palette, axes=1)
        color /= np.maximum(weights.sum(axis=0), 1e-6)[..., None]
        # Relieve: luz del noroeste (como los minimapas del juego)
        light = np.array([1.0, 1.0, 1.6])
        light /= np.linalg.norm(light)
        shade = 0.55 + 0.45 * np.clip(self.normals(X, Y) @ light, 0, 1) / light[2]
        color = color * np.clip(shade, 0.3, 1.15)[..., None]
        outside = self.nearest(self.playable.astype(np.float64), X, Y, 0.0) < 0.5
        color = np.where(outside[..., None], color * 0.3, color)        # fuera del mapa jugable: oscuro
        water = self.nearest(self.water, X, Y, False).astype(bool)
        color = np.where(water[..., None], color * 0.35 + np.array(MINIMAP_WATER) / 255.0 * 0.65, color)
        if self.models:
            wall = self._model_mask(X, Y)
            pad = np.pad(wall, 1, mode='edge')
            inner = pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:]
            color = np.where(wall[..., None], np.array(MINIMAP_WALL) / 255.0, color)
            color = np.where((wall & ~inner)[..., None], np.array(MINIMAP_WALL_EDGE) / 255.0, color)
        return np.clip(color, 0, 1)

    def _model_mask(self, X, Y):
        """Puntos bajo la caja de algun modelo de muro."""
        bx0, by0, _, bx1, by1, _ = self.wall_model_cfg['box']
        mask = np.zeros(X.shape, dtype=bool)
        xmin, xmax, ymin, ymax = X.min(), X.max(), Y.min(), Y.max()
        for m in self.models:
            r = m['radius']
            if m['x'] + r < xmin or m['x'] - r > xmax or m['y'] + r < ymin or m['y'] - r > ymax:
                continue
            s, c, si = m['scale'], math.cos(m['angle']), math.sin(m['angle'])
            dx, dy = X - m['x'], Y - m['y']
            lx, ly = dx * c + dy * si, -dx * si + dy * c
            mask |= (lx >= bx0 * s) & (lx <= bx1 * s) & (ly >= by0 * s) & (ly <= by1 * s)
        return mask

    # --- Puntos de interes -------------------------------------------------------------------------------------

    def points(self):
        out = []
        for unit in self.map.start_locations():
            X, Y = self.to_wow(unit.x, unit.y)
            Z = float(self.height(np.array(X), np.array(Y)))
            o = (unit.angle - math.pi / 2) % (2 * math.pi)
            out.append(('Inicio jugador %d' % (unit.player + 1), X, Y, Z, o))
        names = self.info.get('regionNames', {})
        for region in sorted(self.map.regions, key=lambda r: names.get(r.name, r.name)):
            X, Y = self.to_wow(*region.center())
            Z = float(self.height(np.array(X), np.array(Y)))
            label = '%s (%s)' % (names[region.name], region.name) if region.name in names else region.name
            out.append(('Region ' + label, X, Y, Z, 0.0))
        return out


def add_tile_doodads(tile, conv, tx, ty):
    """Modelos que tocan el ADT (conv.models con indice en conv.model_names), con uniqueId global k + 1."""
    local = {}
    for k, m in conv.tile_doodads(tx, ty):
        if m['model'] not in local:
            local[m['model']] = len(tile.models)
            tile.models.append(conv.model_names[m['model']])
        tile.doodads.append(wow.Doodad(local[m['model']], k + 1, m['x'], m['y'], m['z'], m['angle'], m['scale'],
                                       m['radius'], m.get('rot_x', 0.0), m.get('rot_z', 0.0)))


def load_config():
    with open(os.path.join(ROOT, 'Maps', 'maps.json'), encoding='utf-8') as f:
        cfg = json.load(f)
    maps = []
    for entry in cfg['maps']:
        info = dict(DEFAULTS)
        info.update(entry)
        if not 750 <= info['id'] <= 799:
            raise ValueError('mapa %s: id %d fuera del rango reservado 750-799' % (info['directory'], info['id']))
        maps.append(info)
    return maps


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


def write_vmaps(server, info, conv, client_data):
    """vmaps del mapa (modelos con colision) en <server>/vmaps: .vmtree, .vmtile y un .vmo por modelo (vmaps.py).
    Borra antes los del mismo mapa (sin modelos no queda ninguno: el servidor no aplica vmaps al mapa)."""
    out = os.path.join(server, 'vmaps')
    prefix = '%03d_' % info['id']
    if os.path.isdir(out):
        for name in os.listdir(out):
            if name == vmaps.tree_name(info['id']) or (name.startswith(prefix) and name.endswith('.vmtile')):
                os.remove(os.path.join(out, name))
    if not conv.models:
        return 0
    meshes = {}
    for i, model in enumerate(conv.model_names):
        verts, tris = vmaps.m2_collision(vmaps.read_client_file(client_data, model))
        if len(tris) == 0:
            continue                                # sin colision (hierba, matorrales): no va a los vmaps
        name = vmaps.vmo_name(model)
        write(os.path.join(out, name + '.vmo'), vmaps.build_vmo(verts, tris))
        meshes[i] = (name, verts)
    tiles = {}
    for tx, ty in conv.tiles:
        for k, _ in conv.tile_doodads(tx, ty):
            tiles.setdefault(k, []).append((tx, ty))
    spawns = []
    for k, m in enumerate(conv.models):
        if m['model'] not in meshes:
            continue
        name, verts = meshes[m['model']]
        d = wow.Doodad(0, k + 1, m['x'], m['y'], m['z'], m['angle'], m['scale'], m['radius'], m.get('rot_x', 0.0),
                       m.get('rot_z', 0.0))
        _, uid, px, pz, py, rx, ry, rz, scale, _ = struct.unpack('<II3f3fHH', d.mddf())
        # Igual que el extractor sobre el MDDF: posicion (pos.z, pos.x, pos.y), giro tal cual, escala / 1024
        spawns.append(vmaps.Spawn(uid, name, (py, px, pz), (rx, ry, rz), scale / 1024.0, verts, tiles.get(k, [])))
    if not spawns:
        return 0
    vmtree, vmtiles = vmaps.build_map(spawns)
    write(os.path.join(out, vmaps.tree_name(info['id'])), vmtree)
    for (tx, ty), data in vmtiles.items():
        write(os.path.join(out, vmaps.tile_name(info['id'], tx, ty)), data)
    return len(spawns)


def minimap_name(info, tx, ty):
    """Archivo del minimapa en Textures/Minimap (nombre propio en vez de un md5: el .trs solo lo traduce)."""
    return 'eventwow_%d_%d_%d.blp' % (info['id'], tx, ty)


def write_minimap_trs(client, original, entries):
    """md5translate.trs del parche = el original del cliente + nuestros mapas (el del parche lo sustituye entero).
    entries: [(directorio del mapa, [(tx, ty, archivo)])]."""
    with open(original, 'rb') as f:
        text = f.read().decode('latin1')
    ours = {d.lower() for d, _ in entries}
    keep = []
    skipping = False
    for line in text.split('\r\n'):                 # sin nuestros directorios si el original ya los tuviera
        if line.startswith('dir: '):
            skipping = line[5:].strip().lower() in ours
        if not skipping and line:
            keep.append(line)
    for directory, tiles in entries:
        keep.append('dir: %s' % directory)
        for tx, ty, name in tiles:
            keep.append('%s\\map%d_%d.blp\t%s' % (directory, tx, ty, name))
    write(os.path.join(client, 'Textures', 'Minimap', 'md5translate.trs'),
          ('\r\n'.join(keep) + '\r\n').encode('latin1'))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--client', required=True, help='carpeta raiz del parche (p. ej. client\\patches\\patch-4.MPQ)')
    parser.add_argument('--server', help='DataDir del worldserver (se escribe en <server>\\maps)')
    parser.add_argument('--only', type=int, help='solo el mapa con este id')
    parser.add_argument('--minimap-trs', help='md5translate.trs original del cliente (client\\Minimap): '
                                              'con el se generan los minimapas; sin el no hay minimapa')
    parser.add_argument('--preview', help='carpeta donde dejar las vistas previas de los circuitos (PNG)')
    parser.add_argument('--wow-data', help='carpeta Data del cliente (MPQ originales): colision de los modelos para '
                                           'los vmaps del servidor; sin ella no se generan vmaps')
    args = parser.parse_args()

    minimaps = []
    for info in load_config():
        if args.only is not None and info['id'] != args.only:
            continue
        source = os.path.join(ROOT, 'Maps', info['source'])
        directory = info['directory']
        print('Mapa %d "%s" <- %s' % (info['id'], directory, info['source']))
        plan_type = None
        if source.lower().endswith('.json'):
            with open(source, encoding='utf-8') as f:
                plan_type = json.load(f).get('type', 'track')
        track = plan_type is not None
        if plan_type == 'parkour':
            # Recorrido de saltos con modelos M2 sobre el vacio, por secciones (parkourgen.py)
            conv = parkourgen.ParkourConverter(info, source, args.wow_data)
            for line in conv.summary():
                print(line)
            if args.preview:
                os.makedirs(args.preview, exist_ok=True)
                conv.preview(os.path.join(args.preview, '%s_plano.png' % directory))
                print('  Vista previa: %s' % args.preview)
            if args.server:
                write(os.path.join(args.server, 'maps', '%03d_parkour.txt' % info['id']),
                      conv.parkour_lines().encode('utf-8'))
        elif plan_type == 'platforms':
            # Pista de piezas M2 sobre el vacio, sin terreno (platformgen.py)
            conv = platformgen.PlatformConverter(info, source, args.wow_data)
            for line in conv.summary():
                print(line)
            if args.preview:
                os.makedirs(args.preview, exist_ok=True)
                conv.preview(os.path.join(args.preview, '%s_plano.png' % directory))
                print('  Vista previa: %s' % args.preview)
            if args.server and conv.race():
                write(os.path.join(args.server, 'maps', '%03d_pista.json' % info['id']),
                      json.dumps(conv.path_samples()).encode('ascii'))
        elif track:
            # Circuito de carreras desde un plano (trackgen.py)
            conv = trackgen.TrackConverter(info, source, args.wow_data)
            for line in conv.summary():
                print(line)
            if args.preview:
                os.makedirs(args.preview, exist_ok=True)
                conv.preview(os.path.join(args.preview, '%s_plano.png' % directory))
                print('  Vista previa: %s' % args.preview)
            if args.server:
                write(os.path.join(args.server, 'maps', '%03d_pista.json' % info['id']),
                      json.dumps(conv.path_samples()).encode('ascii'))
        else:
            conv = Converter(info, wc3.Wc3Map(source))
            t = conv.t
            print('  WC3: %dx%d casillas, tileset %s, texturas %s, acantilados %s'
                  % (t.width - 1, t.height - 1, t.tileset, t.ground, t.cliffs))
            print('  WoW: %d ADT (%s), muro a %.1f yardas' % (len(conv.tiles), ', '.join('%d_%d' % c for c in conv.tiles),
                                                             conv.wall_height))
            if conv.models:
                print('  Muros: %d modelos %s (%d de relleno en cruces/cuellos)'
                      % (len(conv.models), conv.wall_model_cfg['model'].split('\\')[-1], conv.filler_models))
        client_dir = os.path.join(args.client, 'World', 'Maps', directory)
        write(os.path.join(client_dir, directory + '.wdt'), wow.build_wdt(conv.tiles))
        for tx, ty in conv.tiles:
            tile = conv.build_tile(tx, ty)
            write(os.path.join(client_dir, '%s_%d_%d.adt' % (directory, tx, ty)), wow.build_adt(tile))
            if args.server:
                write(os.path.join(args.server, 'maps', '%03d%02d%02d.map' % (info['id'], ty, tx)),
                      wow.build_server_map(tile))
        if args.server and args.wow_data:
            n = write_vmaps(args.server, info, conv, args.wow_data)
            print('  vmaps: %d modelos' % n if n else '  vmaps: ninguno (sin modelos)')
        if args.minimap_trs:
            tiles = []
            for tx, ty in conv.tiles:
                name = minimap_name(info, tx, ty)
                write(os.path.join(args.client, 'Textures', 'Minimap', name),
                      wow.build_minimap_blp(conv.minimap(tx, ty)))
                tiles.append((tx, ty, name))
            minimaps.append((directory, tiles))
            print('  Minimapa: %d texturas' % len(tiles))
        if conv.unknown:
            print('  AVISO: casillas sin textura en la tabla (se usa "default"): %s' % ', '.join(sorted(conv.unknown)))
        if not track and conv.map.doodads:
            print('  AVISO: %d decoraciones de WC3 sin convertir todavia' % len(conv.map.doodads))
        print('  Puntos (X, Y, Z, orientacion):')
        for name, X, Y, Z, o in conv.points():
            print('    %-44s %9.2f %9.2f %8.2f %5.2f' % (name, X, Y, Z, o))
        if args.server:
            print('  Servidor: %s listo. Falta: mmaps_generator %d (desde el DataDir)' % (args.server, info['id']))
    if minimaps:
        write_minimap_trs(args.client, args.minimap_trs, minimaps)
    elif not args.minimap_trs:
        print('AVISO: sin --minimap-trs no se generan minimapas')


if __name__ == '__main__':
    main()
