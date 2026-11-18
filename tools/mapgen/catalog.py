"""Catalogo de modelos M2 para montar recorridos (parkour): mide la colision de cada modelo del cliente.

Uso: py -I -B catalog.py --wow-data "D:\\Clientes de Wow\\Wow - copia\\Data" --filter "chair|table" [--out cat.csv]
     (--filter: expresion regular sobre la ruta; por defecto solo modelos de World\\...\\Doodads)

Por modelo (escala 1): triangulos de colision, caja de colision y la superficie pisable MAS ALTA: el nivel plano
(normal casi vertical) mas alto con area >= --min-area, con su altura, area y extension (largo x ancho). Un modelo
sin colision se atraviesa: no sirve como apoyo (puede servir de decoracion).
"""
import argparse
import csv
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import vmaps                    # noqa: E402
from mpq import MPQ             # noqa: E402

LISTFILE_MPQS = ['common.MPQ', 'common-2.MPQ', 'expansion.mpq', 'lichking.mpq', 'patch.mpq', 'patch-2.mpq',
                 'patch-3.MPQ']


def list_models(data_dir):
    names = set()
    for name in LISTFILE_MPQS:
        full = os.path.join(data_dir, name)
        if not os.path.exists(full):
            continue
        archive = MPQ(full)
        try:
            if archive.has('(listfile)'):
                for line in archive.read('(listfile)').decode('latin1').splitlines():
                    if line.lower().endswith('.m2'):
                        names.add(line.strip())
        finally:
            archive.close()
    return sorted(names)


class ClientFiles:
    """MPQ del cliente abiertos una vez (vmaps.read_client_file los abre en cada lectura: lento para miles)."""

    def __init__(self, data_dir):
        self.archives = [MPQ(os.path.join(data_dir, n)) for n in vmaps.CLIENT_MPQS
                         if os.path.exists(os.path.join(data_dir, n))]

    def read(self, path):
        for archive in self.archives:
            if archive.has(path):
                return archive.read(path)
        raise FileNotFoundError(path)


def walkable_levels(v, t, min_area=0.5):
    """[(altura, area, x0, y0, x1, y1)] de los niveles planos pisables, del mas alto al mas bajo."""
    if len(t) == 0:
        return []
    tri = v[t]
    nrm = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    ln = np.linalg.norm(nrm, axis=1)
    flat = np.abs(nrm[:, 2]) / np.maximum(ln, 1e-9) > 0.94
    if not flat.any():
        return []
    zc = np.round(tri[:, :, 2].mean(axis=1)[flat] * 5) / 5      # niveles cada 0,2 yardas
    area = ln[flat] / 2
    pts = tri[flat]
    out = []
    for z in np.unique(zc):
        sel = zc == z
        a = float(area[sel].sum())
        if a < min_area:
            continue
        p = pts[sel].reshape(-1, 3)
        out.append((float(z), a, float(p[:, 0].min()), float(p[:, 1].min()), float(p[:, 0].max()), float(p[:, 1].max())))
    return sorted(out, key=lambda r: -r[0])


def measure(data):
    v, t = vmaps.m2_collision(data)
    row = {'tris': len(t)}
    if len(t) == 0:
        return row
    lo, hi = v[t].reshape(-1, 3).min(axis=0), v[t].reshape(-1, 3).max(axis=0)
    row['box'] = [round(float(c), 2) for c in (*lo, *hi)]
    levels = walkable_levels(v, t)
    if levels:
        z, a, x0, y0, x1, y1 = levels[0]
        row.update(top=round(z, 2), area=round(a, 1), top_len=round(x1 - x0, 2), top_wid=round(y1 - y0, 2),
                   levels=len(levels))
    return row


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--wow-data', required=True)
    ap.add_argument('--filter', default='')
    ap.add_argument('--out')
    args = ap.parse_args()
    rx = re.compile(args.filter, re.I) if args.filter else None
    models = [m for m in list_models(args.wow_data) if 'doodads\\' in m.lower() and (not rx or rx.search(m))]
    files = ClientFiles(args.wow_data)
    rows = []
    for m in models:
        try:
            r = measure(files.read(m))
        except Exception as e:      # noqa: BLE001 - modelos raros: se anota y se sigue
            r = {'error': str(e)[:60]}
        r['model'] = m
        rows.append(r)
    cols = ['model', 'tris', 'top', 'area', 'top_len', 'top_wid', 'levels', 'box', 'error']
    out = open(args.out, 'w', newline='', encoding='utf-8') if args.out else sys.stdout
    w = csv.DictWriter(out, fieldnames=cols, extrasaction='ignore')
    w.writeheader()
    for r in rows:
        w.writerow(r)
    if args.out:
        out.close()
        print('%d modelos (%d con colision, %d con superficie pisable) -> %s'
              % (len(rows), sum(1 for r in rows if r.get('tris')), sum(1 for r in rows if 'top' in r), args.out))


if __name__ == '__main__':
    main()
