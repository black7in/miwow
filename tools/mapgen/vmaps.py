"""vmaps del servidor (AzerothCore, VMAP_4.8) para los modelos M2 de los mapas propios.

Hace lo mismo que vmap4_extractor + vmap4_assembler, pero desde la lista de modelos de mapgen (el extractor lee los
MPQ del cliente y nuestro parche es una carpeta). Solo modelos M2 (sin WMO ni agua de WMO). Formato tomado de
src/common/Collision (MapTree, TileAssembler, WorldModel, ModelInstance, BoundingIntervalHierarchy) y
src/tools/vmap4_extractor (model.cpp):

- <mapa>.vmtree: magia, tiled = 1, "NODE" + BIH de los limites de todos los modelos, "GOBJ" (vacio).
- <mapa>_<tx>_<ty>.vmtile (orden del ADT): magia, n, por modelo ModelSpawn + indice en el BIH del mapa.
- <nombre>.m2.vmo: WorldModel de un grupo con la malla de colision del M2 (bounding vertices/triangles) + BIH.

Coordenadas internas: (ZERO - X, ZERO - Y, Z) = MDDF reordenado (fixCoords del extractor). Giro = el del MDDF
(grados; ModelInstance: fromEulerAnglesZYX(rot.y, rot.x, rot.z)).
"""
import math
import os
import struct

import numpy as np

from mpq import MPQ

VMAP_MAGIC = b'VMAP_4.8'
MOD_M2 = 1
MOD_HAS_BOUND = 4
MAX_STACK_SIZE = 64
F13 = float(np.float32(1.3))

# Orden de carga de los MPQ del cliente (el primero que tenga el archivo gana)
CLIENT_MPQS = ['patch-3.MPQ', 'patch-2.MPQ', 'patch.MPQ', 'lichking.MPQ', 'expansion.MPQ', 'common-2.MPQ', 'common.MPQ']


def f32(x):
    return float(np.float32(x))


def fbits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def fuzzy_eq(a, b):
    return a == b or abs(a - b) <= 0.00001 * max(1.0, abs(a), abs(b))


# --- BIH (port literal de BoundingIntervalHierarchy.cpp, en float32) ----------------------------------------------

class BIH:
    def __init__(self, bounds, leaf_size=3):
        """bounds: [(lo(3), hi(3))] de cada primitiva."""
        self.tree = [3 << 30, 0, 0]
        self.objects = []
        if not bounds:
            self.lo = [math.inf] * 3
            self.hi = [-math.inf] * 3
            return
        self.prim = [([f32(v) for v in lo], [f32(v) for v in hi]) for lo, hi in bounds]
        self.lo = list(self.prim[0][0])
        self.hi = list(self.prim[0][1])
        for lo, hi in self.prim:
            self.lo = [min(a, b) for a, b in zip(self.lo, lo)]
            self.hi = [max(a, b) for a, b in zip(self.hi, hi)]
        self.max_prims = leaf_size
        self.indices = list(range(len(bounds)))
        self._subdivide(0, len(bounds) - 1, self.tree, [list(self.lo), list(self.hi)],
                        [list(self.lo), list(self.hi)], 0, 1)
        self.objects = self.indices

    def _leaf(self, tree, node, left, right):
        tree[node] = (3 << 30) | left
        tree[node + 1] = right - left + 1

    def _subdivide(self, left, right, tree, grid, nodebox, node, depth):
        if right - left + 1 <= self.max_prims or depth >= MAX_STACK_SIZE:
            self._leaf(tree, node, left, right)
            return
        idx, prim = self.indices, self.prim
        axis, split, prev_clip, was_left = -1, math.nan, math.nan, True
        while True:
            prev_axis, prev_split = axis, split
            d = [f32(grid[1][i] - grid[0][i]) for i in range(3)]
            if min(d) < 0:
                raise ValueError('BIH: negative node extents')
            nx, ny, nz = abs(d[0]), abs(d[1]), abs(d[2])
            if nx > ny:
                axis = 0 if nx > nz else 2
            else:
                axis = 1 if ny > nz else 2
            split = f32(0.5 * f32(grid[0][axis] + grid[1][axis]))
            clip_l, clip_r = -math.inf, math.inf
            right_orig = right
            node_l, node_r = math.inf, -math.inf
            i = left
            while i <= right:
                obj = idx[i]
                minb, maxb = prim[obj][0][axis], prim[obj][1][axis]
                center = f32(f32(minb + maxb) * 0.5)
                if center <= split:
                    i += 1
                    clip_l = max(clip_l, maxb)
                else:
                    idx[i], idx[right] = idx[right], idx[i]
                    right -= 1
                    clip_r = min(clip_r, minb)
                node_l = min(node_l, minb)
                node_r = max(node_r, maxb)
            # espacio vacio: nodo BVH2
            if node_l > nodebox[0][axis] and node_r < nodebox[1][axis]:
                if f32(F13 * f32(node_r - node_l)) < f32(nodebox[1][axis] - nodebox[0][axis]):
                    nxt = len(tree)
                    tree += [0, 0, 0]
                    tree[node] = (axis << 30) | (1 << 29) | nxt
                    tree[node + 1] = fbits(node_l)
                    tree[node + 2] = fbits(node_r)
                    nodebox[0][axis] = node_l
                    nodebox[1][axis] = node_r
                    self._subdivide(left, right_orig, tree, grid, nodebox, nxt, depth + 1)
                    return
            if right == right_orig:                     # todo a la izquierda
                if prev_axis == axis and fuzzy_eq(prev_split, split):
                    self._leaf(tree, node, left, right)
                    return
                if clip_l <= split:
                    grid[1][axis] = split
                    prev_clip, was_left = clip_l, True
                    continue
                grid[1][axis] = split
                prev_clip = math.nan
            elif left > right:                          # todo a la derecha
                right = right_orig
                if prev_axis == axis and fuzzy_eq(prev_split, split):
                    self._leaf(tree, node, left, right)
                    return
                if clip_r >= split:
                    grid[0][axis] = split
                    prev_clip, was_left = clip_r, False
                    continue
                grid[0][axis] = split
                prev_clip = math.nan
            else:
                if prev_axis != -1 and not math.isnan(prev_clip):
                    nxt = len(tree)
                    tree += [0, 0, 0]
                    if was_left:
                        tree[node] = (prev_axis << 30) | nxt
                        tree[node + 1] = fbits(prev_clip)
                        tree[node + 2] = fbits(math.inf)
                    else:
                        tree[node] = (prev_axis << 30) | (nxt - 3)
                        tree[node + 1] = fbits(-math.inf)
                        tree[node + 2] = fbits(prev_clip)
                    depth += 1
                    node = nxt
                break
        nxt = len(tree)
        nl = right - left + 1
        nr = right_orig - (right + 1) + 1
        if nl > 0:
            tree += [0, 0, 0]
        else:
            nxt -= 3
        if nr > 0:
            tree += [0, 0, 0]
        tree[node] = (axis << 30) | nxt
        tree[node + 1] = fbits(clip_l)
        tree[node + 2] = fbits(clip_r)
        grid_l = [list(grid[0]), list(grid[1])]
        grid_r = [list(grid[0]), list(grid[1])]
        node_bl = [list(nodebox[0]), list(nodebox[1])]
        node_br = [list(nodebox[0]), list(nodebox[1])]
        grid_l[1][axis] = grid_r[0][axis] = split
        node_bl[1][axis] = clip_l
        node_br[0][axis] = clip_r
        if nl > 0:
            self._subdivide(left, right, tree, grid_l, node_bl, nxt, depth + 1)
        if nr > 0:
            self._subdivide(right + 1, right_orig, tree, grid_r, node_br, nxt + 3, depth + 1)

    def pack(self):
        return (struct.pack('<6f', *self.lo, *self.hi) + struct.pack('<I', len(self.tree))
                + struct.pack('<%dI' % len(self.tree), *self.tree) + struct.pack('<I', len(self.objects))
                + struct.pack('<%dI' % len(self.objects), *self.objects))


# --- Modelos -------------------------------------------------------------------------------------------------------

def read_client_file(data_dir, path):
    """Archivo de los MPQ del cliente (Data\\), respetando el orden de carga."""
    for name in CLIENT_MPQS:
        full = os.path.join(data_dir, name)
        if not os.path.exists(full):
            continue
        archive = MPQ(full)
        try:
            if archive.has(path):
                return archive.read(path)
        finally:
            archive.close()
    raise FileNotFoundError('%s no esta en los MPQ de %s' % (path, data_dir))


def m2_collision(data):
    """Malla de colision del M2 como la escribe vmap4_extractor: vertices tal cual, triangulos (a, c, b)."""
    n_tri, ofs_tri, n_vert, ofs_vert = struct.unpack_from('<4I', data, 0xD8)
    verts = np.frombuffer(data, dtype='<f4', count=n_vert * 3, offset=ofs_vert).reshape(-1, 3).copy()
    idx = np.frombuffer(data, dtype='<u2', count=n_tri, offset=ofs_tri).reshape(-1, 3)
    tris = idx[:, [0, 2, 1]].astype(np.uint32)
    return verts, tris


def vmo_name(model_path):
    """Nombre del .vmo como el extractor (GetPlainName + fixnamen: cada palabra con mayuscula inicial)."""
    plain = model_path.replace('/', '\\').split('\\')[-1]
    out, up = [], True
    for ch in plain:
        out.append(ch.upper() if up else ch.lower())
        up = not ch.isalnum()
    return ''.join(out).replace('.M2', '.m2')


def build_vmo(verts, tris):
    """WorldModel de un grupo (M2): sin limites de grupo ni agua, BIH de la malla y BIH de grupos."""
    v = verts.astype('<f4')
    tri_bounds = [(v[t].min(axis=0), v[t].max(axis=0)) for t in tris]
    mesh = BIH(tri_bounds)
    group = (struct.pack('<6f', 0, 0, 0, 0, 0, 0) + struct.pack('<II', 0, 0)
             + b'VERT' + struct.pack('<II', 4 + 12 * len(v), len(v)) + v.tobytes()
             + b'TRIM' + struct.pack('<II', 4 + 12 * len(tris), len(tris)) + tris.astype('<u4').tobytes()
             + b'MBIH' + mesh.pack()
             + b'LIQU' + struct.pack('<I', 0))
    groups = BIH([((0.0, 0.0, 0.0), (0.0, 0.0, 0.0))], leaf_size=1)
    return (VMAP_MAGIC + b'WMOD' + struct.pack('<II', 8, 0) + b'GMOD' + struct.pack('<I', 1) + group
            + b'GBIH' + groups.pack())


# --- Mapa ----------------------------------------------------------------------------------------------------------

class Spawn:
    """Modelo colocado (ya en coordenadas internas de vmap)."""

    def __init__(self, uid, name, pos, rot, scale, verts, tiles):
        self.uid, self.name, self.pos, self.rot, self.scale, self.tiles = uid, name, pos, rot, scale, tiles
        # TileAssembler::calculateTransformedBound: R * (v * escala) + pos
        a, b, c = (math.radians(r) for r in (rot[1], rot[0], rot[2]))
        rz = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
        ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
        rx = np.array([[1, 0, 0], [0, math.cos(c), -math.sin(c)], [0, math.sin(c), math.cos(c)]])
        w = (verts.astype(np.float64) * scale) @ (rz @ ry @ rx).T + np.array(pos)
        self.lo, self.hi = w.min(axis=0), w.max(axis=0)

    def pack(self):
        name = self.name.encode('ascii')
        return (struct.pack('<IHI', MOD_M2 | MOD_HAS_BOUND, 0, self.uid) + struct.pack('<3f', *self.pos)
                + struct.pack('<3f', *self.rot) + struct.pack('<f', self.scale)
                + struct.pack('<6f', *self.lo, *self.hi) + struct.pack('<I', len(name)) + name)


def build_map(spawns):
    """(.vmtree, {(tx, ty): .vmtile}). Los modelos se ordenan por uid como en el assembler (std::map)."""
    spawns = sorted(spawns, key=lambda s: s.uid)
    tree = BIH([(s.lo, s.hi) for s in spawns])
    vmtree = VMAP_MAGIC + b'\x01' + b'NODE' + tree.pack() + b'GOBJ'
    per_tile = {}
    for i, s in enumerate(spawns):
        for t in s.tiles:
            per_tile.setdefault(t, []).append(s.pack() + struct.pack('<I', i))
    tiles = {t: VMAP_MAGIC + struct.pack('<I', len(items)) + b''.join(items) for t, items in per_tile.items()}
    return vmtree, tiles


def tree_name(map_id):
    return '%03d.vmtree' % map_id


def tile_name(map_id, tx, ty):
    # StaticMapTree::getTileFileName(map, gx, gy) = map_gy_gx; gx = fila del ADT (ty), gy = columna (tx)
    return '%03d_%02d_%02d.vmtile' % (map_id, tx, ty)
