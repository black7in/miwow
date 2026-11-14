"""Lectura de mapas de Warcraft 3 (.w3m / .w3x, RoC y TFT 1.26): terreno, regiones, puntos de inicio, decoracion.

Formatos: war3map.w3e (terreno), war3map.w3r (regiones), war3mapUnits.doo (unidades: solo se usan los puntos de
inicio 'sloc'), war3map.doo (decoracion). Coordenadas en unidades de WC3 (128 por casilla).
"""
import struct

import numpy as np

from mpq import MPQ

FLAG_RAMP = 0x10
FLAG_BLIGHT = 0x20
FLAG_WATER = 0x40
FLAG_BOUNDARY = 0x80

TILE_UNITS = 128.0
WATER_OFFSET = 89.6  # la superficie del agua se dibuja 89.6 unidades por debajo de su nivel nominal


class Reader:
    def __init__(self, data):
        self.data = data
        self.pos = 0

    def unpack(self, fmt):
        values = struct.unpack_from('<' + fmt, self.data, self.pos)
        self.pos += struct.calcsize('<' + fmt)
        return values if len(values) > 1 else values[0]

    def id4(self):
        value = self.data[self.pos:self.pos + 4].decode('latin1')
        self.pos += 4
        return value

    def cstring(self):
        end = self.data.index(b'\0', self.pos)
        value = self.data[self.pos:end].decode('utf8', 'replace')
        self.pos = end + 1
        return value

    def remaining(self):
        return len(self.data) - self.pos


class Terrain:
    """war3map.w3e. Los arrays son [y][x] (y = sur -> norte, x = oeste -> este), uno por vertice de casilla."""

    def __init__(self, data):
        r = Reader(data)
        if r.id4() != 'W3E!':
            raise ValueError('war3map.w3e: cabecera invalida')
        self.version = r.unpack('i')
        self.tileset = r.data[r.pos:r.pos + 1].decode('latin1')
        r.pos += 1
        r.unpack('i')  # tilesets personalizados
        self.ground = [r.id4() for _ in range(r.unpack('i'))]
        self.cliffs = [r.id4() for _ in range(r.unpack('i'))]
        self.width, self.height = r.unpack('ii')
        self.offset_x, self.offset_y = r.unpack('ff')
        n = self.width * self.height
        raw = np.frombuffer(data, dtype=np.dtype([('h', '<i2'), ('w', '<i2'), ('f', 'u1'), ('d', 'u1'), ('c', 'u1')]),
                            count=n, offset=r.pos).reshape(self.height, self.width)
        self.ground_height = raw['h'].astype(np.float64)                 # 0x2000 = nivel 0
        water = raw['w'].astype(np.int32) & 0xFFFF
        self.water_level = (water & 0x3FFF).astype(np.float64)
        self.flags = (raw['f'] & 0xF0).astype(np.int32)
        self.boundary = ((water & 0x4000) != 0) | ((self.flags & FLAG_BOUNDARY) != 0)
        # La ultima fila/columna de vertices no lleva la marca de borde: el perimetro siempre es borde
        self.boundary[[0, -1], :] = True
        self.boundary[:, [0, -1]] = True
        self.texture = (raw['f'] & 0x0F).astype(np.int32)
        self.layer = (raw['c'] & 0x0F).astype(np.int32)
        self.cliff_texture = (raw['c'] >> 4).astype(np.int32)

    def center(self):
        return (self.offset_x + (self.width - 1) * TILE_UNITS / 2,
                self.offset_y + (self.height - 1) * TILE_UNITS / 2)


class Region:
    def __init__(self, name, left, bottom, right, top):
        self.name, self.left, self.bottom, self.right, self.top = name, left, bottom, right, top

    def center(self):
        return (self.left + self.right) / 2, (self.bottom + self.top) / 2


def read_regions(data):
    r = Reader(data)
    r.unpack('i')  # version
    regions = []
    for _ in range(r.unpack('i')):
        left, bottom, right, top = r.unpack('ffff')
        name = r.cstring()
        r.unpack('i')       # indice
        r.id4()             # clima
        r.cstring()         # sonido ambiental
        r.pos += 4          # color BGR + 0xFF
        regions.append(Region(name, left, bottom, right, top))
    return regions


class Placed:
    """Unidad o decoracion colocada: tipo, variacion, posicion (unidades WC3), angulo (radianes), escala."""

    def __init__(self, kind, variation, x, y, z, angle, scale, player=-1):
        self.kind, self.variation, self.x, self.y, self.z = kind, variation, x, y, z
        self.angle, self.scale, self.player = angle, scale, player


def _skip_item_sets(r):
    for _ in range(r.unpack('i')):
        for _ in range(r.unpack('i')):
            r.pos += 8  # id + probabilidad


def read_units(data):
    """war3mapUnits.doo (v7 RoC / v8 TFT)."""
    r = Reader(data)
    if r.id4() != 'W3do':
        raise ValueError('war3mapUnits.doo: cabecera invalida')
    version = r.unpack('i')
    r.unpack('i')  # subversion
    tft = version >= 8
    units = []
    for _ in range(r.unpack('i')):
        kind = r.id4()
        variation = r.unpack('i')
        x, y, z = r.unpack('fff')
        angle = r.unpack('f')
        sx, _, _ = r.unpack('fff')
        r.pos += 1                      # flags
        player = r.unpack('i')
        r.pos += 2                      # desconocido
        r.pos += 8                      # vida, mana
        if tft:
            r.pos += 4                  # tabla de objetos
        _skip_item_sets(r)
        r.pos += 4 + 4 + 4              # oro, adquisicion de objetivo, nivel de heroe
        if tft:
            r.pos += 12                 # fuerza, agilidad, inteligencia
            count = r.unpack('i')
            r.pos += 8 * count          # inventario (casilla, id)
        count = r.unpack('i')
        r.pos += 12 * count             # habilidades (id, activa, nivel)
        random = r.unpack('i')
        if random == 0:
            r.pos += 4
        elif random == 1:
            r.pos += 8
        elif random == 2:
            count = r.unpack('i')
            r.pos += 8 * count
        # color, puerta de paso, numero de creacion (v7 RoC 1.26: un entero mas, comprobado con un .w3m)
        r.pos += 12 if tft else 16
        units.append(Placed(kind, variation, x, y, z, angle, sx, player))
    if r.remaining() != 0:
        print('AVISO: war3mapUnits.doo: %d bytes sin leer (formato no reconocido del todo)' % r.remaining())
    return units


def read_doodads(data):
    """war3map.doo (v7 RoC / v8 TFT). Solo la lista principal (no los 'special doodads')."""
    r = Reader(data)
    if r.id4() != 'W3do':
        raise ValueError('war3map.doo: cabecera invalida')
    version = r.unpack('i')
    r.unpack('i')
    tft = version >= 8
    doodads = []
    for _ in range(r.unpack('i')):
        kind = r.id4()
        variation = r.unpack('i')
        x, y, z = r.unpack('fff')
        angle = r.unpack('f')
        sx, _, _ = r.unpack('fff')
        r.pos += 2                      # flags, vida
        if tft:
            r.pos += 4
            _skip_item_sets(r)
        r.pos += 4                      # numero de creacion
        doodads.append(Placed(kind, variation, x, y, z, angle, sx))
    return doodads


def _optional(archive, name, reader):
    if not archive.has(name):
        return []
    try:
        return reader(archive.read(name))
    except Exception as error:  # noqa: BLE001 - formato de otra version del editor
        print('AVISO: %s no se pudo leer (%s); se ignora' % (name, error))
        return []


class Wc3Map:
    def __init__(self, path):
        archive = MPQ(path)
        try:
            self.terrain = Terrain(archive.read('war3map.w3e'))
            self.regions = read_regions(archive.read('war3map.w3r')) if archive.has('war3map.w3r') else []
            # Unidades y decoracion son opcionales: si el formato no se reconoce se avisa y se sigue con el terreno
            self.units = _optional(archive, 'war3mapUnits.doo', read_units)
            self.doodads = _optional(archive, 'war3map.doo', read_doodads)
        finally:
            archive.close()

    def start_locations(self):
        return [u for u in self.units if u.kind == 'sloc']
