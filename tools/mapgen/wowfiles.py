"""Escritura de archivos de terreno de WoW 3.3.5 (build 12340).

Cliente: WDT + ADT (formato comprobado contra Azeroth_32_48.adt / PVPZone01_32_32.adt del cliente):
  ADT  = MVER MHDR MCIN MTEX MMDX MMID MWMO MWID MDDF MODF [MH2O] MCNK x256
  MCNK = cabecera (128) + MCVT MCNR(+13 bytes de relleno, fuera del tamano) MCLY MCRF MCAL MCSE
  Alfa de 4 bits (2048 bytes por capa, WDT sin el flag 0x4) y MCNK con flag 0x8000 (alfa 64x64 sin "arreglar").
Servidor: .map de AzerothCore (src/tools/map_extractor/System.cpp ConvertADT, MAP_VERSION_MAGIC 9).

Rejillas por ADT (129 = vertices exteriores, 128 = interiores), indice [fila][columna]:
  fila    -> X del mundo decreciente (hacia el sur),  columna -> Y del mundo decreciente (hacia el este).
"""
import struct

import numpy as np

TILE = 1600.0 / 3.0          # 533.333 yardas
CHUNK = TILE / 16.0
UNIT = CHUNK / 8.0
ZERO = 32.0 * TILE

LIQUID_SLOW_WATER = 5        # LiquidType.dbc (el que usan los rios de Elwynn); sonido = agua
MAP_LIQUID_TYPE_WATER = 0x01
MAP_LIQUID_NO_TYPE = 0x0001
MAP_LIQUID_NO_HEIGHT = 0x0002
MAP_AREA_NO_AREA = 0x0001
NO_LIQUID_HEIGHT = -500.0    # CONF_use_minHeight del extractor


def chunk(magic, data=b''):
    return magic[::-1].encode('ascii') + struct.pack('<I', len(data)) + data


def tile_origin(tx, ty):
    """Esquina noroeste (X, Y) del ADT <mapa>_<tx>_<ty>."""
    return ZERO - ty * TILE, ZERO - tx * TILE


# --- WDT -------------------------------------------------------------------------------------------------------

def build_wdt(tiles):
    main = bytearray(64 * 64 * 8)
    for tx, ty in tiles:
        struct.pack_into('<II', main, (ty * 64 + tx) * 8, 1, 0)
    return (chunk('MVER', struct.pack('<I', 18)) + chunk('MPHD', bytes(32)) + chunk('MAIN', bytes(main))
            + chunk('MWMO'))


# --- ADT -------------------------------------------------------------------------------------------------------

def _mcvt_order(outer, inner):
    """Alterna filas: 9 exteriores, 8 interiores... (145 valores)."""
    rows = []
    for r in range(9):
        rows.append(outer[r])
        if r < 8:
            rows.append(inner[r])
    return np.concatenate(rows)


def _pack_alpha4(alpha):
    """alpha: 64x64 en 0..1 -> 2048 bytes (dos valores de 4 bits por byte, el primero en el nibble bajo)."""
    q = np.clip(np.rint(alpha * 15.0), 0, 15).astype(np.uint8)
    return (q[:, 0::2] | (q[:, 1::2] << 4)).tobytes()


class TileData:
    """Datos de un ADT ya muestreados.

    heights_outer[129,129], heights_inner[128,128]: alturas absolutas.
    normals_outer[129,129,3], normals_inner[128,128,3]: normales unitarias (X, Y, arriba).
    textures: lista de rutas BLP; layers[(cr, cc)] = [(indice_textura, alfa 64x64 o None para la base), ...].
    water[128,128] bool por celda; water_height[129,129] altura de la superficie por vertice.
    """

    def __init__(self, tx, ty):
        self.tx, self.ty = tx, ty
        self.heights_outer = self.heights_inner = None
        self.normals_outer = self.normals_inner = None
        self.textures = []
        self.layers = {}
        self.water = np.zeros((128, 128), dtype=bool)
        self.water_height = np.zeros((129, 129))


def _mh2o(tile):
    """MH2O: una instancia 8x8 por MCNK con agua (bitmap de celdas + alturas y profundidad por vertice)."""
    header = bytearray(256 * 12)
    body = bytearray()
    base = len(header)
    for cr in range(16):
        for cc in range(16):
            cells = tile.water[cr * 8:(cr + 1) * 8, cc * 8:(cc + 1) * 8]
            if not cells.any():
                continue
            levels = tile.water_height[cr * 8:cr * 8 + 9, cc * 8:cc * 8 + 9].astype(np.float32)
            ground = tile.heights_outer[cr * 8:cr * 8 + 9, cc * 8:cc * 8 + 9]
            depth = np.clip(np.rint(levels - ground), 0, 255).astype(np.uint8)
            bitmap = 0
            for i, value in enumerate(cells.flatten()):
                if value:
                    bitmap |= 1 << i
            ofs_instance = base + len(body)
            ofs_attributes = ofs_instance + 24
            ofs_exists = ofs_attributes + 16
            ofs_vertex = ofs_exists + 8
            body += struct.pack('<HHffBBBBII', LIQUID_SLOW_WATER, 0, float(levels.min()), float(levels.max()),
                                0, 0, 8, 8, ofs_exists, ofs_vertex)
            body += struct.pack('<QQ', bitmap, 0)          # pescable, profunda
            body += struct.pack('<Q', bitmap)
            body += levels.tobytes() + depth.tobytes()
            while len(body) % 4:
                body.append(0)
            struct.pack_into('<III', header, (cr * 16 + cc) * 12, ofs_instance, 1, ofs_attributes)
    return bytes(header) + bytes(body)


def _mcnk(tile, cr, cc):
    outer = tile.heights_outer[cr * 8:cr * 8 + 9, cc * 8:cc * 8 + 9]
    inner = tile.heights_inner[cr * 8:cr * 8 + 8, cc * 8:cc * 8 + 8]
    base = float(min(outer.min(), inner.min()))
    mcvt = (_mcvt_order(outer, inner) - base).astype(np.float32).tobytes()

    n_outer = tile.normals_outer[cr * 8:cr * 8 + 9, cc * 8:cc * 8 + 9]
    n_inner = tile.normals_inner[cr * 8:cr * 8 + 8, cc * 8:cc * 8 + 8]
    rows = []
    for r in range(9):
        rows.append(n_outer[r])
        if r < 8:
            rows.append(n_inner[r])
    normals = np.clip(np.rint(np.concatenate(rows) * 127.0), -127, 127).astype(np.int8)
    mcnr = normals.tobytes()                                # 435 bytes; el cliente espera 13 mas fuera del chunk

    layers = tile.layers[(cr, cc)]
    mcly = bytearray()
    mcal = bytearray()
    for i, (texture, alpha) in enumerate(layers):
        if i == 0:
            mcly += struct.pack('<4I', texture, 0, 0, 0)
        else:
            mcly += struct.pack('<4I', texture, 0x100, len(mcal), 0)
            mcal += _pack_alpha4(alpha)

    sub = bytearray()
    offsets = {}
    header_size = 8 + 128
    for magic, data, pad in (('MCVT', mcvt, b''), ('MCNR', mcnr, bytes(13)), ('MCLY', bytes(mcly), b''),
                             ('MCRF', b'', b''), ('MCAL', bytes(mcal), b''), ('MCSE', b'', b'')):
        offsets[magic] = header_size + len(sub)
        sub += chunk(magic, data) + pad

    x, y = tile_origin(tile.tx, tile.ty)
    header = struct.pack(
        '<16I4I6I3f3I',
        0x8000, cc, cr, len(layers), 0,
        offsets['MCVT'], offsets['MCNR'], offsets['MCLY'], offsets['MCRF'], offsets['MCAL'], 8 + len(mcal),
        0, 0,                       # MCSH
        0, 0, 0,                    # area, objetos de mapa, agujeros
        0, 0, 0, 0,                 # textura de baja calidad
        0, 0, offsets['MCSE'], 0, 0, 0,
        x - cr * CHUNK, y - cc * CHUNK, base,
        0, 0, 0)
    assert len(header) == 128
    return chunk('MCNK', header + bytes(sub))


def build_adt(tile):
    mver = chunk('MVER', struct.pack('<I', 18))
    mtex = chunk('MTEX', b''.join(t.encode('ascii') + b'\0' for t in tile.textures))
    empties = [chunk(m) for m in ('MMDX', 'MMID', 'MWMO', 'MWID', 'MDDF', 'MODF')]
    mh2o = chunk('MH2O', _mh2o(tile)) if tile.water.any() else b''
    mcnks = [_mcnk(tile, cr, cc) for cr in range(16) for cc in range(16)]

    mhdr_data_start = len(mver) + 8
    pos = len(mver) + 8 + 64                                # tras MHDR
    ofs = {'MCIN': pos}
    pos += 8 + 4096
    ofs['MTEX'] = pos
    pos += len(mtex)
    for magic, data in zip(('MMDX', 'MMID', 'MWMO', 'MWID', 'MDDF', 'MODF'), empties):
        ofs[magic] = pos
        pos += len(data)
    ofs['MH2O'] = pos if mh2o else 0
    pos += len(mh2o)

    mcin = bytearray()
    for data in mcnks:
        mcin += struct.pack('<4I', pos, len(data), 0, 0)
        pos += len(data)

    def rel(magic):
        return ofs[magic] - mhdr_data_start if ofs[magic] else 0

    mhdr = struct.pack('<16I', 0, rel('MCIN'), rel('MTEX'), rel('MMDX'), rel('MMID'), rel('MWMO'), rel('MWID'),
                       rel('MDDF'), rel('MODF'), 0, rel('MH2O'), 0, 0, 0, 0, 0)
    out = mver + chunk('MHDR', mhdr) + chunk('MCIN', bytes(mcin)) + mtex + b''.join(empties) + mh2o + b''.join(mcnks)
    assert len(out) == pos
    return out


# --- .map del servidor -----------------------------------------------------------------------------------------

def build_server_map(tile, build=12340):
    area = b'AREA' + struct.pack('<HH', MAP_AREA_NO_AREA, 0)

    v9 = tile.heights_outer.astype(np.float32)
    v8 = tile.heights_inner.astype(np.float32)
    height = b'MHGT' + struct.pack('<Iff', 0, float(min(v9.min(), v8.min())), float(max(v9.max(), v8.max())))
    height += v9.tobytes() + v8.tobytes()

    liquid = b''
    if tile.water.any():
        entry = np.zeros((16, 16), dtype=np.uint16)
        flags = np.zeros((16, 16), dtype=np.uint8)
        for cr in range(16):
            for cc in range(16):
                if tile.water[cr * 8:(cr + 1) * 8, cc * 8:(cc + 1) * 8].any():
                    entry[cr, cc] = LIQUID_SLOW_WATER
                    flags[cr, cc] = MAP_LIQUID_TYPE_WATER
        levels = tile.water_height.astype(np.float32).copy()
        shown = tile.water
        levels[:128, :128][~shown] = NO_LIQUID_HEIGHT       # igual que el extractor
        ys, xs = np.nonzero(shown)
        min_x, max_x, min_y, max_y = xs.min(), xs.max(), ys.min(), ys.max()
        width, rows = max_x - min_x + 2, max_y - min_y + 2
        visible = levels[:128, :128]
        min_level = float(visible.min())
        max_level = float(visible.max())
        header_flags = 0
        if max_level == min_level:
            header_flags |= MAP_LIQUID_NO_HEIGHT
        full_type = not ((entry == entry[0, 0]).all() and (flags == flags[0, 0]).all())
        if not full_type:
            header_flags |= MAP_LIQUID_NO_TYPE
        liquid = b'MLIQ' + struct.pack('<BBHBBBBf', header_flags,
                                       int(flags[0, 0]) if not full_type else 0,
                                       int(entry[0, 0]) if not full_type else 0,
                                       int(min_x), int(min_y), int(width), int(rows), min_level)
        if full_type:
            liquid += entry.tobytes() + flags.tobytes()
        if not header_flags & MAP_LIQUID_NO_HEIGHT:
            liquid += levels[min_y:min_y + rows, min_x:min_x + width].astype(np.float32).tobytes()

    header_size = 44
    area_ofs = header_size
    height_ofs = area_ofs + len(area)
    liquid_ofs = height_ofs + len(height) if liquid else 0
    header = b'MAPS' + struct.pack('<10I', 9, build, area_ofs, len(area), height_ofs, len(height),
                                   liquid_ofs, len(liquid), 0, 0)
    return header + area + height + liquid
