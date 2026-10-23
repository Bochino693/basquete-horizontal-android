"""Gera os efeitos sonoros sintetizados do Swish Arena (WAV 16 bits mono).

    python3 tools/gerar_sons.py

Sons curtos e leves para a TV Box: WAV não precisa ser decodificado na hora.
"""
import os
import wave

import numpy as np

TAXA = 44100
PASTA = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "sons")


def salvar(nome, sinal):
    sinal = np.clip(sinal, -1.0, 1.0)
    dados = (sinal * 32767 * 0.9).astype(np.int16)
    with wave.open(os.path.join(PASTA, nome), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes(dados.tobytes())
    print(nome, "%.2f s" % (len(sinal) / TAXA))


def t(seg):
    return np.arange(int(seg * TAXA)) / TAXA


def envelope(n, ataque=0.005, queda=4.0):
    x = np.arange(n) / TAXA
    a = np.clip(x / max(ataque, 1e-4), 0, 1)
    return a * np.exp(-x * queda)


def filtro_passa_banda(sinal, centro, largura):
    espectro = np.fft.rfft(sinal)
    freqs = np.fft.rfftfreq(len(sinal), 1 / TAXA)
    ganho = np.exp(-((freqs - centro) / largura) ** 2)
    return np.fft.irfft(espectro * ganho, len(sinal))


rng = np.random.default_rng(7)

# SWISH: a bola passando pela rede (ruído filtrado que desce) + toque no aro.
n = int(0.55 * TAXA)
ruido = rng.normal(0, 1, n)
partes = []
for i, centro in enumerate(np.linspace(5200, 1800, 8)):
    trecho = filtro_passa_banda(ruido, centro, 900)
    partes.append(trecho * np.exp(-((np.arange(n) / TAXA - 0.05 - i * 0.035) / 0.05) ** 2))
swish = sum(partes)
swish /= np.max(np.abs(swish))
aro = np.sin(2 * np.pi * 660 * t(0.55)) * envelope(n, 0.001, 18) * 0.25
salvar("swish.wav", swish * 0.9 + aro)

# PONTO: moedinha de dois tons.
p1 = np.sin(2 * np.pi * 988 * t(0.08)) * envelope(int(0.08 * TAXA), 0.002, 10)
p2 = np.sin(2 * np.pi * 1319 * t(0.32)) * envelope(int(0.32 * TAXA), 0.002, 9)
salvar("ponto.wav", np.concatenate([p1, p2]) * 0.7)

# BIP da contagem e VAI!
salvar("bip.wav", np.sign(np.sin(2 * np.pi * 880 * t(0.16))) * envelope(int(0.16 * TAXA), 0.003, 6) * 0.35)
vai = np.sign(np.sin(2 * np.pi * 1320 * t(0.55))) * 0.25 + np.sin(2 * np.pi * 660 * t(0.55)) * 0.3
salvar("vai.wav", vai * envelope(len(vai), 0.003, 3))

# TIQUE dos últimos segundos.
salvar("tique.wav", np.sin(2 * np.pi * 1760 * t(0.05)) * envelope(int(0.05 * TAXA), 0.001, 60) * 0.6)

# BUZINA de fim de tempo (como o placar de ginásio).
x = t(1.3)
buz = (2 * ((x * 196) % 1) - 1) * 0.5 + (2 * ((x * 247) % 1) - 1) * 0.4
buz *= np.clip(x / 0.02, 0, 1) * np.clip((1.3 - x) / 0.15, 0, 1)
salvar("buzina.wav", buz * 0.55)

# FOGO: "whoosh" subindo (entrou no modo EM CHAMAS).
n = int(0.9 * TAXA)
ruido = rng.normal(0, 1, n)
fogo = np.zeros(n)
for i, centro in enumerate(np.linspace(300, 3200, 10)):
    fogo += filtro_passa_banda(ruido, centro, 500) * np.exp(-((np.arange(n) / TAXA - i * 0.07) / 0.09) ** 2)
fogo /= np.max(np.abs(fogo))
salvar("fogo.wav", fogo * np.clip((0.9 - t(0.9)) / 0.3, 0, 1) * 0.9)


def nota(freq, dur, onda="quadrada"):
    x = t(dur)
    if onda == "quadrada":
        s = np.sign(np.sin(2 * np.pi * freq * x)) * 0.35 + np.sin(2 * np.pi * freq * 2 * x) * 0.2
    else:
        s = np.sin(2 * np.pi * freq * x)
    return s * envelope(len(x), 0.004, 5)


# FASE: arpejo subindo (passou de fase).
salvar("fase.wav", np.concatenate([nota(f, 0.11) for f in (523, 659, 784)] + [nota(1047, 0.5)]) * 0.8)

# RECORDE: fanfarra.
fan = np.concatenate([nota(f, d) for f, d in ((523, 0.12), (523, 0.12), (523, 0.12), (784, 0.3), (659, 0.12), (784, 0.7))])
salvar("recorde.wav", fan * 0.8)

# ALERTA: meta não batida / fim de jogo.
salvar("alerta.wav", np.concatenate([nota(392, 0.2), nota(330, 0.2), nota(262, 0.6)]) * 0.7)

# IMPACTO: pancada grave com brilho (o logo da apresentação ganhando vida).
# Com semente fixa: gerar de novo dá o mesmo arquivo.
def impacto():
    x = t(1.1)
    queda = 95 * np.exp(-x * 5) + 38
    corpo = np.sin(np.cumsum(2 * np.pi * queda / TAXA)) * np.exp(-x * 4.5)
    ruido = np.random.default_rng(11).uniform(-1, 1, len(x))
    estalo = filtro_passa_banda(ruido, 2400, 1800) * np.exp(-x * 30) * 0.6
    brilho = np.sin(2 * np.pi * 1568 * x) * np.exp(-x * 6) * 0.12 + np.sin(2 * np.pi * 2093 * x) * np.exp(-x * 7) * 0.08
    s = corpo * 0.9 + estalo + brilho
    return s / np.max(np.abs(s))


salvar("impacto.wav", impacto() * 0.95)


# ARREMESSO: o "vuuup" da bola grande saindo da frente da tela até o aro
# (ar passando: ruído filtrado subindo de tom, que some no fim).
def arremesso():
    x = t(0.5)
    r = np.random.default_rng(21).normal(0, 1, len(x))
    partes = []
    for i, centro in enumerate(np.linspace(700, 2600, 10)):
        trecho = filtro_passa_banda(r, centro, 500)
        partes.append(trecho * np.exp(-((x - 0.04 - i * 0.04) / 0.07) ** 2))
    s = sum(partes)
    return s / np.max(np.abs(s)) * np.clip(x / 0.05, 0, 1)


salvar("arremesso.wav", arremesso() * 0.5)


# FOGOS: o estouro do fogo de artifício (pancada curta + estalinhos).
def fogos():
    x = t(0.9)
    rr = np.random.default_rng(23)
    corpo = np.sin(np.cumsum(2 * np.pi * (120 * np.exp(-x * 9) + 60) / TAXA)) * np.exp(-x * 9)
    estouro = filtro_passa_banda(rr.uniform(-1, 1, len(x)), 1800, 1600) * np.exp(-x * 22)
    estalos = np.zeros(len(x))
    for _ in range(26):
        i0 = int(rr.uniform(0.08, 0.8) * TAXA)
        n = int(0.012 * TAXA)
        estalos[i0:i0 + n] += rr.uniform(-1, 1, n) * np.exp(-np.arange(n) / (0.002 * TAXA)) * rr.uniform(0.2, 0.6)
    s = corpo * 0.8 + estouro * 0.7 + filtro_passa_banda(estalos, 4000, 2500) * 1.6
    return s / np.max(np.abs(s))


salvar("fogos.wav", fogos() * 0.8)
