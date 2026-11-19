# Amber VFD tools

The Amber VFD theme draws every screen on one grid of square cells, from the bitmap font here.

- `font_data.py`: the original 5×7 font (2 descender rows), ASCII 32–126 plus extras.
- `scale.py`: Scale2x (EPX) and Scale3x, used for the mid (10×14) and big (15×21) sizes.
- `gen_swift.py`: writes `Sources/Design/VFD/VFDFont.swift`. Run it after changing the font:
  `cd tools/vfd && python3 gen_swift.py ../../Sources/Design/VFD/VFDFont.swift`
- `vfd.py`, `screens.py`, `icons.py`: a preview renderer with the same grid, palette and
  drawing API as the app (`VFDBuffer`), for laying out screens without a build:
  `python3 screens.py` writes PNGs at iPhone 17 Pro (1206×2622, 5 px pitch) and 2x (4 px pitch)
  sizes to `out/`. `sheet.py out.png a.png b.png …` puts several side by side.
