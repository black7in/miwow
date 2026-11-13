"""Lector minimo de archivos MPQ (formato v0/v1: mapas de Warcraft 3 y MPQ de WoW 3.3.5). Solo lectura.

Soporta tablas cifradas, sectores, cifrado de archivos y compresion zlib/bzip2 (lo que usan los .w3x/.w3m
guardados por el World Editor y los MPQ de WoW para los archivos de terreno). No soporta PKWARE implode ni
compresiones de audio.
"""
import bz2
import struct
import zlib


def _init_crypt():
    seed = 0x00100001
    table = [0] * 0x500
    for i in range(0x100):
        idx = i
        for _ in range(5):
            seed = (seed * 125 + 3) % 0x2AAAAB
            t1 = (seed & 0xFFFF) << 16
            seed = (seed * 125 + 3) % 0x2AAAAB
            t2 = seed & 0xFFFF
            table[idx] = t1 | t2
            idx += 0x100
    return table


_CRYPT = _init_crypt()


def hash_string(s, kind):
    seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
    for ch in s.upper().replace('/', '\\'):
        c = ord(ch)
        seed1 = (_CRYPT[(kind << 8) + c] ^ (seed1 + seed2)) & 0xFFFFFFFF
        seed2 = (c + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
    return seed1


def decrypt(data, key):
    seed = 0xEEEEEEEE
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    out = []
    for v in vals:
        seed = (seed + _CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        r = (v ^ (key + seed)) & 0xFFFFFFFF
        key = ((((~key) << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (r + seed + (seed << 5) + 3) & 0xFFFFFFFF
        out.append(r)
    return struct.pack('<%dI' % n, *out) + data[n * 4:]


F_IMPLODE = 0x100
F_COMPRESS = 0x200
F_ENCRYPTED = 0x10000
F_FIX_KEY = 0x20000
F_SINGLE = 0x1000000


class MPQ:
    def __init__(self, path):
        self.file = open(path, 'rb')
        off = 0
        while True:
            self.file.seek(off)
            if self.file.read(4) == b'MPQ\x1a':
                break
            off += 512
            if not self.file.read(1):
                raise ValueError('%s: cabecera MPQ no encontrada' % path)
        self.base = off
        self.file.seek(off)
        (_, _, _, _, sshift, htpos, btpos, htn, btn) = struct.unpack('<4sIIHHIIII', self.file.read(32))
        self.sector = 512 << sshift
        ht = decrypt(self._raw(htpos, htn * 16), hash_string('(hash table)', 3))
        bt = decrypt(self._raw(btpos, btn * 16), hash_string('(block table)', 3))
        self.hashes = [struct.unpack_from('<IIHHI', ht, i * 16) for i in range(htn)]
        self.blocks = [struct.unpack_from('<IIII', bt, i * 16) for i in range(btn)]

    def _raw(self, pos, size):
        self.file.seek(self.base + pos)
        return self.file.read(size)

    def close(self):
        self.file.close()

    def _find(self, name):
        n = len(self.hashes)
        if n == 0:
            return None
        start = hash_string(name, 0) % n
        a, b = hash_string(name, 1), hash_string(name, 2)
        i = start
        while True:
            h = self.hashes[i]
            if h[4] == 0xFFFFFFFF:
                return None
            if h[0] == a and h[1] == b and h[4] < len(self.blocks):
                blk = self.blocks[h[4]]
                return blk if blk[3] & 0x80000000 else None
            i = (i + 1) % n
            if i == start:
                return None

    def has(self, name):
        return self._find(name) is not None

    def read(self, name):
        blk = self._find(name)
        if blk is None:
            raise KeyError(name)
        pos, csize, fsize, flags = blk
        data = self._raw(pos, csize)
        key = 0
        if flags & F_ENCRYPTED:
            key = hash_string(name.replace('/', '\\').split('\\')[-1], 3)
            if flags & F_FIX_KEY:
                key = ((key + pos) ^ fsize) & 0xFFFFFFFF
        if flags & F_SINGLE:
            if flags & F_ENCRYPTED:
                data = decrypt(data, key)
            return self._decompress(data, fsize, flags)
        nsec = (fsize + self.sector - 1) // self.sector
        if not (flags & (F_COMPRESS | F_IMPLODE)):
            if flags & F_ENCRYPTED:
                return b''.join(decrypt(data[s * self.sector:(s + 1) * self.sector], (key + s) & 0xFFFFFFFF)
                                for s in range(nsec))[:fsize]
            return data[:fsize]
        table = data[:(nsec + 1) * 4]
        if flags & F_ENCRYPTED:
            table = decrypt(table, (key - 1) & 0xFFFFFFFF)
        offsets = struct.unpack('<%dI' % (nsec + 1), table)
        out = bytearray()
        for s in range(nsec):
            chunk = data[offsets[s]:offsets[s + 1]]
            if flags & F_ENCRYPTED:
                chunk = decrypt(chunk, (key + s) & 0xFFFFFFFF)
            out += self._decompress(chunk, min(self.sector, fsize - s * self.sector), flags)
        return bytes(out)

    @staticmethod
    def _decompress(chunk, want, flags):
        if len(chunk) >= want:
            return chunk[:want]
        if flags & F_IMPLODE:
            raise NotImplementedError('compresion PKWARE implode no soportada')
        mask, body = chunk[0], chunk[1:]
        if mask == 0x02:
            return zlib.decompress(body)
        if mask == 0x10:
            return bz2.decompress(body)
        raise NotImplementedError('compresion 0x%02x no soportada' % mask)
