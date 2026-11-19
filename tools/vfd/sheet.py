import sys
from PIL import Image
files = sys.argv[2:]; out = sys.argv[1]
ims = [Image.open(f) for f in files]
H = 1300; ims = [im.resize((round(im.width * H / im.height), H), Image.LANCZOS) for im in ims]
W = sum(i.width for i in ims) + 20 * (len(ims) + 1)
sheet = Image.new('RGB', (W, H + 40), (40, 40, 40)); x = 20
for im in ims: sheet.paste(im, (x, 20)); x += im.width + 20
sheet.save(out)
