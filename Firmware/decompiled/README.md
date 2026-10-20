# Decompiled bracelet firmware (rough source)

Ghidra 11.1.2 headless decompilations of the official firmware images in `Firmware/*.zip`
(nRF51822, application loaded at 0x1b000 after the SoftDevice). One `.c` per image:

| Folder | Image |
|---|---|
| `bondTouch/` | Bond Touch (original) |
| `bondTouch-hw203/` | Bond Touch, hardware 2.03 |
| `bondTouch4/` | Bond Touch 4 |
| `bondTouchMore/` | Bond Touch More (touch bar) |
| `bondMini/` | Bond Mini |

This is a raw first pass: pseudo-C with Ghidra's generated names (`FUN_0001b108`), not
recompilable. Annotated versions (named handlers for the GATT command dispatch, LED/PWM,
motor and pattern player) replace these as they're done; the facts drawn from them are in
`docs/FIRMWARE_LED_VIBE.md`.

Derived from the vendor's firmware — kept in this private repo for interoperability study
only; don't publish it.
