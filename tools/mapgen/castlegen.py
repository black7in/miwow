"""Defensa del castillo sin Warcraft 3: plano JSON (Maps/Planos, "type": "castle") -> mapa de WoW + datos del servidor.

Mismo relieve, texturas y decoracion que los circuitos (trackgen.py), pero la linea central es un CAMINO ABIERTO:
empieza en el portal por el que salen las oleadas y acaba en el castillo (una torre: la criatura con la vida del
castillo, la pone el servidor). Plano:
  - "track": puntos del camino (Catmull-Rom centripeta abierta) desde el portal hasta la torre, con z, ancho "w",
    ambiente y borde a cada lado como en los circuitos ("cut" = canon: las oleadas no se salen del camino).
  - "castle":
      attack: yardas delante de la torre donde acaba la ruta de las oleadas (desde ahi la atacan)
      start: yardas delante de la torre donde aparece (y reaparece) el jugador
      guards: {"out": yardas, "lateral": [yardas a la derecha (+) o izquierda (-) mirando hacia el camino, ...]}
      portal: {"back": yardas detras del inicio del camino}
      boss: {"back": yardas, "lateral": yardas}: jefe final, quieto junto al portal hasta su oleada
      pathStep: yardas entre los puntos de ruta de las oleadas
      objects (opcional): edificios que invoca el servidor como objetos, copiados de un sitio de referencia del juego
        con sus coordenadas originales ("reference": [X, Y, Z, O] del punto que va al final del camino, O = "fuera");
        castlegen los traslada y gira. [{"entry", "pos": [X, Y, Z, O], "door": true (se dana con la vida)}]
Salida del servidor (<DataDir>/maps/<id>_castillo.txt), una linea por elemento (WoW, orientacion en radianes):
  spawn | portal | boss | gate (la torre) | start | guard  X Y Z O,  path X Y Z (el ultimo = punto de ataque),
  object | door  <entry> X Y Z O
"""
import math

import numpy as np

import trackgen
import wowfiles as wow

CASTLE_DEFAULTS = {
    'attack': 8.0,
    'start': 22.0,
    'guards': {'out': 13.0, 'lateral': [-9.0, 0.0, 9.0]},
    'portal': {'back': 6.0},
    'boss': {'back': 2.0, 'lateral': 9.0},
    'vendor': {'out': 6.0, 'lateral': 15.0},
    'pathStep': 10.0,
    'objects': [],
}


class Lane(trackgen.Track):
    """Como Track pero abierta: de la primera muestra (aparicion) a la ultima (puerta), sin vuelta."""

    def __init__(self, plan, biome_index):
        pts = plan['track']
        n = len(pts)
        if n < 2:
            raise ValueError('el camino necesita al menos 2 puntos')
        P = np.array([p['p'] for p in pts], dtype=np.float64)
        Z = np.array([p['z'] for p in pts], dtype=np.float64)
        W = np.array([p.get('w', 24.0) for p in pts], dtype=np.float64)
        # Extremos prolongados por reflexion (Catmull-Rom abierta: la curva pasa por el primero y el ultimo)
        Pe = np.vstack([2 * P[0] - P[1], P, 2 * P[-1] - P[-2]])
        Ze = np.concatenate([[Z[0]], Z, [Z[-1]]])
        xs, ys, zs, ws, seg = [], [], [], [], []
        sub = 240
        for i in range(n - 1):
            p0, p1, p2, p3 = Pe[i], Pe[i + 1], Pe[i + 2], Pe[i + 3]
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
            z0, z1, z2, z3 = Ze[i], Ze[i + 1], Ze[i + 2], Ze[i + 3]
            zz = 0.5 * ((2 * z1) + (-z0 + z2) * u + (2 * z0 - 5 * z1 + 4 * z2 - z3) * u ** 2
                        + (-z0 + 3 * z1 - 3 * z2 + z3) * u ** 3)
            xs.append(c[:, 0])
            ys.append(c[:, 1])
            zs.append(zz)
            ws.append(W[i] * (1 - u) + W[i + 1] * u)
            seg.append(np.full(sub, i))
        # Ultimo punto exacto
        xs.append([P[-1, 0]])
        ys.append([P[-1, 1]])
        zs.append([Z[-1]])
        ws.append([W[-1]])
        seg.append([n - 2])
        x, y, z, w, seg = (np.concatenate([np.asarray(a, dtype=np.float64) for a in arr]) for arr in (xs, ys, zs, ws, seg))
        seg = seg.astype(np.int64)
        # Remuestreo por longitud de arco: una muestra por yarda, la primera en la aparicion y la ultima en la puerta
        dl = np.hypot(np.diff(x), np.diff(y))
        s = np.concatenate([[0.0], np.cumsum(dl)])
        self.length = float(s[-1])
        m = int(round(self.length)) + 1
        su = np.linspace(0.0, self.length, m)
        self.x = np.interp(su, s, x)
        self.y = np.interp(su, s, y)
        self.z = self._smooth(np.interp(su, s, z), 30)
        self.half = np.interp(su, s, w) / 2.0
        self.seg = seg[np.minimum(np.searchsorted(s, su, side='right') - 1, len(seg) - 1)]
        self.s = su
        self.n = m
        self.ds = self.length / (m - 1)

        def side_param(key, name):
            vals = np.array([trackgen.EDGE_TYPES[pts[i].get(key, 'berm')][name] for i in range(n - 1)])
            return self._smooth(vals[self.seg], 12)
        self.berm_l, self.band_l = side_param('left', 'berm'), side_param('left', 'band')
        self.berm_r, self.band_r = side_param('right', 'berm'), side_param('right', 'band')
        self.biome = np.array([biome_index[pts[i]['biome']] for i in range(n - 1)])[self.seg]
        tx, ty = np.gradient(self.x), np.gradient(self.y)
        norm = np.maximum(np.hypot(tx, ty), 1e-9)
        self.tx, self.ty = tx / norm, ty / norm
        self.start = 0

    @staticmethod
    def _smooth(v, r):
        r = int(r)
        if r < 1 or len(v) < 2 * r + 1:
            return v
        p = np.pad(v, r, mode='edge')
        k = np.ones(2 * r + 1) / (2 * r + 1)
        return np.convolve(p, k, mode='same')[r:-r]

    def point(self, s):
        """(x, y, z, direccion) en la posicion s (yardas desde la aparicion; fuera del camino, el extremo)."""
        k = int(min(max(round(s / self.ds), 0), self.n - 1))
        return self.x[k], self.y[k], self.z[k], math.atan2(self.ty[k], self.tx[k]), k


class CastleConverter(trackgen.TrackConverter):
    def __init__(self, info, plan_path, wow_data):
        super().__init__(info, plan_path, wow_data)
        cfg = dict(CASTLE_DEFAULTS)
        cfg.update(self.plan.get('castle', {}))
        self.castle = cfg

    def make_track(self, plan):
        return Lane(plan, self.biome_index)

    # --- Coordenadas WoW ----------------------------------------------------------------------------------------

    def _ground(self, X, Y):
        return float(self.height(np.array(X), np.array(Y)))

    def _frame(self):
        """Puerta (WoW X, Y), direccion hacia fuera (unitaria WoW) y su orientacion."""
        tr = self.track
        k = tr.n - 1
        X, Y = self.to_wow(tr.x[k], tr.y[k])
        # Tangente del plano (x este, y norte) -> WoW (X norte, Y oeste): (dX, dY) = (ty, -tx). Fuera = hacia atras.
        dX, dY = -tr.ty[k], tr.tx[k]
        return float(X), float(Y), dX, dY, math.atan2(dY, dX)

    def _ahead(self, dist, lateral=0.0):
        """Punto delante de la puerta (dist yardas hacia fuera, lateral a la derecha mirando hacia fuera)."""
        X, Y, dX, dY, o = self._frame()
        # Derecha de la direccion (dX, dY) en WoW (Y = oeste): girar -90 grados
        rX, rY = dY, -dX
        PX, PY = X + dX * dist + rX * lateral, Y + dY * dist + rY * lateral
        return PX, PY, self._ground(PX, PY), o

    def _behind_start(self, dist, lateral=0.0):
        """Punto detras del inicio del camino (dist yardas hacia atras), mirando hacia el camino."""
        tr = self.track
        X, Y = self.to_wow(tr.x[0], tr.y[0])
        fX, fY = tr.ty[0], -tr.tx[0]          # direccion del camino en WoW
        rX, rY = fY, -fX                       # derecha mirando hacia el camino
        PX, PY = X - fX * dist + rX * lateral, Y - fY * dist + rY * lateral
        return float(PX), float(PY), self._ground(PX, PY), math.atan2(fY, fX) % (2 * math.pi)

    def castle_objects(self):
        """[(entry, X, Y, Z, O, puerta)] de los edificios, trasladados y girados desde el sitio de referencia."""
        cfg = self.castle
        if not cfg['objects']:
            return []
        rx, ry, _, ro = cfg['reference']
        X, Y, _, _, o_out = self._frame()
        rot = o_out - ro
        c, s = math.cos(rot), math.sin(rot)
        out = []
        for obj in cfg['objects']:
            if 'entry' not in obj:          # comentarios ("_...")
                continue
            ox, oy, _, oo = obj['pos']
            dx, dy = ox - rx, oy - ry
            PX, PY = X + dx * c - dy * s, Y + dx * s + dy * c
            out.append((int(obj['entry']), PX, PY, self._ground(PX, PY) + obj.get('dz', 0.0),
                        (oo + rot) % (2 * math.pi), bool(obj.get('door'))))
        return out

    def castle_points(self):
        """[(nombre, X, Y, Z, O)]: aparicion, portal, jefe final, torre, inicio del jugador, intendente y guardias."""
        cfg = self.castle
        out = [('Aparicion', *self._behind_start(0.0)),
               ('Portal', *self._behind_start(cfg['portal']['back'])),
               ('Jefe final', *self._behind_start(cfg['boss']['back'], cfg['boss']['lateral']))]
        out.append(('Torre', *self._ahead(0.0)))
        out.append(('Inicio', *self._ahead(cfg['start'])))
        out.append(('Intendente', *self._ahead(cfg['vendor']['out'], cfg['vendor']['lateral'])))
        guards = cfg['guards']
        for i, lat in enumerate(guards['lateral']):
            out.append(('Guardia %d' % (i + 1), *self._ahead(guards['out'], lat)))
        return out

    def route(self):
        """Puntos de ruta de las oleadas (WoW X, Y, Z): por el centro del camino hasta el punto de ataque."""
        tr = self.track
        step = self.castle['pathStep']
        end = max(tr.length - self.castle['attack'], 0.0)
        out = []
        s = step
        while s < end - step * 0.5:
            x, y, _, _, _ = tr.point(s)
            X, Y = self.to_wow(x, y)
            out.append((float(X), float(Y), self._ground(X, Y)))
            s += step
        gx, gy, gz, _ = self._ahead(self.castle['attack'])
        out.append((gx, gy, gz))
        return out

    def castle_lines(self):
        lines = ['# MiWow: defensa del castillo (tools/mapgen/castlegen.py, no editar a mano)']
        kinds = {'Aparicion': 'spawn', 'Portal': 'portal', 'Jefe final': 'boss', 'Torre': 'gate', 'Inicio': 'start',
                 'Intendente': 'vendor'}
        for name, X, Y, Z, o in self.castle_points():
            kind = kinds.get(name, 'guard')
            lines.append('%s %.3f %.3f %.3f %.4f' % (kind, X, Y, Z, o))
        for X, Y, Z in self.route():
            lines.append('path %.3f %.3f %.3f' % (X, Y, Z))
        for entry, X, Y, Z, o, door in self.castle_objects():
            lines.append('%s %d %.3f %.3f %.3f %.4f' % ('door' if door else 'object', entry, X, Y, Z, o))
        return '\n'.join(lines) + '\n'

    # --- Lo que usa mapgen ---------------------------------------------------------------------------------------

    def markers(self):
        """Para la vista previa: [(nombre, x, y, z, angulo del plano, s)]."""
        out = []
        for name, X, Y, Z, o in self.castle_points():
            x, y = self.to_local(X, Y)
            out.append((('Meta' if name == 'Torre' else 'Control' if name.startswith('Guardia') else name),
                        x, y, Z, o + math.pi / 2, 0.0))
        return out

    def points(self):
        pts = list(self.castle_points())
        for entry, X, Y, Z, o, door in self.castle_objects():
            pts.append(('%s %d' % ('Puerta (objeto)' if door else 'Edificio', entry), X, Y, Z, o))
        return pts

    def summary(self):
        tr = self.track
        grade = np.abs(np.diff(tr.z)) / tr.ds
        route = self.route()
        return ['  Camino: %.0f yardas del portal a la torre, ancho %.0f-%.0f, pendiente max %.1f %%, '
                '%d puntos de ruta' % (tr.length, tr.half.min() * 2, tr.half.max() * 2, grade.max() * 100, len(route)),
                '  Castillo: %d edificios (objetos del servidor)' % len(self.castle_objects()),
                '  WoW: %d ADT (%s), relieve de %.1f a %.1f' % (len(self.tiles), ', '.join('%d_%d' % t for t in self.tiles),
                                                                float(self.heights.min()), self.top),
                '  Decoracion: %d modelos (%d distintos)' % (len(self.models), len(self.model_names))]
