#!/usr/bin/env python3
"""Convert a CFF OpenType font to TrueType (glyf) for Android Emacs.

Standard fontTools recipe: draw every CFF charstring through cu2qu into
a TrueType glyph pen (cubics -> quadratics), build glyf/loca, rebuild
post as format 2.0 with glyph names, drop the CFF table.
"""
import sys
from fontTools.ttLib import TTFont, newTable
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen

def main(src, dst, max_err=1.0):
    font = TTFont(src)
    glyph_order = font.getGlyphOrder()
    glyph_set = font.getGlyphSet()
    hmtx = font["hmtx"]

    glyf = newTable("glyf")
    glyf.glyphOrder = glyph_order
    glyf.glyphs = {}
    for name in glyph_order:
        pen = TTGlyphPen(glyph_set)
        # reverse_direction: CFF outlines wind counter-clockwise,
        # TrueType expects clockwise.
        glyph_set[name].draw(Cu2QuPen(pen, max_err=max_err,
                                      reverse_direction=True))
        glyf.glyphs[name] = pen.glyph()
    font["glyf"] = glyf
    font["loca"] = newTable("loca")

    # maxp must be version 1.0 for glyf fonts; numbers are recalculated
    # from the glyf table when compiling.
    maxp = newTable("maxp")
    maxp.tableVersion = 0x00010000
    maxp.numGlyphs = len(glyph_order)
    for field in ("maxPoints", "maxContours", "maxCompositePoints",
                  "maxCompositeContours", "maxZones", "maxTwilightPoints",
                  "maxStorage", "maxFunctionDefs", "maxInstructionDefs",
                  "maxStackElements", "maxSizeOfInstructions",
                  "maxComponentElements", "maxComponentDepth"):
        setattr(maxp, field, 0)
    maxp.maxZones = 1
    font["maxp"] = maxp

    post = font["post"]
    post.formatType = 2.0
    post.extraNames = []
    post.mapping = {}
    post.glyphOrder = glyph_order

    for tag in ("CFF ", "VORG"):
        if tag in font:
            del font[tag]
    font["head"].glyphDataFormat = 0
    # The container tag must say TrueType, not OTTO — FreeType rejects
    # a glyf font in an OTTO wrapper before reading a single table.
    font.sfntVersion = "\x00\x01\x00\x00"

    # Fix left side bearings to the new (quadratic) outlines' xMin.
    for name in glyph_order:
        glyph = glyf.glyphs[name]
        glyph.recalcBounds(glyf)
        adv, _ = hmtx[name]
        hmtx[name] = (adv, getattr(glyph, "xMin", 0))

    font.save(dst)
    print(f"{src} -> {dst}: {len(glyph_order)} glyphs converted")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
