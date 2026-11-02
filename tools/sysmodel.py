#!/usr/bin/env python3
"""Reference model of the Apple I system: ref6502 CPU + the same I/O semantics and terminal behaviour. usage: sysmodel.py rom.hex keys.txt > screen.txt"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import ref6502

class Term:
    def __init__(s): s.rows=[[' ']*40 for _ in range(24)]; s.x=0; s.y=0
    def nl(s):
        s.x=0
        if s.y==23: s.rows=s.rows[1:]+[[' ']*40]
        else: s.y+=1
    def put(s,ch):
        if ch==0x0D: s.nl()
        elif ch==0x08:
            if s.x: s.x-=1; s.rows[s.y][s.x]=' '
        elif 0x20<=ch<0x7F:
            s.rows[s.y][s.x]=chr(ch)
            if s.x==39: s.nl()
            else: s.x+=1

class Sys(ref6502.CPU):
    def __init__(s, rom, keys):
        mem=[0]*65536
        for i,b in enumerate(rom): mem[0xF000+i]=b
        s.keys=list(keys); s.kbd=0; s.rdy=False; s.term=Term(); s.ram=[0]*4096; s.rom=rom
        s.m=mem
        super().__init__(mem)
    def feed(s):
        if not s.rdy and s.keys:
            c=s.keys.pop(0)
            if 0x61<=c<=0x7A: c-=0x20
            if c==0x0A: c=0x0D
            s.kbd=c&0x7F; s.rdy=True
    def rd(s,a):
        a&=0xFFFF
        if a<0x1000: return s.ram[a]
        if a>=0xF000: return s.rom[a-0xF000]
        if 0xD010<=a<=0xD013:
            r=a&3
            if r==0: s.rdy=False; return 0x80|s.kbd
            if r==1: s.feed(); return 0x80 if s.rdy else 0
            return 0
        return 0
    def wr(s,a,v):
        a&=0xFFFF
        if a<0x1000: s.ram[a]=v&255
        elif 0xD010<=a<=0xD013 and (a&3)==2: s.term.put(v&0x7F)

if __name__=='__main__':
    rom=[int(x,16) for x in open(sys.argv[1]).read().split()]
    keys=[ord(c) for c in open(sys.argv[2]).read()]
    system=Sys(rom,keys)
    system.feed()
    for _ in range(3_000_000):
        system.step()
        if not system.keys and not system.rdy and system.PC in range(0xF000,0xF100): pass
    print('\n'.join(''.join(r) for r in system.term.rows))
