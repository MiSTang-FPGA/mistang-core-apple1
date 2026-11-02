import subprocess, sys, random, os
sys.path.insert(0, os.path.dirname(__file__)); import ref6502
seed=int(sys.argv[1]); dec=len(sys.argv)>2
def ok(n): return subprocess.run(['python3','tools/difftest.py',str(seed),str(n)]+(['dec'] if dec else []),capture_output=True,timeout=120).returncode==0
lo,hi=0,400
while lo+1<hi:
    mid=(lo+hi)//2
    if ok(mid): lo=mid
    else: hi=mid
r=random.Random(seed); mem=[r.randrange(256) for _ in range(65536)]
mem[0xFFFC],mem[0xFFFD]=0,2; mem[0xFFFE],mem[0xFFFF]=0,3
for i in range(0x200,0x300): mem[i]=r.randrange(256)
if dec: mem[0x200]=0xF8
c=ref6502.CPU(list(mem))
for i in range(hi):
    pc=c.PC; st=(c.A,c.X,c.Y,c.S,c.P()); c.step()
print('first bad instruction #%d at %04x: %02x %02x %02x ; before A=%02x X=%02x Y=%02x S=%02x P=%02x'%((hi,pc,mem[pc],mem[pc+1],mem[pc+2])+st))
