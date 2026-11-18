"""Recorridos de parkour sin Warcraft 3: plano JSON ("type": "parkour") -> mapa sin terreno con una ruta de saltos
hecha de modelos M2 (muebles, cajas, columnas...) colocados como decoracion del ADT (colision en el cliente y en los
vmaps del servidor), dividida en secciones con un punto de control al empezar cada una.

Como platformgen: los ADT existen pero todos sus trozos son agujeros (sin suelo); el cielo lo pone una luz del mapa
(Light.dbc, SQL del modulo). Caer no mata: el juego (EventWowGameParkour.cpp) devuelve al ultimo punto de control
cuando el jugador baja de la "altura de caida" de su seccion.

Saltos (fisica del cliente 3.3.5): impulso vertical `velocity` (7,9555 yd/s), gravedad `gravity` (19,2911 yd/s2,
Movement::gravity del core) y carrera a `speed` (7 yd/s). Alcance horizontal con desnivel dz:
    t = (v + sqrt(v^2 - 2 g dz)) / g,   alcance = speed * t      (dz > v^2 / 2g = 1,64 yd: imposible)
El hueco de cada salto (borde a borde de las caras pisables) se elige como fraccion `gap` del alcance: 0,4 = facil,
0,8 = dificil, > 0,92 = el resumen avisa (casi imposible).

Plano:
  seed, adts, bounds (media anchura util en yardas), jump {speed, velocity, gravity}, groundZ, texture
  start: {at: [x, y, z], heading: grados (0 = este, 90 = norte), model, scale}     z = altura de la cara pisable
  sections: [{name, rest: {model, scale} (plataforma del punto de control; la 1a seccion empieza en start),
              jumps, gap: [min, max], dz: [min, max], turn: grados maximos por salto, seed?,
              pieces: {clave: {model, scale, weight, align: "along" | "across" | "random" | "side"}},
              segments?: [tramo, ...]}]
  Tramos (segments; sin ellos la seccion es un solo "run" de `jumps` saltos). Cada tramo puede cambiar gap, dz,
  turn y pieces; si no, usa los de su tipo (TRAMOS) y despues los de la seccion:
    {"type": "run", "jumps": n}       camino normal
    {"type": "climb", "jumps": n}     subida: escalon a escalon casi al maximo del salto, huecos cortos, casi recta
                                      (p. ej. sillas con align "side": el respaldo queda a un lado)
    {"type": "descent", "jumps": n}   bajada: caidas de 2 a 4 yardas
    {"type": "zigzag", "jumps": n}    giros fuertes alternos (turn = [min, max] grados)
    {"type": "deadend", "jumps": [min, max]}   callejon sin salida: desde la pieza actual sale un ramal que no
                                      lleva a ninguna parte (se genera al final, lejos del resto de la ruta)
  finish: {model, scale}
  decor: [{models: [...], count, scale: [min, max], distance: [min, max] (borde a borde), z: [min, max] (respecto a
           la ruta), seed, tilt, wmo: true (WMO: sin escala, solo cliente: los vmaps no los incluyen)}
          | {models, every: N piezas de la ruta, z: [min, max], scale, seed}]          (efectos a lo largo de la ruta)

  templates: {nombre: pieza}   una pieza {"use": nombre, ...} = la plantilla con lo demas encima

Opciones de una pieza (start/rest/finish/pieces):
  walk: {cx, cy, top, length, width}   cara pisable a mano (escala 1) en vez de medirla (islas: cara con relieve)
  surface: true                        cara irregular: la altura del borde de salida se mide en la colision
                                       (el salto siguiente parte de ahi, no del centro)
  dress: [{models, count, ring: [min, max] (fraccion de la media cara), scale: [min, max], avoid: grados, sink}]
         adornos encima (arboles, matas, haces de luz...), sobre la superficie real y lejos de la linea de
         entrada/salida (avoid); ring [0, 0] = en el centro

align "side": la pieza se gira para que lo que sobresale de su cara (el respaldo de una silla) quede a un lado
del camino, ni delante ni detras.

Pieza: se mide del M2 la cara pisable = el nivel plano MAS ALTO con al menos el 40 % del area del mayor (asi una mesa
da su tablero y no las patas o el suelo de la caja) y su rectangulo. Se coloca para que el centro de esa cara quede en
el punto de la ruta. Lo que sobresale por encima de la cara (respaldos...) se avisa en el resumen.

Salida para el servidor: <DataDir>/maps/<id>_parkour.txt (lineas "checkpoint X Y Z O radio caida nombre" y
"finish X Y Z O radio"; ver EventWowGameParkour.cpp).

Coordenadas del plano: yardas, x = este, y = norte, origen en el centro del mapa (n x n ADT desde el 32_32).
Expone la interfaz de mapgen.Converter (tiles, build_tile, tile_doodads, minimap, points, models, model_names).
"""
import json
import math
import struct

import numpy as np

import vmaps
import wowfiles as wow
from catalog import walkable_levels
from platformgen import PlatformConverter, rotation
from trackgen import m2_box

PLAN_DEFAULTS = {
    'seed': 1,
    'adts': 2,
    'bounds': 470.0,
    'groundZ': -900.0,
    'texture': 'Tileset\\Expansion02\\Nexus\\Nexus_Ground_01.blp',
    'jump': {},
    'decor': [],
}

JUMP_DEFAULTS = {'speed': 7.0, 'velocity': 7.9555, 'gravity': 19.2911}

SECTION_DEFAULTS = {
    'jumps': 30,
    'gap': [0.4, 0.6],
    'dz': [-0.3, 0.8],
    'turn': 35.0,
}

FALL_MARGIN = 8.0       # la altura de caida de una seccion: su cara mas baja menos esto
CLEARANCE = 6.0         # separacion minima (2D, borde a borde) entre piezas cercanas en la ruta (no consecutivas)...
CLEARANCE_FAR = 20.0    # ...y entre tramos lejanos (mas de NEAR piezas): que no se pueda saltar de uno a otro (atajos)
NEAR = 8
CLEARANCE_DZ = 30.0     # piezas con mas diferencia de altura que esto pueden cruzarse por encima
EDGE_MARGIN = 60.0      # cerca del borde (bounds) la ruta gira hacia el centro
EDGE_DROP = 4.0         # cara irregular (islas): el borde es donde el suelo cae mas que esto (yardas) bajo el centro
SKIP_LAST = 3           # _fits no compara con las ultimas piezas (en subidas estan muy juntas)

# Valores por tipo de tramo (encima de los de la seccion; el tramo puede cambiarlos)
TRAMOS = {
    'run': {},
    'climb': {'gap': [0.15, 0.35], 'dz': [1.05, 1.35], 'turn': 10.0},
    'descent': {'gap': [0.25, 0.5], 'dz': [-4.0, -2.0], 'turn': 20.0},
    'zigzag': {'turn': [45.0, 70.0]},
    'deadend': {'jumps': [4, 7]},
}


def walk_geometry(data):
    """Cara pisable del M2 (escala 1): centro (cx, cy), altura, largo (X), ancho (Y) y lo que sobresale encima."""
    v, t = vmaps.m2_collision(data)
    levels = walkable_levels(v, t)
    if not levels:
        raise ValueError('el modelo no tiene colision con caras planas (se atravesaria)')
    amax = max(lv[1] for lv in levels)
    z, _, x0, y0, x1, y1 = next(lv for lv in levels if lv[1] >= 0.4 * amax)
    p = v[t].reshape(-1, 3)
    inside = (p[:, 0] > x0 - 0.1) & (p[:, 0] < x1 + 0.1) & (p[:, 1] > y0 - 0.1) & (p[:, 1] < y1 + 0.1)
    g = {'cx': (x0 + x1) / 2, 'cy': (y0 + y1) / 2, 'top': z, 'length': x1 - x0, 'width': y1 - y0,
         'above': float(p[inside, 2].max() - z), 'below': float(z - p[:, 2].min())}
    # Lo que sobresale por encima (respaldo...): su direccion desde el centro de la cara, en el modelo
    m = 0.3 * max(g['length'], g['width'])
    high = (v[:, 2] > z + 0.3) & (v[:, 0] > x0 - m) & (v[:, 0] < x1 + m) & (v[:, 1] > y0 - m) & (v[:, 1] < y1 + m)
    if high.any():
        bx, by = v[high, 0].mean() - g['cx'], v[high, 1].mean() - g['cy']
        if math.hypot(bx, by) > 0.1 * max(g['length'], g['width']):
            g['back'] = math.atan2(by, bx)
    return g


class Jump:
    def __init__(self, cfg):
        c = dict(JUMP_DEFAULTS)
        c.update(cfg)
        self.speed, self.v, self.g = float(c['speed']), float(c['velocity']), float(c['gravity'])
        self.max_dz = self.v * self.v / (2 * self.g)

    def reach(self, dz):
        """Alcance horizontal (yardas) para caer dz mas arriba (negativo = mas abajo); None si no se llega."""
        disc = self.v * self.v - 2 * self.g * dz
        if disc < 0:
            return None
        return self.speed * (self.v + math.sqrt(disc)) / self.g


def extent(item, ux, uy):
    """Media extension de la cara de una pieza en la direccion (ux, uy)."""
    ca, sa = math.cos(item['angle']), math.sin(item['angle'])
    return (abs(ux * ca + uy * sa) * item['length'] + abs(-ux * sa + uy * ca) * item['width']) / 2


class ParkourConverter(PlatformConverter):
    def __init__(self, info, plan_path, wow_data):     # noqa: C901 - generador de un paso
        if not wow_data:
            raise ValueError('mapa %s: el parkour necesita --wow-data (modelos)' % info['directory'])
        with open(plan_path, encoding='utf-8') as f:
            plan = dict(PLAN_DEFAULTS)
            plan.update(json.load(f))
        templates = plan.get('templates', {})

        def resolve(piece):
            """{"use": "plantilla", ...}: la plantilla de plan.templates con lo demas encima."""
            if 'use' not in piece:
                return piece
            out = dict(templates[piece['use']])
            out.update({k: v for k, v in piece.items() if k != 'use'})
            return out

        plan['start'] = resolve(plan['start'])
        plan['finish'] = resolve(plan['finish'])
        for sec in plan['sections']:
            if 'rest' in sec:
                sec['rest'] = resolve(sec['rest'])
            sec['pieces'] = {k: resolve(v) for k, v in sec['pieces'].items()}
        self.info, self.plan, self.wow_data = info, plan, wow_data
        self.unknown = set()
        self.n = int(plan['adts'])
        self.tiles = [(32 + i, 32 + j) for j in range(self.n) for i in range(self.n)]
        self.X0, self.Y0 = wow.tile_origin(*self.tiles[0])
        self.half = self.n * wow.TILE / 2.0
        self.bounds = min(float(plan['bounds']), self.half - 30.0)
        self.jump = Jump(plan['jump'])
        self.model_names, self.model_index, self.model_box, self.models = [], {}, [], []
        self.geometry = {}
        self.tris = {}
        self.wmo_boxes = {}
        self.wmos = []          # decoracion WMO: dict(name, x, y, z, angle, radius) en coordenadas WoW
        self.items = []         # caras pisables de la ruta en orden: dict(x, y, z, angle, length, width, ...)
        self.sections = []      # [(nombre, indice del item del punto de control, altura de caida)]
        self.forks = []         # callejones pendientes: (indice de la pieza de la que salen, tramo, seccion)
        self.branches = []      # callejones sin salida: [(indice de la pieza de la que salen, [items])]
        self.warnings = []

        start = plan['start']
        x, y, z = (float(c) for c in start['at'])
        heading = math.radians(float(start.get('heading', 0.0)))
        self._place(start, x, y, z, heading, 'start', 0)
        count = len(plan['sections'])
        for k, sec in enumerate(plan['sections']):
            cfg = dict(SECTION_DEFAULTS)
            cfg.update(sec)
            # Plataforma que cierra la seccion (punto de control de la siguiente o meta): se coloca dentro de
            # _section para que, si no cabe, se deshagan saltos y se pruebe otro camino
            if k + 1 < count:
                closing = (plan['sections'][k + 1]['rest'], 'rest', k + 1, 0.0)
            else:
                closing = (plan['finish'], 'finish', k, 0.5)
            first = len(self.items) - 1
            heading = self._section(cfg, k, heading, closing)
            tops = [it['z'] for it in self.items[first:-1]]
            self.sections.append((cfg['name'], first, min(tops) - FALL_MARGIN))
        for fork, spec, k in self.forks:
            self._branch(fork, spec, k)
        self.track_models = len(self.models)
        for idx, it in enumerate(self.items):
            for dress in it['piece'].get('dress', []):
                self._dress(idx, dress)
        for deco in plan['decor']:
            self._decor(deco)

    # --- Piezas --------------------------------------------------------------------------------------------------

    def _geometry(self, model, walk=None):
        if walk:
            g = {'cx': 0.0, 'cy': 0.0, 'above': 0.0, 'below': 0.0}
            g.update({k: float(v) for k, v in walk.items()})
            return g
        if model not in self.geometry:
            data = vmaps.read_client_file(self.wow_data, model)
            try:
                self.geometry[model] = walk_geometry(data)
            except ValueError as e:
                raise ValueError('%s: %s' % (model, e))
        return self.geometry[model]

    def _model(self, path):
        if path not in self.model_index:
            box = m2_box(vmaps.read_client_file(self.wow_data, path))
            self.model_index[path] = len(self.model_names)
            self.model_names.append(path)
            self.model_box.append(box)
        return self.model_index[path]

    def _item(self, piece, x, y, z, angle, kind, section):
        g = self._geometry(piece['model'], piece.get('walk'))
        s = float(piece.get('scale', 1.0))
        return {'model': piece['model'], 'scale': s, 'x': x, 'y': y, 'z': z, 'angle': angle, 'kind': kind,
                'section': section, 'length': g['length'] * s, 'width': g['width'] * s, 'above': g['above'] * s,
                'piece': piece}

    def _place(self, piece, x, y, z, angle, kind, section, target=None):
        """Coloca la pieza con el centro de su cara pisable en (x, y, z), su +X hacia angle (radianes)."""
        it = self._item(piece, x, y, z, angle, kind, section)
        g = self._geometry(piece['model'], piece.get('walk'))
        s = it['scale']
        offset = rotation(angle, 0.0, 0.0) @ (np.array([g['cx'], g['cy'], g['top']]) * s)
        it['origin'] = (x - offset[0], y - offset[1], z - offset[2])
        self._add(piece['model'], it['origin'][0], it['origin'][1], it['origin'][2], angle, s)
        (self.items if target is None else target).append(it)
        return it

    def _triangles(self, model):
        if model not in self.tris:
            v, t = vmaps.m2_collision(vmaps.read_client_file(self.wow_data, model))
            self.tris[model] = v[t]
        return self.tris[model]

    def surface_z(self, it, x, y):
        """Altura de la colision de la pieza en (x, y) del plano (rayo vertical; la cara mas alta), o None."""
        ox, oy, oz = it['origin']
        ca, sa = math.cos(it['angle']), math.sin(it['angle'])
        dx, dy = (x - ox) / it['scale'], (y - oy) / it['scale']
        z = self._surface_local(it['model'], dx * ca + dy * sa, -dx * sa + dy * ca)
        return None if z is None else oz + z * it['scale']

    def _surface_local(self, model, lx, ly):
        """Altura (escala 1, coordenadas del modelo) de la cara mas alta de la colision en (lx, ly), o None."""
        p = self._triangles(model)
        a, b, c = p[:, 0], p[:, 1], p[:, 2]
        v0, v1 = b - a, c - a
        den = v0[:, 0] * v1[:, 1] - v1[:, 0] * v0[:, 1]
        ok = np.abs(den) > 1e-9
        den = np.where(ok, den, 1.0)
        wx, wy = lx - a[:, 0], ly - a[:, 1]
        u = (wx * v1[:, 1] - v1[:, 0] * wy) / den
        w = (v0[:, 0] * wy - wx * v0[:, 1]) / den
        inside = ok & (u >= -1e-6) & (w >= -1e-6) & (u + w <= 1 + 1e-6)
        if not inside.any():
            return None
        z = a[:, 2] + u * v0[:, 2] + w * v1[:, 2]
        return float(z[inside].max())

    def _edge(self, it, ux, uy):
        """(distancia del centro de la cara al borde en la direccion (ux, uy), altura en el borde).

        Cara rectangular: su media extension y su altura. Cara irregular (surface: islas): se avanza por la
        colision desde el centro hasta que se acaba o cae mas de EDGE_DROP (precipicio); la altura es la de ese
        punto. Asi el hueco del salto se mide desde donde de verdad termina el suelo."""
        if not it['piece'].get('surface'):
            return extent(it, ux, uy), it['z']
        g = self._geometry(it['model'], it['piece'].get('walk'))
        ca, sa = math.cos(it['angle']), math.sin(it['angle'])
        lx, ly = ux * ca + uy * sa, -ux * sa + uy * ca            # direccion en coordenadas del modelo
        s = it['scale']
        top = self._surface_local(it['model'], g['cx'], g['cy'])
        top = g['top'] if top is None else top
        step = 0.5 / s                                             # media yarda
        last, last_z = 0.0, top
        r = step
        while r < 2000.0:
            z = self._surface_local(it['model'], g['cx'] + lx * r, g['cy'] + ly * r)
            if z is None or top - z > EDGE_DROP / s:
                break
            last, last_z = r, z
            r += step
        return last * s, it['z'] - (top - last_z) * s

    def _exit_z(self, prev, ux, uy):
        """Altura desde la que se salta (la del borde de salida)."""
        return min(prev['z'], self._edge(prev, ux, uy)[1])

    def _fits(self, it):
        """Lejos del borde y de las piezas anteriores (salvo las 2 ultimas) que esten a una altura parecida: las
        cercanas en la ruta a CLEARANCE, las lejanas a CLEARANCE_FAR (sin atajos entre tramos)."""
        r = math.hypot(it['length'], it['width']) / 2
        if abs(it['x']) + r > self.bounds or abs(it['y']) + r > self.bounds:
            return False
        count = len(self.items)
        for i, other in enumerate(self.items[:-SKIP_LAST]):
            # Las islas (cara a mano) son altas y llevan haz de luz: nada por encima ni por debajo de ellas
            limit = CLEARANCE_DZ * (3 if 'walk' in other['piece'] or 'walk' in it['piece'] else 1)
            if abs(other['z'] - it['z']) > limit:
                continue
            ro = math.hypot(other['length'], other['width']) / 2
            clearance = CLEARANCE if count - i <= NEAR else CLEARANCE_FAR
            if math.hypot(other['x'] - it['x'], other['y'] - it['y']) < r + ro + clearance:
                return False
        return True

    def _candidate(self, piece, heading, gap, dz, kind, section, prev=None):
        """Pieza a continuacion de prev (la ultima): hueco = gap * alcance(dz) borde a borde en la direccion heading."""
        prev = self.items[-1] if prev is None else prev
        ux, uy = math.cos(heading), math.sin(heading)
        align = piece.get('align', 'along')
        if align == 'random':
            align = 'along' if self.rng.random() < 0.5 else 'across'
        back = self._geometry(piece['model'], piece.get('walk')).get('back')
        if align == 'side' and back is not None:
            # respaldo hacia un lado del camino: angulo + back = rumbo +- 90 grados
            angle = heading + (math.pi / 2 if self.rng.random() < 0.5 else -math.pi / 2) - back
        else:
            angle = heading if align in ('along', 'side') else heading + math.pi / 2
        base = self._exit_z(prev, ux, uy)
        it = self._item(piece, 0.0, 0.0, base + dz, angle, kind, section)
        it['from_z'] = base
        dist = self._edge(prev, ux, uy)[0] + gap * self.jump.reach(dz) + self._edge(it, -ux, -uy)[0]
        it['x'], it['y'] = prev['x'] + ux * dist, prev['y'] + uy * dist
        return it

    def _steer(self, heading, max_turn, prev=None):
        """Giros a probar: al azar dentro de max_turn, con sesgo hacia el centro cerca del borde; luego mas abiertos."""
        prev = self.items[-1] if prev is None else prev
        near = max(abs(prev['x']), abs(prev['y'])) > self.bounds - EDGE_MARGIN
        to_center = math.atan2(-prev['y'], -prev['x'])
        turns = []
        for i in range(40):
            limit = max_turn * (1.0 + i / 10.0)
            t = self.rng.uniform(-limit, limit)
            if near:
                diff = (to_center - heading + math.pi) % (2 * math.pi) - math.pi
                t = max(-limit, min(limit, diff)) * 0.7 + t * 0.3
            turns.append(t)
        return turns

    def _next(self, piece, heading, kind, section, gap, dz):
        """Plataforma (punto de control / meta) a continuacion, con un salto facil."""
        for t in [0.0] + self._steer(heading, math.radians(30)):
            h = heading + t
            it = self._candidate(piece, h, gap, dz, kind, section)
            if self._fits(it):
                self._place(piece, it['x'], it['y'], it['z'], it['angle'], kind, section)
                self.items[-1]['from_z'] = it['from_z']
                return h
        return None

    def _spec(self, cfg, seg):
        """Parametros de un tramo: los de la seccion, encima los de su tipo y encima los del propio tramo."""
        kind = seg.get('type', 'run')
        if kind not in TRAMOS:
            raise ValueError('seccion "%s": tramo desconocido "%s"' % (cfg['name'], kind))
        spec = {key: cfg[key] for key in ('gap', 'dz', 'turn', 'pieces')}
        spec.update(TRAMOS[kind])
        spec.update(seg)
        spec['type'] = kind
        keys = list(spec['pieces'])
        weights = np.array([float(spec['pieces'][key].get('weight', 1.0)) for key in keys])
        spec['_keys'], spec['_weights'] = keys, weights / weights.sum()
        return spec

    def _pick(self, spec):
        """Pieza, desnivel y hueco al azar segun el tramo."""
        piece = spec['pieces'][spec['_keys'][int(self.rng.choice(len(spec['_keys']), p=spec['_weights']))]]
        dz = min(float(self.rng.uniform(*spec['dz'])), self.jump.max_dz * 0.85)
        gap = float(self.rng.uniform(*spec['gap']))
        return piece, dz, gap

    def _turns(self, spec, heading, index, prev=None):
        """Giros a probar para el salto `index` del tramo."""
        if spec['type'] == 'zigzag':
            lo, hi = spec['turn']
            sign = 1.0 if index % 2 == 0 else -1.0
            first = [sign * math.radians(self.rng.uniform(lo, hi)) for _ in range(12)]
            return first + self._steer(heading, math.radians(hi), prev)
        return self._steer(heading, math.radians(float(spec['turn'])), prev)

    def _section(self, cfg, k, heading, closing):
        self.rng = np.random.default_rng(int(cfg.get('seed', int(self.plan['seed']) * 100 + k)))
        # Un salto = (tramo, indice dentro del tramo); los callejones se apuntan en el salto en que salen
        plan = []
        forks = []
        for seg in cfg.get('segments') or [{'type': 'run', 'jumps': cfg['jumps']}]:
            spec = self._spec(cfg, seg)
            if spec['type'] == 'deadend':
                forks.append((len(plan), spec))
                continue
            plan.extend((spec, i) for i in range(int(spec['jumps'])))
        jumps = len(plan)
        first = len(self.items) - 1
        headings = []           # rumbo antes de cada salto colocado (para deshacer)
        backtracks = 0
        while True:
            if len(headings) == jumps:
                piece, kind, section, dz = closing
                h = self._next(piece, heading, kind, section, gap=0.45, dz=dz)
                if h is not None:
                    self.forks.extend((first + n, spec, k) for n, spec in forks)
                    return h
            placed = False
            spec, index = plan[len(headings)] if len(headings) < jumps else (None, 0)
            for t in self._turns(spec, heading, index) if spec else []:
                piece, dz, gap = self._pick(spec)
                it = self._candidate(piece, heading + t, gap, dz, 'jump', k)
                if self._fits(it):
                    self._place(piece, it['x'], it['y'], it['z'], it['angle'], 'jump', k)
                    self.items[-1]['from_z'] = it['from_z']
                    headings.append(heading)
                    heading += t
                    placed = True
                    break
            if placed:
                continue
            # Callejon sin salida: se deshacen los ultimos saltos (mas cuantas mas veces pase) y se prueba otro camino
            backtracks += 1
            if backtracks > 300 or not headings:
                raise ValueError('seccion %d "%s": la ruta se encierra en el salto %d (cambia seed, turn o bounds)'
                                 % (k + 1, cfg['name'], len(headings) + 1))
            for _ in range(min(len(headings), 3 + backtracks // 25)):
                heading = headings.pop()
                self.items.pop()
                self.models.pop()

    # --- Callejones sin salida -----------------------------------------------------------------------------------

    def _fits_branch(self, it, fork, own, fall):
        """Como _fits para un ramal: lejos del borde, de la ruta (salvo junto a la pieza de la que sale), de los
        otros ramales y de su propio camino; y por encima de la altura de caida de la seccion."""
        if it['z'] < fall + 4.0:
            return False
        r = math.hypot(it['length'], it['width']) / 2
        if abs(it['x']) + r > self.bounds or abs(it['y']) + r > self.bounds:
            return False
        # Junto a la bifurcacion (la pieza anterior y la siguiente de la ruta) basta con no tocarse; mas alla, como
        # la ruta: a CLEARANCE las cercanas y a CLEARANCE_FAR las lejanas (que el callejon no sea un atajo)
        others = [(other, 1.0 if abs(i - fork) <= 2 else CLEARANCE if abs(i - fork) <= NEAR else CLEARANCE_FAR)
                  for i, other in enumerate(self.items) if i != fork]
        others += [(other, CLEARANCE_FAR) for _, items in self.branches for other in items]
        others += [(other, CLEARANCE) for other in own[:-SKIP_LAST]]
        for other, clearance in others:
            limit = CLEARANCE_DZ * (3 if 'walk' in other['piece'] else 1)
            if abs(other['z'] - it['z']) > limit:
                continue
            ro = math.hypot(other['length'], other['width']) / 2
            if math.hypot(other['x'] - it['x'], other['y'] - it['y']) < r + ro + clearance:
                return False
        return True

    def _branch(self, fork, spec, k):
        """Ramal que sale de la pieza `fork` hacia un lado y se acaba (callejon sin salida)."""
        self.rng = np.random.default_rng(int(self.plan['seed']) * 7919 + fork)
        lo, hi = (spec['jumps'] if isinstance(spec['jumps'], list) else [spec['jumps'], spec['jumps']])
        want = int(self.rng.integers(int(lo), int(hi) + 1))
        fall = self.sections[k][2]
        out = self._heading_out(fork)
        best = []
        for attempt in range(24):
            side = 1.0 if attempt % 2 == 0 else -1.0
            heading = out + side * math.radians(self.rng.uniform(55.0, 115.0))
            own = []
            prev = self.items[fork]
            for index in range(want):
                for t in ([0.0] if index == 0 else []) + self._turns(spec, heading, index, prev):
                    piece, dz, gap = self._pick(spec)
                    it = self._candidate(piece, heading + t, gap, dz, 'deadend', k, prev)
                    if self._fits_branch(it, fork, own, fall):
                        self._place(piece, it['x'], it['y'], it['z'], it['angle'], 'deadend', k, target=own)
                        own[-1]['from_z'] = it['from_z']
                        heading += t
                        prev = own[-1]
                        break
                else:
                    break
            if len(own) == want or len(own) > len(best):
                if best:
                    self._drop_models(len(best), keep_last=len(own))
                best = own
            else:
                self._drop_models(len(own))
            if len(best) == want:
                break
        if len(best) < 2:
            self._drop_models(len(best))
            self.warnings.append('seccion %d: no cabe el callejon de la pieza %d' % (k + 1, fork))
            return
        self.branches.append((fork, best))

    def _drop_models(self, count, keep_last=0):
        """Quita `count` modelos colocados justo antes de los ultimos `keep_last`."""
        if count <= 0:
            return
        end = len(self.models) - keep_last
        del self.models[end - count:end]

    # --- Decoracion ----------------------------------------------------------------------------------------------

    def _dress(self, idx, dress):
        """Adornos encima de una plataforma (isla): sobre su superficie real, lejos de la entrada y la salida."""
        it = self.items[idx]
        rng = np.random.default_rng(int(self.plan['seed']) * 1000 + idx * 7 + len(self.models))
        half = min(it['length'], it['width']) / 2
        lo_r, hi_r = dress.get('ring', [0.3, 0.85])
        lo_s, hi_s = dress.get('scale', [1.0, 1.0])
        avoid = math.radians(float(dress.get('avoid', 0.0)))
        dirs = []
        if idx > 0:
            p = self.items[idx - 1]
            dirs.append(math.atan2(p['y'] - it['y'], p['x'] - it['x']))
        if idx + 1 < len(self.items):
            dirs.append(self._heading_out(idx))
        placed, tries = 0, 0
        while placed < int(dress['count']) and tries < 400:
            tries += 1
            a = rng.uniform(0, 2 * math.pi)
            if any(abs((a - d + math.pi) % (2 * math.pi) - math.pi) < avoid for d in dirs):
                continue
            r = half * rng.uniform(lo_r, hi_r)
            x, y = it['x'] + r * math.cos(a), it['y'] + r * math.sin(a)
            z = self.surface_z(it, x, y)
            if z is None:
                z = it['z']
            model = dress['models'][int(rng.integers(len(dress['models'])))]
            self._add(model, x, y, z - float(dress.get('sink', 0.2)), rng.uniform(0, 2 * math.pi),
                      rng.uniform(lo_s, hi_s))
            placed += 1

    def _decor(self, deco):
        rng = np.random.default_rng(int(deco.get('seed', self.plan['seed'])))
        pts = np.array([[it['x'], it['y'], it['z']] for it in self.items])
        lo_z, hi_z = deco.get('z', [-80.0, 60.0])
        lo_s, hi_s = deco.get('scale', [0.6, 1.6])
        if 'every' in deco:                     # efectos a lo largo de la ruta (luciernagas, particulas...)
            for k, it in enumerate(self.items[::int(deco['every'])]):
                model = deco['models'][k % len(deco['models'])]
                self._add(model, it['x'], it['y'], it['z'] + rng.uniform(lo_z, hi_z), rng.uniform(0, 2 * math.pi),
                          rng.uniform(lo_s, hi_s))
            return
        lo_d, hi_d = deco.get('distance', [40.0, 400.0])
        wmo = bool(deco.get('wmo'))
        placed, tries = 0, 0
        while placed < int(deco['count']) and tries < int(deco['count']) * 200:
            tries += 1
            x, y = rng.uniform(-self.half + 30, self.half - 30, 2)
            model = deco['models'][int(rng.integers(len(deco['models'])))]
            if wmo:
                scale = 1.0
                box = self._wmo_box(model)
            else:
                scale = rng.uniform(lo_s, hi_s)
                box = self.model_box[self._model(model)]
            reach = max(abs(box[0]), abs(box[1]), abs(box[3]), abs(box[4])) * scale    # radio en planta
            d = np.hypot(pts[:, 0] - x, pts[:, 1] - y) - reach
            if not lo_d <= d.min() <= hi_d:
                continue
            zref = float(pts[int(d.argmin()), 2])
            z = zref + rng.uniform(lo_z, hi_z)
            angle = rng.uniform(0, 2 * math.pi)
            if wmo:
                X, Y = self.to_wow(x, y)
                radius = max(abs(c) for c in box) * math.sqrt(2) + 1.0
                self.wmos.append({'name': model, 'x': float(X), 'y': float(Y), 'z': float(z),
                                  'angle': float(angle - math.pi / 2), 'radius': radius})
            else:
                tilt = float(deco.get('tilt', 20.0))
                self._add(model, x, y, z, angle, scale,
                          math.radians(rng.uniform(-tilt, tilt)), math.radians(rng.uniform(-tilt, tilt)))
            placed += 1

    def _wmo_box(self, path):
        """Caja del WMO raiz (MOHD): minX, minY, minZ, maxX, maxY, maxZ."""
        if path not in self.wmo_boxes:
            data = vmaps.read_client_file(self.wow_data, path)
            if not data:
                raise ValueError('no existe en el cliente: %s' % path)
            i = 0
            while i < len(data) - 8:
                tag = data[i:i + 4][::-1]
                size = struct.unpack_from('<I', data, i + 4)[0]
                if tag == b'MOHD':
                    self.wmo_boxes[path] = struct.unpack_from('<6f', data, i + 8 + 36)
                    break
                i += 8 + size
            else:
                raise ValueError('WMO sin MOHD: %s' % path)
        return self.wmo_boxes[path]

    # --- ADT: WMO ademas de los M2 -------------------------------------------------------------------------------

    def build_tile(self, tx, ty):
        tile = super().build_tile(tx, ty)
        x0, y0 = wow.tile_origin(tx, ty)
        names = {}
        for k, w in enumerate(self.wmos):
            r = w['radius']
            if not (x0 - wow.TILE - r <= w['x'] <= x0 + r and y0 - wow.TILE - r <= w['y'] <= y0 + r):
                continue
            if w['name'] not in names:
                names[w['name']] = len(tile.wmo_names)
                tile.wmo_names.append(w['name'])
            tile.wmos.append(wow.MapObject(names[w['name']], 1000000 + k, w['x'], w['y'], w['z'], w['angle'], r))
        return tile

    # --- Salidas -------------------------------------------------------------------------------------------------

    def _heading_out(self, idx):
        """Rumbo de salida de una plataforma: hacia la pieza siguiente."""
        a, b = self.items[idx], self.items[min(idx + 1, len(self.items) - 1)]
        return math.atan2(b['y'] - a['y'], b['x'] - a['x'])

    def parkour_lines(self):
        lines = ['# EventWow: parkour del mapa %d (tools/mapgen/parkourgen.py; generado, no editar)' % self.info['id'],
                 '# checkpoint X Y Z O radio altura_de_caida nombre  |  finish X Y Z O radio']
        for name, idx, fall in self.sections:
            it = self.items[idx]
            X, Y = self.to_wow(it['x'], it['y'])
            o = (self._heading_out(idx) - math.pi / 2) % (2 * math.pi)
            radius = math.hypot(it['length'], it['width']) / 2      # circulo que contiene la cara
            lines.append('checkpoint %.2f %.2f %.2f %.3f %.2f %.2f %s' % (X, Y, it['z'] + 0.5, o, radius, fall, name))
        it = self.items[-1]
        X, Y = self.to_wow(it['x'], it['y'])
        o = (it['angle'] - math.pi / 2) % (2 * math.pi)
        lines.append('finish %.2f %.2f %.2f %.3f %.2f' % (X, Y, it['z'] + 0.5, o, math.hypot(it['length'], it['width']) / 2))
        return '\n'.join(lines) + '\n'

    def points(self):
        out = []
        for name, idx, _ in self.sections:
            it = self.items[idx]
            X, Y = self.to_wow(it['x'], it['y'])
            out.append(('Control: %s' % name, X, Y, it['z'] + 1.0, (self._heading_out(idx) - math.pi / 2) % (2 * math.pi)))
        it = self.items[-1]
        X, Y = self.to_wow(it['x'], it['y'])
        out.append(('Meta', X, Y, it['z'] + 1.0, 0.0))
        return out

    def race(self):
        return None

    def summary(self):
        lines = []
        hard, impossible = [], []
        pairs = list(zip(self.items, self.items[1:]))
        for fork, items in self.branches:
            pairs += list(zip([self.items[fork]] + items, items))
        for a, b in pairs:
            dx, dy = b['x'] - a['x'], b['y'] - a['y']
            d = math.hypot(dx, dy)
            ux, uy = dx / d, dy / d
            gap = d - self._edge(a, ux, uy)[0] - self._edge(b, -ux, -uy)[0]
            dz = b['z'] - b.get('from_z', a['z'])
            reach = self.jump.reach(dz)
            frac = gap / reach if reach else 99.0
            if frac > 0.92 or reach is None:
                impossible.append((b, gap, dz))
            elif frac > 0.8:
                hard.append(b)
        for k, (name, idx, fall) in enumerate(self.sections):
            its = [it for it in self.items if it['section'] == k and it['kind'] == 'jump']
            zs = [it['z'] for it in its]
            lines.append('  Seccion %d "%s": %d saltos, z %.0f..%.0f, caida por debajo de %.0f'
                         % (k + 1, name, len(its), min(zs), max(zs), fall))
        lines.append('  Ruta: %d piezas, %d saltos dificiles (> 80 %% del alcance); %d callejones sin salida (%d piezas)'
                     % (len(self.items), len(hard), len(self.branches), sum(len(b) for _, b in self.branches)))
        for w in self.warnings:
            lines.append('  AVISO: ' + w)
        for b, gap, dz in impossible:
            lines.append('  AVISO: salto casi imposible a %s (%.0f, %.0f): hueco %.1f yd, desnivel %+.1f'
                         % (b['model'].split('\\')[-1], b['x'], b['y'], gap, dz))
        for model, g in self.geometry.items():
            if g['above'] > 0.5:
                lines.append('  Aviso: %s sobresale %.1f yd por encima de su cara pisable (x escala)'
                             % (model.split('\\')[-1], g['above']))
        lines.append('  Decoracion: %d modelos (%d distintos en total) + %d WMO'
                     % (len(self.models) - self.track_models, len(self.model_names), len(self.wmos)))
        return lines

    def preview(self, path, scale=1.0):
        """Vista cenital (piezas y ruta coloreada por seccion) + perfil de altura a lo largo de la ruta."""
        from PIL import Image, ImageDraw
        size = int(self.n * wow.TILE / scale)
        img = np.zeros((size, size, 3))
        img[:] = (0.02, 0.03, 0.08)
        self._draw(img, self.X0, self.Y0, scale)
        im = Image.fromarray((img * 255).astype(np.uint8))
        dr = ImageDraw.Draw(im)
        colors = [(255, 170, 60), (120, 200, 255), (255, 230, 90), (180, 140, 255), (120, 255, 150), (255, 110, 110)]

        def px(it):
            X, Y = self.to_wow(it['x'], it['y'])
            return (self.Y0 - Y) / scale, (self.X0 - X) / scale

        for a, b in zip(self.items, self.items[1:]):
            dr.line([px(a), px(b)], fill=colors[b['section'] % len(colors)], width=2)
        for fork, items in self.branches:
            chain = [self.items[fork]] + items
            for a, b in zip(chain, chain[1:]):
                dr.line([px(a), px(b)], fill=(150, 150, 150), width=1)
            cx, cy = px(items[-1])
            dr.line([cx - 4, cy - 4, cx + 4, cy + 4], fill=(255, 80, 80), width=2)
            dr.line([cx - 4, cy + 4, cx + 4, cy - 4], fill=(255, 80, 80), width=2)
        for name, idx, _ in self.sections:
            cx, cy = px(self.items[idx])
            dr.ellipse([cx - 6, cy - 6, cx + 6, cy + 6], outline=(0, 0, 0), fill=(255, 255, 255))
            dr.text((cx + 9, cy - 6), name, fill=(255, 255, 255))
        cx, cy = px(self.items[-1])
        dr.ellipse([cx - 7, cy - 7, cx + 7, cy + 7], outline=(0, 0, 0), fill=(255, 60, 60))
        dr.text((cx + 9, cy - 6), 'Meta', fill=(255, 255, 255))
        # Perfil: altura de cada pieza a lo largo de la ruta
        ph = 220
        prof = Image.new('RGB', (size, ph), (12, 14, 24))
        pd = ImageDraw.Draw(prof)
        zs = [it['z'] for it in self.items]
        z0, z1 = min(zs) - 5, max(zs) + 5
        for i, it in enumerate(self.items):
            x = 10 + (size - 20) * i / max(1, len(self.items) - 1)
            y = ph - 10 - (ph - 20) * (it['z'] - z0) / (z1 - z0)
            pd.rectangle([x - 1, y - 1, x + 1, y + 1], fill=colors[it['section'] % len(colors)])
        out = Image.new('RGB', (size, size + ph))
        out.paste(im, (0, 0))
        out.paste(prof, (0, size))
        out.save(path)
