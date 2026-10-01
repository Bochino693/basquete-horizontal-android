"""Gera o fundo da partida (arena) em Full HD + a mascara das luzes animadas.

    python3 tools/gerar_arena.py

imagens/fundo_arena.png          1920x1080, a arena parada (nitida na TV Full HD)
imagens/fundo_arena_mascara.png  1920x1080 (e _720), onde tem luz animada (o shader le):
    R = tubos de neon (a luz corre por eles)
    G = lampadas de fliperama (acendem em sequencia, como marquise)
    B = fase de cada lampada (ordem da sequencia)

Mesma ideia do brilho da pista do Dragon Bowling: a arte e a mascara sao
calculadas uma vez aqui; na TV Box o shader so le dois pixels e soma a luz.

A tabela com a marcacao da cesta fica onde o jogo desenha o aro
(centro x=960, aro em y=900 na tela Full HD).
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1920, 1080
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(RAIZ, "imagens")
rng = np.random.default_rng(24)

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)


def cor(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32) / 255.0


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def camada_blur(desenhar, raio, tam=(W, H)):
    """Desenha em RGBA preto transparente e borra (para brilhos)."""
    im = Image.new("RGBA", tam, (0, 0, 0, 0))
    desenhar(ImageDraw.Draw(im))
    if raio > 0:
        im = im.filter(ImageFilter.GaussianBlur(raio))
    return np.asarray(im, np.float32) / 255.0


def somar(base, camada, forca=1.0):
    """Luz aditiva (cor * alfa)."""
    return base + camada[..., :3] * camada[..., 3:4] * forca


def por_cima(base, camada):
    a = camada[..., 3:4]
    return base * (1 - a) + camada[..., :3] * a


# ------------------------------------------------------------------ ceu
# Fundo: roxo profundo no alto, azul-noite no meio, mais escuro embaixo.
topo, meio, baixo = cor("#12052e"), cor("#0a0a24"), cor("#05030c")
k = yy / H
img = np.where(k[..., None] < 0.55,
               topo * (1 - k[..., None] / 0.55) + meio * (k[..., None] / 0.55),
               meio * (1 - (k[..., None] - 0.55) / 0.45) + baixo * ((k[..., None] - 0.55) / 0.45))
# vinheta
vin = 1 - 0.55 * np.clip(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H * 0.45) / (H * 0.85)) ** 2, 0, 1)
img = img * vin[..., None]

# ---------------------------------------------------- arquibancada (bokeh)
# Luzes desfocadas da torcida e do ginasio ao fundo.
def bokeh(d):
    for _ in range(110):
        x = rng.uniform(0, W)
        y = rng.uniform(300, 720)
        r = rng.uniform(4, 15)
        c = [(255, 140, 40), (140, 70, 255), (255, 60, 150), (40, 200, 255), (255, 230, 150)][rng.integers(0, 5)]
        a = int(rng.uniform(30, 95))
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (a,))
img = somar(img, camada_blur(bokeh, 5), 0.8)

# silhuetas da torcida (fileiras de cabecas bem escuras)
def torcida(d):
    for fila, (y0, esc) in enumerate(((700, 1.0), (650, 0.85), (605, 0.72))):
        x = -20
        while x < W + 20:
            r = rng.uniform(13, 19) * esc
            y = y0 + rng.uniform(-6, 6)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(4, 2, 12, 235))
            d.rounded_rectangle([x - r * 1.6, y + r * 0.7, x + r * 1.6, y + r * 4], radius=int(r), fill=(4, 2, 12, 235))
            x += r * 2.3 + rng.uniform(0, 8)
rng_torcida = rng.bit_generator.state
def torcida_luz(d):
    # a mesma torcida, deslocada 3 px para cima em roxo: vira contorno de luz
    for fila, (y0, esc) in enumerate(((700, 1.0), (650, 0.85), (605, 0.72))):
        x = -20
        while x < W + 20:
            r = rng.uniform(13, 19) * esc
            y = y0 + rng.uniform(-6, 6) - 3
            d.ellipse([x - r, y - r, x + r, y + r], fill=(150, 80, 255, 150))
            x += r * 2.3 + rng.uniform(0, 8)
img = somar(img, camada_blur(torcida_luz, 1.5), 0.8)
rng.bit_generator.state = rng_torcida
img = por_cima(img, camada_blur(torcida, 2))

# ------------------------------------------------- faixa de LED (ribbon)
RIB_Y0, RIB_Y1 = 730, 776
def ribbon_fundo(d):
    d.rectangle([0, RIB_Y0, W, RIB_Y1], fill=(6, 4, 14, 255))
    d.line([(0, RIB_Y0), (W, RIB_Y0)], fill=(90, 60, 160, 255), width=2)
    d.line([(0, RIB_Y1), (W, RIB_Y1)], fill=(90, 60, 160, 255), width=2)
img = por_cima(img, camada_blur(ribbon_fundo, 0))
# texto em pontos de LED: fonte 5x7 desenhada ponto a ponto (fonte TTF
# reduzida a 9 px deformava as letras).
FONTE_5X7 = {
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "N": ["10001", "11001", "10101", "10101", "10011", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "&": ["01100", "10010", "10100", "01000", "10101", "10010", "01101"],
    "*": ["00000", "00000", "01110", "01110", "01110", "00000", "00000"],
    " ": ["00000"] * 7,
}
PASSO = 6                                   # distancia entre LEDs (px)
topo_rib = RIB_Y0 + (RIB_Y1 - RIB_Y0 - 6 * PASSO) / 2.0
# O LETREIRO ANDA: as frases sao desenhadas numa faixa propria (imagens/
# letreiro.png, e a _720) que o jogo faz correr LED a LED, sumindo atras da
# tabela de vidro (scripts/letreiro_led.gd). Na arte fica so a faixa escura.
FRASES = [("SWISH ARENA", (255, 160, 40)), ("SHOW YOUR GAME", (200, 120, 255)),
          ("LAZER & SPORT GAMES", (40, 220, 255))]
colunas = []                                # (7 bits, cor)
for txt, c in FRASES:
    for ch in txt:
        for k in range(5):
            colunas.append(([FONTE_5X7[ch][r][k] == "1" for r in range(7)], c))
        colunas.append(([False] * 7, c))
    for _ in range(4):
        colunas.append(([False] * 7, c))
    for k in range(5):                      # estrelinha entre as frases
        colunas.append(([FONTE_5X7["*"][r][k] == "1" for r in range(7)], (255, 230, 150)))
    for _ in range(5):
        colunas.append(([False] * 7, c))
print("letreiro: colunas", len(colunas))


def letreiro(passo, nome):
    """Faixa de LEDs (todas as colunas lado a lado, emenda sem costura)."""
    k = passo / 6.0
    lw, lh = len(colunas) * int(passo), int(round(RIB_Y1 - RIB_Y0))
    lh = int(round(lh * k))
    g = 4                                   # desenha em 4x e reduz (liso)
    acesos = Image.new("RGBA", (lw * g, lh * g), (0, 0, 0, 0))
    apagados = Image.new("RGBA", (lw * g, lh * g), (0, 0, 0, 0))
    da, dp = ImageDraw.Draw(acesos), ImageDraw.Draw(apagados)
    y0 = (lh - 6 * passo) / 2.0
    for i, (col, c) in enumerate(colunas):
        x = (i + 0.5) * passo
        for r in range(7):
            y = y0 + r * passo
            if col[r]:
                rr = 2.2 * k * g
                da.ellipse([x * g - rr, y * g - rr, x * g + rr, y * g + rr], fill=c + (255,))
            else:
                rr = 1.2 * k * g
                dp.ellipse([x * g - rr, y * g - rr, x * g + rr, y * g + rr], fill=(40, 26, 60, 255))
    acesos = acesos.resize((lw, lh), Image.LANCZOS)
    apagados = apagados.resize((lw, lh), Image.LANCZOS)
    # brilho em volta dos LEDs acesos (a faixa da direita e da esquerda
    # emendam: borra com a faixa repetida)
    triplo = Image.new("RGBA", (lw * 3, lh), (0, 0, 0, 0))
    for j in range(3):
        triplo.paste(acesos, (j * lw, 0))
    brilho = triplo.filter(ImageFilter.GaussianBlur(2.5 * k)).crop((lw, 0, lw * 2, lh))
    out = Image.alpha_composite(apagados, brilho)
    out = Image.alpha_composite(out, acesos)
    out.save(os.path.join(IMG, nome), optimize=True)
    print(nome, out.size)


letreiro(6, "letreiro.png")
letreiro(4, "letreiro_720.png")

# ------------------------------------------------------------ quadra
# Piso brilhante em perspectiva, com reflexo das luzes.
piso_y = 778
fp = np.clip((yy - piso_y) / (H - piso_y), 0, 1)
piso = cor("#1b0d0a") * (1 - fp[..., None]) + cor("#3a1d10") * fp[..., None]
madeira = 0.05 * np.sin(xx / 34.0 + (yy - piso_y) * 0.02) * fp
piso = piso * (1 + madeira[..., None])
img = np.where((yy >= piso_y)[..., None], piso, img)
# brilho do piso (reflexo da tabela e das luzes)
refl = camada_blur(lambda d: d.ellipse([620, 840, 1300, 1120], fill=(255, 150, 60, 90)), 60)
img = somar(img, refl, 0.8)

def linhas_quadra(d):
    # garrafao e arco em perspectiva, neon laranja
    fuga = (960, 520)
    for x in (640, 1280):
        d.line([(x, piso_y + 4), (fuga[0] + (x - fuga[0]) * 1.9, H)], fill=(255, 120, 40, 200), width=5)
    d.line([(560, piso_y + 4), (1360, piso_y + 4)], fill=(255, 120, 40, 200), width=5)
    d.arc([700, 900, 1220, 1260], 180, 360, fill=(255, 120, 40, 200), width=5)
    d.arc([220, 820, 1700, 1500], 190, 350, fill=(140, 70, 255, 170), width=5)
img = somar(img, camada_blur(linhas_quadra, 5), 1.0)
img = somar(img, camada_blur(linhas_quadra, 0), 0.7)

# reflexo espelhado (piso encerado)
espelho = img[max(0, 2 * piso_y - H):piso_y][::-1]
alt = min(espelho.shape[0], H - piso_y)
atenua = (0.14 * np.exp(-np.arange(alt) / 90.0))[:, None, None]
# linha k do reflexo vem da linha piso_y - 1 - k: o letreiro nao reflete
origem = piso_y - 1 - np.arange(alt)
atenua = atenua * np.where((origem >= RIB_Y0 - 8) & (origem <= RIB_Y1 + 8), 0.0, 1.0)[:, None, None]
img[piso_y:piso_y + alt] += espelho[:alt] * atenua

# ------------------------------------------------------ holofotes do teto
def holofotes(d):
    for x in (180, 560, 1360, 1740):
        d.polygon([(x - 18, 48), (x + 18, 48), (x + 230, 860), (x - 230, 860)], fill=(255, 235, 200, 24))
img = somar(img, camada_blur(holofotes, 22), 1.0)
def lampadas_teto(d):
    for x in (180, 560, 1360, 1740):
        d.ellipse([x - 22, 34, x + 22, 62], fill=(255, 245, 225, 255))
def carcaca(d):
    for x in (180, 560, 1360, 1740):
        d.rounded_rectangle([x - 40, 20, x + 40, 56], radius=10, fill=(30, 26, 44, 255))
img = por_cima(img, camada_blur(carcaca, 0.6))
img = somar(img, camada_blur(lampadas_teto, 16), 1.2)
img = somar(img, camada_blur(lampadas_teto, 3), 1.0)

# ------------------------------------------------------------- tabela
# Vidro com moldura branca, marcacao da cesta e reflexo, sobre o piso.
tab = (640, 470, 1280, 950)          # tabela
quad = (812, 690, 1108, 900)         # marcacao (quadrado do arremesso)
def tabela_vidro(d):
    d.rounded_rectangle(tab, radius=18, fill=(16, 24, 52, 205))
img = por_cima(img, camada_blur(tabela_vidro, 0))
# reflexo diagonal no vidro
refl_vidro = np.zeros((H, W, 4), np.float32)
dentro = (xx > tab[0]) & (xx < tab[2]) & (yy > tab[1]) & (yy < tab[3])
faixa = np.exp(-(((xx - tab[0]) * 0.8 - (yy - tab[1]) - 60) / 55.0) ** 2) * 0.22 + \
        np.exp(-(((xx - tab[0]) * 0.8 - (yy - tab[1]) - 190) / 18.0) ** 2) * 0.12
refl_vidro[..., :3] = 1.0
refl_vidro[..., 3] = faixa * dentro
img = somar(img, refl_vidro, 1.0)
def moldura(d):
    d.rounded_rectangle(tab, radius=18, outline=(255, 255, 255, 255), width=12)
    d.rectangle(quad, outline=(255, 255, 255, 255), width=10)
def moldura_brilho(d):
    d.rounded_rectangle(tab, radius=18, outline=(90, 200, 255, 255), width=26)
    d.rectangle(quad, outline=(255, 140, 50, 255), width=22)
img = somar(img, camada_blur(moldura_brilho, 18), 0.9)
img = por_cima(img, camada_blur(moldura, 0.6))
# suporte do aro (placa atras do aro)
def suporte(d):
    d.rectangle([915, 890, 1005, 912], fill=(40, 40, 50, 255))
img = por_cima(img, camada_blur(suporte, 0.5))

# --------------------------------------------- moldura neon da maquina
# Tubo amarelo em volta da tela (como o gabinete da Game On) + faixas
# diagonais laranja/roxo nas laterais de baixo.
margem = 14
def tubo(d, largura, c):
    d.rounded_rectangle([margem, margem, W - margem, H - margem], radius=34, outline=c, width=largura)
img = somar(img, camada_blur(lambda d: tubo(d, 22, (255, 190, 30, 255)), 12), 0.6)
img = por_cima(img, camada_blur(lambda d: tubo(d, 8, (255, 236, 150, 255)), 1))

def faixas(d, alfa=255, grossura=16):
    for i in range(4):
        dx = i * 46
        c = (255, 120, 30, alfa) if i % 2 == 0 else (150, 70, 255, alfa)
        d.line([(60 + dx, H - 40), (300 + dx, 560)], fill=c, width=grossura)
        d.line([(W - 60 - dx, H - 40), (W - 300 - dx, 560)], fill=c, width=grossura)
img = somar(img, camada_blur(lambda d: faixas(d, 255, 26), 12), 0.4)
img = por_cima(img, camada_blur(lambda d: faixas(d, 200, 10), 1))

# lampadas de fliperama (base apagada, o shader acende)
lampadas = []
for y in np.arange(430, H - 70, 52):
    lampadas.append((46, y))
    lampadas.append((W - 46, y))
for x in np.arange(120, W - 100, 58):
    lampadas.append((x, H - 44))
# bulbo apagado desenhado em 4x e reduzido (borda lisa em 1080p): aro
# cromado, vidro ambar escuro com o filamento e o reflexo branco
def bulbo(R=15):
    g = R * 2 * 4 + 8
    im = Image.new("RGBA", (g, g), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = g / 2
    e = 4
    d.ellipse([c - (R + 1) * e, c - (R + 1) * e, c + (R + 1) * e, c + (R + 1) * e], fill=(10, 8, 16, 230))
    for k in range(12):                    # aro cromado (degrade)
        rr = (R - k * 0.25) * e
        t = k / 11
        v = int(120 + 120 * (1 - abs(t - 0.35) * 1.6))
        d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=(v, v - 6, v - 18, 255))
    rv = (R - 3.6) * e
    d.ellipse([c - rv, c - rv, c + rv, c + rv], fill=(70, 40, 12, 255))
    rv2 = (R - 5.5) * e
    d.ellipse([c - rv2, c - rv2, c + rv2, c + rv2], fill=(120, 72, 22, 255))
    d.arc([c - 3 * e, c - 2 * e, c + 3 * e, c + 4 * e], 200, 340, fill=(170, 110, 40, 255), width=e)
    d.ellipse([c - 6.5 * e, c - 7 * e, c - 2.5 * e, c - 3.5 * e], fill=(255, 245, 220, 200))
    return im.resize((g // 4, g // 4), Image.LANCZOS)
BULBO = bulbo()
camada_b = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for (x, y) in lampadas:
    camada_b.alpha_composite(BULBO, (int(round(x - BULBO.width / 2)), int(round(y - BULBO.height / 2))))
img = por_cima(img, np.asarray(camada_b, np.float32) / 255.0)

final = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB")
final.save(os.path.join(IMG, "fundo_arena.png"), optimize=True)
print("fundo_arena.png", final.size)
# Versao para TV Box que roda a janela em 720p: reduzida aqui com filtro bom
# (a placa de video reduz sem mipmap e as linhas finas e lampadas serrilham).
final.resize((1280, 720), Image.LANCZOS).save(os.path.join(IMG, "fundo_arena_720.png"), optimize=True)
print("fundo_arena_720.png", (1280, 720))

# ------------------------------------------------------------ mascara
# Em resolucao cheia (antes 960x540: as lampadas viravam aneis serrilhados).
MW, MH = W, H
masc = np.zeros((MH, MW, 3), np.float32)
esc = 1.0
def para_mascara(desenhar, raio):
    im = Image.new("L", (MW, MH), 0)
    desenhar(ImageDraw.Draw(im))
    if raio:
        im = im.filter(ImageFilter.GaussianBlur(raio))
    return np.asarray(im, np.float32) / 255.0

def tubos_m(d):
    d.rounded_rectangle([margem * esc, margem * esc, (W - margem) * esc, (H - margem) * esc], radius=34, outline=255, width=18)
    for i in range(4):
        dx = i * 46
        d.line([((60 + dx) * esc, (H - 40) * esc), ((300 + dx) * esc, 560 * esc)], fill=255, width=18)
        d.line([((W - 60 - dx) * esc, (H - 40) * esc), ((W - 300 - dx) * esc, 560 * esc)], fill=255, width=18)
    d.rounded_rectangle([c * esc for c in tab], radius=18, outline=160, width=16)
    d.rectangle([c * esc for c in quad], outline=200, width=14)
masc[..., 0] = para_mascara(tubos_m, 6)
rib = np.zeros((MH, MW), np.float32)
rib[int(RIB_Y0 * esc):int(RIB_Y1 * esc) + 1, :] = 0.7
masc[..., 0] = np.maximum(masc[..., 0], rib)

# lampadas: forma (G) e fase (B) = posicao exata na volta da moldura
# (esquerda de cima p/ baixo, embaixo da esquerda p/ direita, direita de
# baixo p/ cima): o shader acende 1 a cada 3 e a luz "roda" em volta.
# G = vidro aceso (disco liso, desenhado em 4x) + halo em volta;
# B = fase pintada num disco MAIOR que o halo: a lampada inteira (vidro e
# halo) acende junta, sem anel na borda.
esq = sorted([p for p in lampadas if p[0] < W * 0.1], key=lambda p: p[1])
baixo_l = sorted([p for p in lampadas if W * 0.1 <= p[0] <= W * 0.9], key=lambda p: p[0])
dir_ = sorted([p for p in lampadas if p[0] > W * 0.9], key=lambda p: -p[1])
ordem_l = esq + baixo_l + dir_
N = len(ordem_l)
print("lampadas:", N)
g4 = Image.new("L", (MW * 2, MH * 2), 0)
b = Image.new("L", (MW, MH), 0)
dg, db = ImageDraw.Draw(g4), ImageDraw.Draw(b)
for i, (x, y) in enumerate(ordem_l):
    r = 10.5 * 2
    dg.ellipse([x * 2 - r, y * 2 - r, x * 2 + r, y * 2 + r], fill=255)
    rb = 24
    db.ellipse([x - rb, y - rb, x + rb, y + rb], fill=int(round((i + 0.5) / N * 255)))
vidro = np.asarray(g4.resize((MW, MH), Image.LANCZOS), np.float32) / 255.0
halo = np.asarray(g4.resize((MW, MH), Image.LANCZOS).filter(ImageFilter.GaussianBlur(8)), np.float32) / 255.0
masc[..., 1] = np.clip(np.maximum(vidro, halo * 0.75), 0, 1)
masc[..., 2] = np.asarray(b, np.float32) / 255.0
m8 = Image.fromarray((masc * 255 + 0.5).astype(np.uint8), "RGB")
m8.save(os.path.join(IMG, "fundo_arena_mascara.png"), optimize=True)
print("fundo_arena_mascara.png", (MW, MH))
# versao 720p: G e R reduzidos com filtro; B pelo vizinho (a fase nao pode
# misturar entre lampadas)
m7 = Image.merge("RGB", (m8.getchannel(0).resize((1280, 720), Image.LANCZOS),
                         m8.getchannel(1).resize((1280, 720), Image.LANCZOS),
                         m8.getchannel(2).resize((1280, 720), Image.NEAREST)))
m7.save(os.path.join(IMG, "fundo_arena_mascara_720.png"), optimize=True)
print("fundo_arena_mascara_720.png", (1280, 720))
