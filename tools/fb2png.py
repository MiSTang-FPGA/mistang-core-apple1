#!/usr/bin/env python3
"""framebuffer text dump (# and .) -> PNG (stdlib only). usage: fb2png.py in.txt out.png [scale]"""
import sys, zlib, struct
rows = [l.rstrip('\n') for l in open(sys.argv[1]) if l.strip()]
sc = int(sys.argv[3]) if len(sys.argv) > 3 else 10
fg, bg, grid = (0xE8,0xE8,0xE8), (0x0B,0x0B,0x0B), (0x16,0x16,0x16)
w, h = len(rows[0])*sc, len(rows)*sc
raw = bytearray()
for y in range(h):
    raw.append(0)
    r = rows[y//sc]
    for x in range(w):
        on = r[x//sc] == '#'
        edge = sc > 1 and ((x % sc == 0) or (y % sc == 0))
        raw += bytes(fg if on and not edge else grid if edge else bg)
def chunk(t, d): c = struct.pack('>I', len(d)) + t + d; return c + struct.pack('>I', zlib.crc32(t + d))
open(sys.argv[2], 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
