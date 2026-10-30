"""Gera as malhas suaves da mão e do pé (SDF + marching cubes).

Uso (no PC):  python3 tools/bodygen.py   -> assets/body/*.json
Depois:       godot --headless --path . -s tools/convert_body.gd
O jogo só precisa dos .res gerados (não precisa rodar isto no celular).
"""
import json, math, os, sys
import numpy as np
from skimage import measure

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "body")

# ---------------------------------------------------------------- SDF helpers

def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)

def capsule(p, a, b, r1, r2=None):
    if r2 is None:
        r2 = r1
    a = np.asarray(a, float); b = np.asarray(b, float)
    pa = p - a; ba = b - a
    h = np.clip((pa @ ba) / (ba @ ba), 0.0, 1.0)
    r = r1 + (r2 - r1) * h
    return np.linalg.norm(pa - h[:, None] * ba, axis=1) - r

def ellipsoid(p, c, rad):
    q = (p - np.asarray(c, float)) / np.asarray(rad, float)
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / np.asarray(rad, float), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)

def flat_y(p, s):
    q = p.copy(); q[:, 1] *= s
    return q

def chain(p, pts, radii, ys=1.15):
    q = flat_y(p, ys)
    d = None
    for i in range(len(pts) - 1):
        a = np.array(pts[i]); b = np.array(pts[i + 1])
        a[1] *= ys; b[1] *= ys
        di = capsule(q, a, b, radii[i], radii[i + 1])
        d = di if d is None else smin(d, di, 0.03)
    return d

def finger_pts(base, direction, lengths, drop):
    """pontos da falange: base -> ponta, com leve curvatura para baixo"""
    d = np.array(direction, float); d /= np.linalg.norm(d)
    pts = [np.array(base, float)]
    for i, L in enumerate(lengths):
        nxt = pts[-1] + d * L
        nxt[1] -= drop[i]
        pts.append(nxt)
    return [list(x) for x in pts]

# ---------------------------------------------------------------- MÃO
# Mão esquerda, palma para baixo, dedos apontando +X, polegar em -Z.

HAND_FINGERS = []
def hand_sdf(p):
    global HAND_FINGERS
    HAND_FINGERS = []
    palm = ellipsoid(p, [0.0, 0.0, 0.02], [0.62, 0.17, 0.52])
    palm = smin(palm, ellipsoid(p, [0.25, -0.01, 0.0], [0.42, 0.15, 0.5]), 0.15)
    arm = chain(p, [[-0.35, -0.02, 0.0], [-1.4, 0.0, 0.0], [-3.2, 0.03, 0.0]], [0.36, 0.33, 0.4], ys=1.45)
    d = smin(palm, arm, 0.35)
    # dedos: indicador, médio, anelar, mínimo
    specs = [
        ([0.52, 0.02, -0.33], [1.0, 0, -0.10], [0.46, 0.30, 0.25], 0.108, 0.092),
        ([0.58, 0.02, -0.11], [1.0, 0, -0.03], [0.50, 0.33, 0.27], 0.112, 0.095),
        ([0.55, 0.02, 0.11],  [1.0, 0, 0.05],  [0.47, 0.31, 0.25], 0.108, 0.09),
        ([0.45, 0.01, 0.31],  [1.0, 0, 0.14],  [0.36, 0.24, 0.21], 0.096, 0.082),
    ]
    fingers = None
    for base, dirv, lens, r0, r1 in specs:
        pts = finger_pts(base, dirv, lens, [0.02, 0.04, 0.05])
        rr = [r0, r0 * 0.95, (r0 + r1) / 2, r1]
        f = chain(p, pts, rr)
        # nós dos dedos
        for j in (1, 2):
            f = smin(f, ellipsoid(p, [pts[j][0], pts[j][1] + 0.025, pts[j][2]], [0.05, 0.04, rr[j] * 0.85]), 0.04)
        HAND_FINGERS.append({"pts": pts, "r": rr})
        fingers = f if fingers is None else np.minimum(fingers, f)
    d = smin(d, fingers, 0.07)
    # nós (juntas) no dorso
    for base, *_ in specs:
        d = smin(d, ellipsoid(p, [base[0] - 0.06, base[1] + 0.08, base[2]], [0.07, 0.045, 0.08]), 0.08)
    # polegar
    tpts = finger_pts([0.05, -0.03, -0.42], [0.75, 0.05, -0.66], [0.38, 0.32, 0.26], [0.0, 0.03, 0.05])
    thumb = chain(p, tpts, [0.16, 0.12, 0.11, 0.095], ys=1.2)
    thumb = smin(thumb, ellipsoid(p, [-0.05, -0.02, -0.38], [0.36, 0.14, 0.2]), 0.12)
    HAND_FINGERS.insert(0, {"pts": tpts, "r": [0.16, 0.12, 0.11, 0.095]})
    d = smin(d, thumb, 0.1)
    # tendões sutis no dorso
    for base, *_ in specs:
        d = smin(d, capsule(p, [-0.35, 0.12, base[2] * 0.45], [base[0] - 0.08, 0.12, base[2]], 0.025), 0.06)
    return d

# ---------------------------------------------------------------- PÉ
# Pé direito visto de cima, dedos apontando +X, dedão em -Z.

FOOT_TOES = []
def foot_sdf(p):
    global FOOT_TOES
    FOOT_TOES = []
    heel = ellipsoid(p, [-1.25, 0.05, 0.03], [0.42, 0.33, 0.36])
    mid = ellipsoid(p, [-0.35, 0.08, 0.0], [0.85, 0.3, 0.42])
    ball = ellipsoid(p, [0.45, -0.02, -0.02], [0.45, 0.2, 0.6])
    d = smin(heel, mid, 0.3)
    d = smin(d, ball, 0.3)
    # peito do pé mais alto perto do tornozelo
    d = smin(d, ellipsoid(p, [-0.75, 0.22, -0.02], [0.6, 0.25, 0.35]), 0.25)
    leg = chain(p, [[-0.9, 0.22, 0.0], [-2.0, 0.24, 0.0], [-3.4, 0.26, 0.0]], [0.36, 0.37, 0.4], ys=1.25)
    d = smin(d, leg, 0.35)
    # tornozelos
    d = smin(d, ellipsoid(p, [-1.0, 0.28, -0.33], [0.13, 0.12, 0.08]), 0.1)
    d = smin(d, ellipsoid(p, [-1.0, 0.25, 0.34], [0.13, 0.12, 0.08]), 0.1)
    toes = None
    specs = [
        ([0.82, 0.0, -0.4],  [1, 0.0, -0.04], [0.24, 0.2],  0.17, 0.155),
        ([0.86, -0.02, -0.12], [1, 0, 0.02], [0.17, 0.13, 0.1], 0.1, 0.085),
        ([0.8, -0.03, 0.08],  [1, 0, 0.08],  [0.15, 0.12, 0.09], 0.095, 0.08),
        ([0.7, -0.04, 0.26],  [1, 0, 0.15],  [0.13, 0.1, 0.08], 0.088, 0.075),
        ([0.55, -0.05, 0.42], [1, 0, 0.25],  [0.11, 0.08, 0.07], 0.08, 0.068),
    ]
    for i, (base, dirv, lens, r0, r1) in enumerate(specs):
        drop = [0.0, 0.03, 0.03][:len(lens)]
        pts = finger_pts(base, dirv, lens, drop)
        rr = list(np.linspace(r0, r1, len(pts)))
        t = chain(p, pts, rr, ys=1.25)
        FOOT_TOES.append({"pts": pts, "r": rr})
        toes = t if toes is None else np.minimum(toes, t)
    d = smin(d, toes, 0.08)
    # tendões
    for base, *_ in specs[:4]:
        d = smin(d, capsule(p, [-0.5, 0.3, base[2] * 0.3], [base[0] - 0.2, 0.15, base[2]], 0.025), 0.07)
    return d

# ---------------------------------------------------------------- malha

def build(sdf_fn, bmin, bmax, step, name, tips_key):
    xs = np.arange(bmin[0], bmax[0] + step, step)
    ys = np.arange(bmin[1], bmax[1] + step, step)
    zs = np.arange(bmin[2], bmax[2] + step, step)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    P = np.stack([X.ravel(), Y.ravel(), Z.ravel()], axis=1)
    vol = sdf_fn(P).reshape(X.shape)
    # corta a parte de baixo (fica enterrada no travesseiro)
    verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
    verts += np.array(bmin)
    # normais pelo gradiente do SDF (bem suaves)
    e = step * 0.5
    def grad(v):
        g = np.zeros_like(v)
        for i in range(3):
            o = np.zeros(3); o[i] = e
            g[:, i] = sdf_fn(v + o) - sdf_fn(v - o)
        n = np.linalg.norm(g, axis=1, keepdims=True)
        return g / np.maximum(n, 1e-9)
    # suavização leve (Laplaciano) para tirar degraus
    for _ in range(2):
        nb_sum = np.zeros_like(verts); cnt = np.zeros(len(verts))
        for a, b in ((0, 1), (1, 2), (2, 0)):
            np.add.at(nb_sum, faces[:, a], verts[faces[:, b]]); np.add.at(cnt, faces[:, a], 1)
            np.add.at(nb_sum, faces[:, b], verts[faces[:, a]]); np.add.at(cnt, faces[:, b], 1)
        verts = verts * 0.5 + 0.5 * nb_sum / np.maximum(cnt[:, None], 1)
        # reprojeta na superfície
        n = grad(verts)
        verts = verts - n * sdf_fn(verts)[:, None]
    norms = grad(verts)
    # oclusão ambiente "assada" pelo SDF -> dá sombra nos vãos dos dedos
    ao = np.ones(len(verts))
    for i, dist in enumerate([0.04, 0.09, 0.16, 0.26]):
        s = sdf_fn(verts + norms * dist)
        ao -= (dist - np.clip(s, 0, dist)) / dist * (0.5 ** i) * 0.45
    ao = np.clip(ao, 0.25, 1.0)
    # remove triângulos muito abaixo (embaixo do travesseiro)
    keep = verts[faces].mean(axis=1)[:, 1] > bmin[1] + step * 1.5
    faces = faces[keep]
    # godot usa ordem horária: inverte
    faces = faces[:, [0, 2, 1]]

    # heightmap visto de cima
    hres = 0.01
    hx = np.arange(bmin[0], bmax[0], hres); hz = np.arange(bmin[2], bmax[2], hres)
    HX, HZ = np.meshgrid(hx, hz, indexing="ij")
    rp = np.stack([HX.ravel(), np.full(HX.size, bmax[1] + 0.05), HZ.ravel()], axis=1)
    hit = np.zeros(len(rp), bool)
    for _ in range(320):
        dd = sdf_fn(rp)
        hit |= dd < 0.001
        # passo reduzido: o SDF achatado superestima a distância
        rp[:, 1] -= np.where(hit, 0, np.maximum(dd * 0.4, 0.0008))
        rp[:, 1] = np.maximum(rp[:, 1], bmin[1])
    hgt = np.where(hit & (rp[:, 1] > bmin[1] + 0.05), rp[:, 1], -9.0)
    hn = grad(rp)
    print(name, "verts", len(verts), "tris", len(faces))
    data = {
        "verts": np.round(verts, 5).ravel().tolist(),
        "norms": np.round(norms, 4).ravel().tolist(),
        "ao": np.round(ao, 3).tolist(),
        "faces": faces.ravel().astype(int).tolist(),
        "hmap": {"x0": float(bmin[0]), "z0": float(bmin[2]), "res": hres, "w": len(hx), "h": len(hz),
                 "y": np.round(hgt, 4).tolist(), "n": np.round(hn, 3).ravel().tolist()},
        "digits": tips_key,
    }
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(data, f)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    step = float(sys.argv[1]) if len(sys.argv) > 1 else 0.022
    hand_sdf(np.zeros((1, 3)))
    build(hand_sdf, [-2.9, -0.3, -1.35], [2.05, 0.36, 0.9], step, "hand", HAND_FINGERS)
    foot_sdf(np.zeros((1, 3)))
    build(foot_sdf, [-2.9, -0.36, -0.85], [1.45, 0.66, 0.85], step, "foot", FOOT_TOES)
