"""Texturas dos efeitos novos do Swish Arena (feitas por conta):

    python3 -I tools/gerar_efeitos.py

raios       explosao de raios de luz (o SWISH! no aro)
anel_onda   anel macio (as ondas de choque do aro: elipse pela escala)
rastro      o rastro comprido da bola voando (brilho esticado)
coroa       coroa de ouro detalhada (o RECORDE da abertura)
medalha_1..3 medalhas de ouro, prata e bronze (o RANKING da abertura)
            (os mesmos desenhos do Slam Arena)
Precisa de numpy e Pillow.
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


# ------------------------------------------------ coroa e medalhas (icones)
# Desenhados em 4x e reduzidos (borda lisa); o metal e um degrade por pixel.
SS = 4


def _mascara(tam, desenhar):
    im = Image.new("L", (tam[0] * SS, tam[1] * SS), 0)
    desenhar(ImageDraw.Draw(im), SS)
    return np.asarray(im).astype(np.float64) / 255


def _metal(h, w, claro, medio, escuro, y0, y1, brilhos=()):
    """Degrade de metal: claro em cima, escuro embaixo, mais escuro nas
    laterais (volume) e faixas de brilho verticais."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    t = np.clip((y - y0) / max(y1 - y0, 1), 0, 1)
    claro, medio, escuro = (np.array(c) for c in (claro, medio, escuro))
    c = np.where(t[..., None] < 0.45, claro + (medio - claro) * (t[..., None] / 0.45),
                 medio + (escuro - medio) * ((t[..., None] - 0.45) / 0.55))
    lado = np.abs(x - w / 2) / (w / 2)
    c = c * (1.0 - 0.28 * lado[..., None] ** 2)
    for bx, larg, forca in brilhos:
        c = c + forca * np.exp(-((x - bx) / larg) ** 2)[..., None]
    return np.clip(c, 0, 1)


def _esfera(h, w, cx, cy, r, cor, brilho=(1, 1, 1)):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / r
    luz = np.clip(1.15 - np.sqrt((x - cx + r * 0.35) ** 2 + (y - cy + r * 0.35) ** 2) / r, 0, 1)
    c = np.array(cor) * (0.45 + 0.75 * luz[..., None])
    esp = np.exp(-(((x - cx + r * 0.38) ** 2 + (y - cy + r * 0.42) ** 2) / (r * 0.22) ** 2))
    c = c + np.array(brilho) * esp[..., None] * 0.9
    return np.clip(c, 0, 1), d


def _compor(base, cor, alfa):
    a = alfa[..., None]
    base[..., :3] = base[..., :3] * (1 - a) + cor * a
    base[..., 3] = np.maximum(base[..., 3], alfa)


def _gravar_rgba(nome, rgba, tam):
    im = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    im = im.resize(tam, Image.LANCZOS)
    im.save(os.path.join(IMG, nome + ".png"), optimize=True)


def _contorno(alfa, px):
    im = Image.fromarray((alfa * 255).astype(np.uint8), "L")
    im = im.filter(ImageFilter.MaxFilter(px * 2 + 1))
    return np.asarray(im).astype(np.float64) / 255


def gerar_coroa():
    W, H = 256, 184
    pontas = [(26, 50), (77, 40), (128, 16), (179, 40), (230, 50)]
    vales = [(54, 104), (102, 98), (154, 98), (202, 104)]
    corpo = [(36, 128)]
    for i, p in enumerate(pontas):
        corpo.append(p)
        if i < len(vales):
            corpo.append(vales[i])
    corpo.append((220, 128))

    def d_corpo(d, k):
        d.polygon([(x * k, y * k) for x, y in corpo], fill=255)

    def d_faixa(d, k):
        d.rounded_rectangle([28 * k, 120 * k, 228 * k, 164 * k], radius=10 * k, fill=255)

    def d_perolas(d, k):
        for x, y in pontas:
            d.ellipse([(x - 11) * k, (y - 19) * k, (x + 11) * k, (y + 3) * k], fill=255)

    h, w = H * SS, W * SS
    m_corpo = _mascara((W, H), d_corpo)
    m_faixa = _mascara((W, H), d_faixa)
    m_per = _mascara((W, H), d_perolas)
    tudo = np.maximum(np.maximum(m_corpo, m_faixa), m_per)
    rgba = np.zeros((h, w, 4))
    # contorno escuro (define a forma de longe)
    _compor(rgba, np.array([0.28, 0.13, 0.02]), _contorno(tudo, 3 * SS))
    ouro = _metal(h, w, (1.0, 0.96, 0.62), (1.0, 0.78, 0.20), (0.78, 0.46, 0.06), 16 * SS, 128 * SS,
                  [(96 * SS, 7 * SS, 0.30), (166 * SS, 5 * SS, 0.18)])
    _compor(rgba, ouro, m_corpo)
    # recorte interno das pontas (relevo): uma linha mais escura por dentro
    borda_int = np.clip(m_corpo - _contorno(1 - m_corpo, 5 * SS) * m_corpo, 0, 1)
    rgba[..., :3] *= (1 - 0.18 * (m_corpo - borda_int)[..., None])
    faixa = _metal(h, w, (1.0, 0.88, 0.42), (0.92, 0.62, 0.12), (0.62, 0.34, 0.04), 120 * SS, 164 * SS,
                   [(96 * SS, 9 * SS, 0.22)])
    _compor(rgba, np.array([0.30, 0.14, 0.02]), _contorno(m_faixa, 2 * SS))
    _compor(rgba, faixa, m_faixa)
    # friso claro em cima e embaixo da faixa
    y = np.mgrid[0:h, 0:w][0] / SS
    frisos = (np.exp(-((y - 125) / 1.6) ** 2) + np.exp(-((y - 159) / 1.6) ** 2)) * m_faixa
    rgba[..., :3] = np.clip(rgba[..., :3] + 0.35 * frisos[..., None], 0, 1)
    # joias da faixa: rubi no meio, safiras e esmeraldas
    joias = [(128, 142, 15, (0.95, 0.08, 0.16)), (84, 142, 10, (0.10, 0.35, 1.0)),
             (172, 142, 10, (0.10, 0.35, 1.0)), (47, 142, 7, (0.05, 0.80, 0.35)),
             (209, 142, 7, (0.05, 0.80, 0.35))]
    for x, yy, r, cor in joias:
        c, d = _esfera(h, w, x * SS, yy * SS, r * SS, cor)
        _compor(rgba, np.array([0.25, 0.12, 0.02]), np.clip((1.18 - d) * 6, 0, 1))
        _compor(rgba, c, np.clip((1.0 - d) * r * SS / 2.5, 0, 1))
    # perolas nas pontas
    for x, yy in pontas:
        c, d = _esfera(h, w, x * SS, (yy - 8) * SS, 10 * SS, (1.0, 0.97, 0.92))
        _compor(rgba, c, np.clip((1.0 - d) * 10 * SS / 2.5, 0, 1))
    _gravar_rgba("coroa", rgba, (W, H))


def gerar_medalhas():
    L = 128
    metais = {
        1: ((1.0, 0.96, 0.60), (1.0, 0.78, 0.16), (0.72, 0.42, 0.04)),
        2: ((1.0, 1.0, 1.0), (0.80, 0.84, 0.90), (0.46, 0.51, 0.60)),
        3: ((1.0, 0.82, 0.58), (0.86, 0.52, 0.24), (0.50, 0.26, 0.08)),
    }
    fonte = ImageFont.truetype(os.path.join(RAIZ, "fontes", "titan.ttf"), 64 * SS)
    h = w = L * SS
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    cx = cy = L * SS / 2
    ang = np.arctan2(y - cy, x - cx)
    r = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / SS
    for n, (claro, medio, escuro) in metais.items():
        rgba = np.zeros((h, w, 4))
        # aro serrilhado (24 dentes)
        r_aro = 58 + 2.2 * np.cos(ang * 24)
        aro = np.clip((r_aro - r) * SS / 2.0, 0, 1)
        _compor(rgba, np.array(escuro) * 0.45, np.clip((r_aro + 2.5 - r) * SS / 2.0, 0, 1))
        _compor(rgba, _metal(h, w, claro, medio, escuro, 8 * SS, 120 * SS, [(44 * SS, 10 * SS, 0.25)]), aro)
        # disco de dentro, um pouco mais fundo (degrade invertido = relevo)
        disco = np.clip((47 - r) * SS / 2.0, 0, 1)
        _compor(rgba, np.array(escuro) * 0.7, np.clip((49 - r) * SS / 2.0, 0, 1))
        _compor(rgba, _metal(h, w, medio, claro, medio, 20 * SS, 108 * SS, [(50 * SS, 8 * SS, 0.15)]), disco)
        # estrela em relevo atras do numero
        pts = []
        for k in range(10):
            a = -np.pi / 2 + k * np.pi / 5
            rr = 40 if k % 2 == 0 else 17
            pts.append((L / 2 + rr * np.cos(a), L / 2 + rr * np.sin(a) + 2))
        estrela = _mascara((L, L), lambda d, k: d.polygon([(px * k, py * k) for px, py in pts], fill=255))
        rgba[..., :3] = np.clip(rgba[..., :3] * (1 - 0.10 * estrela[..., None]) + 0.10 * estrela[..., None] * np.array(claro), 0, 1)
        # o numero: escuro, com a luz embaixo (gravado no metal)
        def d_num(d, k, dx=0.0, dy=0.0):
            d.text(((L / 2 + dx) * k, (L / 2 + 3 + dy) * k), str(n), font=fonte, fill=255, anchor="mm")
        luz = _mascara((L, L), lambda d, k: d_num(d, k, 0, 2.2))
        num = _mascara((L, L), d_num)
        _compor(rgba, np.array(claro), luz * 0.9)
        _compor(rgba, np.array(escuro) * 0.55, num)
        # brilho do vidro/metal: um arco claro em cima
        reflexo = np.clip(1 - np.abs(np.sqrt((x - cx) ** 2 + (y - cy - 30 * SS) ** 2) / SS - 66) / 5, 0, 1)
        reflexo *= np.clip((cy - y) / (40 * SS), 0, 1) * (r < 56)
        rgba[..., :3] = np.clip(rgba[..., :3] + 0.22 * reflexo[..., None], 0, 1)
        _gravar_rgba("medalha_%d" % n, rgba, (L, L))


def main():
    gerar_raios()
    gerar_anel()
    gerar_rastro()
    gerar_coroa()
    gerar_medalhas()
    print("ok: imagens/raios, anel_onda, rastro, coroa, medalha_1..3")


if __name__ == "__main__":
    main()
