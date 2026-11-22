"""Empaqueta una carpeta en un MPQ (formato v0, el que lee el cliente 3.3.5a y el wasm del cliente web).

Uso: py tools/mpqpack.py <carpeta> <salida.MPQ>

- Archivos por sectores de 4 KB comprimidos con zlib (si no ganan, se guardan tal cual), sin cifrar.
- Incluye "(listfile)" para que los editores de MPQ muestren los nombres.
- El cliente web cachea por TAMANO del MPQ (va en la URL de los bloques): si el nuevo saliera del mismo tamano que el
  anterior, se anade relleno a "MiWow-version.txt" hasta que cambie (docs/cliente-web.md, seccion 5).
- Despues de escribir, lo relee con tools/mapgen/mpq.py y compara archivo por archivo.
"""
import os
import struct
import sys
import time
import zlib

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'mapgen'))
from mpq import MPQ, _CRYPT, hash_string  # noqa: E402

SECTOR_SHIFT = 3                  # 512 << 3 = 4096
SECTOR = 512 << SECTOR_SHIFT
F_EXISTS = 0x80000000
F_COMPRESS = 0x200
VERSION_FILE = 'MiWow-version.txt'


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


def pack_file(raw):
    """Datos de un archivo en el MPQ: tabla de sectores + sectores (zlib o crudos)."""
    if not raw:
        return b'', F_EXISTS
    nsec = (len(raw) + SECTOR - 1) // SECTOR
    sectors = []
    for s in range(nsec):
        chunk = raw[s * SECTOR:(s + 1) * SECTOR]
        z = zlib.compress(chunk, 9)
        sectors.append(b'\x02' + z if len(z) + 1 < len(chunk) else chunk)
    offsets = [(nsec + 1) * 4]
    for sec in sectors:
        offsets.append(offsets[-1] + len(sec))
    return struct.pack('<%dI' % (nsec + 1), *offsets) + b''.join(sectors), F_EXISTS | F_COMPRESS


def collect(folder):
    files = []
    for root, _, names in os.walk(folder):
        for n in names:
            abs_path = os.path.join(root, n)
            rel = os.path.relpath(abs_path, folder).replace('/', '\\')
            if rel.lower() in ('(listfile)', '(attributes)', VERSION_FILE.lower()):
                continue
            with open(abs_path, 'rb') as f:
                files.append((rel, f.read()))
    files.sort(key=lambda x: x[0].lower())
    return files


def build(files):
    names = [n for n, _ in files] + ['(listfile)']
    listfile = ('\r\n'.join(names) + '\r\n').encode('utf-8')
    entries = files + [('(listfile)', listfile)]

    hcount = 16
    while hcount < len(entries) * 2:
        hcount *= 2

    body = bytearray()
    blocks = []
    for name, raw in entries:
        data, flags = pack_file(raw)
        blocks.append((32 + len(body), len(data), len(raw), flags))
        body += data

    hashes = [(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFF, 0xFFFF, 0xFFFFFFFF)] * hcount
    for bi, (name, _) in enumerate(entries):
        i = hash_string(name, 0) & (hcount - 1)
        while hashes[i][4] != 0xFFFFFFFF:
            i = (i + 1) & (hcount - 1)
        hashes[i] = (hash_string(name, 1), hash_string(name, 2), 0, 0, bi)

    ht = encrypt(b''.join(struct.pack('<IIHHI', *h) for h in hashes), hash_string('(hash table)', 3))
    bt = encrypt(b''.join(struct.pack('<IIII', *b) for b in blocks), hash_string('(block table)', 3))
    htpos = 32 + len(body)
    btpos = htpos + len(ht)
    total = btpos + len(bt)
    header = struct.pack('<4sIIHHIIII', b'MPQ\x1a', 32, total, 0, SECTOR_SHIFT, htpos, btpos, hcount, len(blocks))
    return header + bytes(body) + ht + bt


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    folder, out = sys.argv[1], sys.argv[2]
    files = collect(folder)
    old_size = os.path.getsize(out) if os.path.exists(out) else -1

    stamp = time.strftime('MiWow patch-4 %Y-%m-%d %H:%M:%S\r\n')
    pad = 0
    while True:
        version = (stamp + ' ' * pad).encode('ascii')
        data = build(files + [(VERSION_FILE, version)])
        if len(data) != old_size:
            break
        pad += 1

    tmp = out + '.tmp'
    with open(tmp, 'wb') as f:
        f.write(data)

    check = MPQ(tmp)
    try:
        for name, raw in files:
            if check.read(name) != raw:
                raise SystemExit('ERROR: %s no coincide al releer el MPQ' % name)
    finally:
        check.close()
    os.replace(tmp, out)
    print('%s: %d archivos, %d bytes (antes %s)' % (out, len(files), len(data), old_size if old_size >= 0 else '-'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
