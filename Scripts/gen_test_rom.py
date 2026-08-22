#!/usr/bin/env python3
"""Writes Tests/tinbox-test.gba — a tiny hand-assembled GBA ROM (no toolchain
needed) that switches to video mode 3 and draws scrolling colour bands. CI
auto-opens it in the simulator so the screenshots prove the mGBA core runs.

    python3 Scripts/gen_test_rom.py
"""
import os
import struct

rom = bytearray(4096)

def w32(off, value):
    struct.pack_into('<I', rom, off, value & 0xFFFFFFFF)

# --- header ------------------------------------------------------------
w32(0x00, 0xEA00002E)               # b 0xC0 (entry point)
rom[0xA0:0xAC] = b'TINBOX TEST '    # game title (12)
rom[0xAC:0xB0] = b'TBOX'            # game code
rom[0xB0:0xB2] = b'01'              # maker code
rom[0xB2] = 0x96                    # fixed value (mGBA checks this)
rom[0xB3] = 0x00                    # main unit code
rom[0xBC] = 0x00                    # software version
chk = 0
for i in range(0xA0, 0xBD):
    chk = (chk - rom[i]) & 0xFF
rom[0xBD] = (chk - 0x19) & 0xFF     # header checksum

# --- code (ARM) at 0xC0 -------------------------------------------------
code = [
    0xE3A00404,  # mov   r0, #0x04000000      ; I/O base
    0xE3A01B01,  # mov   r1, #0x400
    0xE3811003,  # orr   r1, r1, #3           ; DISPCNT = mode 3 | BG2 on
    0xE5801000,  # str   r1, [r0]
    0xE3A04000,  # mov   r4, #0               ; frame colour offset
    # frame:                      (0xD4)
    0xE3A02406,  # mov   r2, #0x06000000      ; VRAM
    0xE3A03C96,  # mov   r3, #0x9600          ; 240*160 pixels
    0xE1A05004,  # mov   r5, r4
    # pixel:                      (0xE0)
    0xE0C250B2,  # strh  r5, [r2], #2
    0xE2855001,  # add   r5, r5, #1
    0xE2533001,  # subs  r3, r3, #1
    0x1AFFFFFB,  # bne   pixel
    0xE2844C02,  # add   r4, r4, #0x200       ; scroll the bands next frame
    # vwait:                      (0xF4)
    0xE1D060B6,  # ldrh  r6, [r0, #6]         ; VCOUNT
    0xE35600A0,  # cmp   r6, #160
    0x1AFFFFFC,  # bne   vwait
    0xEAFFFFF3,  # b     frame
]
for i, instr in enumerate(code):
    w32(0xC0 + 4 * i, instr)

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, 'Tests', 'tinbox-test.gba')
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, 'wb') as f:
    f.write(rom)
print(f'Wrote {out} ({len(rom)} bytes)')
