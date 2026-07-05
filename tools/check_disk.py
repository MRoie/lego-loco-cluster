#!/usr/bin/env python3
"""Search QCOW2 disk image for LEGO-related strings."""
import sys

def search_image(path, patterns):
    results = {}
    for p in patterns:
        results[p] = 0
    
    chunk_size = 1024 * 1024  # 1 MB chunks
    with open(path, 'rb') as f:
        offset = 0
        while True:
            chunk = f.read(chunk_size)
            if not chunk:
                break
            for p in patterns:
                needle = p.encode('ascii')
                pos = 0
                while True:
                    idx = chunk.find(needle, pos)
                    if idx == -1:
                        break
                    results[p] += 1
                    # Show context
                    ctx_start = max(0, idx - 20)
                    ctx_end = min(len(chunk), idx + len(needle) + 40)
                    ctx = chunk[ctx_start:ctx_end]
                    # Print only printable context
                    printable = ''.join(chr(b) if 32 <= b < 127 else '.' for b in ctx)
                    if results[p] <= 5:
                        print("  [%s] offset=%d: %s" % (p, offset + idx, printable))
                    pos = idx + 1
            offset += chunk_size
    
    return results

def main():
    img_path = '/opt/builtin-images/win98.qcow2.builtin'
    overlay_path = None
    
    import glob
    overlays = glob.glob('/tmp/win98_*.qcow2')
    if overlays:
        overlay_path = overlays[0]
    
    patterns = ['LEGO', 'Lego', 'lego', 'LOCO', 'Loco', 'loco', 'Constructive', 'DirectPlay']
    
    print("=== Searching BASE image: %s ===" % img_path)
    r = search_image(img_path, patterns)
    for p, c in r.items():
        if c > 0:
            print("  %s: %d occurrences" % (p, c))
    if all(c == 0 for c in r.values()):
        print("  NO LEGO/LOCO references found in base image!")
    
    if overlay_path:
        print("\n=== Searching OVERLAY: %s ===" % overlay_path)
        r2 = search_image(overlay_path, patterns)
        for p, c in r2.items():
            if c > 0:
                print("  %s: %d occurrences" % (p, c))
        if all(c == 0 for c in r2.values()):
            print("  NO LEGO/LOCO references found in overlay!")
    
    # Also check: what IS on the disk? Look for common Win98 files
    print("\n=== Checking for Windows 98 markers ===")
    win_patterns = ['WINDOWS', 'COMMAND.COM', 'Program Files', 'PROGRA~1', 'SoftGPU', 'SOFTGPU', 'SCITECH']
    r3 = search_image(img_path, win_patterns)
    for p, c in r3.items():
        if c > 0:
            print("  %s: %d occurrences" % (p, c))

if __name__ == '__main__':
    main()
