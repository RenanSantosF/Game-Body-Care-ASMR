"""Gera logo e ícone do app (PIL). python3 tools/make_art.py"""
import math, os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = os.path.join(os.path.dirname(__file__), "..")
FONT = os.path.join(ROOT, "assets/fonts/LilitaOne-Regular.ttf")
OUT = os.path.join(ROOT, "assets/ui")
random.seed(3)

def grad(size, top, bottom):
    w, h = size
    g = Image.new("RGBA", size)
    d = ImageDraw.Draw(g)
    for y in range(h):
        k = y / max(1, h - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * k) for i in range(4))
        d.line([(0, y), (w, y)], fill=c)
    return g

def text_layer(text, size, font, pos):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).text(pos, text, font=font, fill=255)
    return m

def word(canvas, text, font, pos, top, bottom, outline, drips=False, sparkle=False):
    W, H = canvas.size
    mask = text_layer(text, (W, H), font, pos)
    if drips:
        d = ImageDraw.Draw(mask)
        bbox = mask.getbbox()
        x0, y0, x1, y1 = bbox
        for i in range(7):
            x = random.randint(x0 + 20, x1 - 20)
            # só pinga onde há letra embaixo
            col = [mask.getpixel((x, y)) for y in range(y0, y1)]
            ys = [y0 + i for i, v in enumerate(col) if v > 128]
            if not ys:
                continue
            yb = max(ys)
            L = random.randint(25, 70)
            r = random.randint(9, 15)
            d.rounded_rectangle([x - r * 0.6, yb - 10, x + r * 0.6, yb + L], radius=int(r * 0.6), fill=255)
            d.ellipse([x - r, yb + L - r, x + r, yb + L + r], fill=255)
    # sombra
    sh = mask.filter(ImageFilter.GaussianBlur(10))
    shadow = Image.new("RGBA", (W, H), (40, 10, 60, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.6)))
    canvas.alpha_composite(shadow, (0, 14))
    # contorno grosso
    ol = mask.filter(ImageFilter.MaxFilter(25))
    layer = Image.new("RGBA", (W, H), outline + (255,))
    layer.putalpha(ol)
    canvas.alpha_composite(layer)
    ol2 = mask.filter(ImageFilter.MaxFilter(11))
    layer2 = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    layer2.putalpha(ol2)
    canvas.alpha_composite(layer2)
    # preenchimento em degradê
    bbox = mask.getbbox()
    g = grad((W, bbox[3] - bbox[1] + 4), top, bottom)
    fill = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fill.paste(g, (0, bbox[1]))
    fill.putalpha(ImageChops.multiply(fill.split()[3], mask))
    canvas.alpha_composite(fill)
    # brilho no topo das letras
    hl = ImageChops.subtract(mask, ImageChops.offset(mask, 0, -12))
    hl = hl.filter(ImageFilter.GaussianBlur(3)).point(lambda v: int(v * 0.55))
    hli = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    hli.putalpha(ImageChops.subtract(mask, ImageChops.offset(mask, 0, 10)).point(lambda v: int(v * 0.0)) )
    gloss = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    gl = ImageChops.multiply(mask, ImageChops.offset(mask.point(lambda v: 255 - v), 0, 16).point(lambda v: 255 - v))
    gl = ImageChops.subtract(mask, ImageChops.offset(mask, 0, -18)).point(lambda v: 0)
    top_band = Image.new("L", (W, H), 0)
    ImageDraw.Draw(top_band).rectangle([0, bbox[1], W, bbox[1] + (bbox[3] - bbox[1]) * 0.38], fill=110)
    gloss.putalpha(ImageChops.multiply(mask.filter(ImageFilter.MinFilter(9)), top_band))
    canvas.alpha_composite(gloss)
    if sparkle:
        d = ImageDraw.Draw(canvas)
        for (sx, sy, r) in [(bbox[2] - 10, bbox[1] + 5, 34), (bbox[0] + 40, bbox[1] + 15, 22), (bbox[2] - 120, bbox[3] - 20, 18)]:
            star(d, sx, sy, r)
    return bbox

def star(d, x, y, r):
    pts = []
    for k in range(8):
        a = k * math.pi / 4
        rr = r if k % 2 == 0 else r * 0.28
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    d.polygon(pts, fill=(255, 255, 255, 255))

def logo():
    W, H = 1100, 760
    c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    big = ImageFont.truetype(FONT, 250)
    small = ImageFont.truetype(FONT, 120)
    word(c, "GROSS", big, (140, 10), (190, 255, 90, 255), (60, 170, 40, 255), (30, 70, 20), drips=True)
    word(c, "to", small, (480, 290), (255, 255, 255, 255), (230, 220, 255, 255), (70, 40, 110))
    word(c, "GLOW", big, (175, 420), (255, 245, 150, 255), (255, 160, 40, 255), (120, 55, 0), sparkle=True)
    c = c.crop(c.getbbox())
    c.save(os.path.join(OUT, "logo.png"))

def icon():
    S = 1024
    c = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = grad((S, S), (255, 120, 190, 255), (125, 90, 255, 255))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1], radius=220, fill=255)
    c.paste(bg, (0, 0), m)
    d = ImageDraw.Draw(c)
    # bolhas
    for i in range(14):
        x, y, r = random.randint(60, S - 60), random.randint(60, S - 60), random.randint(14, 50)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, 40))
    # "pele" com espinha
    skin = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sd = ImageDraw.Draw(skin)
    sd.ellipse([150, 230, 874, 954], fill=(246, 196, 160, 255))
    sh = skin.split()[3].filter(ImageFilter.GaussianBlur(18))
    shadow = Image.new("RGBA", (S, S), (60, 20, 80, 0))
    shadow.putalpha(sh.point(lambda v: int(v * 0.5)))
    c.alpha_composite(shadow, (0, 22))
    c.alpha_composite(skin)
    # vermelhidão
    rm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rm).ellipse([330, 420, 690, 780], fill=200)
    red = Image.new("RGBA", (S, S), (230, 90, 90, 255))
    red.putalpha(rm.filter(ImageFilter.GaussianBlur(50)))
    c.alpha_composite(red)
    # espinha com cabeça de pus
    d = ImageDraw.Draw(c)
    d.ellipse([400, 480, 620, 700], fill=(240, 120, 110, 255))
    pm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(pm).ellipse([450, 500, 580, 630], fill=255)
    pus = Image.new("RGBA", (S, S), (255, 222, 110, 255))
    pus.putalpha(pm.filter(ImageFilter.GaussianBlur(6)))
    c.alpha_composite(pus)
    d.ellipse([480, 515, 525, 555], fill=(255, 255, 240, 230))
    # pinça entrando
    d.polygon([(860, 120), (895, 150), (620, 470), (600, 455)], fill=(205, 215, 230, 255), outline=(60, 50, 90, 255))
    d.polygon([(905, 165), (935, 200), (640, 490), (620, 470)], fill=(185, 195, 215, 255), outline=(60, 50, 90, 255))
    # brilhos
    for (x, y, r) in [(230, 220, 60), (820, 760, 44), (180, 760, 30)]:
        star(d, x, y, r)
    c.save(os.path.join(ROOT, "icon.png"))
    c.resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon512.png"))

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    logo()
    icon()
    print("ok")
