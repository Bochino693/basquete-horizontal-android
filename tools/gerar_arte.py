"""Gera as pecas de arte do Swish Arena desenhadas por codigo.

    python3 tools/gerar_arte.py

bola, brilhos, faisca, chama, estrela, splash e icone. Tudo pequeno (a TV Box
tem pouca memoria de video) e em branco/tons neutros quando a cor e dada pelo
jogo (modulate), para uma imagem servir a varias cores.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(RAIZ, "imagens")


def salvar(im, nome):
    im.save(os.path.join(IMG, nome), optimize=True)
    print(nome, im.size)


def radial(tam, expoente=2.0, cor=(255, 255, 255)):
    y, x = np.mgrid[0:tam, 0:tam]
    c = (tam - 1) / 2
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    a = np.clip(1 - d, 0, 1) ** expoente
    arr = np.zeros((tam, tam, 4), np.uint8)
    arr[..., 0], arr[..., 1], arr[..., 2] = cor
    arr[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


# Brilho macio (luzes, halo do aro, fundo da tabela)
salvar(radial(128, 2.2), "brilho.png")
# Faisca: nucleo forte e borda curta
salvar(radial(32, 1.3), "faisca.png")

# Estrela de 4 pontas (brilho de destaque)
tam = 64
est = Image.new("L", (tam, tam), 0)
d = ImageDraw.Draw(est)
c = tam / 2
for ang in (0, 90):
    r = math.radians(ang)
    pts = []
    for k, (raio, off) in enumerate(((c, 0), (4, 90), (c, 180), (4, 270))):
        a = r + math.radians(off)
        pts.append((c + math.cos(a) * raio, c + math.sin(a) * raio))
    d.polygon(pts, fill=255)
est = est.filter(ImageFilter.GaussianBlur(1.2))
im = Image.new("RGBA", (tam, tam), (255, 255, 255, 0))
im.putalpha(est)
salvar(Image.alpha_composite(im, radial(tam, 3.0)), "estrela.png")

# Bola de basquete com volume e costuras
S = 192
esc = 4
g = S * esc
bola = Image.new("RGBA", (g, g), (0, 0, 0, 0))
yy, xx = np.mgrid[0:g, 0:g]
cx = cy = (g - 1) / 2
r = g * 0.47
dx, dy = (xx - cx) / r, (yy - cy) / r
dist = np.sqrt(dx ** 2 + dy ** 2)
dentro = dist <= 1
nz = np.sqrt(np.clip(1 - dx ** 2 - dy ** 2, 0, 1))
luz = np.clip(dx * -0.45 + dy * -0.55 + nz * 0.75, 0, 1)
base = np.array([236, 104, 24], float)
cor = base[None, None, :] * (0.35 + 0.8 * luz[..., None])
brilho = np.clip((luz - 0.82) / 0.18, 0, 1) ** 2
cor = cor + brilho[..., None] * 90
# textura de "gomos" (pontinhos)
pont = (np.sin(xx * 0.9) * np.sin(yy * 0.9) > 0.92) * 18
cor = cor - pont[..., None]
arr = np.zeros((g, g, 4), np.uint8)
arr[..., :3] = np.clip(cor, 0, 255).astype(np.uint8)
arr[..., 3] = np.where(dentro, 255, 0).astype(np.uint8)
bola = Image.fromarray(arr, "RGBA")
d = ImageDraw.Draw(bola)
lw = int(g * 0.022)
cor_costura = (38, 16, 6, 255)
d.line([(cx, cy - r), (cx, cy + r)], fill=cor_costura, width=lw)
d.line([(cx - r, cy), (cx + r, cy)], fill=cor_costura, width=lw)
d.arc([cx - r * 1.55, cy - r * 0.95, cx - r * 0.25, cy + r * 0.95], -62, 62, fill=cor_costura, width=lw)
d.arc([cx + r * 0.25, cy - r * 0.95, cx + r * 1.55, cy + r * 0.95], 118, 242, fill=cor_costura, width=lw)
mascara = Image.new("L", (g, g), 0)
ImageDraw.Draw(mascara).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
bola.putalpha(mascara)
bola = bola.resize((S, S), Image.LANCZOS)
salvar(bola, "bola.png")

# Splash (inicializacao do Android) e icone: da arte de abertura
ab = Image.open(os.path.join(IMG, "fundo_abertura.png")).convert("RGB")
W, H = ab.size
alvo_h = int(W * 720 / 1280)
topo = (H - alvo_h) // 2
splash = ab.crop((0, topo, W, topo + alvo_h)).resize((1280, 720), Image.LANCZOS)
salvar(splash, "splash.png")
# icone: logo SWISH + bola (regiao central da arte)
lado = int(W * 0.62)
x0, y0 = int(W * 0.04), (H - lado) // 2
ic = ab.crop((x0, y0, x0 + lado, y0 + lado)).resize((432, 432), Image.LANCZOS)
salvar(ic, "icone.png")

# Facho de refletor: cone estreito em cima, largo embaixo, sumindo (branco;
# a cor vem do jogo). Usado com mistura aditiva na arena.
fw, fh = 256, 640
yy, xx = np.mgrid[0:fh, 0:fw].astype(np.float32)
larg = 0.06 + 0.94 * (yy / fh)
dx = np.abs(xx - fw / 2) / (fw / 2) / larg
a = np.clip(1 - dx, 0, 1) ** 1.8 * (1 - yy / fh) ** 1.3 * np.clip(yy / 40, 0, 1)
arr = np.zeros((fh, fw, 4), np.uint8)
arr[..., :3] = 255
arr[..., 3] = (a * 255).astype(np.uint8)
salvar(Image.fromarray(arr, "RGBA").filter(ImageFilter.GaussianBlur(3)), "feixe.png")
