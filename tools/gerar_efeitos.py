"""Texturas dos efeitos novos do Swish Arena (feitas por conta):

    python3 -I tools/gerar_efeitos.py

d7_*        os caracteres do placar de LED (0-9, vazio) em CAMPO DE
            DISTANCIA: R = distancia ate os segmentos acesos, G = ate o "8"
            (os apagados). O shaders/display7.shader tira disso a borda lisa
            (1 pixel da tela), o miolo quente e o brilho - nitido em
            qualquer tamanho, e trocar o numero so troca a textura (nada de
            geometria por quadro: o placar contando nao pesa na TV Box).
raios       explosao de raios de luz (o SWISH! no aro)
anel_onda   anel macio (as ondas de choque do aro: elipse pela escala)
rastro      o rastro comprido da bola voando (brilho esticado)
Precisa de numpy e Pillow.
"""
import os

import numpy as np
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(RAIZ, "imagens")


def suave(v):
    v = np.clip(v, 0, 1)
    return v * v * (3 - 2 * v)


def gravar_alfa(nome, alfa):
    a = (np.clip(alfa, 0, 1) * 255 + 0.5).astype(np.uint8)
    rgba = np.zeros(a.shape + (4,), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = a
    Image.fromarray(rgba, "RGBA").save(os.path.join(IMG, nome + ".png"), optimize=True)


# ------------------------------------------------ placar de LED (campo de distancia)
D7_W, D7_T, D7_INC = 0.56, 0.135, 0.10
D7_SEGMENTOS = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg", "vazio": "",
}
D7_LADO = 256
D7_ESCALA = 160.0
D7_CENTRO = (0.28, 0.5)
D7_DMIN, D7_DMAX = -0.10, 0.30


def d7_segmento(seg):
    m = D7_T * 0.5
    g = D7_T * 0.14
    w, h = D7_W, 1.0
    a, b = {
        "a": ((m + g, m), (w - m - g, m)), "g": ((m + g, h * 0.5), (w - m - g, h * 0.5)),
        "d": ((m + g, h - m), (w - m - g, h - m)), "f": ((m, m + g), (m, h * 0.5 - g)),
        "b": ((w - m, m + g), (w - m, h * 0.5 - g)), "e": ((m, h * 0.5 + g), (m, h - m - g)),
        "c": ((w - m, h * 0.5 + g), (w - m, h - m - g)),
    }[seg]
    a, b = np.array(a), np.array(b)
    d = (b - a) / np.linalg.norm(b - a)
    n = np.array([-d[1], d[0]])
    pts = [a, a + d * m + n * m, b - d * m + n * m, b, b - d * m - n * m, a + d * m - n * m]
    return [np.array([p[0] + (h * 0.5 - p[1]) * D7_INC, p[1]]) for p in pts]


def d7_distancia(poli, px, py):
    n = len(poli)
    dist = np.full(px.shape, np.inf)
    dentro = np.ones(px.shape, bool)
    area = sum(poli[i][0] * poli[(i + 1) % n][1] - poli[(i + 1) % n][0] * poli[i][1] for i in range(n))
    for i in range(n):
        ax, ay = poli[i]
        bx, by = poli[(i + 1) % n]
        ex, ey = bx - ax, by - ay
        wx, wy = px - ax, py - ay
        t = np.clip((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1)
        dx, dy = wx - ex * t, wy - ey * t
        dist = np.minimum(dist, np.sqrt(dx * dx + dy * dy))
        lado = ex * wy - ey * wx
        dentro &= (lado > 0) if area > 0 else (lado < 0)
    return np.where(dentro, -dist, dist)


def d7_campo(segs, px, py):
    d = np.full(px.shape, D7_DMAX * 4)
    for s in segs:
        d = np.minimum(d, d7_distancia(d7_segmento(s), px, py))
    return np.clip((D7_DMAX - d) / (D7_DMAX - D7_DMIN), 0, 1)


def gerar_display7():
    j, i = np.mgrid[0:D7_LADO, 0:D7_LADO].astype(np.float64)
    px = (i + 0.5 - D7_LADO / 2) / D7_ESCALA + D7_CENTRO[0]
    py = (j + 0.5 - D7_LADO / 2) / D7_ESCALA + D7_CENTRO[1]
    todos = d7_campo("abcdefg", px, py)
    for nome, segs in D7_SEGMENTOS.items():
        rgba = np.zeros((D7_LADO, D7_LADO, 4), np.uint8)
        rgba[..., 0] = (d7_campo(segs, px, py) * 255 + 0.5).astype(np.uint8)
        rgba[..., 1] = (todos * 255 + 0.5).astype(np.uint8)
        rgba[..., 3] = 255
        Image.fromarray(rgba, "RGBA").save(os.path.join(IMG, "d7_%s.png" % nome), optimize=True)


# ------------------------------------------------------------- efeitos
def gerar_raios():
    n = 256
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    dx, dy = (x - c) / c, (y - c) / c
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)
    # 14 raios de larguras diferentes (parece explosao de verdade)
    raios = np.zeros_like(r)
    rng = np.random.default_rng(5)
    for k in range(14):
        a0 = k / 14 * 2 * np.pi + rng.uniform(-0.12, 0.12)
        larg = rng.uniform(0.035, 0.09)
        d = np.abs(np.angle(np.exp(1j * (ang - a0))))
        comp = rng.uniform(0.7, 1.0)
        raios = np.maximum(raios, np.clip(1 - d / larg, 0, 1) ** 1.5 * np.clip(1 - r / comp, 0, 1) ** 1.2)
    miolo = np.clip(1 - r / 0.32, 0, 1) ** 2
    gravar_alfa("raios", np.maximum(raios * 0.9, miolo) * np.clip((1 - r) / 0.05, 0, 1))


def gerar_anel():
    n = 256
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    c = (n - 1) / 2
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2) / c
    gravar_alfa("anel_onda", np.clip(1 - np.abs(r - 0.86) / 0.11, 0, 1) ** 1.6)


def gerar_rastro():
    w, h = 64, 256
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    u = np.abs(x - (w - 1) / 2) / ((w - 1) / 2)
    v = y / (h - 1)                      # 0 = cabeca (a bola), 1 = ponta do rastro
    gravar_alfa("rastro", np.clip(1 - u, 0, 1) ** 1.8 * (1 - v) ** 1.4 * suave(v / 0.06 + 0.3))


def main():
    gerar_display7()
    gerar_raios()
    gerar_anel()
    gerar_rastro()
    print("ok: imagens/d7_*.png, raios, anel_onda, rastro")


if __name__ == "__main__":
    main()
