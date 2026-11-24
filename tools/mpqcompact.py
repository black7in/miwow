"""Compacta los MPQ de Data/ del cliente 3.3.5a: quita los archivos que un MPQ posterior sustituye.

El cliente lee los MPQ en orden y el ultimo que tiene un archivo gana; las copias de los anteriores son datos muertos.
Solo se borra un archivo si un MPQ POSTERIOR de la lista (que se queda) tiene una copia real (tamano > 0 y sin marca
de borrado): el archivo que ve el cliente no cambia. Los MPQ de locale (Data/<locale>) no se tocan y nuestro
patch-4.MPQ no cuenta (cambia en cada version).

Reconstruye cada MPQ copiando los bloques comprimidos tal cual (sin recomprimir): misma tabla hash (mismo tamano y
posiciones; las entradas de lo borrado pasan a "borrada"), tabla de bloques compacta, (listfile) sin los nombres
borrados y (attributes) reindexado. Solo MPQ v0/v1 < 4 GB sin cifrado (los de WoW 3.3.5).

Uso:
  python3 mpqcompact.py <Data> --simular          cuanto se ganaria
  python3 mpqcompact.py <Data> <Salida>           escribe los MPQ compactados en <Salida> y los comprueba
  python3 mpqcompact.py <Data> <Salida> --verificar   solo la comprobacion (lo que ve el cliente, byte a byte)
Los originales no se tocan; despues, a mano: mover los de <Salida> a <Data>.
Los MPQ sin nada que quitar no se escriben (se quedan los originales).
"""
import hashlib
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mapgen'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mpq import MPQ, hash_string, _CRYPT  # noqa: E402

ORDER = ['common.MPQ', 'common-2.MPQ', 'expansion.MPQ', 'lichking.MPQ', 'patch.MPQ', 'patch-2.MPQ', 'patch-3.MPQ']
F_EXISTS = 0x80000000
F_ENCRYPTED = 0x10000
F_DELETE = 0x2000000
HASH_FREE, HASH_DELETED = 0xFFFFFFFF, 0xFFFFFFFE
LISTFILE, ATTRIBUTES, SIGNATURE = '(listfile)', '(attributes)', '(signature)'
KEY = {n: (hash_string(n, 1), hash_string(n, 2)) for n in (LISTFILE, ATTRIBUTES, SIGNATURE)}
CHUNK = 64 << 20


def encrypt(data, key):
    seed = 0xEEEEEEEE
    n = len(data) // 4
    vals = struct.unpack('<%dI' % n, data[:n * 4])
    out = []
    for v in vals:
        seed = (seed + _CRYPT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
        out.append((v ^ (key + seed)) & 0xFFFFFFFF)
        key = ((((~key) << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
        seed = (v + seed + (seed << 5) + 3) & 0xFFFFFFFF
    return struct.pack('<%dI' % n, *out) + data[n * 4:]


def open_mpq(path):
    m = MPQ(path)
    m.file.seek(m.base)
    hdr = m.file.read(44)
    magic, hsize, asize, ver = struct.unpack_from('<4sIIH', hdr)
    if m.base != 0 or ver > 1 or (ver == 1 and struct.unpack_from('<QHH', hdr, 32) != (0, 0, 0)):
        raise SystemExit('%s: formato no soportado (base %d, version %d, tabla alta)' % (path, m.base, ver))
    m.hsize = hsize
    return m


def entries(m):
    """(hashA, hashB, locale) -> bloque, solo archivos que existen (sin los especiales)."""
    out = {}
    for (ha, hb, loc, plat, bi) in m.hashes:
        if bi >= len(m.blocks) or not m.blocks[bi][3] & F_EXISTS:
            continue
        if (ha, hb) in KEY.values():
            continue
        out[(ha, hb, loc)] = m.blocks[bi]
    return out


def real(blk):
    return blk[2] > 0 and not blk[3] & F_DELETE


def dead_keys(data_dir):
    """MPQ -> claves muertas (las sustituye un MPQ posterior con una copia real)."""
    inv = [(a, entries(open_mpq(os.path.join(data_dir, a)))) for a in ORDER]
    result = {}
    for i, (a, ent) in enumerate(inv):
        later = [e for _, e in inv[i + 1:]]
        result[a] = {k for k in ent if any(k in e and real(e[k]) for e in later)}
    return inv, result


def copy_range(src, dst, pos, size, md5=None):
    src.seek(pos)
    while size:
        b = src.read(min(CHUNK, size))
        if not b:
            raise IOError('archivo truncado')
        dst.write(b)
        if md5:
            md5.update(b)
        size -= len(b)


def read_special(m, name):
    try:
        return m.read(name) if m.has(name) else None
    except Exception as e:  # compresion no soportada, etc.
        print('   aviso: no se pudo leer %s (%s): se quita' % (name, e))
        return None


def compact(path, dead, out_path):
    m = open_mpq(path)
    if any(b[3] & F_ENCRYPTED for b in m.blocks if b[3] & F_EXISTS):
        raise SystemExit('%s: tiene archivos cifrados (no soportado)' % path)
    n_hash = len(m.hashes)
    hashes = [list(h) for h in m.hashes]
    special = {}
    # 1) quitar de la tabla hash lo muerto y los especiales (se reescriben al final)
    for h in hashes:
        if h[4] >= len(m.blocks):
            continue
        k = (h[0], h[1])
        if k in KEY.values():
            special[k] = h
            h[4] = HASH_DELETED
            h[0] = h[1] = 0xFFFFFFFF
            h[2] = h[3] = 0xFFFF
        elif (h[0], h[1], h[2]) in dead:
            h[4] = HASH_DELETED
            h[0] = h[1] = 0xFFFFFFFF
            h[2] = h[3] = 0xFFFF
    keep = sorted({h[4] for h in hashes if h[4] < len(m.blocks)}, key=lambda bi: m.blocks[bi][0])
    old_attr = read_special(m, ATTRIBUTES)
    old_list = read_special(m, LISTFILE)

    new_index = {}
    new_blocks = []
    with open(out_path, 'wb') as out:
        out.write(b'\0' * m.hsize)
        for bi in keep:
            pos, csize, fsize, flags = m.blocks[bi]
            new_index[bi] = len(new_blocks)
            new_blocks.append([out.tell(), csize, fsize, flags])
            copy_range(m.file, out, pos, csize)
        # 2) (listfile) sin los nombres borrados
        alive = {(h[0], h[1]) for h in hashes if h[4] < len(m.blocks)}
        extra = []
        if old_list is not None:
            names = [n.strip() for n in old_list.decode('latin-1').replace('\r', '\n').split('\n')]
            kept = [n for n in names if n and (hash_string(n, 1), hash_string(n, 2)) in alive]
            extra.append((LISTFILE, ('\r\n'.join(kept) + '\r\n').encode('latin-1')))
        # 3) (attributes) reindexado (CRC32 / fecha / MD5 por bloque); cero para los especiales nuevos
        if old_attr is not None and len(old_attr) >= 8:
            ver, aflags = struct.unpack_from('<II', old_attr)
            nb_old = len(m.blocks)
            off = 8
            cols = []
            for bit, width in ((1, 4), (2, 8), (4, 16)):
                if aflags & bit:
                    cols.append((width, old_attr[off:off + width * nb_old]))
                    off += width * nb_old
            ok = off <= len(old_attr) and ver == 100
            if not ok:
                print('   aviso: (attributes) con formato inesperado: se quita')
            else:
                total = len(new_blocks) + len(extra) + 1
                body = struct.pack('<II', ver, aflags & 7)
                for width, col in cols:
                    vals = [col[bi * width:(bi + 1) * width] for bi in keep]
                    vals += [b'\0' * width] * (total - len(keep))
                    body += b''.join(vals)
                extra.append((ATTRIBUTES, body))
        # 4) indices de bloque nuevos (antes de anadir los especiales)
        for h in hashes:
            if h[4] < len(m.blocks):
                h[4] = new_index[h[4]]
        for name, data in extra:
            h = special.get(KEY[name])
            bi = len(new_blocks)
            new_blocks.append([out.tell(), len(data), len(data), F_EXISTS])
            out.write(data)
            slot = place(hashes, name)
            hashes[slot][:] = [KEY[name][0], KEY[name][1], h[2] if h else 0, h[3] if h else 0, bi]
        # 5) tablas
        ht_pos = out.tell()
        ht = b''.join(struct.pack('<IIHHI', *h) for h in hashes)
        out.write(encrypt(ht, hash_string('(hash table)', 3)))
        bt_pos = out.tell()
        bt = b''.join(struct.pack('<IIII', *b) for b in new_blocks)
        out.write(encrypt(bt, hash_string('(block table)', 3)))
        size = out.tell()
        out.seek(0)
        m.file.seek(0)
        hdr = bytearray(m.file.read(m.hsize))   # 0 firma, 4 tamano cabecera, 12 version, 14 sector: intactos
        struct.pack_into('<I', hdr, 8, size)
        struct.pack_into('<II', hdr, 16, ht_pos, bt_pos)
        struct.pack_into('<II', hdr, 24, n_hash, len(new_blocks))
        out.write(hdr)
    m.close()
    return out_path, len(keep), size


def place(hashes, name):
    """Hueco libre o borrado para un nombre nuevo (sondeo lineal desde su posicion)."""
    n = len(hashes)
    i = start = hash_string(name, 0) % n
    while True:
        if hashes[i][4] in (HASH_FREE, HASH_DELETED):
            return i
        i = (i + 1) % n
        if i == start:
            raise SystemExit('tabla hash llena')


def raw_md5(m, blk):
    md5 = hashlib.md5()

    class Sink:
        def write(self, b):
            pass
    copy_range(m.file, Sink(), blk[0], blk[1], md5)
    return md5.hexdigest()


def verify(data_dir, out_dir):
    """Lo que ve el cliente (ganador de cada archivo) es identico antes y despues, byte a byte (datos crudos)."""
    old = [(a, open_mpq(os.path.join(data_dir, a))) for a in ORDER]
    new = [(a, open_mpq(os.path.join(out_dir, a)) if os.path.exists(os.path.join(out_dir, a))
            else open_mpq(os.path.join(data_dir, a))) for a in ORDER]

    def winners(arcs):
        w = {}
        for a, m in arcs:
            for k, blk in entries(m).items():
                w[k] = (a, m, blk)
        return w
    wo, wn = winners(old), winners(new)
    bad = 0
    if set(wo) != set(wn):
        print('DISTINTO conjunto de archivos: solo antes %d, solo despues %d' % (len(set(wo) - set(wn)), len(set(wn) - set(wo))))
        bad += 1
    checked = 0
    total = len(wo)
    for k, (a, m, blk) in wo.items():
        if k not in wn:
            continue
        a2, m2, blk2 = wn[k]
        if a != a2 or blk[1:] != blk2[1:] or raw_md5(m, blk) != raw_md5(m2, blk2):
            bad += 1
            if bad < 20:
                print('  DISTINTO %08x%08x loc %04x: %s %s -> %s %s' % (k[0], k[1], k[2], a, blk[1:], a2, blk2[1:]))
        checked += 1
        if checked % 20000 == 0:
            print('  ... %d / %d' % (checked, total))
    # los especiales nuevos se leen bien
    for a, m in new:
        for name in (LISTFILE, ATTRIBUTES):
            if m.has(name):
                m.read(name)
    print('verificados %d archivos (ganadores): %s' % (checked, 'OK' if not bad else '%d ERRORES' % bad))
    return bad == 0


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    data_dir = args[0]
    out_dir = args[1] if len(args) > 1 else None
    if '--verificar' in sys.argv:
        sys.exit(0 if verify(data_dir, out_dir) else 1)
    inv, dead = dead_keys(data_dir)
    total = 0
    for a, ent in inv:
        d = dead[a]
        saved = sum(ent[k][1] for k in d)
        total += saved
        print('%-14s archivos %6d  muertos %6d  %.2f GB' % (a, len(ent), len(d), saved / 2 ** 30))
    print('total ~%.2f GB' % (total / 2 ** 30))
    if '--simular' in sys.argv or not out_dir:
        return
    if os.path.abspath(out_dir) == os.path.abspath(data_dir):
        raise SystemExit('la salida debe ser otra carpeta')
    os.makedirs(out_dir, exist_ok=True)
    for a, _ in inv:
        if not dead[a]:
            print('%s: nada que quitar' % a)
            continue
        p = os.path.join(data_dir, a)
        before = os.path.getsize(p)
        out, nb, size = compact(p, dead[a], os.path.join(out_dir, a))
        print('%s: %.2f -> %.2f GB (%d bloques) -> %s' % (a, before / 2 ** 30, size / 2 ** 30, nb, out))
    sys.exit(0 if verify(data_dir, out_dir) else 1)


if __name__ == '__main__':
    main()
