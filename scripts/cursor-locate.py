#!/usr/bin/env python3
"""Find the guest cursor in a screenshot by template-matching its sprite.

    cursor-locate.py extract SHOT.png X0 Y0 X1 Y1 TEMPLATE.png   # cut a template
    cursor-locate.py find SHOT.png TEMPLATE.png [--near X Y] [--window N]

Why this exists: frame-differencing — the obvious way to find a cursor — died
the moment the guests started auto-running LEGO LOCO, whose menu animates.
A diff picks up trains and water as enthusiastically as the cursor, and the
numbers it produced sent the pointer work in the wrong direction twice.
Matching the sprite itself doesn't care what the background is doing.

The match is masked: only pixels that are confidently *sprite* (not background
showing through the crop) participate. For LOCO's hand cursor the skin tones do
the work; for the Win98 arrow it is the white body plus its black outline. The
mask is rebuilt from the template at load time, so a template is just a PNG
crop — no separate mask file to keep in sync.

Positions are reported as the template's top-left corner. For measuring the
pointer transfer function that is enough: commanded-vs-observed *displacements*
cancel the hotspot offset entirely, so calibrating where the hotspot sits
inside the sprite is only needed for absolute click accuracy, not for gain.

Pure PIL + stdlib, because the measurement host has no numpy. A coarse pass at
stride 3 over the search window, then a full-resolution refine around the best
coarse hit, keeps that fast enough (~1s for a 300x300 window).
"""

import argparse
import sys

from PIL import Image


def is_skin(px):
    r, g, b = px
    return r > 130 and 70 < g < 200 and b < 150 and r > g > b


def is_arrow_body(px):
    r, g, b = px
    return (r > 200 and g > 200 and b > 200) or (r < 60 and g < 60 and b < 60)


def build_mask(tmpl):
    """Pick the sprite's own pixels out of a rectangular crop.

    Tries the skin classifier first (LOCO's hand), falls back to white+black
    (the Win98 arrow). A usable template needs a few dozen confident pixels;
    fewer than that means the crop missed the sprite.
    """
    w, h = tmpl.size
    px = tmpl.load()
    for classify, name in ((is_skin, "skin"), (is_arrow_body, "arrow")):
        mask = [(x, y) for y in range(h) for x in range(w) if classify(px[x, y])]
        if len(mask) >= 40:
            return mask, name
    raise SystemExit("template has too few classifiable sprite pixels "
                     "(%dx%d crop)" % (w, h))


def sad(shot_px, tmpl_px, ox, oy, mask, cutoff):
    """Sum of absolute differences over the mask, with early exit."""
    total = 0
    for x, y in mask:
        sp = shot_px[ox + x, oy + y]
        tp = tmpl_px[x, y]
        total += abs(sp[0] - tp[0]) + abs(sp[1] - tp[1]) + abs(sp[2] - tp[2])
        if total >= cutoff:
            return cutoff
    return total


def find(shot, tmpl, near=None, window=160):
    sw, sh = shot.size
    tw, th = tmpl.size
    shot_px, tmpl_px = shot.load(), tmpl.load()
    mask, kind = build_mask(tmpl)
    # Subsample the mask for the coarse pass; full mask for the refine.
    coarse_mask = mask[::max(1, len(mask) // 80)]

    if near:
        x0 = max(0, near[0] - window)
        y0 = max(0, near[1] - window)
        x1 = min(sw - tw, near[0] + window)
        y1 = min(sh - th, near[1] + window)
    else:
        x0, y0, x1, y1 = 0, 0, sw - tw, sh - th

    best, best_xy = None, None
    cutoff = 3 * 255 * len(coarse_mask)
    for oy in range(y0, y1 + 1, 3):
        for ox in range(x0, x1 + 1, 3):
            s = sad(shot_px, tmpl_px, ox, oy, coarse_mask, best if best else cutoff)
            if best is None or s < best:
                best, best_xy = s, (ox, oy)

    if best_xy is None:
        return None

    # Refine at stride 1 with the full mask.
    cx, cy = best_xy
    best, best_xy = None, None
    for oy in range(max(0, cy - 4), min(sh - th, cy + 4) + 1):
        for ox in range(max(0, cx - 4), min(sw - tw, cx + 4) + 1):
            s = sad(shot_px, tmpl_px, ox, oy, mask, best if best else 10**12)
            if best is None or s < best:
                best, best_xy = s, (ox, oy)

    score = best / (3.0 * 255.0 * len(mask))   # 0 = pixel-perfect, 1 = inverse
    return dict(x=best_xy[0], y=best_xy[1], score=score, kind=kind,
                mask_pixels=len(mask))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    ex = sub.add_parser("extract", help="cut a template out of a screenshot")
    ex.add_argument("shot"); ex.add_argument("x0", type=int); ex.add_argument("y0", type=int)
    ex.add_argument("x1", type=int); ex.add_argument("y1", type=int)
    ex.add_argument("out")

    fd = sub.add_parser("find", help="locate the template in a screenshot")
    fd.add_argument("shot"); fd.add_argument("template")
    fd.add_argument("--near", nargs=2, type=int, metavar=("X", "Y"),
                    help="search only a window around this position")
    fd.add_argument("--window", type=int, default=160)

    args = ap.parse_args()

    if args.cmd == "extract":
        im = Image.open(args.shot).convert("RGB")
        crop = im.crop((args.x0, args.y0, args.x1, args.y1))
        mask, kind = build_mask(crop)          # validates the crop
        crop.save(args.out)
        print("template %s: %dx%d, %d %s pixels"
              % (args.out, crop.size[0], crop.size[1], len(mask), kind))
        return 0

    shot = Image.open(args.shot).convert("RGB")
    tmpl = Image.open(args.template).convert("RGB")
    hit = find(shot, tmpl, near=tuple(args.near) if args.near else None,
               window=args.window)
    if not hit:
        print("no match", file=sys.stderr)
        return 1
    # score: matched sprites land well under 0.1; anything above ~0.25 means
    # the cursor is probably a different sprite or off-screen.
    print("%d %d score=%.4f kind=%s mask=%d"
          % (hit["x"], hit["y"], hit["score"], hit["kind"], hit["mask_pixels"]))
    return 0 if hit["score"] < 0.25 else 2


if __name__ == "__main__":
    sys.exit(main())
