"""Texturas del HUD tactil del cliente web (aspecto MiWow sobre la logica de Last Havens).

Uso: py -I tools/touchui/gen_touchui.py [--preview carpeta]

Escribe BLP2 paletizados (256 colores + alfa de 8 bits, con mipmaps) en client/src/Interface/TouchUI/:
  DragonUI/forever_circle_lh.blp  anillo de TODOS los botones (su Lua lo carga con SetTexCoord 0.5 +- 0.667:
                                  la textura ocupa el 75 % central del cuadro -> el borde debe ser transparente)
  PadDisc.blp                     disco blanco (puntos de la cuenta atras de cinematicas)
  MiWow/disc.blp                  fondo de boton (sustituye a UI-Minimap-Background en el HUD)
  MiWow/well.blp, MiWow/knob.blp  base y bola del joystick
  MiWow/jump.blp                  icono de saltar (pictograma dorado, figura en salto lateral; elegido por el usuario)
  MiWow/s_<estado>.blp            iconos del boton inteligente (objetivo, atacar, saquear, hablar...)
  MiWow/u_<nombre>.blp            resto de botones fijos (objetivo amigo, correr, montar, menu, chat...)
  MiWow/m_<nombre>.blp            botones del menu (personaje, hechizos, talentos...)
Con --preview guarda tambien los PNG para revisarlos. MiWowTouchSkin.lua (FrameXML) los aplica.
"""
import math
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'client', 'src', 'Interface', 'TouchUI')
SS = 4  # supermuestreo

GOLD_HI = (255, 236, 150)
GOLD = (255, 213, 53)
GOLD_LO = (248, 177, 0)


# --- BLP2 paletizado -------------------------------------------------------------------------------------------

def _mips(img):
    out = [img]
    while max(out[-1].size) > 1:
        w, h = out[-1].size
        out.append(out[-1].resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS))
    return out


def write_blp(img, path):
    """img RGBA (lado potencia de 2). Paleta comun a todos los mipmaps; alfa de 8 bits aparte."""
    img = img.convert('RGBA')
    mips = _mips(img)
    rgb = img.convert('RGB')
    pal_img = rgb.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    palette = pal_img.getpalette()[:768]
    palette += [0] * (768 - len(palette))
    data, offsets, sizes = b'', [], []
    pos = 1172
    for m in mips:
        idx = m.convert('RGB').quantize(palette=pal_img, dither=Image.Dither.NONE).tobytes()
        alpha = m.getchannel('A').tobytes()
        chunk = idx + alpha
        offsets.append(pos)
        sizes.append(len(chunk))
        data += chunk
        pos += len(chunk)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    pal = b''.join(struct.pack('<BBBB', palette[i * 3 + 2], palette[i * 3 + 1], palette[i * 3], 0) for i in range(256))
    w, h = img.size
    header = b'BLP2' + struct.pack('<IBBBBII', 1, 1, 8, 8, 1, w, h)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(header + struct.pack('<16I', *offsets) + struct.pack('<16I', *sizes) + pal + data)


# --- utilidades de dibujo --------------------------------------------------------------------------------------

def field(size):
    """Distancia al centro (en pixeles de la imagen final) y coordenada vertical normalizada -1..1."""
    n = size * SS
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    c = (n - 1) / 2
    r = np.hypot(x - c, y - c) / SS
    v = (y - c) / c
    return r, v


def smooth(edge, r, width=0.8):
    return np.clip((edge - r) / width + 0.5, 0, 1)


def to_img(rgb, a, size):
    arr = np.dstack([np.clip(rgb, 0, 255), np.clip(a, 0, 1) * 255]).astype(np.uint8)
    return Image.fromarray(arr, 'RGBA').resize((size, size), Image.LANCZOS)


def lerp(c1, c2, t):
    t = np.clip(t, 0, 1)[..., None]
    return np.array(c1, np.float32) * (1 - t) + np.array(c2, np.float32) * t


def over(dst_rgb, dst_a, src_rgb, src_a):
    a = src_a + dst_a * (1 - src_a)
    rgb = (src_rgb * src_a[..., None] + dst_rgb * (dst_a * (1 - src_a))[..., None]) / np.maximum(a, 1e-6)[..., None]
    return rgb, a


# --- texturas --------------------------------------------------------------------------------------------------

def ring():
    """Anillo dorado fino con sombra. Radio del boton en esta textura = 128 * 18 / 43.5 = 53 px."""
    size = 128
    r, v = field(size)
    shadow = np.clip(1 - np.abs(r - 53) / 7, 0, 1) ** 2 * 0.55
    rgb = np.zeros(r.shape + (3,), np.float32)
    a = shadow
    band = smooth(55, r) * (1 - smooth(49.5, r))
    col = lerp(GOLD_HI, GOLD_LO, (v + 1) / 2)
    rgb, a = over(rgb, a, col, band * 0.95)
    inner = smooth(50, r) * (1 - smooth(48.6, r))
    rgb, a = over(rgb, a, np.zeros_like(col) + 10, inner * 0.6)
    return to_img(rgb, a, size)


def disc():
    size = 128
    r, v = field(size)
    t = np.clip(np.hypot((r / 62), v * 0.0) , 0, 1)
    col = lerp((58, 49, 37), (16, 13, 10), (v + 1) / 2 * 0.6 + r / 62 * 0.4)
    a = smooth(63, r) * 0.9
    hi = np.clip(1 - np.abs(r - 58) / 3, 0, 1) * np.clip(-v, 0, 1) * 0.35
    rgb, a = over(col, a, np.zeros_like(col) + 255, hi * smooth(63, r))
    return to_img(rgb, a, size)


def white_disc():
    size = 32
    r, _ = field(size)
    a = smooth(14.5, r, 1.2)
    return to_img(np.zeros(r.shape + (3,)) + 255, a, size)


def pill(edge_only=False):
    """Pastilla blanca 128x32 (extremos redondos) para teñir con SetVertexColor: fondo o solo el borde."""
    w, h, rad = 128, 32, 15.0
    y, x = np.mgrid[0:h, 0:w].astype(float) + 0.5
    cx = np.clip(x, rad + 1, w - rad - 1)
    d = np.hypot(x - cx, y - h / 2)
    a = smooth(rad, d, 1.0)
    if edge_only:
        a = a * (1 - smooth(rad - 1.6, d, 1.0))
    rgb = np.zeros((h, w, 3)) + 255
    img = Image.fromarray(np.dstack([rgb, a * 255]).astype(np.uint8), 'RGBA')
    return img


def _square_dist(size, half, rad):
    """Distancia con signo al borde de un cuadrado redondeado centrado (lado 2*half, esquinas de radio rad)."""
    y, x = np.mgrid[0:size, 0:size].astype(float) + 0.5
    qx = np.abs(x - size / 2) - (half - rad)
    qy = np.abs(y - size / 2) - (half - rad)
    out = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0)
    return out - rad, y


def slot():
    """Casilla de bolsa 64x64: cuadrado redondeado oscuro con borde dorado tenue."""
    size = 64
    d, y = _square_dist(size, 30.5, 8)
    a = smooth(0, d, 1.0)
    col = lerp((40, 34, 27), (17, 14, 11), y / size)
    edge = a * (1 - smooth(0, d + 2.0, 1.0)) * 0.45
    rgb, a2 = over(col, a * 0.92, np.zeros_like(col) + (255, 213, 53), edge)
    return to_img(rgb, a2, size)


def slot_edge():
    """Borde blanco de casilla (para teñir con el color de la calidad del objeto)."""
    size = 64
    d, _ = _square_dist(size, 30.5, 8)
    a = smooth(0, d, 1.0) * (1 - smooth(0, d + 3.0, 1.0))
    return to_img(np.zeros(d.shape + (3,)) + 255, a, size)


def well():
    size = 256
    r, v = field(size)
    rgb = np.zeros(r.shape + (3,), np.float32) + 12
    a = smooth(122, r) * 0.6
    band = smooth(122, r) * (1 - smooth(117, r))
    rgb, a = over(rgb, a, lerp(GOLD_HI, GOLD_LO, (v + 1) / 2), band * 0.7)
    return to_img(rgb, a, size)


def knob():
    size = 128
    r, v = field(size)
    y, x = np.mgrid[0:size * SS, 0:size * SS].astype(np.float32)
    c = (size * SS - 1) / 2
    hl = np.hypot(x - c * 0.7, y - c * 0.6) / SS / 60
    col = lerp((255, 248, 205), GOLD, hl * 1.6)
    col = lerp(col, GOLD_LO, np.clip(hl * 1.6 - 1, 0, 1) * 2)
    edge = np.clip((r - 50) / 10, 0, 1)
    col = lerp(col, (176, 116, 0), edge * 0.7)
    a = smooth(60, r)
    glow = np.clip(1 - (r - 60) / 4, 0, 1) * (1 - smooth(60, r)) * 0.4
    rgb, a = over(np.zeros_like(col) + np.array(GOLD), glow, col, a)
    return to_img(rgb, a, size)


ERASE = 0  # color de "borrar" en los pictogramas (recorta huecos en lo ya pintado)


class _Pen:
    """Primitivas de dibujo en una rejilla de 24 x 24 (como los iconos de linea)."""

    def __init__(self, d, k, off):
        self.d, self.k, self.off = d, k, off

    def P(self, x, y):
        return (self.off + x * self.k, self.off + y * self.k)

    def line(self, *pts, width=3.0, fill=255):
        w = int(width * self.k)
        q = [self.P(*p) for p in pts]
        self.d.line(q, fill=fill, width=w, joint='curve')
        for p in q:
            self.d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=fill)

    def dot(self, x, y, r, fill=255):
        self.d.ellipse([self.P(x - r, y - r), self.P(x + r, y + r)], fill=fill)

    def ell(self, x0, y0, x1, y1, fill=255):
        self.d.ellipse([self.P(x0, y0), self.P(x1, y1)], fill=fill)

    def poly(self, *pts, fill=255):
        self.d.polygon([self.P(*p) for p in pts], fill=fill)

    def rrect(self, x0, y0, x1, y1, r, fill=255):
        self.d.rounded_rectangle([self.P(x0, y0), self.P(x1, y1)], radius=r * self.k, fill=fill)

    def chord(self, x0, y0, x1, y1, a0, a1, fill=255):
        self.d.chord([self.P(x0, y0), self.P(x1, y1)], a0, a1, fill=fill)

    def leaf(self, x, y, length, ang, width, fill=255):
        a = math.radians(ang)
        ux, uy = math.cos(a), -math.sin(a)
        px, py = -uy, ux
        side = []
        for i in range(21):
            t = i / 20
            h = width * math.sin(math.pi * t)
            side.append((x + ux * length * t, y + uy * length * t, h))
        pts = [(cx + px * h, cy + py * h) for cx, cy, h in side] + [(cx - px * h, cy - py * h) for cx, cy, h in reversed(side)]
        self.poly(*pts, fill=fill)


def pictogram(draw_fn, size=64, mirror=False):
    """Pictograma dorado macizo (degradado vertical como el anillo) con sombra suave."""
    n = size * 8
    mask = Image.new('L', (n, n), 0)
    draw_fn(_Pen(ImageDraw.Draw(mask), n / 24 * 0.92, n * 0.04))
    if mirror:
        mask = mask.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.array(mask, np.float32) / 255
    sh = np.roll(np.array(mask.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255 * 0.8, 8, axis=0)
    out_a = a + sh * (1 - a)
    v = np.linspace(0, 1, n, dtype=np.float32)[:, None] * np.ones((1, n), np.float32)
    rgb = lerp(GOLD_HI, GOLD_LO, v) * (a / np.maximum(out_a, 1e-6))[..., None]
    return Image.fromarray(np.dstack([rgb, out_a * 255]).astype(np.uint8), 'RGBA').resize((size, size), Image.LANCZOS)


def jump_figure(g):
    """Figura en salto lateral (una pierna adelantada) sobre dos trazos de suelo; se usa en espejo."""
    g.dot(15.6, 3.4, 2.5)
    g.line((14.6, 7.6), (11.6, 13))
    g.line((14.4, 8.2), (18.6, 6.6), width=2.4)
    g.line((14.2, 8.4), (10.2, 6.2), (8.2, 7.8), width=2.4)
    g.line((11.6, 13), (16.4, 14.6), (19.4, 13), width=2.8)
    g.line((11.6, 13), (8.4, 17.2), (4.6, 17.4), width=2.8)
    g.line((3, 21.5), (9, 21.5), width=1.8)
    g.line((13, 21.5), (21, 21.5), width=1.8)


# --- Boton inteligente: un icono por estado (MiWow/s_<estado>; MiWowTouchSkin.lua los asocia a sus iconos) -------

def s_target(g):
    g.dot(12, 12, 8.4)
    g.dot(12, 12, 5.6, fill=ERASE)
    for p in (((12, 1.2), (12, 6.5)), ((12, 17.5), (12, 22.8)), ((1.2, 12), (6.5, 12)), ((17.5, 12), (22.8, 12))):
        g.line(*p, width=2.6)
    g.dot(12, 12, 2.1)


def s_attack(g):
    for a, b, guard, hilt, pommel in (((3, 3), (16.5, 16.5), ((13.6, 19.8), (19.8, 13.6)), (21, 21), (21.6, 21.6)),
                                      ((21, 3), (7.5, 16.5), ((4.2, 13.6), (10.4, 19.8)), (3, 21), (2.4, 21.6))):
        g.line(a, b, width=2.9)
        g.line(*guard, width=2.3)
        g.line(b, hilt, width=2.2)
        g.dot(*pommel, 1.5)


def s_loot(g):
    g.ell(3.5, 8.5, 20.5, 23)
    g.poly((8.2, 10), (15.8, 10), (14.2, 6.2), (9.8, 6.2))
    g.poly((9.8, 6.6), (6.5, 2.4), (12, 4.4), (17.5, 2.4), (14.2, 6.6))
    g.line((8.4, 9.4), (15.6, 9.4), width=1.1, fill=ERASE)
    g.dot(12, 16, 3.4, fill=ERASE)
    g.dot(12, 16, 2.1)


def s_skin(g):
    g.poly((12, 2.2), (15, 4), (19, 2.6), (18.6, 7), (21.4, 10), (19, 12.4), (21.4, 16.2), (18, 17.6), (18.6, 21.6),
           (14.6, 20.2), (12, 22.4), (9.4, 20.2), (5.4, 21.6), (6, 17.6), (2.6, 16.2), (5, 12.4), (2.6, 10), (5.4, 7),
           (5, 2.6), (9, 4))
    g.line((12, 7), (12, 17.5), width=1.0, fill=ERASE)


def s_herb(g):
    g.line((12, 22.5), (12, 8.5), width=1.9)
    g.leaf(12, 15.5, 9, 150, 2.8)
    g.leaf(12, 12, 9, 30, 2.8)
    g.leaf(12, 9.2, 8, 90, 2.6)


def s_ore(g):
    g.line((4.5, 20.5), (14.6, 9), width=2.5)
    g.line((6, 4.2), (10.5, 4.8), (14.8, 7.2), (18.4, 11), (20.4, 15.6), width=3.2)
    g.poly((6.6, 2.6), (3, 4.4), (6.6, 5.8))
    g.poly((22, 15), (20.4, 18.8), (18.8, 15.4))


def s_talk(g):
    g.rrect(2.3, 3, 21.7, 16.6, 4.2)
    g.poly((6, 15), (4.6, 21.8), (12.4, 16))
    for x in (7.4, 12, 16.6):
        g.dot(x, 9.8, 1.55, fill=ERASE)


def s_open(g):
    g.rrect(3, 10, 21, 20.8, 1.6)
    g.chord(3, 3.6, 21, 16.4, 180, 360)
    g.line((3, 10.4), (21, 10.4), width=1.1, fill=ERASE)
    g.rrect(10.2, 8.4, 13.8, 13.8, 0.8, fill=ERASE)
    g.rrect(11, 9.4, 13, 12.8, 0.4)


def s_mail(g):
    g.rrect(2, 5, 22, 19, 2)
    g.line((3, 6.2), (12, 13), (21, 6.2), width=1.5, fill=ERASE)


def s_fish(g):
    g.ell(2.5, 7.6, 17.5, 16.4)
    g.poly((15.6, 12), (21.8, 6.8), (20.2, 12), (21.8, 17.2))
    g.dot(6.8, 11, 1.25, fill=ERASE)
    g.line((10.4, 8.6), (11.6, 12), (10.4, 15.4), width=0.9, fill=ERASE)


def s_use(g):
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        g.line((12 + 6 * math.cos(a), 12 + 6 * math.sin(a)), (12 + 9.6 * math.cos(a), 12 + 9.6 * math.sin(a)), width=3.4)
    g.dot(12, 12, 7.6)
    g.dot(12, 12, 3.1, fill=ERASE)


def s_leave(g):
    g.line((10.5, 3), (4, 3), (4, 21), (10.5, 21), width=2.6)
    g.line((9, 12), (17, 12), width=2.9)
    g.poly((15.4, 6.2), (22.6, 12), (15.4, 17.8))


# --- Resto de botones fijos (MiWow/u_<nombre>) ----------------------------------------------------------------

def u_friend(g):
    g.dot(12, 12, 8.4)
    g.dot(12, 12, 5.6, fill=ERASE)
    for p in (((12, 1.2), (12, 6.5)), ((12, 17.5), (12, 22.8)), ((1.2, 12), (6.5, 12)), ((17.5, 12), (22.8, 12))):
        g.line(*p, width=2.6)
    g.line((12, 9), (12, 15), width=2.2)
    g.line((9, 12), (15, 12), width=2.2)


def u_run(g):
    g.dot(16.2, 3.8, 2.5)
    g.line((15.2, 8), (12.6, 13))
    g.line((14.8, 8.6), (18.4, 10.4), (19.8, 8), width=2.4)
    g.line((14.6, 8.8), (10.8, 9.6), (9.2, 12.4), width=2.4)
    g.line((12.6, 13), (16.2, 15.6), (15.4, 20.6), width=2.8)
    g.line((12.6, 13), (9.6, 16.4), (5.8, 15.8), width=2.8)
    g.line((2, 6.5), (6.4, 6.5), width=1.8)
    g.line((1.4, 10.5), (5.2, 10.5), width=1.8)


def u_mount(g):
    pts = [(12 + 6.6 * math.cos(math.radians(a)), 11 + 6.6 * math.sin(math.radians(a))) for a in range(180, 361, 10)]
    g.line((5.4, 20), *pts, (18.6, 20), width=4.2)
    for x, y in ((5.4, 13.6), (7.4, 7.4), (16.6, 7.4), (18.6, 13.6)):
        g.dot(x, y, 0.85, fill=ERASE)
    g.rrect(3, 19.2, 8, 22, 0.8)
    g.rrect(16, 19.2, 21, 22, 0.8)


def u_sit(g):
    g.dot(10.6, 13.4, 8.4)
    g.dot(15.4, 9.6, 7.4, fill=ERASE)
    g.line((14.6, 2.6), (20.8, 2.6), (14.6, 8.8), (20.8, 8.8), width=2.1)


def u_edit(g):
    g.line((4.6, 19.4), (13.6, 10.4), width=3.6)
    g.dot(16.2, 7.8, 5.2)
    g.line((16.2, 7.8), (21.6, 2.4), width=3.4, fill=ERASE)
    g.dot(4.6, 19.4, 0.9, fill=ERASE)


def u_up(g):
    g.poly((12, 2), (21, 11.5), (15.4, 11.5), (15.4, 21.5), (8.6, 21.5), (8.6, 11.5), (3, 11.5))


def u_down(g):
    g.poly((12, 22), (21, 12.5), (15.4, 12.5), (15.4, 2.5), (8.6, 2.5), (8.6, 12.5), (3, 12.5))

def u_close(g):
    g.line((5.5, 5.5), (18.5, 18.5), width=3.4)
    g.line((18.5, 5.5), (5.5, 18.5), width=3.4)


def u_menu(g):
    for y in (5.2, 12, 18.8):
        g.rrect(3, y - 1.9, 21, y + 1.9, 1.9)


def u_quick(g):
    g.poly((14, 1.2), (4.2, 13.6), (11, 13.6), (9.6, 22.8), (20.2, 9.6), (13.2, 9.6))


def u_mic(g):
    g.rrect(8.2, 1.6, 15.8, 14.6, 3.8)
    pts = [(12 + 6.6 * math.cos(math.radians(a)), 10.8 + 6.6 * math.sin(math.radians(a))) for a in range(0, 181, 15)]
    g.line(*pts, width=2.1)
    g.line((12, 17.4), (12, 21.4), width=2.1)
    g.line((8, 21.6), (16, 21.6), width=2.1)


# --- Botones del menu (micro botones de Blizzard en el cajon: MiWow/m_<nombre>) ------------------------------------

def m_char(g):
    g.dot(12, 7, 4.6)
    g.chord(3.5, 13.4, 20.5, 30.6, 180, 360)


def m_book(g):
    g.rrect(4, 2.6, 20, 21.6, 1.8)
    g.line((7.2, 3.4), (7.2, 20.8), width=0.9, fill=ERASE)
    g.rrect(9.6, 6.6, 17, 8.4, 0.5, fill=ERASE)
    g.rrect(9.6, 10.4, 15, 12, 0.5, fill=ERASE)


def m_star(g):
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = 10.4 if i % 2 == 0 else 4.4
        pts.append((12 + r * math.cos(a), 12.6 + r * math.sin(a)))
    g.poly(*pts)


def m_trophy(g):
    g.chord(5.6, -3.6, 18.4, 15.4, 0, 180)
    g.rrect(5.6, 2.2, 18.4, 6.4, 0.6)
    g.line((5.8, 4.4), (3, 4.6), (3.4, 8.2), (6.8, 10.6), width=1.7)
    g.line((18.2, 4.4), (21, 4.6), (20.6, 8.2), (17.2, 10.6), width=1.7)
    g.rrect(10.6, 14, 13.4, 18.4, 0.3)
    g.rrect(7.2, 18, 16.8, 21.8, 1)


def m_quest(g):
    g.rrect(9.9, 2.2, 14.1, 15.6, 2.1)
    g.dot(12, 19.8, 2.2)


def m_social(g):
    g.dot(8.6, 7.4, 3.8)
    g.chord(1.6, 13.6, 15.6, 28.4, 180, 360)
    g.dot(16.8, 8.6, 3)
    g.chord(14.2, 14.6, 23, 27.4, 180, 360)


def m_pvp(g):
    g.poly((12, 1.6), (21, 4.8), (21, 11), (19.4, 16.2), (15.6, 20.2), (12, 22.4), (8.4, 20.2), (4.6, 16.2), (3, 11), (3, 4.8))
    g.line((8, 7.6), (16, 15.6), width=2.1, fill=ERASE)
    g.line((16, 7.6), (8, 15.6), width=2.1, fill=ERASE)


def m_lfg(g):
    g.dot(10, 10, 7.6)
    g.dot(10, 10, 4.6, fill=ERASE)
    g.line((15.4, 15.4), (21, 21), width=3.4)


def m_help(g):
    g.dot(12, 12, 10)
    g.line((8.6, 9.2), (9, 7.2), (10.6, 5.8), (12.6, 5.6), (14.6, 6.6), (15.4, 8.6), (14.6, 10.4), (12.4, 12), (12, 14.6),
           width=2.2, fill=ERASE)
    g.dot(12, 18.2, 1.5, fill=ERASE)


# Pictogramas: s_ = estados del boton inteligente, u_ = resto de botones fijos, m_ = botones del menu
GLYPHS = [name for name in list(globals()) if name[:2] in ('s_', 'u_', 'm_') and callable(globals()[name])]


def main():
    preview = None
    if '--preview' in sys.argv:
        preview = sys.argv[sys.argv.index('--preview') + 1]
        os.makedirs(preview, exist_ok=True)
    items = {
        'DragonUI/forever_circle_lh': ring(),
        'PadDisc': white_disc(),
        'MiWow/disc': disc(),
        'MiWow/well': well(),
        'MiWow/knob': knob(),
        'MiWow/pill': pill(),
        'MiWow/pill_edge': pill(True),
        'MiWow/slot': slot(),
        'MiWow/slot_edge': slot_edge(),
        'MiWow/jump': pictogram(jump_figure, mirror=True),
    }
    for name in GLYPHS:
        items['MiWow/' + name] = pictogram(globals()[name])
    for rel, img in items.items():
        write_blp(img, os.path.join(OUT, *rel.split('/')) + '.blp')
        if preview:
            img.save(os.path.join(preview, rel.replace('/', '_') + '.png'))
    print('TouchUI: %d texturas en %s' % (len(items), OUT))


if __name__ == '__main__':
    main()
