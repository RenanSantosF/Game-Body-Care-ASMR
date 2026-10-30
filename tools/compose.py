"""Compõe as músicas do jogo (síntese própria, sem samples).

clinic.ogg: lo-fi calmo para tratar (82 BPM, swing)
menu.ogg:   alegre para o menu (108 BPM)
Uso: python3 tools/compose.py   (precisa de numpy e ffmpeg)
"""
import os, subprocess, wave
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "music")
rng = np.random.default_rng(7)

def mf(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)

def env(n, a=0.005, d=1.5):
    t = np.arange(n) / SR
    e = np.exp(-t * d)
    an = max(1, int(a * SR))
    e[:an] *= np.linspace(0, 1, an)
    return e

def lowpass(x, k):
    y = np.zeros_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += k * (x[i] - acc)
        y[i] = acc
    return y

def lp_fast(x, k):
    # filtro de 1 polo vetorizado (aproximação por convolução exponencial)
    n = int(min(4000, 6 / max(k, 1e-4)))
    kern = k * (1 - k) ** np.arange(n)
    return np.convolve(x, kern)[: len(x)]

def epiano(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    mod = 0.9 * np.exp(-t * 4.0) * np.sin(2 * np.pi * f * 2.0 * t)
    s = np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t * 6)
    return s * env(n, 0.004, 1.6) * vel * 0.32

def marimba(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t * 18)
    return s * env(n, 0.002, 5.5) * vel * 0.33

def pluck(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    saw = 2 * ((f * t) % 1.0) - 1
    s = lp_fast(saw, 0.08) * 1.6 + 0.4 * np.sin(2 * np.pi * f * t)
    return s * env(n, 0.002, 7.0) * vel * 0.22

def bass(f, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2 * t)
    e = env(n, 0.01, 2.2)
    e[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    return s * e * vel * 0.45

def pad(freqs, dur, vel=1.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    s = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.11):
            ff = f * 2 ** (det / 12)
            s += 2 * ((ff * t + rng.random()) % 1.0) - 1
    s = lp_fast(s / (len(freqs) * 3), 0.02)
    e = np.minimum(1, t / 0.6) * np.minimum(1, (dur - t) / 0.4)
    return s * e * vel * 0.5

def kick(vel=1.0):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 45 + 90 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9) * vel * 0.9

def snare(vel=1.0):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    nz = nz - lp_fast(nz, 0.15)
    return (nz * 0.5 * np.exp(-t * 18) + np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25) * 0.4) * vel * 0.5

def hat(vel=1.0, open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    nz = nz - lp_fast(nz, 0.5)
    return nz * np.exp(-t * (14 if open_ else 70)) * vel * 0.07

def clap(vel=1.0):
    n = int(0.2 * SR)
    t = np.arange(n) / SR
    nz = rng.standard_normal(n)
    nz = nz - lp_fast(nz, 0.2)
    e = np.exp(-t * 20) * (1 + 0.8 * (np.sin(2 * np.pi * 90 * t) > 0) * (t < 0.03))
    return nz * e * vel * 0.22

class Track:
    def __init__(self, bpm, bars):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.len = int(bars * 4 * self.beat * SR)
        self.buf = np.zeros(self.len + SR * 4)

    def add(self, beat_pos, sig, gain=1.0):
        i = int(beat_pos * self.beat * SR)
        self.buf[i:i + len(sig)] += sig * gain

    def render(self, reverb=0.25, warmth=0.45):
        x = lp_fast(self.buf, warmth)
        # reverb simples (pentes) para dar ambiente
        out = x.copy()
        for d, g in ((0.0297, 0.5), (0.0371, 0.45), (0.0411, 0.4), (0.0437, 0.35)):
            k = int(d * SR)
            y = np.zeros_like(x)
            for rep in range(1, 7):
                y[k * rep:] += x[:-k * rep] * (g ** rep)
            out += lp_fast(y, 0.3) * reverb * 0.5
        # loop perfeito: o rabo volta para o começo
        tail = out[self.len:]
        loop = out[: self.len].copy()
        loop[: len(tail)] += tail
        loop = np.tanh(loop * 1.1)
        return loop / (np.max(np.abs(loop)) + 1e-9) * 0.85

def save(name, mono):
    # estéreo leve: atraso de alguns ms num canal
    d = int(0.008 * SR)
    left = mono
    right = np.roll(mono, d)
    st = np.stack([left, right], axis=1)
    pcm = (st * 32767).astype(np.int16)
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)

def chord(root, kind):
    iv = {"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "6": [0, 4, 7, 9], "add9": [0, 4, 7, 14]}[kind]
    return [root + i for i in iv]

def clinic():
    t = Track(82, 16)
    prog = [(60, "maj7"), (57, "m7"), (62, "m7"), (55, "7")]
    melody = [
        [(0, 76, 1), (1.5, 79, 0.5), (2, 81, 1), (3, 79, 1)],
        [(0, 76, 1.5), (2, 72, 1), (3, 74, 1)],
        [(0, 77, 1), (1, 76, 0.5), (1.5, 74, 1.5), (3, 72, 1)],
        [(0, 74, 2), (2.5, 71, 0.5), (3, 74, 1)],
    ]
    for bar in range(16):
        root, kind = prog[bar % 4]
        notes = chord(root, kind)
        b0 = bar * 4
        # piano elétrico: acorde no 1 e no "e" do 2 (swing)
        for beat in (0, 1.66):
            for k, m in enumerate(notes):
                t.add(b0 + beat + k * 0.02, epiano(mf(m), 2.2, 0.8 if beat == 0 else 0.55))
        t.add(b0, pad([mf(m) for m in notes], 4 * t.beat), 0.35)
        # baixo
        t.add(b0, bass(mf(root - 24), 1.4 * t.beat))
        t.add(b0 + 2.66, bass(mf(root - 24 + 7), 1.0 * t.beat), 0.8)
        # bateria lo-fi
        t.add(b0, kick())
        t.add(b0 + 2.66, kick(0.7))
        t.add(b0 + 1, snare(0.55))
        t.add(b0 + 3, snare(0.6))
        for h in range(4):
            t.add(b0 + h, hat(0.8))
            t.add(b0 + h + 0.66, hat(0.5))
        # melodia de marimba (entra depois dos 4 primeiros compassos)
        if bar >= 4 and bar < 14:
            for pos, m, d in melody[bar % 4]:
                t.add(b0 + pos, marimba(mf(m), d * t.beat + 0.4), 0.9)
    # chiado de vinil bem baixinho
    t.buf[: t.len] += lp_fast(rng.standard_normal(t.len), 0.25) * 0.0012
    save("clinic", t.render(0.35, 0.3))

def menu():
    t = Track(108, 16)
    prog = [(65, "maj7"), (67, "6"), (64, "m7"), (69, "m7")]
    hook = [(0, 81, 0.5), (0.5, 84, 0.5), (1, 86, 1), (2, 84, 0.5), (2.5, 81, 0.5), (3, 79, 1)]
    hook2 = [(0, 79, 0.5), (0.5, 81, 0.5), (1, 84, 1.5), (3, 86, 0.5), (3.5, 88, 0.5)]
    for bar in range(16):
        root, kind = prog[bar % 4]
        notes = chord(root, kind)
        b0 = bar * 4
        # arpejo de pluck em semicolcheias
        arp = notes + [notes[1] + 12, notes[2] + 12]
        for s in range(16):
            m = arp[(s * 3) % len(arp)]
            t.add(b0 + s * 0.25, pluck(mf(m), 0.3, 0.9 if s % 4 == 0 else 0.6))
        t.add(b0, pad([mf(m) for m in notes], 4 * t.beat), 0.3)
        for q in (0, 1.5, 2, 3.5):
            t.add(b0 + q, bass(mf(root - 24 if q < 2 else root - 17), 0.45 * t.beat))
        for q in range(4):
            t.add(b0 + q, kick(0.9))
            t.add(b0 + q + 0.5, hat(0.7, q == 3))
        t.add(b0 + 1, clap())
        t.add(b0 + 3, clap())
        if bar >= 4:
            for pos, m, d in (hook if bar % 2 == 0 else hook2):
                t.add(b0 + pos, marimba(mf(m), d * t.beat + 0.3), 0.85)
    save("menu", t.render(0.25, 0.5))

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    clinic()
    menu()
    print("ok")
