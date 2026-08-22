#!/usr/bin/env python3
"""Renders the Tinbox app icon (design_handoff_gba_player/Tinbox Icon.dc.html)
to a 1024x1024 PNG using only the standard library.

    python3 Scripts/gen_icon.py

Output: Tinbox/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
The squircle mask is applied by iOS; the PNG is a full opaque square.
"""
import math
import os
import struct
import sys
import zlib

SIZE = 1024
SS = 2                      # supersampling factor
SCALE = SIZE * SS / 240.0   # design units -> supersampled pixels


def hex_rgb(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def rrect_sdf(px, py, x, y, w, h, r_tl, r_tr, r_br, r_bl):
    """Signed distance to a rounded rectangle with per-corner radii (design units)."""
    cx, cy = x + w / 2, y + h / 2
    qx, qy = px - cx, py - cy
    if qx >= 0 and qy < 0:
        r = r_tr
    elif qx >= 0 and qy >= 0:
        r = r_br
    elif qx < 0 and qy >= 0:
        r = r_bl
    else:
        r = r_tl
    dx = abs(qx) - (w / 2 - r)
    dy = abs(qy) - (h / 2 - r)
    ox, oy = max(dx, 0), max(dy, 0)
    return math.hypot(ox, oy) + min(max(dx, dy), 0) - r


def circle_sdf(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r


def coverage(d):
    # d in design units; anti-alias over ~0.6 design units
    return max(0.0, min(1.0, 0.5 - d / 0.6))


BG_A, BG_B = hex_rgb('#2B2016'), hex_rgb('#160F09')
LID_A, LID_B = hex_rgb('#D08A57'), hex_rgb('#AB6236')
BODY_A, BODY_B = hex_rgb('#BC7245'), hex_rgb('#8F4F2C')
STAMP = (58, 30, 14)
STAMP_ALPHA = 0.5

# Layout in 240-unit design space (from the HTML concept).
LID = (44, 64, 152, 34)
BODY = (53, 96, 134, 80)
DPAD_V = (53 + 30, 96 + 22, 12, 36)
DPAD_H = (53 + 18, 96 + 34, 36, 12)
DOT_1 = (53 + 84 + 7.5, 96 + 20 + 7.5, 7.5)
DOT_2 = (53 + 102 + 7.5, 96 + 38 + 7.5, 7.5)


def shade(px, py):
    # Background: 160deg gradient (top-left -> bottom-right-ish).
    ang = math.radians(160)
    gx, gy = math.sin(ang), -math.cos(ang)
    t = ((px - 120) * gx + (py - 120) * gy) / 240.0 + 0.5
    t = max(0.0, min(1.0, t))
    color = lerp(BG_A, BG_B, t)

    # Soft drop shadow under the tin.
    sh = coverage(rrect_sdf(px, py - 6, 48, 70, 144, 104, 14, 14, 18, 18) - 6)
    color = lerp(color, (0, 0, 0), 0.35 * sh)

    # Lid
    d = rrect_sdf(px, py, *LID, 12, 12, 12, 12)
    c = coverage(d)
    if c > 0:
        t = (py - LID[1]) / LID[3]
        lid = lerp(LID_A, LID_B, max(0.0, min(1.0, t)))
        if py - LID[1] < 2:  # inset top highlight
            lid = lerp(lid, (255, 255, 255), 0.3)
        color = lerp(color, lid, c)

    # Body (rounded bottom corners only)
    d = rrect_sdf(px, py, *BODY, 0, 0, 16, 16)
    c = coverage(d)
    if c > 0:
        t = (py - BODY[1]) / BODY[3]
        body = lerp(BODY_A, BODY_B, max(0.0, min(1.0, t)))
        if py - BODY[1] < 2:
            body = lerp(body, (255, 255, 255), 0.18)
        color = lerp(color, body, c)

        # Stamped d-pad + dots
        stamp = 0.0
        for rr in (DPAD_V, DPAD_H):
            stamp = max(stamp, coverage(rrect_sdf(px, py, *rr, 4, 4, 4, 4)))
        for dot in (DOT_1, DOT_2):
            stamp = max(stamp, coverage(circle_sdf(px, py, *dot)))
        if stamp > 0:
            color = lerp(color, STAMP, STAMP_ALPHA * stamp * c)
            # bottom-edge highlight of the stamp
            hl = 0.0
            for rr in (DPAD_V, DPAD_H):
                hl = max(hl, coverage(rrect_sdf(px, py - 1.2, *rr, 4, 4, 4, 4)))
            for dot in (DOT_1, DOT_2):
                hl = max(hl, coverage(circle_sdf(px, py - 1.2, *dot)))
            edge = max(0.0, hl - stamp)
            color = lerp(color, (255, 255, 255), 0.15 * edge * c)
    return color


def render():
    w = SIZE
    rows = []
    inv = 1.0 / SCALE
    for y in range(w):
        row = bytearray()
        for x in range(w):
            r = g = b = 0.0
            for sy in range(SS):
                for sx in range(SS):
                    px = (x * SS + sx + 0.5) * inv
                    py = (y * SS + sy + 0.5) * inv
                    cr, cg, cb = shade(px, py)
                    r += cr
                    g += cg
                    b += cb
            n = SS * SS
            row += bytes((int(round(r / n)), int(round(g / n)), int(round(b / n))))
        rows.append(bytes(row))
        if y % 128 == 0:
            print(f"  {y}/{w}", file=sys.stderr)
    return rows


def write_png(path, rows):
    def chunk(tag, data):
        c = struct.pack('>I', len(data)) + tag + data
        return c + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b''.join(b'\x00' + r for r in rows)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', SIZE, SIZE, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


if __name__ == '__main__':
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, 'Tinbox', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, 'AppIcon-1024.png')
    print('Rendering icon…', file=sys.stderr)
    write_png(out, render())
    print(f'Wrote {out}', file=sys.stderr)
