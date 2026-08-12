#!/usr/bin/env python3
"""Synthesize a Demi weight from a TrueType font by outline offsetting.

For every simple glyph: union(outline, stroke(outline, W)) — every stroke
gets W/2 thicker on each side while letterform proportions stay intact.
Composites are left alone (their referenced base glyphs get emboldened).
Advance widths are preserved so metrics/kerning feel identical.
"""
import sys
import pathops
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen

def embolden_glyph(glyf, glyph_name, width):
    glyph = glyf[glyph_name]
    if glyph.numberOfContours <= 0:      # empty or composite
        return False
    path = pathops.Path()
    glyph.draw(path.getPen(), glyf)
    stroked = pathops.Path(path)
    try:
        stroked.stroke(width, pathops.LineCap.SQUARE_CAP,
                       pathops.LineJoin.MITER_JOIN, 4.0)
    except pathops.PathOpsError:
        return False
    result = pathops.op(path, stroked, pathops.PathOp.UNION, fix_winding=True,
                        keep_starting_points=False)
    result.simplify(fix_winding=True)
    pen = TTGlyphPen(None)
    result.draw(Cu2QuPen(pen, max_err=1.0, reverse_direction=False))
    glyf[glyph_name] = pen.glyph()
    return True

def rename(font, suffix):
    name = font["name"]
    for rec in name.names:
        if rec.nameID in (1, 16):                 # family
            rec.string = (rec.toUnicode() + " " + suffix)
        elif rec.nameID == 4:                     # full name
            rec.string = (rec.toUnicode() + " " + suffix)
        elif rec.nameID == 6:                     # postscript name
            rec.string = (rec.toUnicode() + "-" + suffix)
        elif rec.nameID == 3:                     # unique id
            rec.string = (rec.toUnicode() + "-" + suffix)

def main(src, dst, width, suffix="Demi", weight_class=600):
    font = TTFont(src)
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    done = 0
    for gname in font.getGlyphOrder():
        if embolden_glyph(glyf, gname, width):
            done += 1
    # Recompute per-glyph bounds, then fix hmtx left side bearings.
    for gname in font.getGlyphOrder():
        glyph = glyf[gname]
        glyph.recalcBounds(glyf)
        adv, _lsb = hmtx[gname]
        hmtx[gname] = (adv, getattr(glyph, "xMin", 0))
    rename(font, suffix)
    if "OS/2" in font:
        font["OS/2"].usWeightClass = weight_class
    font.save(dst)
    print(f"{src} -> {dst}: {done} glyphs emboldened by {width} units")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]),
         *( [sys.argv[4], int(sys.argv[5])] if len(sys.argv) > 5 else [] ))
