#!/usr/bin/env python3
"""Generate PWA app icons (PNG) — pure Python, no Pillow.
Harbor-blue gradient with white Gantt bars + a gold 'today' line.
Run from the project root: python .claude/make_icons.py"""
import zlib, struct, os

OUT = "."
TOP = (42, 134, 192)     # #2a86c0
BOT = (19, 76, 116)      # #134c74
WHITE = (255, 255, 255)
GOLD = (255, 209, 102)   # #ffd166

# Bars as fractions of size: (x, y, w, h, alpha)
BARS = [
    (0.234, 0.293, 0.391, 0.066, 0.95),
    (0.332, 0.414, 0.449, 0.066, 0.78),
    (0.273, 0.535, 0.293, 0.066, 0.90),
    (0.410, 0.656, 0.352, 0.066, 0.66),
]
TODAY = (0.586, 0.250, 0.0137, 0.520)   # x,y,w,h fraction (gold line)

def make_icon(size, path):
    W = H = size
    corner = size * 0.219  # rounded-rect radius fraction (112/512)
    def in_round_rect(x, y):
        # outer icon rounded corners
        if x < corner and y < corner:
            return (x-corner)**2 + (y-corner)**2 <= corner*corner
        if x > W-corner and y < corner:
            return (x-(W-corner))**2 + (y-corner)**2 <= corner*corner
        if x < corner and y > H-corner:
            return (x-corner)**2 + (y-(H-corner))**2 <= corner*corner
        if x > W-corner and y > H-corner:
            return (x-(W-corner))**2 + (y-(H-corner))**2 <= corner*corner
        return True

    bars_px = [(bx*W, by*H, bw*W, bh*H, ba) for (bx,by,bw,bh,ba) in BARS]
    tx, ty, tw, th = (TODAY[0]*W, TODAY[1]*H, TODAY[2]*W, TODAY[3]*H)

    def bar_hit(x, y):
        for (bx,by,bw,bh,ba) in bars_px:
            r = bh/2
            if by <= y <= by+bh:
                if bx+r <= x <= bx+bw-r:
                    return ba
                # rounded ends
                cy = by+bh/2
                if (x-(bx+r))**2 + (y-cy)**2 <= r*r: return ba
                if (x-(bx+bw-r))**2 + (y-cy)**2 <= r*r: return ba
        return 0.0

    def today_hit(x, y):
        return (tx <= x <= tx+tw) and (ty <= y <= ty+th)

    raw = bytearray()
    for y in range(H):
        raw.append(0)
        t = y/(H-1)
        bg = (int(TOP[0]+(BOT[0]-TOP[0])*t), int(TOP[1]+(BOT[1]-TOP[1])*t), int(TOP[2]+(BOT[2]-TOP[2])*t))
        for x in range(W):
            if not in_round_rect(x+0.5, y+0.5):
                raw += bytes((0,0,0,0)); continue
            r,g,b = bg
            if today_hit(x+0.5, y+0.5):
                r,g,b = GOLD
            else:
                a = bar_hit(x+0.5, y+0.5)
                if a > 0:
                    r = int(r+(WHITE[0]-r)*a); g = int(g+(WHITE[1]-g)*a); b = int(b+(WHITE[2]-b)*a)
            raw += bytes((r,g,b,255))

    def chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ+data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
           + chunk(b'IEND', b''))
    with open(os.path.join(OUT, path), 'wb') as f:
        f.write(png)
    print(path, len(png), "bytes")

for s, p in [(180,'icon-180.png'), (192,'icon-192.png'), (512,'icon-512.png')]:
    make_icon(s, p)
print("done")
