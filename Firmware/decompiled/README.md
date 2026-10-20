# Decompiled bracelet firmware (rough source)

Ghidra 11.1.2 headless decompilations of the official firmware images in `Firmware/*.zip`
(the application image, loaded after the SoftDevice at the base shown). One `.c` per image:

| Folder | Image | Base |
|---|---|---|
| `bondTouch/` | Bond Touch (original), `application.bin` | 0x1b000 |
| `bondTouch-hw203/` | Bond Touch, hardware 2.03, `ble_bracelet_s130.bin` | 0x1b000 |
| `bondTouch4/` | Bond Touch 4, `application.bin` | 0x26000 |
| `bondTouchMore/` | Bond Touch More (touch bar), `nrf51822_xxac.bin` | 0x1b000 |
| `bondMini/` | Bond Mini, `application.bin` | 0x26000 |

This is a raw first pass: pseudo-C with Ghidra's generated names (`FUN_0001b108`), not
recompilable. Annotated versions (named handlers for the GATT command dispatch, LED/PWM,
motor and pattern player) replace these as they're done; the facts drawn from them are in
`docs/FIRMWARE_LED_VIBE.md`.

Derived from the vendor's firmware — kept in this private repo for interoperability study
only; don't publish it.
