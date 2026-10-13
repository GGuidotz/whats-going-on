#!/usr/bin/env python3
"""Disegna l'icona di What's Going On (Resources/Icon/AppIcon-1024.png): un fumetto con dentro il tracciato di un
battito. È la risposta dell'app alla domanda del suo nome: una frase (il fumetto) su cosa batte nel Mac (la linea).
Griglia delle icone macOS: forma 824x824 centrata su 1024, raggio ~185.
    python3 -I tools/render-icon.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 4                      # sovracampionamento
N = 1024 * S
OUT = os.path.join(ROOT, "Resources", "Icon", "AppIcon-1024.png")


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))

    # Fondo: forma arrotondata con sfumatura verticale, blu notte.
    inset, size, radius = 100 * S, 824 * S, 185 * S
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    top, bottom = (40, 64, 110), (14, 22, 44)
    for y in range(N):
        gd.line([(0, y), (N, y)], fill=lerp(top, bottom, y / N) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([inset, inset, inset + size, inset + size], radius=radius, fill=255)
    img.paste(grad, (0, 0), mask)

    # Ombra morbida del fumetto.
    bubble = [250 * S, 300 * S, 774 * S, 700 * S]
    shadow = Image.new("L", (N, N), 0)
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle([bubble[0], bubble[1] + 18 * S, bubble[2], bubble[3] + 18 * S], radius=120 * S, fill=110)
    shadow = shadow.filter(ImageFilter.GaussianBlur(28 * S))
    img.paste((0, 0, 0, 255), (0, 0), shadow)

    # Fumetto bianco caldo, con la coda in basso a sinistra.
    d = ImageDraw.Draw(img)
    paper = (246, 248, 252, 255)
    d.rounded_rectangle(bubble, radius=120 * S, fill=paper)
    d.polygon([(330 * S, 660 * S), (300 * S, 800 * S), (450 * S, 690 * S)], fill=paper)

    # Il battito: piatto, un picco, un'onda, di nuovo piatto.
    pts = [(300, 520), (410, 520), (450, 460), (500, 610), (560, 380), (615, 560), (650, 500), (724, 500)]
    pts = [(x * S, y * S) for x, y in pts]
    d.line(pts, fill=(36, 112, 255, 255), width=34 * S, joint="curve")
    for x, y in (pts[0], pts[-1]):
        r = 17 * S
        d.ellipse([x - r, y - r, x + r, y + r], fill=(36, 112, 255, 255))

    img = img.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.save(OUT)
    print(OUT)


if __name__ == "__main__":
    main()
