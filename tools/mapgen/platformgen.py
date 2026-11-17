"""Pistas en el espacio sin Warcraft 3: plano JSON ("type": "platforms") -> mapa sin terreno con la pista hecha de
piezas M2 encadenadas (decoracion del ADT, con colision en el cliente y en los vmaps del servidor).

El terreno existe (el cliente necesita los ADT para la decoracion) pero todos sus trozos son agujeros: no se dibuja y
el servidor no tiene suelo (GridTerrainData::isHole -> INVALID_HEIGHT; solo los vmaps de las piezas). El cielo lo
pone una luz del mapa (Light.dbc, SQL del modulo). Caer al vacio: el servidor mata por debajo de MIN_HEIGHT (-500).

Plano:
  pieces: {clave: {model, scale, kind: "rect" | "disc", overlap, maxTurn, zigzag}}
      rect = pieza alargada en su +X (la pista va a lo largo); disc = pieza redonda, se encadena solapada.
  paths: [{name, piece, ...}] de dos clases:
      abierta: start: [x, y, z], heading (grados, 0 = este, 90 = norte), segments: [...]
          segmento: {"straight": yardas, "dz": subida} | {"arc": grados (+ izquierda), "radius": yardas, "dz": subida}
      circuito cerrado: points: [{p: [x, y], z, start?}] (Catmull-Rom centripeta cerrada, como trackgen), checkpoints
          La primera pista cerrada es la carrera: meta (punto con "start"), parrilla de 8, puntos de control y la
          linea central para el servidor (<DataDir>/maps/<id>_pista.json, mismo formato que trackgen).
      Las pistas pueden cruzarse por encima/debajo (las piezas son modelos): summary avisa si falta altura libre.
  decor: [{models: [...], count, scale: [min, max], distance: [min, max], z: [min, max], seed}]
      rocas flotantes alrededor de las pistas (a distancia minima de ellas).

Coordenadas del plano: yardas, x = este, y = norte, origen en el centro del mapa (n x n ADT desde el 32_32).
Expone la interfaz de mapgen.Converter (tiles, build_tile, tile_doodads, minimap, points, models, model_names).
"""
import json
import math

import numpy as np

import vmaps
import wowfiles as wow
from trackgen import Track, m2_box

PLAN_DEFAULTS = {
    'seed': 1,
    'adts': 2,
    'groundZ': -900.0,          # altura del terreno invisible (todo agujeros)
    'texture': 'Tileset\\Expansion02\\Nexus\\Nexus_Ground_01.blp',
    'decor': [],
}

PIECE_DEFAULTS = {
    'kind': 'rect',
    'scale': 1.0,
    'overlap': 0.15,            # fraccion de la pieza que se solapa con la siguiente
    'maxTurn': 12.0,            # giro maximo entre dos piezas seguidas (grados): en curva se acortan los pasos
    'zigzag': 0.04,             # desnivel alterno entre piezas solapadas (evita el parpadeo de caras coplanarias)
}


def piece_geometry(data):
    """Del M2: centro (x, y) y altura de la cara superior plana de la colision (la mayor por area) y su extension."""
    v, t = vmaps.m2_collision(data)
    if len(t) == 0:
        raise ValueError('la pieza no tiene colision (se atravesaria)')
    tri = v[t]
    nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    ln = np.linalg.norm(nrm, axis=1)
    flat = np.abs(nrm[:, 2]) / np.maximum(ln, 1e-9) > 0.985
    if not flat.any():
        raise ValueError('la pieza no tiene una cara superior plana')
    zc = tri[:, :, 2].mean(axis=1)
    levels = {}
    for z, a in zip(np.round(zc[flat], 1), ln[flat] / 2):
        levels[z] = levels.get(z, 0.0) + a
    top = max(levels.items(), key=lambda kv: kv[1])[0]
    sel = flat & (np.abs(zc - top) < 0.15)
    p = tri[sel].reshape(-1, 3)
    lo, hi = p.min(axis=0), p.max(axis=0)
    return {'cx': float(lo[0] + hi[0]) / 2, 'cy': float(lo[1] + hi[1]) / 2, 'top': float(p[:, 2].mean()),
            'length': float(hi[0] - lo[0]), 'width': float(hi[1] - lo[1])}


def rotation(angle, pitch, roll):
    """Giro de una pieza en el mundo: Rz(angulo) * Ry(-cabeceo) * Rx(alabeo) (convencion de MDDF/vmaps, ver Doodad)."""
    ca, sa = math.cos(angle), math.sin(angle)
    b, c = -pitch, roll
    rz = np.array([[ca, -sa, 0], [sa, ca, 0], [0, 0, 1]])
    ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    rx = np.array([[1, 0, 0], [0, math.cos(c), -math.sin(c)], [0, math.sin(c), math.cos(c)]])
    return rz @ ry @ rx


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


class Path:
    """Linea central muestreada cada yarda: x, y, z, rumbo (radianes, 0 = este) y distancia s."""

    def __init__(self, cfg):
        self.closed = 'points' in cfg
        if self.closed:
            self._closed(cfg)
        else:
            self._open(cfg)
        self.hu = np.unwrap(self.h)

    def _closed(self, cfg):
        pts = [dict(p, biome='-') for p in cfg['points']]
        tr = Track({'track': pts}, {'-': 0})
        self.x, self.y, self.z = tr.x, tr.y, tr.z
        self.h = np.arctan2(tr.ty, tr.tx)
        self.s = tr.s
        self.length = tr.length
        self.start = float(tr.s[tr.start])

    def _open(self, cfg):
        self.start = 0.0
        x, y, z = (float(c) for c in cfg['start'])
        a = math.radians(float(cfg.get('heading', 0.0)))
        xs, ys, zs, hs = [x], [y], [z], [a]
        for seg in cfg['segments']:
            dz = float(seg.get('dz', 0.0))
            if 'straight' in seg:
                length, turn = float(seg['straight']), 0.0
            else:
                turn = math.radians(float(seg['arc']))
                length = abs(turn) * float(seg['radius'])
            n = max(1, int(round(length)))
            z0 = z
            for i in range(1, n + 1):
                f = i / n
                a += turn / n
                x += math.cos(a - turn / n / 2) * length / n
                y += math.sin(a - turn / n / 2) * length / n
                z = z0 + dz * (3 * f * f - 2 * f ** 3)         # subida suave (sin escalon al empezar/acabar)
                xs.append(x); ys.append(y); zs.append(z); hs.append(a)
        self.x, self.y, self.z, self.h = (np.array(v) for v in (xs, ys, zs, hs))
        seg = np.hypot(np.diff(self.x), np.diff(self.y))
        self.s = np.concatenate([[0.0], np.cumsum(seg)])
        self.length = float(self.s[-1])

    def at(self, s):
        """(x, y, z, rumbo) a la distancia s (en un circuito cerrado, s da la vuelta)."""
        if self.closed:
            s %= self.length
            S = np.append(self.s, self.length)
            h = np.append(self.hu, self.hu[-1] + wrap(self.hu[0] - self.hu[-1]))
            return (float(np.interp(s, S, np.append(self.x, self.x[0]))),
                    float(np.interp(s, S, np.append(self.y, self.y[0]))),
                    float(np.interp(s, S, np.append(self.z, self.z[0]))), float(np.interp(s, S, h)))
        s = min(max(s, 0.0), self.length)
        return (float(np.interp(s, self.s, self.x)), float(np.interp(s, self.s, self.y)),
                float(np.interp(s, self.s, self.z)), float(np.interp(s, self.s, self.hu)))


class PlatformConverter:
    def __init__(self, info, plan_path, wow_data):
        if not wow_data:
            raise ValueError('mapa %s: las pistas de plataformas necesitan --wow-data (modelos)' % info['directory'])
        with open(plan_path, encoding='utf-8') as f:
            plan = dict(PLAN_DEFAULTS)
            plan.update(json.load(f))
        self.info, self.plan, self.wow_data = info, plan, wow_data
        self.unknown = set()
        self.n = int(plan['adts'])
        self.tiles = [(32 + i, 32 + j) for j in range(self.n) for i in range(self.n)]
        self.X0, self.Y0 = wow.tile_origin(*self.tiles[0])
        self.half = self.n * wow.TILE / 2.0
        self.rng = np.random.default_rng(plan['seed'])

        self.model_names, self.model_index, self.model_box, self.models = [], {}, [], []
        self.pieces = {}
        for key, cfg in plan['pieces'].items():
            piece = dict(PIECE_DEFAULTS)
            piece.update(cfg)
            data = vmaps.read_client_file(wow_data, piece['model'])
            try:
                piece.update(piece_geometry(data))
            except ValueError as e:
                raise ValueError('pieza %s (%s): %s' % (key, piece['model'], e))
            self.pieces[key] = piece
        self.paths = [(cfg, Path(cfg)) for cfg in plan['paths']]
        self.piece_count = {}
        for cfg, path in self.paths:
            self._place_path(cfg, path)
        self.track_models = len(self.models)
        for deco in plan['decor']:
            self._decor(deco)

    # --- Coordenadas y modelos -----------------------------------------------------------------------------------

    def to_wow(self, x, y):
        return self.X0 - self.half + y, self.Y0 - self.half - x

    def _model(self, path):
        if path not in self.model_index:
            box = m2_box(vmaps.read_client_file(self.wow_data, path))
            self.model_index[path] = len(self.model_names)
            self.model_names.append(path)
            self.model_box.append(box)
        return self.model_index[path]

    def _add(self, path, x, y, z, angle, scale, pitch=0.0, roll=0.0):
        """Modelo con su origen en (x, y, z) del plano; angle = rumbo de su +X en el plano (0 = este)."""
        m = self._model(path)
        X, Y = self.to_wow(x, y)
        bx0, by0, bz0, bx1, by1, bz1 = self.model_box[m]
        radius = max(abs(bx0), abs(bx1), abs(by0), abs(by1), abs(bz0), abs(bz1)) * math.sqrt(2) * scale + 1.0
        # Rumbo WoW del +X: plano este = -Y de WoW, plano norte = +X de WoW -> angulo WoW = rumbo - 90 grados
        self.models.append({'model': m, 'x': float(X), 'y': float(Y), 'z': float(z),
                            'angle': float(angle - math.pi / 2), 'scale': float(scale), 'radius': radius,
                            'rot_x': -math.degrees(pitch), 'rot_z': math.degrees(roll)})

    # --- Pista ---------------------------------------------------------------------------------------------------

    def _place_path(self, cfg, path):
        piece = self.pieces[cfg['piece']]
        scale = float(piece['scale'])
        if piece['kind'] == 'disc':
            size = min(piece['length'], piece['width']) * scale
            step0 = size * (1.0 - float(piece.get('overlap', 0.55)))
        else:
            size = piece['length'] * scale
            step0 = size * (1.0 - float(piece['overlap']))
        max_turn = math.radians(float(piece['maxTurn']))
        half = size / 2.0
        s, i = (0.0, 0) if path.closed else (half, 0)
        while True:
            if path.closed:
                last = s + step0 * 0.5 >= path.length
            else:
                last = s >= path.length - half
                s = min(s, path.length - half)
            x0, y0, z0, _ = path.at(s - half)
            x1, y1, z1, _ = path.at(s + half)
            x, y, z, _ = path.at(s)
            heading = math.atan2(y1 - y0, x1 - x0)          # cuerda: la pieza recta tapa mejor la curva
            pitch = math.atan2(z1 - z0, math.hypot(x1 - x0, y1 - y0))
            zz = z + (float(piece['zigzag']) if i % 2 else 0.0)
            # Origen tal que el centro de la cara superior (girada y escalada) quede en el punto de la pista
            R = rotation(heading, pitch, 0.0)
            offset = R @ (np.array([piece['cx'], piece['cy'], piece['top']]) * scale)
            self._add(piece['model'], x - offset[0], y - offset[1], zz - offset[2], heading, scale, pitch)
            i += 1
            if last:
                break
            # Siguiente paso: el normal, o mas corto si el rumbo cambia mas de maxTurn
            step = step0
            while step > 1.0:
                _, _, _, h0 = path.at(s)
                _, _, _, h1 = path.at(s + step)
                if abs(wrap(h1 - h0)) <= max_turn:
                    break
                step *= 0.8
            s += step
        self.piece_count[cfg['name']] = i

    def _decor(self, deco):
        rng = np.random.default_rng(int(deco.get('seed', self.plan['seed'])))
        pts = np.concatenate([np.stack([p.x, p.y], axis=1) for _, p in self.paths])
        lo_d, hi_d = deco.get('distance', [40.0, 400.0])
        lo_z, hi_z = deco.get('z', [-80.0, 60.0])
        lo_s, hi_s = deco.get('scale', [0.6, 1.6])
        zref = float(np.mean([p.z.mean() for _, p in self.paths]))
        placed, tries = 0, 0
        margin = 30.0
        while placed < int(deco['count']) and tries < int(deco['count']) * 200:
            tries += 1
            x, y = rng.uniform(-self.half + margin, self.half - margin, 2)
            d = np.hypot(pts[:, 0] - x, pts[:, 1] - y).min()
            if not lo_d <= d <= hi_d:
                continue
            model = deco['models'][int(rng.integers(len(deco['models'])))]
            self._add(model, x, y, zref + rng.uniform(lo_z, hi_z), rng.uniform(0, 2 * math.pi), rng.uniform(lo_s, hi_s),
                      math.radians(rng.uniform(-25, 25)), math.radians(rng.uniform(-25, 25)))
            placed += 1

    # --- ADT -----------------------------------------------------------------------------------------------------

    def tile_doodads(self, tx, ty):
        x0, y0 = wow.tile_origin(tx, ty)
        out = []
        for k, m in enumerate(self.models):
            r = m['radius']
            if x0 - wow.TILE - r <= m['x'] <= x0 + r and y0 - wow.TILE - r <= m['y'] <= y0 + r:
                out.append((k, m))
        return out

    def build_tile(self, tx, ty):
        tile = wow.TileData(tx, ty)
        tile.area_id = int(self.info['areaId'])
        gz = float(self.plan['groundZ'])
        tile.heights_outer = np.full((129, 129), gz)
        tile.heights_inner = np.full((128, 128), gz)
        tile.normals_outer = np.zeros((129, 129, 3)); tile.normals_outer[..., 2] = 1.0
        tile.normals_inner = np.zeros((128, 128, 3)); tile.normals_inner[..., 2] = 1.0
        tile.textures = [self.plan['texture']]
        for cr in range(16):
            for cc in range(16):
                tile.layers[(cr, cc)] = [(0, None)]
                tile.holes[(cr, cc)] = 0xFFFF              # sin terreno: solo el vacio y las piezas
        local = {}
        for k, m in self.tile_doodads(tx, ty):
            if m['model'] not in local:
                local[m['model']] = len(tile.models)
                tile.models.append(self.model_names[m['model']])
            tile.doodads.append(wow.Doodad(local[m['model']], k + 1, m['x'], m['y'], m['z'], m['angle'], m['scale'],
                                           m['radius'], m['rot_x'], m['rot_z']))
        return tile

    # --- Minimapa, vista previa y puntos -------------------------------------------------------------------------

    def _draw(self, img, Xtop, Yleft, px):
        """Piezas de pista (claras) y decoracion (tenue) como discos, vista cenital."""
        h, w = img.shape[:2]
        for k, m in enumerate(self.models):
            track = k < self.track_models
            i = (Xtop - m['x']) / px
            j = (Yleft - m['y']) / px
            r = max(1.0, (m['radius'] / math.sqrt(2) * (0.75 if track else 0.4)) / px)
            if i < -r or j < -r or i > h + r or j > w + r:
                continue
            i0, i1 = int(max(0, i - r)), int(min(h - 1, i + r))
            j0, j1 = int(max(0, j - r)), int(min(w - 1, j + r))
            if i1 < i0 or j1 < j0:
                continue
            ii, jj = np.mgrid[i0:i1 + 1, j0:j1 + 1]
            mask = (ii - i) ** 2 + (jj - j) ** 2 <= r * r
            img[i0:i1 + 1, j0:j1 + 1][mask] = (0.80, 0.82, 0.95) if track else (0.30, 0.22, 0.40)

    def minimap(self, tx, ty):
        x0, y0 = wow.tile_origin(tx, ty)
        img = np.zeros((256, 256, 3))
        img[:] = (0.02, 0.02, 0.07)
        self._draw(img, x0, y0, wow.TILE / 256)
        return img

    def preview(self, path, scale=1.0):
        from PIL import Image, ImageDraw
        size = int(self.n * wow.TILE / scale)
        img = np.zeros((size, size, 3))
        img[:] = (0.02, 0.02, 0.07)
        self._draw(img, self.X0, self.Y0, scale)
        im = Image.fromarray((img * 255).astype(np.uint8))
        dr = ImageDraw.Draw(im)
        for name, X, Y, Z, o in self.points():
            cx, cy = (self.Y0 - Y) / scale, (self.X0 - X) / scale
            dr.ellipse([cx - 5, cy - 5, cx + 5, cy + 5], outline=(0, 0, 0), fill=(255, 80, 80))
            dr.text((cx + 8, cy - 6), name, fill=(255, 255, 255))
        im.save(path)

    def race(self):
        """La pista de la carrera: la primera cerrada (o None)."""
        return next(((cfg, p) for cfg, p in self.paths if p.closed), None)

    def markers(self):
        """[(nombre, x, y, z, rumbo, s desde la meta)] de la carrera: meta, parrilla y puntos de control."""
        race = self.race()
        if not race:
            return []
        cfg, path = race
        piece = self.pieces[cfg['piece']]
        width = piece['width'] * float(piece['scale'])
        s0 = path.start
        x, y, z, h = path.at(s0)
        out = [('Meta', x, y, z, h, 0.0)]
        # Parrilla: 2 columnas, filas cada 9 yardas detras de la meta, escalonadas (igual que trackgen)
        for slot in range(8):
            row, col = slot // 2, slot % 2
            back = 10.0 + row * 9.0 + col * 4.5
            px, py, pz, ph = path.at(s0 - back)
            lat = width * 0.22 * (1 if col == 0 else -1)
            out.append(('Parrilla %d' % (slot + 1), px - math.sin(ph) * lat, py + math.cos(ph) * lat, pz, ph, -back))
        n = int(cfg.get('checkpoints', 8))
        for c in range(1, n):
            s = path.length * c / n
            px, py, pz, ph = path.at(s0 + s)
            out.append(('Control %d' % c, px, py, pz, ph, s))
        return out

    def path_samples(self, every=2.0):
        """Linea central de la carrera desde la meta: [(s, X, Y, Z, media anchura)] (Z = superficie)."""
        race = self.race()
        if not race:
            return []
        cfg, path = race
        piece = self.pieces[cfg['piece']]
        half = piece['width'] * float(piece['scale']) / 2.0
        out = []
        s = 0.0
        while s < path.length:
            x, y, z, _ = path.at(path.start + s)
            X, Y = self.to_wow(x, y)
            out.append((round(s, 2), round(X, 2), round(Y, 2), round(z, 2), round(half, 2)))
            s += every
        return out

    def points(self):
        out = []
        for name, x, y, z, h, _ in self.markers():
            X, Y = self.to_wow(x, y)
            out.append((name, X, Y, z + 1.0, (h - math.pi / 2) % (2 * math.pi)))
        for cfg, path in self.paths:
            if path.closed:
                continue
            x, y, z, h = path.at(6.0)
            X, Y = self.to_wow(x, y)
            # Orientacion WoW: 0 = norte (+X), pi/2 = oeste (+Y); h = rumbo en el plano (0 = este)
            out.append(('Inicio %s' % cfg['name'], X, Y, z + 1.0, (h - math.pi / 2) % (2 * math.pi)))
        return out

    def summary(self):
        lines = []
        for cfg, path in self.paths:
            grade = np.abs(np.diff(path.z)) / np.maximum(np.diff(path.s), 1e-6)
            if path.closed:
                turn = np.abs([wrap(d) for d in np.diff(path.h)]) / np.maximum(np.diff(path.s), 1e-6)
                lines.append('  %s: circuito cerrado, radio de curva minimo %.0f yardas'
                             % (cfg['name'], 1.0 / max(float(np.max(turn)), 1e-6)))
            piece = self.pieces[cfg['piece']]
            lines.append('  %s: %.0f yardas, z %.0f..%.0f, pendiente max %.1f %%, %d piezas %s (escala %.2f, %.0f x %.0f)'
                         % (cfg['name'], path.length, path.z.min(), path.z.max(), grade.max() * 100,
                            self.piece_count[cfg['name']], piece['model'].split('\\')[-1], piece['scale'],
                            piece['length'] * piece['scale'], piece['width'] * piece['scale']))
        # Cruces: tramos alejados en la pista que pasan uno sobre otro (altura libre entre superficies)
        rows = []
        for k, (cfg, path) in enumerate(self.paths):
            for j in range(0, len(path.s), 3):
                rows.append((k, path.s[j], path.x[j], path.y[j], path.z[j], path.length if path.closed else 0.0))
        A = np.array(rows)
        worst = None
        for k, s_, x, y, z, loop in rows:
            ds = np.abs(A[:, 1] - s_)
            if loop:
                ds = np.minimum(ds, loop - ds)
            other = (np.hypot(A[:, 2] - x, A[:, 3] - y) < 26.0) & ((A[:, 0] != k) | (ds > 80.0))
            if other.any():
                gap = float(np.abs(A[other, 4] - z).min())
                if worst is None or gap < worst[0]:
                    worst = (gap, x, y)
        if worst:
            lines.append('  Cruces: altura libre minima entre superficies %.1f yardas (en %.0f, %.0f)%s'
                         % (worst[0], worst[1], worst[2], '  AVISO: menos de 18' if worst[0] < 18 else ''))
        lines.append('  Decoracion: %d modelos (%d distintos en total)'
                     % (len(self.models) - self.track_models, len(self.model_names)))
        return lines
