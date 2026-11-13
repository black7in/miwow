"""Depuracion: muestra la estructura de un ADT o WDT de WoW 3.3.5 (chunks, MHDR, primer MCNK, MH2O, texturas).

  py tools\\mapgen\\inspect_adt.py archivo.adt [indice_mcnk]
"""
import struct
import sys


def chunks(data, start=0, end=None):
    end = len(data) if end is None else end
    pos = start
    while pos + 8 <= end:
        magic = data[pos:pos + 4][::-1].decode('latin1')
        size, = struct.unpack_from('<I', data, pos + 4)
        yield magic, pos, size
        pos += 8 + size + (13 if magic == 'MCNR' else 0)  # relleno de MCNR fuera de su tamano


def strings(blob):
    return [s.decode('latin1') for s in blob.split(b'\0') if s]


def main():
    data = open(sys.argv[1], 'rb').read()
    want = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    mcnk_index = 0
    for magic, pos, size in chunks(data):
        if magic == 'MCNK':
            if mcnk_index == want:
                print('MCNK #%d @%d size %d' % (mcnk_index, pos, size))
                hdr = struct.unpack_from('<20I', data, pos + 8)
                names = ['flags', 'ix', 'iy', 'nLayers', 'nDoodadRefs', 'ofsMCVT', 'ofsMCNR', 'ofsMCLY', 'ofsMCRF',
                         'ofsMCAL', 'sizeMCAL', 'ofsMCSH', 'sizeMCSH', 'areaid', 'nMapObjRefs', 'holes',
                         'lq0', 'lq1', 'lq2', 'lq3']
                print('  ', dict(zip(names, hdr)))
                rest = struct.unpack_from('<IIIIII3fIII', data, pos + 8 + 80)
                print('   predTex,noEffDood,ofsMCSE,nSnd,ofsMCLQ,sizeMCLQ =', rest[:6], 'pos =', rest[6:9],
                      'ofsMCCV,MCLV,unused =', rest[9:])
                for m2, p2, s2 in chunks(data, pos + 8 + 128, pos + 8 + size):
                    print('    %s @+%d size %d' % (m2, p2 - pos, s2))
                    if m2 == 'MCLY':
                        for i in range(s2 // 16):
                            print('      layer', struct.unpack_from('<4I', data, p2 + 8 + i * 16))
                    if m2 == 'MCNR':
                        print('      first normals', struct.unpack_from('<9b', data, p2 + 8))
            mcnk_index += 1
            continue
        print('%s @%d size %d' % (magic, pos, size))
        if magic == 'MHDR':
            print('  ', struct.unpack_from('<16I', data, pos + 8))
        elif magic == 'MPHD':
            print('  ', struct.unpack_from('<8I', data, pos + 8))
        elif magic in ('MTEX', 'MMDX', 'MWMO'):
            for s in strings(data[pos + 8:pos + 8 + size])[:40]:
                print('   ', s)
        elif magic == 'MCIN':
            print('   first', struct.unpack_from('<8I', data, pos + 8))
        elif magic == 'MH2O':
            base = pos + 8
            for c in range(256):
                ofs_inst, layers, ofs_attr = struct.unpack_from('<3I', data, base + c * 12)
                if layers:
                    inst = struct.unpack_from('<HHffBBBBII', data, base + ofs_inst)
                    print('   chunk %d layers %d attr@%d inst %s' % (c, layers, ofs_attr, inst))
                    if ofs_attr:
                        print('     attrs', struct.unpack_from('<QQ', data, base + ofs_attr))
                    break
    print('MCNK total', mcnk_index)


if __name__ == '__main__':
    main()
