#!/usr/bin/env python3
"""Disegna l'icona di What's Going On. Concetto: un MacBook Air color argento visto di fronte (schermo con la tacca, base
sottile e più larga con l'incavo per aprirlo), e sullo schermo nero il tracciato di un monitoraggio che sale dal verde
al rosso. Fondo chiaro, bianco che sfuma appena nel grigio perla, come vetro smerigliato.

Due uscite, con la stessa geometria:
    python3 -I tools/render-icon.py                 Resources/Icon/AppIcon-1024.png (icona classica, vetro simulato)
    python3 -I tools/render-icon.py --layers DIR    strati PNG per Icon Composer (Resources/Icon/WhatsGoingOn.icon/Assets)
Nell'icona Liquid Glass vetro, riflessi e ombre li aggiunge il sistema: gli strati sono forme nette su trasparente.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 3                      # sovracampionamento
N = 1024 * S

# Colori (sRGB 0…255). Il fondo è lo stesso "fill" di icon.json.
BG_TOP = (255, 255, 255)   # bianco
BG_BOTTOM = (222, 227, 234)  # grigio perla, appena freddo
SILVER_TOP = (238, 239, 242)
SILVER_BOTTOM = (176, 181, 189)
SILVER_EDGE = (128, 134, 143)
GREEN = (52, 209, 122)
YELLOW = (247, 199, 68)
RED = (240, 69, 63)
SCREEN = (10, 14, 18)

# Geometria sulla tela 1024, centro ottico appena sotto il centro.
DISPLAY = (192, 240, 832, 662)      # x0, y0, x1, y1 del coperchio
BEZEL = 24
DISPLAY_R = 34
NOTCH = (66, 16)                    # larghezza, altezza della tacca
BASE = (128, 668, 896, 704)         # la base, più larga dello schermo
BASE_R = 16
SCOOP = (118, 9)                    # incavo davanti, al centro della base
GRAPH = [(0.06, 0.74), (0.17, 0.60), (0.27, 0.67), (0.38, 0.45), (0.49, 0.55),
         (0.61, 0.31), (0.71, 0.42), (0.83, 0.17), (0.94, 0.25)]
GRAPH_W = 22


def sc(v):
    return v * S


def screen_rect():
    x0, y0, x1, y1 = DISPLAY
    return (x0 + BEZEL, y0 + BEZEL, x1 - BEZEL, y1 - BEZEL)


def graph_points():
    x0, y0, x1, y1 = screen_rect()
    pad = 30
    w, h = (x1 - x0 - 2 * pad), (y1 - y0 - 2 * pad)
    return [(sc(x0 + pad + u * w), sc(y0 + pad + v * h)) for u, v in GRAPH]


def mask_laptop():
    """Coperchio (cornice con la tacca) e base, in bianco."""
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([sc(v) for v in DISPLAY], radius=sc(DISPLAY_R), fill=255)
    sx0, sy0, sx1, sy1 = screen_rect()
    d.rounded_rectangle([sc(sx0), sc(sy0), sc(sx1), sc(sy1)], radius=sc(10), fill=0)
    cx = (DISPLAY[0] + DISPLAY[2]) / 2
    nw, nh = NOTCH
    d.rounded_rectangle([sc(cx - nw / 2), sc(sy0 - 4), sc(cx + nw / 2), sc(sy0 + nh)], radius=sc(7), fill=255)
    d.rounded_rectangle([sc(v) for v in BASE], radius=sc(BASE_R), fill=255)
    bw, bh = SCOOP
    d.rounded_rectangle([sc(cx - bw / 2), sc(BASE[1] - 6), sc(cx + bw / 2), sc(BASE[1] + bh)], radius=sc(6), fill=0)
    return m


def mask_screen():
    m = Image.new("L", (N, N), 0)
    sx0, sy0, sx1, sy1 = screen_rect()
    ImageDraw.Draw(m).rounded_rectangle([sc(sx0), sc(sy0), sc(sx1), sc(sy1)], radius=sc(10), fill=255)
    return m


def mask_graph():
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    pts = graph_points()
    d.line(pts, fill=255, width=sc(GRAPH_W), joint="curve")
    r = sc(GRAPH_W) / 2
    for x, y in (pts[0], pts[-1]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return m


def mask_area():
    """L'area sotto il tracciato, fino al fondo dello schermo."""
    m = Image.new("L", (N, N), 0)
    pts = graph_points()
    bottom = sc(screen_rect()[3] - 18)
    ImageDraw.Draw(m).polygon([(pts[0][0], bottom)] + pts + [(pts[-1][0], bottom)], fill=255)
    # più pieno vicino al tracciato, svanisce verso il basso
    top = min(y for _, y in pts)
    fade = np.clip(1 - (np.arange(N) - top) / (bottom - top), 0, 1) ** 1.3 * 255
    fade = Image.fromarray(np.broadcast_to(fade[:, None], (N, N)).astype(np.uint8), "L")
    return ImageChops.multiply(ImageChops.multiply(m, fade), mask_screen())


def scale_gradient():
    """Verde a sinistra, giallo al centro, rosso a destra, sulla larghezza dello schermo."""
    x0, _, x1, _ = screen_rect()
    xs = (np.arange(N) / S - x0) / (x1 - x0)
    t = np.clip(xs, 0, 1)
    g, y, r = (np.array(c, float) for c in (GREEN, YELLOW, RED))
    t = np.clip(t / 0.85, 0, 1)            # rosso pieno nell'ultimo tratto
    first = t[:, None] < 0.5
    k = np.where(first, t[:, None] * 2, (t[:, None] - 0.5) * 2)
    row = np.where(first, g + (y - g) * k, y + (r - y) * k)
    rgb = np.broadcast_to(row[None, :, :], (N, N, 3))
    a = np.full((N, N, 1), 255.0)
    return Image.fromarray(np.concatenate([rgb, a], 2).astype(np.uint8), "RGBA")


def solid(color):
    return Image.new("RGBA", (N, N), color + (255,))


def background():
    t = np.linspace(0, 1, N)[:, None, None]
    top, bottom = np.array(BG_TOP, float), np.array(BG_BOTTOM, float)
    rgb = (top + (bottom - top) * t) * np.ones((1, N, 1))
    # un bagliore in alto, dove la luce colpisce il vetro
    y, x = np.mgrid[0:N, 0:N] / (N - 1)
    glow = np.clip(1 - np.sqrt((x - 0.5) ** 2 + (y - 0.05) ** 2) / 0.7, 0, 1)[..., None] ** 2
    rgb = rgb + (np.array([255, 255, 255], float) - rgb) * glow * 0.6
    a = np.full((N, N, 1), 255.0)
    return Image.fromarray(np.concatenate([rgb, a], 2).astype(np.uint8), "RGBA")


def silver():
    """Alluminio argento: chiaro in alto, più scuro in basso, sull'altezza del portatile."""
    y0, y1 = DISPLAY[1], BASE[3]
    t = np.clip((np.arange(N) / S - y0) / (y1 - y0), 0, 1)[:, None, None]
    top, bottom = np.array(SILVER_TOP, float), np.array(SILVER_BOTTOM, float)
    rgb = (top + (bottom - top) * t ** 1.4) * np.ones((1, N, 1))
    a = np.full((N, N, 1), 255.0)
    return Image.fromarray(np.concatenate([rgb, a], 2).astype(np.uint8), "RGBA")


def with_alpha(img, mask, opacity=1.0):
    out = img.copy()
    out.putalpha(mask.point(lambda v: int(v * opacity)))
    return out


def shadow(base, mask, offset=14, blur=26, opacity=0.45):
    sh = mask.transform(mask.size, Image.AFFINE, (1, 0, 0, 0, 1, -sc(offset))).filter(ImageFilter.GaussianBlur(sc(blur)))
    return Image.alpha_composite(base, with_alpha(solid((40, 46, 56)), sh, opacity))


def metal(base, mask):
    """Il portatile d'argento per l'icona classica: alluminio, un filo scuro sul bordo e un riflesso in alto."""
    out = Image.alpha_composite(base, with_alpha(silver(), mask))
    k = 5 * S + (1 if (5 * S) % 2 == 0 else 0)
    edge = ImageChops.subtract(mask, mask.filter(ImageFilter.MinFilter(k))).filter(ImageFilter.GaussianBlur(sc(1)))
    out = Image.alpha_composite(out, with_alpha(solid(SILVER_EDGE), edge, 0.55))
    shifted = mask.transform(mask.size, Image.AFFINE, (1, 0, 0, 0, 1, sc(8)))
    spec = ImageChops.subtract(mask, shifted).filter(ImageFilter.GaussianBlur(sc(3)))
    return Image.alpha_composite(out, with_alpha(solid((255, 255, 255)), spec, 0.9))


def render_flat():
    img = background()
    laptop, screen, graph, area = mask_laptop(), mask_screen(), mask_graph(), mask_area()
    img = shadow(img, ImageChops.lighter(laptop, screen), opacity=0.32)
    img = Image.alpha_composite(img, with_alpha(solid(SCREEN), screen, 0.94))
    img = metal(img, laptop)
    colors = scale_gradient()
    img = Image.alpha_composite(img, with_alpha(colors, area, 0.5))
    img = shadow(img, graph, offset=6, blur=10, opacity=0.5)
    img = Image.alpha_composite(img, with_alpha(colors, graph))
    shifted = graph.transform(graph.size, Image.AFFINE, (1, 0, 0, 0, 1, sc(6)))
    spec = ImageChops.subtract(graph, shifted).filter(ImageFilter.GaussianBlur(sc(2)))
    img = Image.alpha_composite(img, with_alpha(solid((255, 255, 255)), spec, 0.45))
    img = img.resize((1024, 1024), Image.LANCZOS)

    # forma macOS: 824 px sulla griglia 1024, angoli continui approssimati, ombra leggera
    size, inset, radius = 1024, 100, 185
    shape = Image.new("L", (size * S, size * S), 0)
    ImageDraw.Draw(shape).rounded_rectangle([inset * S, inset * S, (size - inset) * S, (size - inset) * S],
                                            radius=radius * S, fill=255)
    shape = shape.resize((size, size), Image.LANCZOS)
    art = img.resize((size - 2 * inset, size - 2 * inset), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(art, (inset, inset))
    canvas.putalpha(shape)
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh.putalpha(shape.transform(shape.size, Image.AFFINE, (1, 0, 0, 0, 1, -12)).filter(ImageFilter.GaussianBlur(14))
                .point(lambda v: int(v * 0.35)))
    return Image.alpha_composite(sh, canvas)


def render_layers(outdir):
    os.makedirs(outdir, exist_ok=True)
    colors = scale_gradient()
    layers = {
        "laptop.png": with_alpha(silver(), mask_laptop()),
        "screen.png": with_alpha(solid(SCREEN), mask_screen()),
        "graph.png": with_alpha(colors, mask_graph()),
        "graph-area.png": with_alpha(colors, mask_area()),
    }
    for name, img in layers.items():
        img.resize((1024, 1024), Image.LANCZOS).save(os.path.join(outdir, name))


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--layers":
        render_layers(sys.argv[2])
        print("strati scritti in", sys.argv[2])
    else:
        out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")
        render_flat().save(out)
        print("scritto", out)
