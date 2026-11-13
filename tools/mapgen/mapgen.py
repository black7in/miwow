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
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

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
    # Especiales
    'blight': r'Tileset\Expansion01\BoneWastes\BoneWastesDirtShadow.blp',
    'wall': ROCK,
    'default': r'Tileset\Elwynn\ElwynnDirtBase2.blp',
}

DEFAULTS = {
    'yardsPerTile': 4.0,
    'cliffYards': 8.0,
    'wallHeight': None,         # None = la parte mas alta del mapa + wallExtra
    'wallExtra': 15.0,
}


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
        ramp = (t.flags & wc3.FLAG_RAMP) != 0
        if ramp.any():
            # Aproximacion: en las rampas el nivel es la media de los vecinos (pendiente suave entre niveles)
            padded = np.pad(layer, 1, mode='edge')
            mean = sum(padded[1 + dy:1 + dy + layer.shape[0], 1 + dx:1 + dx + layer.shape[1]]
                       for dy in (-1, 0, 1) for dx in (-1, 0, 1)) / 9.0
            layer = np.where(ramp, mean, layer)
        self.playable = ~t.boundary
        ground = (t.ground_height - 0x2000) / 4.0 * self.s
        heights = ground + (layer - 2.0) * info['cliffYards']
        top = heights[self.playable].max() if self.playable.any() else 0.0
        self.wall_height = info['wallHeight'] if info['wallHeight'] is not None else top + info['wallExtra']
        heights[~self.playable] = self.wall_height
        self.heights = heights
        self.water = ((t.flags & wc3.FLAG_WATER) != 0) & self.playable
        self.water_level = ((t.water_level - 0x2000) / 4.0 - wc3.WATER_OFFSET) * self.s

        # Colocacion: el mapa de WC3 centrado en un bloque de n x n ADT empezando en el 32_32
        size = max(t.width - 1, t.height - 1) * info['yardsPerTile']
        self.n = max(1, math.ceil(size / wow.TILE))
        self.tiles = [(32 + i, 32 + j) for j in range(self.n) for i in range(self.n)]
        self.xc = wow.ZERO - 32 * wow.TILE - self.n * wow.TILE / 2
        self.yc = self.xc
        self.cx, self.cy = t.center()

        self._build_texture_grid()

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
        return self.bilinear(self.heights, X, Y, self.wall_height)

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
        self.point_tex = point

        # Celdas con acantilado: niveles distintos en sus 4 esquinas -> textura del acantilado de la esquina mas alta
        lay = t.layer
        corners = np.stack([lay[:-1, :-1], lay[:-1, 1:], lay[1:, :-1], lay[1:, 1:]])
        self.cliff_cell = corners.max(axis=0) != corners.min(axis=0)
        cliff_ids = [tex_id(self.texture_path(c)) for c in t.cliffs] or [self.wall_tex]
        ctex = np.stack([t.cliff_texture[:-1, :-1], t.cliff_texture[:-1, 1:], t.cliff_texture[1:, :-1],
                         t.cliff_texture[1:, 1:]])
        top = np.take_along_axis(ctex, corners.argmax(axis=0)[None], axis=0)[0]
        self.cell_cliff_tex = np.array(cliff_ids)[np.where(top < len(cliff_ids), top, 0)]
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
        return weights

    # --- ADT ---------------------------------------------------------------------------------------------------

    def build_tile(self, tx, ty):
        tile = wow.TileData(tx, ty)
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
        return tile

    # --- Puntos de interes -------------------------------------------------------------------------------------

    def points(self):
        out = []
        for unit in self.map.start_locations():
            X, Y = self.to_wow(unit.x, unit.y)
            Z = float(self.height(np.array(X), np.array(Y)))
            o = (unit.angle - math.pi / 2) % (2 * math.pi)
            out.append(('Inicio jugador %d' % (unit.player + 1), X, Y, Z, o))
        for region in self.map.regions:
            X, Y = self.to_wow(*region.center())
            Z = float(self.height(np.array(X), np.array(Y)))
            out.append(('Region "%s"' % region.name, X, Y, Z, 0.0))
        return out


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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--client', required=True, help='carpeta raiz del parche (p. ej. client\\patches\\patch-4.MPQ)')
    parser.add_argument('--server', help='DataDir del worldserver (se escribe en <server>\\maps)')
    parser.add_argument('--only', type=int, help='solo el mapa con este id')
    args = parser.parse_args()

    for info in load_config():
        if args.only is not None and info['id'] != args.only:
            continue
        source = os.path.join(ROOT, 'Maps', info['source'])
        directory = info['directory']
        print('Mapa %d "%s" <- %s' % (info['id'], directory, info['source']))
        conv = Converter(info, wc3.Wc3Map(source))
        t = conv.t
        print('  WC3: %dx%d casillas, tileset %s, texturas %s, acantilados %s'
              % (t.width - 1, t.height - 1, t.tileset, t.ground, t.cliffs))
        print('  WoW: %d ADT (%s), muro a %.1f yardas' % (len(conv.tiles), ', '.join('%d_%d' % c for c in conv.tiles),
                                                         conv.wall_height))
        client_dir = os.path.join(args.client, 'World', 'Maps', directory)
        write(os.path.join(client_dir, directory + '.wdt'), wow.build_wdt(conv.tiles))
        for tx, ty in conv.tiles:
            tile = conv.build_tile(tx, ty)
            write(os.path.join(client_dir, '%s_%d_%d.adt' % (directory, tx, ty)), wow.build_adt(tile))
            if args.server:
                write(os.path.join(args.server, 'maps', '%03d%02d%02d.map' % (info['id'], ty, tx)),
                      wow.build_server_map(tile))
        if conv.unknown:
            print('  AVISO: casillas sin textura en la tabla (se usa "default"): %s' % ', '.join(sorted(conv.unknown)))
        if conv.map.doodads:
            print('  AVISO: %d decoraciones de WC3 sin convertir todavia' % len(conv.map.doodads))
        print('  Puntos (X, Y, Z, orientacion):')
        for name, X, Y, Z, o in conv.points():
            print('    %-28s %9.2f %9.2f %8.2f %5.2f' % (name, X, Y, Z, o))
        if args.server:
            print('  Servidor: %s\\maps listo. Falta: mmaps_generator %d (desde el DataDir)' % (args.server, info['id']))


if __name__ == '__main__':
    main()
