#!/usr/bin/env python3
"""Screenshot from the board over the USB-UART: 'APL1' + top40 (2 bytes) + 960 text bytes -> PNG at 960x576 (like the HDMI picture).
usage: capture.py /dev/cu.usbserial-XXXX out.png"""
import os, sys, termios, time, subprocess
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=0; a[1]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL; a[3]=0
a[4]=a[5]=termios.B115200; a[6][termios.VMIN]=0; a[6][termios.VTIME]=0; termios.tcsetattr(fd, termios.TCSANOW, a)
buf = b''; t = time.time()
while time.time() - t < 10:
    try: buf += os.read(fd, 8192)
    except BlockingIOError: time.sleep(0.02)
    i = buf.find(b'APL1')
    if i >= 0 and len(buf) >= i + 4 + 2 + 960:
        top = (buf[i+4] << 8) | buf[i+5]; ram = buf[i+6:i+6+960]
        rows = [''.join(chr(ram[(top + r*40 + c) % 960]) if 32 <= ram[(top + r*40 + c) % 960] < 127 else ' ' for c in range(40)) for r in range(24)]
        txt = os.path.splitext(sys.argv[2])[0] + '.screen'
        open(txt, 'w').write('\n'.join(rows) + '\n')
        here = os.path.dirname(os.path.abspath(__file__))
        subprocess.run([sys.executable, os.path.join(here, 'render_text.py'), txt, os.path.join(here, '..', 'rom', 'font8x8.hex'), sys.argv[2]], check=True)
        print('captured'); sys.exit(0)
print('no frame, got', len(buf), 'bytes'); sys.exit(1)
