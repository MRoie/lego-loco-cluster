#!/usr/bin/env python3
"""lens_crop.py — reference circular lens crop, mirroring backend/services/lensCrop.js.

Reads a PPM (e.g. a QMP screendump), crops a circular region centred on a
normalized point, and writes a 400x400 PNG with transparent corners. Used to
sanity-check the crop geometry against the JS implementation without the backend.

  lens_crop.py IN.ppm OUT.png [cx] [cy] [zoom]   (defaults 0.5 0.5 1.5)

Requires pillow (pip install pillow).
"""
import sys


def read_ppm(path):
    with open(path, "rb") as fh:
        assert fh.readline().strip() == b"P6", "not a P6 PPM"
        line = fh.readline()
        while line.startswith(b"#"):
            line = fh.readline()
        w, h = map(int, line.split())
        fh.readline()  # maxval
        data = fh.read()
    return w, h, data


def source_rect(fbw, fbh, cx, cy, zoom, base_fraction=0.35):
    min_dim = min(fbw, fbh)
    edge = int((min_dim * base_fraction) / max(0.25, zoom))
    edge = max(16, min(edge, min_dim))
    sx = int(cx * fbw - edge / 2)
    sy = int(cy * fbh - edge / 2)
    sx = max(0, min(sx, fbw - edge))
    sy = max(0, min(sy, fbh - edge))
    return sx, sy, edge, edge


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    from PIL import Image
    inp, out = sys.argv[1], sys.argv[2]
    cx = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
    cy = float(sys.argv[4]) if len(sys.argv) > 4 else 0.5
    zoom = float(sys.argv[5]) if len(sys.argv) > 5 else 1.5
    size = 400

    fbw, fbh, data = read_ppm(inp)
    sx, sy, sw, sh = source_rect(fbw, fbh, cx, cy, zoom)
    src = Image.frombytes("RGB", (fbw, fbh), data)
    crop = src.crop((sx, sy, sx + sw, sy + sh)).resize((size, size), Image.NEAREST).convert("RGBA")

    mask = Image.new("L", (size, size), 0)
    from PIL import ImageDraw
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    crop.putalpha(mask)
    crop.save(out)
    print(f"wrote {out} from rect=({sx},{sy},{sw},{sh}) of {fbw}x{fbh}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
