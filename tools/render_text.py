#!/usr/bin/env python3
"""Render 24 text rows with the 8x8 font at 3x scale into the same text form the video testbench writes ('#' / '.').
usage: render_text.py screen.txt font8x8.hex [out.png]"""
import sys, os, subprocess
rows=[l.rstrip('\n').ljust(40)[:40] for l in open(sys.argv[1])][:24]
font=[int(x,16) for x in open(sys.argv[2]).read().split()]
out=[]
for r in range(24):
    for gy in range(8):
        line=''
        for c in range(40):
            g=font[ord(rows[r][c])*8+gy]
            for gx in range(8): line+=('#' if (g>>(7-gx))&1 else '.')*3
        out+= [line]*3
text='\n'.join(out)+'\n'
if len(sys.argv)>3 and sys.argv[3].endswith('.png'):
    open(sys.argv[3][:-4]+'.txt','w').write(text)
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)),'fb2png.py'), sys.argv[3][:-4]+'.txt', sys.argv[3], '1'], check=True)
else: sys.stdout.write(text)
