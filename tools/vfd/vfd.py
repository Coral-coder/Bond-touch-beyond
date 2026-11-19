"""Frame buffer of whole cells + drawing API + PNG painter. Mirrors the Swift renderer."""
from PIL import Image, ImageDraw
from font import SIZES

UNLIT = (9, 9, 9)
BASES = {  # name: base colour (replaces amber)
    'AMBER': (0xFF, 0xB0, 0x14), 'GREEN': (0x3C, 0xFF, 0x6E), 'TEAL': (0x30, 0xFF, 0xD8),
    'BLUE': (0x48, 0xA8, 0xFF), 'PINK': (0xFF, 0x5C, 0xB8), 'WHITE': (0xF0, 0xF0, 0xF0),
}
OFF, BASE, TEXT, DIM, ALARM = 0, 1, 2, 3, 4

def palette(base):
    if base == BASES['AMBER']:
        return {BASE: base, TEXT: (0xFF, 0xE8, 0xC4), DIM: (0x96, 0x64, 0x28), ALARM: (0xFF, 0x50, 0x28)}
    r, g, b = base
    text = tuple(round(c * .25 + 255 * .75) for c in base)
    dim = tuple(round(c * .58 + 6) for c in base)
    alarm = (0xFF, 0x50, 0x28) if not (r > 200 and g < 120) else (0xFF, 0xFF, 0xFF)
    return {BASE: base, TEXT: text, DIM: dim, ALARM: alarm}

class FB:
    def __init__(self, width_px, height_px, pitch, top_px, bottom_px, base='AMBER'):
        self.pitch, self.wpx, self.hpx = pitch, width_px, height_px
        self.cols, self.rows = width_px // pitch, height_px // pitch
        self.top = -(-top_px // pitch)                 # first row below the status bar
        self.bottom = self.rows - (-(-bottom_px // pitch))  # first row of the home indicator
        self.buf = bytearray(self.cols * self.rows)
        self.pal = palette(BASES[base])
        self.clip = (0, 0, self.cols, self.rows)
        self.hits = []

    # --- cells
    def set(self, c, r, v):
        x0, y0, x1, y1 = self.clip
        if x0 <= c < x1 and y0 <= r < y1: self.buf[r * self.cols + c] = v
    def get(self, c, r): return self.buf[r * self.cols + c]
    def fill(self, c, r, w, h, v):
        for y in range(r, r + h):
            for x in range(c, c + w): self.set(x, y, v)
    def hline(self, c, r, w, v, step=1):
        for x in range(c, c + w, step): self.set(x, r, v)
    def vline(self, c, r, h, v, step=1):
        for y in range(r, r + h, step): self.set(c, y, v)
    def box(self, c, r, w, h, v, step=1):
        self.hline(c, r, w, v, step); self.hline(c, r + h - 1, w, v, step)
        self.vline(c, r, h, v, step); self.vline(c + w - 1, r, h, v, step)
    def line(self, c0, r0, c1, r1, v):
        dx, dy = abs(c1 - c0), -abs(r1 - r0); sx = 1 if c0 < c1 else -1; sy = 1 if r0 < r1 else -1
        err = dx + dy
        while True:
            self.set(c0, r0, v)
            if c0 == c1 and r0 == r1: break
            e2 = 2 * err
            if e2 >= dy: err += dy; c0 += sx
            if e2 <= dx: err += dx; r0 += sy
    def bitmap(self, c, r, rows, v):
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch == '#' or ch == 1: self.set(c + x, r + y, v)

    # --- text (row = top of the capital letters)
    @staticmethod
    def width(s, size='s'):
        return len(s) * SIZES[size][3] - (SIZES[size][3] - SIZES[size][1]) if s else 0
    def text(self, c, r, s, size='s', v=TEXT):
        table, w, capH, adv, _ = SIZES[size]
        for ch in s:
            gl = table.get(ch) or table.get(ch.upper()) or table['?']
            for y, row in enumerate(gl):
                for x, on in enumerate(row):
                    if on: self.set(c + x, r + y, v)
            c += adv
        return c
    def text_right(self, c_end, r, s, size='s', v=TEXT):
        return self.text(c_end - self.width(s, size), r, s, size, v)
    def text_center(self, c, w, r, s, size='s', v=TEXT):
        return self.text(c + (w - self.width(s, size)) // 2, r, s, size, v)
    def fit(self, s, max_w, size='s'):
        if self.width(s, size) <= max_w: return s
        adv = SIZES[size][3]
        n = max(0, (max_w + adv - SIZES[size][1]) // adv - 1)
        return s[:n].rstrip() + '…'
    def text_fit(self, c, r, s, max_w, size='s', v=TEXT):
        return self.text(c, r, self.fit(s, max_w, size), size, v)
    def paragraph(self, c, r, s, max_w, size='s', v=TEXT, max_lines=99):
        adv, lh = SIZES[size][3], SIZES[size][4]
        per = max(1, (max_w + adv - SIZES[size][1]) // adv)
        lines, cur = [], ''
        for word in s.split():
            t = (cur + ' ' + word).strip()
            if len(t) <= per: cur = t
            else: lines.append(cur); cur = word
        if cur: lines.append(cur)
        if len(lines) > max_lines: lines = lines[:max_lines]; lines[-1] = self.fit(lines[-1] + ' …', max_w, size)
        for i, ln in enumerate(lines): self.text(c, r + i * lh, ln, size, v)
        return r + len(lines) * lh

    # --- widgets
    def inverted(self, c, r, w, s, size='s', v=BASE, pad_v=2):
        """Solid block with the text cut out."""
        capH = SIZES[size][2]; h = capH + pad_v * 2 + (1 if size == 's' else 0)
        self.fill(c, r, w, h, v)
        self.text_center(c, w, r + pad_v, self.fit(s, w - 4, size), size, OFF)
        return h
    def led_bar(self, c, r, w, frac=None, zone=None, marker=None, h=6, v=BASE):
        """Dotted dim track; optional lit fill (frac), lit zone (lo, hi) and a 3x6 marker."""
        for y in range(r + 1, r + h - 1, 2): self.hline(c, y, w, DIM, 2)
        if frac is not None: self.fill(c, r, max(0, round(w * frac)), h, v)
        if zone is not None:
            a, b = round(w * zone[0]), round(w * zone[1]); self.fill(c + a, r + 1, b - a, h - 2, v)
        if marker is not None:
            for m, mv in (marker if isinstance(marker, list) else [(marker, TEXT)]):
                x = c + min(w - 3, max(0, round(w * m) - 1)); self.fill(x, r, 3, h, OFF); self.fill(x, r - 1 if False else r, 3, h, mv)
    def chart(self, c, r, w, h, values, v=BASE, lo=None, hi=None):
        self.hline(c, r + h - 1, w, DIM, 2)
        lo = min(values) if lo is None else lo; hi = max(values) if hi is None else hi
        pts = []
        for i, val in enumerate(values):
            x = c + round(i * (w - 1) / (len(values) - 1))
            y = r + h - 2 - round((val - lo) / max(1e-9, hi - lo) * (h - 3))
            pts.append((x, y))
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]): self.line(x0, y0, x1, y1, v)
    def toggle(self, c_end, r, on):
        """[ON|OFF] pixel toggle, right-aligned at c_end; the active half is inverted."""
        w = 21; c = c_end - 2 * w + 1
        self.box(c, r, 2 * w - 1, 11, DIM)
        if on: self.fill(c, r, w, 11, BASE); self.text_center(c, w, r + 2, 'ON', 's', OFF); self.text_center(c + w - 1, w, r + 2, 'OFF', 's', DIM)
        else: self.fill(c + w - 1, r, w, 11, DIM); self.text_center(c, w, r + 2, 'ON', 's', DIM); self.text_center(c + w - 1, w, r + 2, 'OFF', 's', OFF)
        return c
    def stepper(self, c_end, r, value):
        """[-] value [+], right-aligned."""
        bw = 11; c = c_end - (bw * 2 + 22) + 1
        self.box(c, r, bw, 11, DIM); self.text(c + 3, r + 2, '-', 's', BASE)
        self.text_center(c + bw, 22, r + 2, str(value), 's', BASE)
        self.box(c + bw + 22, r, bw, 11, DIM); self.text(c + bw + 25, r + 2, '+', 's', BASE)
        return c
    def option(self, c, r, s, selected):
        w = self.width(s) + 6
        if selected: self.fill(c, r, w, 11, BASE); self.text(c + 3, r + 2, s, 's', OFF)
        else: self.box(c, r, w, 11, DIM); self.text(c + 3, r + 2, s, 's', TEXT)
        return c + w

    # --- painting
    def png(self, path):
        p = self.pitch; lit = p - 1
        im = Image.new('RGB', (self.wpx, self.hpx), (0, 0, 0)); d = ImageDraw.Draw(im)
        cols = {0: UNLIT, **self.pal}
        for r in range(self.rows):
            for c in range(self.cols):
                d.rectangle([c * p, r * p, c * p + lit - 1, r * p + lit - 1], fill=cols[self.buf[r * self.cols + c]])
        im.save(path)
        return im
