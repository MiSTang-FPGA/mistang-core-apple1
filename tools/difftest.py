#!/usr/bin/env python3
"""Random-program differential test: RTL (iverilog) vs tools/ref6502.py. usage: difftest.py SEED INSTR [decimal]"""
import random, subprocess, sys, os
sys.path.insert(0, os.path.dirname(__file__)); import ref6502
seed, n = int(sys.argv[1]), int(sys.argv[2]); dec = len(sys.argv) > 3
r = random.Random(seed)
mem = [r.randrange(256) for _ in range(65536)]
# keep the stack page and low pages tame, put the reset vector at 0x0200, brk vector at 0x0300
mem[0xFFFC], mem[0xFFFD] = 0x00, 0x02; mem[0xFFFE], mem[0xFFFF] = 0x00, 0x03
OFF = {0x00} if False else set()
prog = []
for i in range(0x200, 0x300): mem[i] = r.randrange(256)
if dec:
    mem[0x200] = 0xF8   # SED first
open('build/rand_mem.hex','w').write('\n'.join('%02x'%b for b in mem)+'\n')
ref = ref6502.CPU(list(mem))
for _ in range(n): ref.step()
subprocess.run(['iverilog','-g2012','-DINSTR=%d'%n,'-o','build/tbc.vvp','sim/tb_cpu.sv','rtl/cpu6502.sv'], check=True, stderr=subprocess.DEVNULL)
subprocess.run(['vvp','build/tbc.vvp'], check=True, stdout=subprocess.DEVNULL, timeout=60)
L = open('build/rtl_state.txt').read().split('\n')
pc,a,x,y,s,p = [int(v,16) for v in L[0].split()]
rm = [int(v,16) for v in L[1:65537]]
exp = (ref.PC, ref.A, ref.X, ref.Y, ref.S, ref.P(1) if False else (ref.N<<7|ref.V<<6|0x30|ref.D<<3|ref.I<<2|ref.Z<<1|ref.C))
got = (pc, a, x, y, s, p)
bad = [i for i in range(65536) if rm[i] != ref.m[i]]
if exp == got and not bad: print('seed %d: OK (%d instr)' % (seed, n)); sys.exit(0)
print('seed %d: MISMATCH' % seed); print(' expected', [hex(v) for v in exp]); print(' got     ', [hex(v) for v in got]); print(' mem diffs', [hex(i) for i in bad[:8]]); sys.exit(1)
