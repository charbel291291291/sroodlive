import math, random, os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
OUT = r"C:\Users\user\Documents\Dev\srood_live\assets\gifts"
os.makedirs(OUT, exist_ok=True)

def new_canvas():
    return Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))

def radial_glow(img, cx, cy, radius, r, g, b, a=120, steps=40):
    draw = ImageDraw.Draw(img, "RGBA")
    for i in range(steps, 0, -1):
        frac = i / steps
        cr = radius * frac
        alpha = min(int(a * (1 - frac) * 1.6), 255)
        draw.ellipse((cx - cr, cy - cr, cx + cr, cy + cr), fill=(r, g, b, alpha))

def dark_bg(img, r=20, g=5, b=38, a=210, radius=215):
    layer = new_canvas()
    draw = ImageDraw.Draw(layer, "RGBA")
    cx = cy = SIZE // 2
    draw.ellipse((cx-radius, cy-radius, cx+radius, cy+radius), fill=(r,g,b,a))
    return Image.alpha_composite(img, layer)

# ─── BAALBEK ─────────────────────────────────────────────────────────────────
def make_baalbek():
    img = new_canvas()
    glow = new_canvas()
    radial_glow(glow, SIZE//2, SIZE//2, 210, 80, 0, 140, 90)
    img = Image.alpha_composite(img, glow)
    img = dark_bg(img)

    draw = ImageDraw.Draw(img, "RGBA")
    GOLD = (255, 210, 80)
    GOLD_D = (180, 130, 20)
    GOLD_B = (255, 240, 120)

    # entablature
    draw.rectangle((60, 160, 452, 195), fill=GOLD_D)
    draw.rectangle((60, 145, 452, 162), fill=GOLD)
    draw.rectangle((60, 140, 452, 147), fill=GOLD_B)

    # columns
    for cx in [90, 165, 240, 315, 390]:
        for x in range(cx, cx + 34):
            frac = (x - cx) / 34
            shade = int(170 + 70 * math.sin(frac * math.pi))
            draw.line([(x, 195), (x, 400)],
                      fill=(shade, int(shade*0.82), int(shade*0.25)))
        for seg in range(1, 6):
            lx = cx + int(34 * seg / 6)
            draw.line([(lx, 200), (lx, 395)], fill=(100, 80, 10, 120), width=1)
        draw.rectangle((cx-3, 185, cx+37, 197), fill=GOLD_B)
        draw.ellipse((cx, 163, cx+34, 187), fill=GOLD)
        draw.rectangle((cx-4, 400, cx+38, 414), fill=GOLD)
        draw.rectangle((cx-8, 413, cx+42, 420), fill=GOLD_D)

    # platform
    draw.rectangle((45, 420, 467, 438), fill=GOLD)
    draw.rectangle((55, 410, 457, 422), fill=GOLD_D)

    # frieze dots
    for i in range(10):
        fx = 75 + i * 34
        draw.ellipse((fx, 152, fx+10, 162), fill=GOLD_B)

    # star
    for angle in range(0, 360, 45):
        rad = math.radians(angle)
        x1 = 256 + 20 * math.cos(rad)
        y1 = 95 + 20 * math.sin(rad)
        draw.line([(256, 95), (int(x1), int(y1))], fill=GOLD_B, width=3)

    # gold glow ring
    gl = new_canvas()
    gd = ImageDraw.Draw(gl, "RGBA")
    for r in range(30, 0, -1):
        alpha = int(60 * (1 - r/30))
        gd.ellipse((256-218-r, 256-218-r, 256+218+r, 256+218+r),
                   outline=(255, 210, 80, alpha), width=2)
    img = Image.alpha_composite(img, gl)
    return img.filter(ImageFilter.GaussianBlur(0.4))

# ─── LION ────────────────────────────────────────────────────────────────────
def make_lion():
    img = new_canvas()
    glow = new_canvas()
    radial_glow(glow, SIZE//2, SIZE//2, 200, 160, 80, 0, 90)
    img = Image.alpha_composite(img, glow)
    img = dark_bg(img, 25, 10, 5, 210)

    draw = ImageDraw.Draw(img, "RGBA")
    MANE_G = (200, 130, 10)
    MANE_B = (255, 190, 50)
    FUR = (230, 175, 60)
    FUR_L = (255, 215, 100)
    DARK = (160, 100, 20)
    AMBER = (255, 165, 0)
    PINK = (200, 110, 90)
    WHITE = (255, 250, 240)

    cx, cy = 256, 276

    # mane layers
    for r_off, col in [(105, (120,70,5)), (95, (160,100,10)), (88, MANE_G), (80, MANE_B)]:
        draw.ellipse((cx-r_off, cy-r_off-10, cx+r_off, cy+r_off+5), fill=(*col, 255))

    # mane rays
    for angle in range(0, 360, 18):
        rad = math.radians(angle)
        length = 85 + 8 * math.sin(angle * 0.3)
        x1 = cx + int(65 * math.cos(rad)); y1 = (cy-5) + int(65 * math.sin(rad))
        x2 = cx + int(length * math.cos(rad)); y2 = (cy-5) + int(length * math.sin(rad))
        draw.line([(x1,y1),(x2,y2)], fill=(255,200,60,180), width=3)

    # face
    draw.ellipse((cx-72, cy-68, cx+72, cy+68), fill=FUR)
    draw.ellipse((cx-55, cy-68, cx+55, cy-15), fill=FUR_L)

    # ears
    for ex, ey in [(cx-62, cy-78), (cx+22, cy-78)]:
        draw.polygon([(ex,ey),(ex+38,ey),(ex+19,ey-32)], fill=FUR)
        draw.polygon([(ex+8,ey+2),(ex+30,ey+2),(ex+19,ey-20)], fill=DARK)

    # eyes
    for ex in [cx-28, cx+28]:
        draw.ellipse((ex-18, cy-28, ex+18, cy-2), fill=FUR_L)
        draw.ellipse((ex-13, cy-25, ex+13, cy-5), fill=AMBER)
        draw.ellipse((ex-6, cy-22, ex+6, cy-8), fill=(40,20,5))
        draw.ellipse((ex-3, cy-20, ex+3, cy-14), fill=WHITE)
        draw.arc((ex-16, cy-35, ex+16, cy-18), start=200, end=340, fill=DARK, width=4)

    # nose
    draw.polygon([(cx,cy+10),(cx-20,cy-8),(cx+20,cy-8)], fill=PINK)
    draw.ellipse((cx-5, cy+6, cx+5, cy+14), fill=PINK)

    # mouth
    draw.arc((cx-22, cy+10, cx+4, cy+32), start=190, end=270, fill=DARK, width=4)
    draw.arc((cx-4, cy+10, cx+22, cy+32), start=270, end=350, fill=DARK, width=4)

    # chin
    draw.ellipse((cx-40, cy+30, cx+40, cy+72), fill=FUR_L)

    # whiskers
    for angle, length in [(-170,65),(-165,55),(-160,60),(170,65),(165,55),(160,60)]:
        rad = math.radians(angle)
        x2 = cx + int(length * math.cos(rad)); y2 = (cy+5) + int(length * math.sin(rad))
        draw.line([(cx, cy+5),(x2, y2)], fill=WHITE, width=2)

    # crown
    crown_y = cy - 110
    draw.rectangle((cx-40, crown_y+15, cx+40, crown_y+40), fill=MANE_B)
    for i, tx in enumerate([cx-30, cx, cx+30]):
        h = 20 if i==1 else 14
        draw.polygon([(tx-10,crown_y+15),(tx+10,crown_y+15),(tx,crown_y+15-h)], fill=MANE_B)
        draw.ellipse((tx-5, crown_y+15-h-8, tx+5, crown_y+15-h+2), fill=AMBER)

    gl = new_canvas()
    gd = ImageDraw.Draw(gl, "RGBA")
    for r in range(28, 0, -1):
        alpha = int(70 * (1 - r/28))
        gd.ellipse((cx-215-r, cy-210-r, cx+215+r, cy+210+r), outline=(255,190,50,alpha), width=2)
    img = Image.alpha_composite(img, gl)
    return img.filter(ImageFilter.GaussianBlur(0.5))

# ─── ODROB ───────────────────────────────────────────────────────────────────
def make_odrob():
    img = new_canvas()
    glow = new_canvas()
    radial_glow(glow, SIZE//2, SIZE//2, 200, 200, 80, 255, 80)
    img = Image.alpha_composite(img, glow)
    img = dark_bg(img, 12, 3, 28, 210)

    draw = ImageDraw.Draw(img, "RGBA")
    cx, cy = 266, 261
    GOLD = (255, 210, 60); ORANGE = (255, 140, 0); WHITE = (255, 255, 220)

    # burst rays
    for i in range(16):
        angle = math.radians(i * 22.5)
        inner = 45 + (10 if i%2==0 else 0)
        outer = 160 + (30 if i%2==0 else 0)
        x1 = cx + inner * math.cos(angle); y1 = cy + inner * math.sin(angle)
        x2 = cx + outer * math.cos(angle); y2 = cy + outer * math.sin(angle)
        col = GOLD if i%2==0 else ORANGE
        draw.line([(x1,y1),(x2,y2)], fill=(*col, 200), width=6 if i%2==0 else 3)

    # secondary sparks
    random.seed(42)
    for i in range(8):
        angle = math.radians(i * 45 + 22)
        for r in range(80, 180, 8):
            x = cx + r * math.cos(angle); y = cy + r * math.sin(angle)
            draw.ellipse((x-3, y-3, x+3, y+3), fill=(255, 220, 80, 80))

    # explosion circles
    draw.ellipse((cx-60, cy-60, cx+60, cy+60), fill=(255,180,0,230))
    draw.ellipse((cx-44, cy-44, cx+44, cy+44), fill=(255,230,80,240))
    draw.ellipse((cx-28, cy-28, cx+28, cy+28), fill=WHITE)

    # lightning bolt
    bolt = [(cx+8,cy-42),(cx-5,cy-5),(cx+14,cy-5),(cx-8,cy+42),(cx+8,cy+8),(cx-4,cy+8),(cx+8,cy-42)]
    draw.polygon(bolt, fill=(255,240,40))
    draw.polygon(bolt, outline=(255,120,0), width=2)

    # sparks
    for _ in range(20):
        angle = random.uniform(0, 2*math.pi)
        dist = random.uniform(100, 190)
        sx = cx + dist * math.cos(angle); sy = cy + dist * math.sin(angle)
        sr = random.uniform(4, 10)
        draw.ellipse((sx-sr, sy-sr, sx+sr, sy+sr), fill=(255,230,80,200))

    gl = new_canvas()
    gd = ImageDraw.Draw(gl, "RGBA")
    for r in range(30, 0, -1):
        alpha = int(90 * (1 - r/30))
        gd.ellipse((256-215-r, 256-215-r, 256+215+r, 256+215+r), outline=(180,60,255,alpha), width=2)
    img = Image.alpha_composite(img, gl)
    return img.filter(ImageFilter.GaussianBlur(0.5))

# ─── save ────────────────────────────────────────────────────────────────────
make_baalbek().save(f"{OUT}/baalbek.png", "PNG")
print("baalbek.png saved")
make_lion().save(f"{OUT}/lion.png", "PNG")
print("lion.png saved")
make_odrob().save(f"{OUT}/odrob.png", "PNG")
print("odrob.png saved")
