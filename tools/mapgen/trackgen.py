"""Circuitos de carreras sin Warcraft 3: plano JSON (Maps/Planos) -> terreno, texturas, agua y decoracion de WoW.

El plano describe:
  - la pista: puntos de control de una curva cerrada (Catmull-Rom centripeta) con altura, ancho, ambiente y tipo de
    borde a cada lado por tramo;
  - el relieve natural: ruido de base + montanas, mesetas, lagos y el borde del mapa;
  - los ambientes (texturas de pista, arcen, suelo, roca; decoracion) y adornos a lo largo de la pista.
trackgen calcula la altura por vertice (relieve natural con la pista tallada encima: llana a su altura, con muro de
tierra, corte o caida a cada lado), las texturas (ambiente mezclado por distancia a la pista, pendiente y altura),
el agua, la decoracion (con colision en vmaps) y la linea central para el servidor. Expone la misma interfaz que
mapgen.Converter (tiles, build_tile, minimap, points, models, model_names).

Coordenadas del plano: yardas, x = este, y = norte, origen en el centro del mapa (n x n ADT desde el 32_32).
"""
import json
import math
import os
import struct

import numpy as np

import vmaps
import wowfiles as wow

STEP = wow.UNIT / 2.0           # rejilla de calculo: los vertices exteriores e interiores del ADT caen en ella

EDGE_TYPES = {
    # muro de tierra (berm, yardas), banda de mezcla con el relieve natural (band, yardas)
    'berm': {'berm': 6.0, 'band': 26.0},
    'cut': {'berm': 0.0, 'band': 6.0},          # el relieve natural sube pegado a la pista (canon)
    'drop': {'berm': 0.0, 'band': 10.0},        # el relieve natural cae pegado a la pista (precipicio)
    'open': {'berm': 0.0, 'band': 32.0},        # campo abierto (fuera de pista)
}
BERM_RISE = 3.0                 # yardas en las que sube el muro de tierra (cara empinada: no se sube con la moto)
BERM_TOP = 4.0                  # ancho de la parte de arriba del muro de tierra

PLAN_DEFAULTS = {
    'seed': 1,
    'shoulder': 3.0,            # arcen a cada lado de la pista (misma altura)
    'snowLine': 1e9,            # altura a partir de la que el suelo es nieve (textura snow)
    'snow': None,
    'shore': None,              # textura de orilla (junto al agua)
    'baseNoise': {'amplitude': 6.0, 'scale': 160.0},
    'features': [],
    'checkpoints': 8,
    'props': [],
    'clear': [],                # circulos [x, y, r] sin decoracion aleatoria
    'effects': {},              # textura -> efecto de suelo (GroundEffectTexture: hierba, piedrecitas...)
}


# --- Utilidades ----------------------------------------------------------------------------------------------------

def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _hash(ix, iy, seed):
    h = (ix.astype(np.int64) * 374761393 + iy.astype(np.int64) * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float64) / 32767.5 - 1.0


def value_noise(x, y, scale, seed):
    """Ruido de valor suave en [-1, 1]."""
    fx, fy = x / scale, y / scale
    ix, iy = np.floor(fx), np.floor(fy)
    tx, ty = fx - ix, fy - iy
    tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
    ix, iy = ix.astype(np.int64), iy.astype(np.int64)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed)
    c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(x, y, scale, seed, octaves=4):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total = total + amp * value_noise(x, y, scale / (2 ** o), seed + 101 * o)
        norm += amp
        amp *= 0.5
    return total / norm


def box_blur(a, r, passes=3):
    """Desenfoque de caja separable (r en celdas), bordes repetidos; 3 pasadas ~ gaussiano."""
    r = int(r)
    if r < 1:
        return a
    for _ in range(passes):
        for axis in (0, 1):
            pad = [(0, 0)] * a.ndim
            pad[axis] = (r, r)
            p = np.pad(a, pad, mode='edge')
            c = np.cumsum(p, axis=axis)
            zero = np.zeros_like(np.take(c, [0], axis=axis))
            c = np.concatenate([zero, c], axis=axis)
            n = a.shape[axis]
            a = (np.take(c, range(2 * r + 1, 2 * r + 1 + n), axis=axis) - np.take(c, range(0, n), axis=axis)) \
                / (2 * r + 1)
    return a


def polygon_sdf(px, py, poly):
    """Distancia con signo a un poligono (negativa dentro)."""
    poly = np.asarray(poly, dtype=np.float64)
    d = np.full(px.shape, np.inf)
    inside = np.zeros(px.shape, dtype=bool)
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1)
        d = np.minimum(d, np.hypot(wx - ex * t, wy - ey * t))
        cond = ((ay > py) != (by > py)) & (px < (bx - ax) * (py - ay) / np.where(by != ay, by - ay, 1e-9) + ax)
        inside ^= cond
    return np.where(inside, -d, d)


def m2_box(data):
    """Caja del M2 (minX, minY, minZ, maxX, maxY, maxZ) en yardas (cabecera 0xA0)."""
    return struct.unpack_from('<6f', data, 0xA0)


def blp_mean_color(data):
    """Color medio (0..255) de una textura BLP2 (DXT o paleta) a partir de su mipmap de 4x4 (o el menor >= 4)."""
    if data[:4] != b'BLP2':
        return (128, 128, 128)
    _, compression, alpha_depth, alpha_type, _, w, h = struct.unpack_from('<IBBBBII', data, 4)
    offs = struct.unpack_from('<16I', data, 20)
    sizes = struct.unpack_from('<16I', data, 84)
    level = 0
    while level < 15 and offs[level + 1] and sizes[level + 1] and max(w >> (level + 1), 1) >= 4 \
            and max(h >> (level + 1), 1) >= 4:
        level += 1
    raw = data[offs[level]:offs[level] + sizes[level]]
    if compression == 1:
        palette = np.frombuffer(data, dtype=np.uint8, count=1024, offset=148).reshape(256, 4)
        n = max(w >> level, 1) * max(h >> level, 1)
        idx = np.frombuffer(raw, dtype=np.uint8, count=n)
        bgr = palette[idx][:, :3].mean(axis=0)
        return tuple(int(v) for v in bgr[::-1])
    block = 8 if (compression == 2 and alpha_type == 0 and alpha_depth <= 1) else 16
    cols = []
    for p in range(0, len(raw) - block + 1, block):
        c0, c1 = struct.unpack_from('<HH', raw, p + block - 8)
        for c in (c0, c1):
            cols.append((((c >> 11) & 31) * 255 // 31, ((c >> 5) & 63) * 255 // 63, (c & 31) * 255 // 31))
    if not cols:
        return (128, 128, 128)
    m = np.mean(cols, axis=0)
    return tuple(int(v) for v in m)


# --- Pista --------------------------------------------------------------------------------------------------------

class Track:
    """Linea central muestreada cada yarda: x, y, z, media anchura, parametros de borde por lado y ambiente."""

    def __init__(self, plan, biome_index):
        pts = plan['track']
        n = len(pts)
        P = np.array([p['p'] for p in pts], dtype=np.float64)
        Z = np.array([p['z'] for p in pts], dtype=np.float64)
        W = np.array([p.get('w', 24.0) for p in pts], dtype=np.float64)
        # Catmull-Rom centripeta cerrada; z y ancho con el mismo parametro (uniforme por tramo)
        xs, ys, zs, ws, seg = [], [], [], [], []
        sub = 240
        for i in range(n):
            p0, p1, p2, p3 = P[(i - 1) % n], P[i], P[(i + 1) % n], P[(i + 2) % n]
            t0 = 0.0
            t1 = t0 + max(np.linalg.norm(p1 - p0), 1e-6) ** 0.5
            t2 = t1 + max(np.linalg.norm(p2 - p1), 1e-6) ** 0.5
            t3 = t2 + max(np.linalg.norm(p3 - p2), 1e-6) ** 0.5
            t = np.linspace(t1, t2, sub, endpoint=False)[:, None]
            a1 = (t1 - t) / (t1 - t0) * p0 + (t - t0) / (t1 - t0) * p1
            a2 = (t2 - t) / (t2 - t1) * p1 + (t - t1) / (t2 - t1) * p2
            a3 = (t3 - t) / (t3 - t2) * p2 + (t - t2) / (t3 - t2) * p3
            b1 = (t2 - t) / (t2 - t0) * a1 + (t - t0) / (t2 - t0) * a2
            b2 = (t3 - t) / (t3 - t1) * a2 + (t - t1) / (t3 - t1) * a3
            c = (t2 - t) / (t2 - t1) * b1 + (t - t1) / (t2 - t1) * b2
            u = np.linspace(0, 1, sub, endpoint=False)
            z0, z1, z2, z3 = Z[(i - 1) % n], Z[i], Z[(i + 1) % n], Z[(i + 2) % n]
            zz = 0.5 * ((2 * z1) + (-z0 + z2) * u + (2 * z0 - 5 * z1 + 4 * z2 - z3) * u ** 2
                        + (-z0 + 3 * z1 - 3 * z2 + z3) * u ** 3)
            xs.append(c[:, 0])
            ys.append(c[:, 1])
            zs.append(zz)
            ws.append(W[i] * (1 - u) + W[(i + 1) % n] * u)
            seg.append(np.full(sub, i))
        x, y, z, w, seg = (np.concatenate(a) for a in (xs, ys, zs, ws, seg))
        # Remuestreo por longitud de arco: una muestra por yarda
        dl = np.hypot(np.diff(x, append=x[0]), np.diff(y, append=y[0]))
        s = np.concatenate([[0.0], np.cumsum(dl)])
        self.length = float(s[-1])
        m = int(round(self.length))
        su = np.arange(m) * (self.length / m)
        xx = np.append(x, x[0])
        yy = np.append(y, y[0])
        zz = np.append(z, z[0])
        ww = np.append(w, w[0])
        self.x = np.interp(su, s, xx)
        self.y = np.interp(su, s, yy)
        self.z = np.interp(su, s, zz)
        self.half = np.interp(su, s, ww) / 2.0
        self.seg = seg[np.minimum(np.searchsorted(s, su, side='right') - 1, len(seg) - 1)]
        self.s = su
        self.n = m
        self.ds = self.length / m
        # Altura suavizada (sin quiebros entre tramos)
        self.z = self._smooth(self.z, 30)
        # Parametros por lado (suavizados: los cambios de tipo de borde no son bruscos)
        def side_param(key, name):
            vals = np.array([EDGE_TYPES[pts[i].get(key, 'berm')][name] for i in range(n)])
            return self._smooth(vals[self.seg], 12)
        self.berm_l, self.band_l = side_param('left', 'berm'), side_param('left', 'band')
        self.berm_r, self.band_r = side_param('right', 'berm'), side_param('right', 'band')
        self.biome = np.array([biome_index[pts[i]['biome']] for i in range(n)])[self.seg]
        # Tangente unitaria
        tx = np.gradient(np.concatenate([self.x[-3:], self.x, self.x[:3]]))[3:-3]
        ty = np.gradient(np.concatenate([self.y[-3:], self.y, self.y[:3]]))[3:-3]
        norm = np.hypot(tx, ty)
        self.tx, self.ty = tx / norm, ty / norm
        # Meta: en el punto de control marcado con "start" (por defecto el primero)
        start_cp = next((i for i, p in enumerate(pts) if p.get('start')), 0)
        cp = P[start_cp]
        self.start = int(np.argmin(np.hypot(self.x - cp[0], self.y - cp[1])))

    @staticmethod
    def _smooth(v, r):
        r = int(r)
        if r < 1:
            return v
        p = np.concatenate([v[-r:], v, v[:r]])
        k = np.ones(2 * r + 1) / (2 * r + 1)
        return np.convolve(p, k, mode='same')[r:-r]

    def nearest(self, px, py, chunk=2048):
        """Para cada punto: indice de la muestra mas cercana, distancia (proyectada al tramo) y lado (+1 izquierda)."""
        shape = px.shape
        px, py = px.ravel(), py.ravel()
        idx = np.empty(px.size, dtype=np.int64)
        tx32, ty32 = self.x.astype(np.float32), self.y.astype(np.float32)
        for a in range(0, px.size, chunk):
            dx = px[a:a + chunk, None].astype(np.float32) - tx32[None, :]
            dy = py[a:a + chunk, None].astype(np.float32) - ty32[None, :]
            idx[a:a + chunk] = np.argmin(dx * dx + dy * dy, axis=1)
        # Proyeccion sobre la tangente: distancia perpendicular continua (bordes de la pista nitidos)
        rx, ry = px - self.x[idx], py - self.y[idx]
        along = rx * self.tx[idx] + ry * self.ty[idx]
        side = np.sign(self.tx[idx] * ry - self.ty[idx] * rx)
        perp = np.abs(self.tx[idx] * ry - self.ty[idx] * rx)
        dist = np.where(np.abs(along) < 2.0, perp, np.hypot(rx, ry))
        return idx.reshape(shape), dist.reshape(shape), np.where(side == 0, 1, side).reshape(shape)

    def point(self, s):
        """(x, y, z, direccion) en la posicion s (yardas desde la muestra 0, ciclica)."""
        k = int(round(s / self.ds)) % self.n
        return self.x[k], self.y[k], self.z[k], math.atan2(self.ty[k], self.tx[k]), k


# --- Conversor ----------------------------------------------------------------------------------------------------

class TrackConverter:
    def __init__(self, info, plan_path, wow_data):
        if not wow_data:
            raise ValueError('mapa %s: los circuitos necesitan --wow-data (modelos de la decoracion)' % info['directory'])
        with open(plan_path, encoding='utf-8') as f:
            plan = dict(PLAN_DEFAULTS)
            plan.update(json.load(f))
        self.info, self.plan, self.wow_data = info, plan, wow_data
        self.unknown = set()
        self.n = int(plan.get('adts', 2))
        self.tiles = [(32 + i, 32 + j) for j in range(self.n) for i in range(self.n)]
        self.X0, self.Y0 = wow.tile_origin(*self.tiles[0])
        self.half = self.n * wow.TILE / 2.0
        self.size = int(round(self.n * wow.TILE / STEP)) + 1
        self.rng = np.random.default_rng(plan['seed'])

        self.biome_names = list(plan['biomes'])
        self.biome_index = {b: i for i, b in enumerate(self.biome_names)}
        self.track = Track(plan, self.biome_index)

        # Rejilla: fila i = norte -> sur, columna j = oeste -> este (local y = half - i*STEP, x = j*STEP - half)
        r = np.arange(self.size) * STEP
        self.gx, self.gy = np.meshgrid(r - self.half, self.half - r)
        self._terrain()
        self._textures_setup()
        self._doodads()

    # --- Coordenadas ---------------------------------------------------------------------------------------------

    def to_wow(self, x, y):
        return self.X0 - self.half + y, self.Y0 - self.half - x

    def to_local(self, X, Y):
        return (self.Y0 - self.half) - Y, X - (self.X0 - self.half)

    def bilinear(self, grid, X, Y):
        fi = np.clip((self.X0 - X) / STEP, 0, self.size - 1)
        fj = np.clip((self.Y0 - Y) / STEP, 0, self.size - 1)
        i0 = np.minimum(np.floor(fi).astype(int), self.size - 2)
        j0 = np.minimum(np.floor(fj).astype(int), self.size - 2)
        a, b = fi - i0, fj - j0
        return (grid[..., i0, j0] * (1 - a) * (1 - b) + grid[..., i0 + 1, j0] * a * (1 - b)
                + grid[..., i0, j0 + 1] * (1 - a) * b + grid[..., i0 + 1, j0 + 1] * a * b)

    def nearest_cell(self, grid, X, Y):
        i = np.clip(np.rint((self.X0 - X) / STEP).astype(int), 0, self.size - 1)
        j = np.clip(np.rint((self.Y0 - Y) / STEP).astype(int), 0, self.size - 1)
        return grid[i, j]

    # --- Relieve -------------------------------------------------------------------------------------------------

    def _natural(self, x, y):
        p = self.plan
        seed = p['seed']
        base = p['baseNoise']
        H = base['amplitude'] * fbm(x, y, base['scale'], seed)
        water = np.zeros(x.shape, dtype=bool)
        level = np.zeros(x.shape)
        for k, f in enumerate(p['features']):
            kind = f['type']
            fs = seed + 1000 * (k + 1)
            if kind == 'mountain':
                cx, cy = f['c']
                rx, ry = f.get('rx', f.get('r')), f.get('ry', f.get('r'))
                warp = 1.0 + f.get('warp', 0.18) * fbm(x, y, f.get('warpScale', 120.0), fs)
                d = np.hypot((x - cx) / rx, (y - cy) / ry) / warp
                t = np.clip(1.0 - d, 0.0, 1.0)
                shape = t * t * (3 - 2 * t)
                ridges = 1.0 - np.abs(fbm(x, y, f.get('ridgeScale', 90.0), fs + 7, 5))
                H = H + f['h'] * shape ** f.get('power', 1.0) * (1.0 - f.get('ridges', 0.25)
                                                                 + f.get('ridges', 0.25) * ridges)
            elif kind == 'mesa':
                warp = f.get('warp', 10.0) * fbm(x, y, f.get('warpScale', 70.0), fs)
                sd = polygon_sdf(x, y, f['poly']) + warp
                e = f.get('edge', 14.0)
                top = f['h'] + f.get('topNoise', 3.0) * fbm(x, y, 60.0, fs + 3)
                t = 1.0 - smoothstep(-e, e, sd)
                if f.get('terraces'):
                    steps = f['terraces']
                    tt = t * steps
                    t = (np.floor(tt) + smoothstep(0.35, 0.65, tt - np.floor(tt))) / steps
                H = H + top * t
            elif kind == 'lake':
                cx, cy = f['c']
                rx, ry = f.get('rx', f.get('r')), f.get('ry', f.get('r'))
                warp = 1.0 + 0.12 * fbm(x, y, 60.0, fs)
                d = np.hypot((x - cx) / rx, (y - cy) / ry) / warp
                bed = f['level'] - f.get('depth', 6.0) * (1.0 - smoothstep(0.0, 1.0, d))
                t = 1.0 - smoothstep(0.8, 1.6, d)
                H = H * (1 - t) + np.minimum(H, bed + (H - bed) * smoothstep(0.6, 1.6, d)) * t
                inside = d < 1.25
                water |= inside
                level = np.where(inside, f['level'], level)
            elif kind == 'rim':
                m = f.get('margin', 120.0)
                # Distancia al borde con esquinas redondeadas (superelipse)
                pw = f.get('roundness', 4.0)
                b = self.half - (np.abs(x) ** pw + np.abs(y) ** pw) ** (1.0 / pw)
                b = b + f.get('warp', 30.0) * fbm(x, y, 110.0, fs)
                t = smoothstep(m, 0.0, b)
                ridges = 1.0 - np.abs(fbm(x, y, 80.0, fs + 5, 5))
                H = H + f['h'] * t ** 1.4 * (0.65 + 0.35 * ridges)
            elif kind == 'flat':
                cx, cy = f['c']
                d = np.hypot(x - cx, y - cy)
                t = 1.0 - smoothstep(f['r'] * 0.7, f['r'], d)
                H = H * (1 - t) + f['h'] * t
        return H, water, level

    def _terrain(self):
        x, y = self.gx, self.gy
        N, water, level = self._natural(x, y)
        tr = self.track
        idx, dist, side = tr.nearest(x, y)
        zt = tr.z[idx]
        half = tr.half[idx]
        berm = np.where(side > 0, tr.berm_l[idx], tr.berm_r[idx])
        band = np.where(side > 0, tr.band_l[idx], tr.band_r[idx])
        e = dist - half - self.plan['shoulder']
        # Muro de tierra: sube en BERM_RISE, llano BERM_TOP, y luego se mezcla con el relieve natural
        rise = zt + berm * smoothstep(0.0, BERM_RISE, e)
        t = smoothstep(0.0, band, e - np.where(berm > 0.5, BERM_RISE + BERM_TOP, 0.0))
        outer = (zt + berm) * (1 - t) + N * t
        H = np.where(e <= 0, zt, np.where((berm > 0.5) & (e < BERM_RISE + BERM_TOP), rise, outer))
        self.heights = H
        self.dist = dist
        self.half_grid = half
        self.track_idx = idx
        self.natural = N
        # Agua: lagos del relieve, solo donde el suelo queda por debajo y lejos de la pista
        self.water = water & (H < level - 0.05) & (e > 2.0)
        self.water_level = np.where(self.water, level, H)
        # Pendiente (tangente) para texturas y decoracion
        gi, gj = np.gradient(H, STEP)
        self.slope = np.hypot(gi, gj)
        self.top = float(H.max())

    def height(self, X, Y):
        return self.bilinear(self.heights, X, Y)

    def normals(self, X, Y):
        e = wow.UNIT / 2.0
        dx = (self.height(X + e, Y) - self.height(X - e, Y)) / (2 * e)
        dy = (self.height(X, Y + e) - self.height(X, Y - e)) / (2 * e)
        n = np.stack([-dx, -dy, np.ones_like(dx)], axis=-1)
        return n / np.linalg.norm(n, axis=-1, keepdims=True)

    # --- Texturas ------------------------------------------------------------------------------------------------

    def _textures_setup(self):
        p = self.plan
        names = []
        index = {}

        def tid(path):
            if path is None:
                return None
            if path not in index:
                index[path] = len(names)
                names.append(path)
            return index[path]

        self.biome_tex = []
        for b in self.biome_names:
            cfg = p['biomes'][b]
            ground = cfg['ground']
            self.biome_tex.append({
                'road': tid(cfg['road']), 'verge': tid(cfg['verge']), 'rock': tid(cfg['rock']),
                'ground': tid(ground[0]), 'ground2': tid(cfg.get('ground2', [None])[0]),
                'ground2_amount': cfg.get('ground2', [None, 0.0])[1],
                'snow_line': cfg.get('snowLine', p['snowLine']),
            })
        self.snow_tex = tid(p['snow'])
        self.shore_tex = tid(p['shore'])
        self.texture_names = names
        # Peso de cada ambiente en la rejilla: el de la muestra de pista mas cercana, difuminado
        onehot = np.stack([(self.track.biome[self.track_idx] == b).astype(np.float64)
                           for b in range(len(self.biome_names))])
        blur = int(p.get('biomeBlend', 40.0) / STEP / 1.7)
        self.biome_w = np.stack([box_blur(onehot[b], blur) for b in range(len(self.biome_names))])
        self.biome_w /= np.maximum(self.biome_w.sum(axis=0), 1e-6)
        self.noise = fbm(self.gx, self.gy, 45.0, p['seed'] + 77, 4)
        # Orilla: cerca del agua (agua difuminada)
        self.shore = box_blur(self.water.astype(np.float64), max(1, int(6.0 / STEP)), 2)
        # Colores del minimapa
        self.colors = []
        for path in names:
            try:
                self.colors.append(blp_mean_color(vmaps.read_client_file(self.wow_data, path)))
            except (FileNotFoundError, struct.error):
                self.unknown.add(path)
                self.colors.append((128, 128, 128))

    def texture_weights(self, X, Y):
        p = self.plan
        k = len(self.texture_names)
        W = np.zeros((k,) + X.shape, dtype=np.float32)
        d = self.bilinear(self.dist, X, Y)
        half = self.bilinear(self.half_grid, X, Y)
        H = self.bilinear(self.heights, X, Y)
        slope = self.bilinear(self.slope, X, Y)
        noise = self.bilinear(self.noise, X, Y)
        bw = self.bilinear(self.biome_w, X, Y)
        shore = self.bilinear(self.shore, X, Y)
        road = 1.0 - smoothstep(half - 0.5, half + 0.5, d)
        verge = (1.0 - road) * (1.0 - smoothstep(half + p['shoulder'] - 0.5, half + p['shoulder'] + 0.5, d))
        off = 1.0 - road - verge
        rock = smoothstep(0.62, 0.95, slope)
        sand = smoothstep(0.02, 0.25, shore) if self.shore_tex is not None else np.zeros(X.shape)
        for b, tex in enumerate(self.biome_tex):
            wb = bw[b]
            # Nieve por encima de la cota de nieve del ambiente (cada uno la suya: solo nieva en la montana)
            snow = smoothstep(tex['snow_line'] - 6.0, tex['snow_line'] + 6.0, H + 4.0 * noise) \
                if self.snow_tex is not None else np.zeros(X.shape)
            W[tex['road']] += wb * road
            W[tex['verge']] += wb * verge
            o = wb * off
            W[tex['rock']] += o * rock * (1 - snow)
            g = o * (1 - rock) * (1 - snow) * (1 - sand)
            if tex['ground2'] is not None:
                g2 = smoothstep(0.5 - tex['ground2_amount'] - 0.06, 0.5 - tex['ground2_amount'] + 0.06,
                                (noise + 1) / 2)
                W[tex['ground2']] += g * g2
                g = g * (1 - g2)
            W[tex['ground']] += g
            if self.snow_tex is not None:
                W[self.snow_tex] += o * snow
            if self.shore_tex is not None:
                W[self.shore_tex] += o * (1 - rock) * (1 - snow) * sand
        return W

    # --- Decoracion ----------------------------------------------------------------------------------------------

    def _model(self, path):
        if path not in self.model_index:
            data = vmaps.read_client_file(self.wow_data, path)
            box = m2_box(data)
            self.model_index[path] = len(self.model_names)
            self.model_names.append(path)
            self.model_box.append(box)
        return self.model_index[path]

    def _add(self, path, x, y, angle, scale, z=None, sink=0.3):
        m = self._model(path)
        X, Y = self.to_wow(x, y)
        if z is None:
            z = float(self.height(np.array(X), np.array(Y))) - sink * scale
        bx0, by0, _, bx1, by1, _ = self.model_box[m]
        radius = max(abs(bx0), abs(bx1), abs(by0), abs(by1)) * math.sqrt(2) * scale + 1.0
        self.models.append({'model': m, 'x': float(X), 'y': float(Y), 'z': float(z), 'angle': float(angle),
                            'scale': float(scale), 'radius': radius})

    def _doodads(self):
        p = self.plan
        self.models, self.model_names, self.model_box, self.model_index = [], [], [], {}
        tr = self.track
        rng = self.rng
        # Adornos a lo largo de la pista (farolas, vallas, banderas...)
        # side "center": sobre la pista (arcos de meta: su +X cruza la pista con angle "across").
        # at "meta" / "checkpoints": en la meta / en los puntos de control (en vez de from/to/every).
        for prop in p['props']:
            at = prop.get('at')
            if at == 'meta':
                stations = [0.0]
            elif at == 'checkpoints':
                n = int(p['checkpoints'])
                stations = [tr.length * c / n for c in range(1, n)]
            else:
                stations = list(np.arange(prop.get('from', 0.0), prop.get('to', tr.length) + 1e-6, prop['every']))
            sides = {'both': (1, -1), 'left': (1,), 'right': (-1,), 'center': (0,)}[prop.get('side', 'both')]
            for s in stations:
                x, y, z, a, k = tr.point(tr.s[tr.start] + s)
                for sd in sides:
                    off = 0.0 if sd == 0 else tr.half[k] + p['shoulder'] + prop.get('offset', 1.5)
                    nx, ny = -tr.ty[k] * sd, tr.tx[k] * sd
                    ang = {'along': a, 'across': a + math.pi / 2 * (sd or 1), 'inward': a - math.pi / 2 * sd}.get(
                        prop.get('angle', 'along'), a)
                    # a es el rumbo en el plano (0 = este); el del modelo va en orientacion WoW (0 = norte)
                    self._add(prop['model'], x + nx * off, y + ny * off, ang - math.pi / 2, prop.get('scale', 1.0),
                              sink=prop.get('sink', 0.1))
        # Decoracion aleatoria por ambiente
        spacing = p.get('scatterSpacing', 5.0)
        r = np.arange(-self.half + spacing / 2, self.half, spacing)
        cx, cy = np.meshgrid(r, r)
        cx = cx + rng.uniform(-spacing / 2, spacing / 2, cx.shape)
        cy = cy + rng.uniform(-spacing / 2, spacing / 2, cy.shape)
        cx, cy = cx.ravel(), cy.ravel()
        X, Y = self.to_wow(cx, cy)
        d = self.bilinear(self.dist, X, Y)
        half = self.bilinear(self.half_grid, X, Y)
        e = d - half - p['shoulder']
        slope = self.bilinear(self.slope, X, Y)
        bw = self.bilinear(self.biome_w, X, Y)
        wet = self.nearest_cell(self.water.astype(np.float64), X, Y) > 0.5
        H = self.bilinear(self.heights, X, Y)
        clear = np.zeros(cx.shape, dtype=bool)
        for c in p['clear']:
            clear |= np.hypot(cx - c[0], cy - c[1]) < c[2]
        # Muestras de pista para no tapar la vista en las rectas de salida
        area = spacing * spacing
        u = rng.uniform(0, 1, cx.shape)
        pick = rng.uniform(0, 1, cx.shape)
        prob = np.zeros(cx.shape)
        for b, name in enumerate(self.biome_names):
            cfg = p['biomes'][name].get('scatter')
            if not cfg:
                continue
            dens = cfg.get('density', 1.0) + cfg.get('lining', 0.0) * np.exp(-((e - cfg.get('liningAt', 9.0))
                                                                                / cfg.get('liningWidth', 7.0)) ** 2)
            dens = dens * (1.0 - smoothstep(cfg.get('maxHeight', 1e9) - 10, cfg.get('maxHeight', 1e9), H))
            prob += bw[b] * dens * area / 1000.0
        ok = (u < prob) & (e > p.get('clearance', 3.0)) & ~wet & ~clear & (np.abs(cx) < self.half - 4) \
            & (np.abs(cy) < self.half - 4)
        for i in np.nonzero(ok)[0]:
            # Ambiente segun su peso en el punto
            wsum = np.cumsum(bw[:, i])
            b = int(np.searchsorted(wsum, pick[i] * wsum[-1]))
            cfg = p['biomes'][self.biome_names[min(b, len(self.biome_names) - 1)]].get('scatter')
            if not cfg:
                continue
            items = [it for it in cfg['models'] if slope[i] <= it.get('maxSlope', 0.8)]
            if not items:
                continue
            weights = np.array([it.get('weight', 1.0) for it in items])
            it = items[int(rng.choice(len(items), p=weights / weights.sum()))]
            sc = rng.uniform(*it.get('scale', [0.85, 1.15]))
            self._add(it['model'], cx[i], cy[i], rng.uniform(0, 2 * math.pi), sc, sink=it.get('sink', 0.4))

    def tile_doodads(self, tx, ty):
        x0, y0 = wow.tile_origin(tx, ty)
        out = []
        for k, m in enumerate(self.models):
            r = m['radius']
            if x0 - wow.TILE - r <= m['x'] <= x0 + r and y0 - wow.TILE - r <= m['y'] <= y0 + r:
                out.append((k, m))
        return out

    # --- ADT -----------------------------------------------------------------------------------------------------

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
        tile.water = self.nearest_cell(self.water, Xi, Yi).astype(bool)
        tile.water_height = self.bilinear(self.water_level, Xo, Yo)

        pa = (np.arange(1024) + 0.5) * (wow.TILE / 1024.0)
        Xa, Ya = np.meshgrid(x0 - pa, y0 - pa, indexing='ij')
        weights = self.texture_weights(Xa, Ya)
        used = []
        for cr in range(16):
            for cc in range(16):
                wch = weights[:, cr * 64:(cr + 1) * 64, cc * 64:(cc + 1) * 64]
                totals = wch.reshape(wch.shape[0], -1).sum(axis=1)
                order = [int(i) for i in np.argsort(-totals) if totals[i] > 0][:4] or [0]
                sel = wch[order].astype(np.float64)
                total = sel.sum(axis=0)
                sel = np.where(total > 0, sel / np.where(total > 0, total, 1), 0)
                sel[0] = np.where(total > 0, sel[0], 1.0)
                layers = []
                acc = sel[0].copy()
                for li, t in enumerate(order):
                    if t not in used:
                        used.append(t)
                    local = used.index(t)
                    if li == 0:
                        layers.append((local, None))
                        continue
                    acc = acc + sel[li]
                    alpha = np.where(acc > 0, sel[li] / np.where(acc > 0, acc, 1), 0)
                    layers.append((local, alpha))
                tile.layers[(cr, cc)] = layers
        tile.textures = [self.texture_names[i] for i in used]
        effects = self.plan['effects']
        tile.effects = {i: int(effects.get(name, 0)) for i, name in enumerate(tile.textures)}

        local = {}
        for k, m in self.tile_doodads(tx, ty):
            if m['model'] not in local:
                local[m['model']] = len(tile.models)
                tile.models.append(self.model_names[m['model']])
            tile.doodads.append(wow.Doodad(local[m['model']], k + 1, m['x'], m['y'], m['z'], m['angle'],
                                           m['scale'], m['radius']))
        return tile

    # --- Minimapa y vista previa ---------------------------------------------------------------------------------

    def color_at(self, X, Y):
        weights = self.texture_weights(X, Y)
        palette = np.array(self.colors, dtype=np.float64) / 255.0
        color = np.tensordot(weights.transpose(tuple(range(1, weights.ndim)) + (0,)), palette, axes=1)
        color /= np.maximum(weights.sum(axis=0), 1e-6)[..., None]
        light = np.array([1.0, 1.0, 1.6])
        light /= np.linalg.norm(light)
        shade = 0.55 + 0.45 * np.clip(self.normals(X, Y) @ light, 0, 1) / light[2]
        color = color * np.clip(shade, 0.3, 1.15)[..., None]
        water = self.nearest_cell(self.water, X, Y).astype(bool)
        color = np.where(water[..., None], color * 0.35 + np.array([38, 78, 120]) / 255.0 * 0.65, color)
        return np.clip(color, 0, 1)

    def minimap(self, tx, ty):
        x0, y0 = wow.tile_origin(tx, ty)
        p = (np.arange(256) + 0.5) * (wow.TILE / 256)
        X, Y = np.meshgrid(x0 - p, y0 - p, indexing='ij')
        color = self.color_at(X, Y)
        self._draw_doodads(color, X[0, 0], Y[0, 0], wow.TILE / 256)
        return color

    def _draw_doodads(self, img, Xtop, Yleft, px):
        """Copas de arboles y rocas como manchas oscuras (vista cenital)."""
        h, w = img.shape[:2]
        for m in self.models:
            i = (Xtop - m['x']) / px
            j = (Yleft - m['y']) / px
            r = max(1.0, min(m['radius'] * 0.45, 6.0) / px)
            if i < -r or j < -r or i > h + r or j > w + r:
                continue
            i0, i1 = int(max(0, i - r)), int(min(h - 1, i + r))
            j0, j1 = int(max(0, j - r)), int(min(w - 1, j + r))
            if i1 < i0 or j1 < j0:
                continue
            ii, jj = np.mgrid[i0:i1 + 1, j0:j1 + 1]
            mask = (ii - i) ** 2 + (jj - j) ** 2 <= r * r
            img[i0:i1 + 1, j0:j1 + 1][mask] *= 0.55

    def preview(self, path, scale=1.0):
        """PNG cenital de todo el mapa con la pista, la meta, los puntos de control y la decoracion."""
        from PIL import Image, ImageDraw
        size = int(self.n * wow.TILE / scale)
        p = (np.arange(size) + 0.5) * scale
        X, Y = np.meshgrid(self.X0 - p, self.Y0 - p, indexing='ij')
        img = self.color_at(X, Y)
        self._draw_doodads(img, self.X0, self.Y0, scale)
        im = Image.fromarray((img * 255).astype(np.uint8))
        dr = ImageDraw.Draw(im)
        tr = self.track

        def px(x, y):
            Xw, Yw = self.to_wow(x, y)
            return ((self.Y0 - Yw) / scale, (self.X0 - Xw) / scale)
        for name, x, y, z, o, _ in self.markers():
            cx, cy = px(x, y)
            col = (255, 255, 255) if name.startswith('Meta') else (255, 210, 40) if name.startswith('Control') \
                else (255, 80, 80)
            dr.ellipse([cx - 4, cy - 4, cx + 4, cy + 4], outline=(0, 0, 0), fill=col)
        im.save(path)

    def perspective(self, path, eye, target, fov=70.0, width=960, height=540, far=1400.0):
        """Vista en perspectiva aproximada (trazado de rayos sobre el relieve, sin modelos)."""
        from PIL import Image
        ex, ey, ez = eye
        yaw = math.atan2(target[1] - ey, target[0] - ex)
        dist0 = math.hypot(target[0] - ex, target[1] - ey)
        pitch = math.atan2(target[2] - ez, dist0)
        img = np.zeros((height, width, 3))
        sky = np.linspace(0.85, 0.55, height)[:, None] * np.array([0.55, 0.72, 0.95])
        img[:] = sky[:, None, :]
        ybuf = np.full(width, height)
        f = (width / 2) / math.tan(math.radians(fov) / 2)
        cols = np.arange(width)
        ang = yaw - np.arctan((cols - width / 2) / f)
        dz = 0.6
        z = 1.0
        while z < far:
            x = ex + np.cos(ang) * z
            y = ey + np.sin(ang) * z
            X, Y = self.to_wow(x, y)
            inside = (np.abs(x) < self.half) & (np.abs(y) < self.half)
            h = self.height(X, Y)
            proj = (h - ez) / z * f
            scr = (height / 2 - (proj - math.tan(pitch) * f)).astype(int)
            draw = inside & (scr < ybuf)
            if draw.any():
                c = self.color_at(X[draw], Y[draw])
                fog = min(z / far, 1.0) ** 1.5
                c = c * (1 - fog) + np.array([0.65, 0.75, 0.9]) * fog
                for k, col in enumerate(np.nonzero(draw)[0]):
                    top = max(scr[draw][k], 0)
                    img[top:ybuf[col], col] = c[k]
                ybuf[draw] = np.maximum(scr[draw], 0)
            z += dz
            dz = 0.6 + z * 0.006
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(path)

    # --- Puntos y pista para el servidor -------------------------------------------------------------------------

    def markers(self):
        """[(nombre, x, y, z, orientacion WoW, s)] en coordenadas del plano: meta, parrilla y puntos de control."""
        tr = self.track
        out = []
        s0 = tr.s[tr.start]
        x, y, z, a, k = tr.point(s0)
        out.append(('Meta', x, y, z, a, 0.0))
        # Parrilla: 2 columnas, filas cada 9 yardas detras de la meta, escalonadas
        for slot in range(8):
            row, col = slot // 2, slot % 2
            back = 10.0 + row * 9.0 + col * 4.5
            px_, py_, pz, pa, pk = tr.point(s0 - back)
            lat = (tr.half[pk] * 0.45) * (1 if col == 0 else -1)
            out.append(('Parrilla %d' % (slot + 1), px_ - tr.ty[pk] * lat, py_ + tr.tx[pk] * lat, pz, pa, -back))
        n = int(self.plan['checkpoints'])
        for c in range(1, n):
            s = tr.length * c / n
            px_, py_, pz, pa, _ = tr.point(s0 + s)
            out.append(('Control %d' % c, px_, py_, pz, pa, s))
        return out

    def points(self):
        out = []
        for name, x, y, z, a, _ in self.markers():
            X, Y = self.to_wow(x, y)
            Z = float(self.height(np.array(X), np.array(Y)))
            # Orientacion WoW: 0 = norte (+X), pi/2 = oeste (+Y); a = angulo en el plano (0 = este)
            o = (a - math.pi / 2) % (2 * math.pi)
            out.append((name, X, Y, Z, o))
        return out

    def path_samples(self, every=2.0):
        """Linea central desde la meta: [(s, X, Y, Z, media anchura)]."""
        tr = self.track
        out = []
        s = 0.0
        while s < tr.length:
            x, y, _, _, k = tr.point(tr.s[tr.start] + s)
            X, Y = self.to_wow(x, y)
            out.append((round(s, 2), round(float(X), 2), round(float(Y), 2),
                        round(float(self.height(np.array(X), np.array(Y))), 2), round(float(tr.half[k]), 2)))
            s += every
        return out

    def summary(self):
        tr = self.track
        grade = np.abs(np.diff(np.append(tr.z, tr.z[0]))) / tr.ds
        lines = ['  Circuito: %.0f yardas por vuelta, %d puntos de control, ancho %.0f-%.0f, pendiente max %.1f %%'
                 % (tr.length, self.plan['checkpoints'], tr.half.min() * 2, tr.half.max() * 2, grade.max() * 100),
                 '  WoW: %d ADT (%s), relieve de %.1f a %.1f' % (len(self.tiles), ', '.join('%d_%d' % t for t in self.tiles),
                                                                float(self.heights.min()), self.top),
                 '  Decoracion: %d modelos (%d distintos)' % (len(self.models), len(self.model_names))]
        return lines
