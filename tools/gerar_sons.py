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
