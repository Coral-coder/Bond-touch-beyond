import sys
from vfd import FB, OFF, BASE, TEXT, DIM, ALARM, BASES
from icons import ICONS
from font import SIZES

TABS = [('HOME', 'home'), ('US', 'us'), ('TOUCH', 'touch'), ('MAP', 'map'), ('CHAT', 'chat'), ('SET', 'gear')]

def chrome(fb, title, tab, back=False, right=None):
    M = margin(fb); t = fb.top
    if back:
        fb.text(M, t + 3, '< BACK', 's', BASE)
        fb.text(M, t + 15, title, 'm', TEXT)
    else:
        fb.text(M, t + 9, title, 'm', TEXT)
    if right:
        title_end = M + fb.width(title, 'm'); rw = fb.width(right[0])
        if back or title_end + 6 <= fb.cols - M - rw: fb.text_right(fb.cols - M, t + (3 if back else 12), right[0], 's', right[1])
        else: fb.text_right(fb.cols - M, t, right[0], 's', right[1])   # no room beside the title: above it
    fb.hline(0, t + 32, fb.cols, DIM)
    # tab bar
    y = fb.bottom - 27
    fb.hline(0, y, fb.cols, DIM)
    n = len(TABS)
    for i, (label, icon) in enumerate(TABS):
        c0 = round(i * fb.cols / n); c1 = round((i + 1) * fb.cols / n); w = c1 - c0
        sel = label == tab
        if sel: fb.fill(c0 + 1, y + 2, w - 2, 25, BASE)
        ic = ICONS[icon]; fb.bitmap(c0 + (w - len(ic[0])) // 2, y + 4, ic, OFF if sel else DIM)
        fb.text_center(c0, w, y + 17, label, 's', OFF if sel else TEXT)
    return t + 34, y - 1   # content top, content bottom

def margin(fb): return max(4, fb.cols // 40)
def colx(fb, frac):
    M = margin(fb); return M + round((fb.cols - 2 * M) * frac)

def section(fb, y, label, right=None, v=DIM):
    M = margin(fb)
    fb.text(M, y, label, 's', v)
    if right: fb.text_right(fb.cols - M, y, right, 's', DIM)
    return y + 11

# ----------------------------------------------------------------- HOME
def home(fb):
    M = margin(fb); W = fb.cols - 2 * M
    y, ybot = chrome(fb, 'CONSTELLATION', 'HOME', right=('BAND ● 82%', BASE))
    fb.clip = (0, y, fb.cols, ybot)
    y += 3
    c = M
    for name, sel in (('SAM', True), ('ALEX', False), ('JO', False)):
        c = fb.option(c, y, name, sel) + 3
    fb.option(c, y, '+', False)
    y += 16
    # partner panel
    ph = 92; fb.box(M, y, W, ph, BASE)
    ix = M + 4; iw = W - 8
    fb.text(ix, y + 4, '♥ SAM', 'm', TEXT)
    fb.text_right(M + W - 4, y + 8, 'ONLINE', 's', BASE)
    yy = y + 24
    cols3 = [ix, ix + iw // 3, ix + 2 * iw // 3]
    for cx, lab, val in zip(cols3, ('TOUCH MIN', 'AWAY MI', 'BAND %'), ('4', '12.4', '67')):
        fb.text_fit(cx, yy, lab, iw // 3 - 6, 's', DIM)
        fb.text(cx, yy + 11, val, 'm', BASE)
    yy += 32
    fb.hline(ix, yy, iw, DIM, 2)
    yy += 5
    fb.text(ix, yy, 'HEARTBEAT BPM', 's', DIM)
    fb.text(ix, yy + 11, '72', 'b', BASE)
    ekg = ([0] * 4 + [1, 0, -1, 8, -3, 0, 1, 1, 0] + [0] * 4) * 3
    cx = ix + 44; fb.chart(cx, yy + 4, ix + iw - cx, 30, ekg, BASE, lo=-4, hi=9)
    y += ph + 5
    # buttons
    labels = ('TOUCH', 'KISS', 'HEARTBEAT'); gap = 3; bw = (W - gap * 2) // 3
    for i, lab in enumerate(labels):
        bx = M + i * (bw + gap)
        fb.box(bx, y, bw, 15, BASE if i == 0 else DIM)
        fb.text_center(bx, bw, y + 4, lab, 's', BASE if i == 0 else TEXT)
    y += 20
    # touch pad
    th = 64; fb.box(M, y, W, th, DIM)
    for gy in range(y + 8, y + th - 2, 8): fb.hline(M + 2, gy, W - 4, DIM, 8)
    fb.text_center(M, W, y + 4, 'TAP + SLIDE TO SEND', 's', DIM)
    trace = [30, 30, 28, 22, 14, 10, 12, 20, 30, 40, 46, 44, 36, 30, 30]
    fb.chart(M + 10, y + 14, W - 20, 46, trace, BASE, lo=0, hi=50)
    fb.fill(M + 10, y + th - 4, 1, 1, OFF)
    y += th + 5
    # streak
    fb.text(M, y, 'STREAK DAYS', 's', DIM); fb.text_right(M + W, y, 'BEST 21', 's', DIM)
    fb.text(M, y + 11, '12', 'm', BASE)
    fb.led_bar(M + 30, y + 15, W - 30, frac=12 / 21, marker=[(1.0, TEXT)])
    y += 32
    y = section(fb, y, 'RECENT')
    for who, what, ago, v in (('SAM', 'TOUCHED YOU ♥', '4M', BASE), ('YOU', 'SENT A KISS', '1H', TEXT),
                              ('ALEX', 'HEARTBEAT 68 BPM', '2H', TEXT), ('JO', 'QUIET FOR 6 DAYS', '6D', ALARM)):
        fb.text(M, y, who, 's', v)
        fb.text_fit(colx(fb, .22), y, what, colx(fb, .86) - colx(fb, .22), 's', TEXT if v != ALARM else ALARM)
        fb.text_right(M + W, y, ago, 's', DIM)
        y += 11
    fb.clip = (0, 0, fb.cols, fb.rows)

# ----------------------------------------------------------------- US
def us(fb):
    M = margin(fb); W = fb.cols - 2 * M
    y, ybot = chrome(fb, 'US', 'US', right=('WITH SAM', DIM))
    fb.clip = (0, y, fb.cols, ybot)
    y += 3
    h = fb.inverted(M, y, W, 'CHECK-IN DUE SUNDAY ♥', 's', BASE); y += h + 6
    items = [('WHERE WE STAND', '3 NEW'), ('WISHES', '2'), ('PROMISES', '1 DUE'), ('DATES', 'SAT 14'),
             ('TO-DO', '5'), ('NOTES', ''), ('GAMES', 'YOUR MOVE'), ('MEMORY LANE', ''), ('POLY CALENDAR', ''),
             ('METAMOURS', '2'), ('QUESTION OF THE DAY', '✓'), ('WHITEBOARD', ''), ('BATTERY', '62%')]
    for i, (name, badge) in enumerate(items):
        sel = i == 0
        fb.box(M, y, W, 15, BASE if sel else DIM)
        fb.text(M + 4, y + 4, name, 's', TEXT)
        if badge: fb.text_right(M + W - 12, y + 4, badge, 's', BASE if badge != '1 DUE' else ALARM)
        fb.text_right(M + W - 3, y + 4, '>', 's', DIM)
        y += 17
    fb.clip = (0, 0, fb.cols, fb.rows)

# ----------------------------------------------------------------- WHERE WE STAND
def stand(fb):
    M = margin(fb); W = fb.cols - 2 * M
    y, ybot = chrome(fb, 'WHERE WE STAND', 'US', back=True)
    fb.clip = (0, y, fb.cols, ybot)
    y += 4
    fb.text(M, y, 'CLOSENESS', 's', DIM); fb.text_right(M + W, y, 'YOU ● SAM ○', 's', DIM)
    y += 12
    fb.led_bar(M, y, W, zone=(.62, .78), marker=[(.70, TEXT)]); y += 8
    fb.text(M, y, 'APART', 's', DIM); fb.text_center(M, W, y, 'ALIGNED', 's', BASE); fb.text_right(M + W, y, 'CLOSE', 's', DIM)
    y += 14
    fb.text(M, y, 'STYLE', 's', DIM); y += 11
    c = M
    for s, sel in (('ANCHOR', True), ('NESTING', False), ('COMET', False), ('FWB', False)):
        c = fb.option(c, y, s, sel) + 3
    y += 16
    fb.text(M, y, 'HAPPY WITH IT', 's', DIM); y += 11
    c = M
    for s, sel in (('YES', True), ('MOSTLY', False), ('NOT SURE', False), ('NO', False)):
        c = fb.option(c, y, s, sel) + 3
    y += 18
    y = section(fb, y, 'WISHES', '2 OPEN')
    for wish, state, v in (('MEET HIS FRIENDS', 'YES, LET’S', BASE), ('A WEEKEND AWAY', 'NOT YET · MAR', DIM)):
        fb.text_fit(M, y, wish, colx(fb, .52) - M, 's', TEXT); fb.text_right(M + W, y, state, 's', v); y += 11
    y += 4
    y = section(fb, y, 'PROMISES', '1 MISSED')
    for p, state, v in (('CALL ON SUNDAYS', '✓ KEPT', BASE), ('PLAN THE TRIP', 'MISSED · TALK?', ALARM)):
        fb.text_fit(M, y, p, colx(fb, .52) - M, 's', TEXT); fb.text_right(M + W, y, state, 's', v); y += 11
    y += 6
    fb.text(M, y, 'MOOD 30 DAYS', 's', DIM); fb.text_right(M + W, y, 'NOW 7/10', 's', BASE); y += 11
    mood = [6, 6, 7, 7, 6, 5, 5, 6, 7, 8, 8, 7, 7, 6, 4, 3, 4, 5, 6, 7, 7, 8, 8, 8, 7, 7, 8, 7, 7, 7]
    fb.chart(M, y, W, 40, mood, BASE, lo=0, hi=10); y += 46
    h = fb.inverted(M, y, W, 'MOOD IS LOW · MOVE CHECK-IN?', 's', ALARM)
    fb.clip = (0, 0, fb.cols, fb.rows)

# ----------------------------------------------------------------- CHAT
def chat(fb):
    M = margin(fb); W = fb.cols - 2 * M
    y, ybot = chrome(fb, 'SAM', 'CHAT', back=True, right=('● ONLINE', BASE))
    fb.clip = (0, y, fb.cols, ybot)
    y += 4
    fb.text_center(0, fb.cols, y, '— TODAY 21:04 —', 's', DIM); y += 14
    bw = round(W * .74)
    def bubble(y, text, mine, when, v=TEXT, extra=None):
        x = M + W - bw if mine else M
        lines_end = fb.paragraph(x + 4, y + 4, text, bw - 8, 's', v) if text else y + 4
        if extra: lines_end = extra(x, lines_end)
        h = lines_end - y + 2
        fb.box(x, y, bw, h, BASE if mine else DIM)
        fb.text_right(x + bw - 3, lines_end - 9, when, 's', DIM) if False else None
        (fb.text_right if mine else fb.text)(x + bw if mine else x, y + h + 2, when, 's', DIM)
        return y + h + 13
    y = bubble(y, 'Missed you today. The bracelet buzzed right in the middle of my meeting and I grinned like an idiot', False, '21:04')
    y = bubble(y, 'Good. That was the plan ♥', True, '21:05 · SEEN')
    def photo(x, yy):
        fb.bitmap(x + 4, yy, ICONS['photo'], DIM)
        fb.text(x + 18, yy + 1, 'PHOTO · 10 S', 's', BASE)
        fb.text(x + 4, yy + 12, 'TAP TO VIEW ONCE', 's', DIM)
        return yy + 21
    y = bubble(y, '', False, '21:07', extra=photo)
    fb.text_center(0, fb.cols, y, 'SAM TOOK A SCREENSHOT', 's', ALARM); y += 15
    y = bubble(y, 'Saturday still on? I found the place with the rooftop', False, '21:12')
    # composer
    cy = ybot - 18
    fb.clip = (0, 0, fb.cols, fb.rows)
    fb.fill(0, cy - 2, fb.cols, 20, OFF)
    fb.box(M, cy, W - 34, 15, DIM)
    fb.text(M + 4, cy + 4, 'MESSAGE_', 's', DIM)
    fb.fill(M + W - 31, cy, 31, 15, BASE); fb.text_center(M + W - 31, 31, cy + 4, 'SEND', 's', OFF)

# ----------------------------------------------------------------- SETTINGS
def settings(fb, base_name='AMBER'):
    M = margin(fb); W = fb.cols - 2 * M
    y, ybot = chrome(fb, 'SETTINGS', 'SET')
    fb.clip = (0, y, fb.cols, ybot)
    y += 4
    y = section(fb, y, 'APPEARANCE')
    fb.text(M, y + 2, 'THEME', 's', TEXT); fb.option(M + W - fb.width('AMBER VFD') - 6, y, 'AMBER VFD', True); y += 15
    fb.text(M, y, 'BASE COLOUR', 's', TEXT); y += 11
    names = list(BASES); per = 3; gap = 3; sw = (W - gap * (per - 1)) // per
    from vfd import palette
    for i, n in enumerate(names):
        bx = M + (i % per) * (sw + gap); by = y + (i // per) * 16
        sel = n == base_name
        # each swatch lit in its own colour: use a temporary palette slot
        slot = 10 + i; fb.pal[slot] = BASES[n]
        if sel: fb.fill(bx, by, sw, 13, slot); fb.text_center(bx, sw, by + 3, n, 's', OFF)
        else: fb.box(bx, by, sw, 13, slot); fb.text_center(bx, sw, by + 3, n, 's', slot)
    y += 2 * 16 + 4
    fb.text(M, y + 2, 'APP ICON', 's', TEXT); fb.option(M + W - fb.width('HEART OF STARS') - 6, y, 'HEART OF STARS', False); y += 18
    fb.hline(M, y, W, DIM, 2); y += 5
    y = section(fb, y, 'BRACELET')
    fb.text(M, y, 'MODEL', 's', TEXT); fb.text_right(M + W, y, 'BOND TOUCH MORE', 's', BASE); y += 11
    fb.text(M, y, 'BATTERY %', 's', TEXT); fb.text_right(M + W, y, '82', 's', BASE); y += 10
    fb.led_bar(M, y, W, frac=.82, h=6); y += 10
    fb.text(M, y + 2, 'VIBRATION', 's', TEXT)
    c = M + W
    for s, sel in reversed((('LOW', False), ('MED', False), ('HIGH', True))):
        c -= fb.width(s) + 6; fb.option(c, y, s, sel); c -= 3
    y += 15
    fb.text(M, y + 2, 'TOUCH WINDOW S', 's', TEXT); fb.stepper(M + W, y, 7); y += 15
    fb.hline(M, y, W, DIM, 2); y += 5
    y = section(fb, y, 'BACKGROUND')
    for lab, on in (('STAY CONNECTED', True), ('WATCH STANDS IN', False), ('SHARE WEATHER', True)):
        fb.text(M, y + 2, lab, 's', TEXT); fb.toggle(M + W, y, on); y += 15
    fb.text(M, y + 2, 'NUDGE AFTER DAYS', 's', TEXT); fb.stepper(M + W, y, 2); y += 17
    h = fb.inverted(M, y, W, 'JO’S BAND BATTERY LOW · 9%', 's', ALARM)
    fb.clip = (0, 0, fb.cols, fb.rows)

PHONES = {  # name: (w px, h px, pitch, top inset px, bottom inset px)
    '17pro': (1206, 2622, 5, 62 * 3, 34 * 3),
    '2x':    (828, 1792, 4, 48 * 2, 34 * 2),
}
def render(screen, phone='17pro', base='AMBER', out=None, **kw):
    w, h, p, top, bot = PHONES[phone]
    fb = FB(w, h, p, top, bot, base)
    screen(fb, **kw)
    return fb.png(out or f'out/{screen.__name__}-{phone}-{base.lower()}.png'), fb

if __name__ == '__main__':
    import os; os.makedirs('out', exist_ok=True)
    for s in (home, us, stand, chat): render(s)
    render(settings); render(settings, base='TEAL', base_name='TEAL')
    render(home, '2x'); render(settings, '2x')
    print('done')
