# Bond Touch bracelet firmware

Official firmware from the Bond Touch app (`com.impossible.bondtouch` 11.2.0 / iOS 7.4.5,
© Impossible Labs), bundled so the app can automatically repair a bracelet stuck in
update (DFU) mode. Files are named after the bracelet model they're for:

| File | Bracelet | Update-mode name | Firmware | SHA-256 (zip) |
|---|---|---|---|---|
| bondTouchMore.zip | Bond Touch More | BOND_M_DFU | 3.1.1 (hw3g) | e99e2080…7cae22 |
| bondTouch.zip | Bond Touch | BOND_DFU | 2.7.9 (hw 2g) | 0b5cbbc8…5cffa99 |
| bondTouch-hw203.zip | Bond Touch (older hardware) | BOND_DFU | 2.6.0 (hw 2.0.3) | 27cc927b…ed7b |
| bondTouch4.zip | Bond Touch 4 | BOND_4_DFU | 2.0.3 (hw4g) | 75080bd3…e8b45b8 |
| bondMini.zip | Bond Mini | BOND_MINI_DFU | 1.2.0 | 8da75cec…ac2068 |

`scripts/fetch-bracelet-firmware.sh` can re-extract them from the official Android package.
