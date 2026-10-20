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

Each folder has:
- `<image>.c` — pseudo-C for every function. The key ones (GATT command dispatch, LED driver
  (AW9109 over I2C), motor, pattern queue and player, timers) carry descriptive names and
  comments; the rest keep Ghidra's `FUN_xxxxxxxx`. Not recompilable.
- `<image>.lst` — the annotated disassembly listing, for the few jump-table switches Ghidra
  couldn't follow (the hw203 dispatcher and two Touch More handlers).
- `names.txt` — address → name map of the identified functions.

The findings (command layouts, LED-only bytes, timing limits, POV) are in
`docs/FIRMWARE_LED_VIBE.md`.

Derived from the vendor's firmware — kept in this private repo for interoperability study
only; don't publish it.
