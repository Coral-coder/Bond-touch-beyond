from font_data import G
from scale import scale2x, scale3x
def bits(rows): return [[1 if c == '#' else 0 for c in r] for r in rows]
SMALL = {ch: bits(r) for ch, r in G.items()}           # 5 x 9
MID = {ch: scale2x(b) for ch, b in SMALL.items()}      # 10 x 18
BIG = {ch: scale3x(b) for ch, b in SMALL.items()}      # 15 x 27
SIZES = {  # name: (table, glyph w, cap h, advance, line height)
    's': (SMALL, 5, 7, 6, 10),
    'm': (MID, 10, 14, 12, 19),
    'b': (BIG, 15, 21, 18, 28),
}
