Decompiled Bond Touch bracelet firmware -- private interoperability study only.
Derived from the vendor's firmware; do not commit or redistribute.

Tool: Ghidra 11.1.2 headless (analyzeHeadless, BinaryLoader, language ARM:LE:32:Cortex),
post-script tools/DecompAll.py (seeds functions from the vector table and from every
bl target that starts with a push, re-runs auto-analysis, applies names.txt, then
decompiles every function).

Per image directory:
  <image>.c    Ghidra pseudo-C for all functions (FUN_xxxxxxxx = unnamed)
  <image>.lst  capstone linear Thumb disassembly, literal-pool/adr string xrefs annotated
  names.txt    the names/comments applied (address, name, note)

Bases: bondTouch, bondTouchMore, bondTouch-hw203 = 0x1B000 (nRF51822, Cortex-M0);
       bondTouch4, bondMini = 0x26000 (nRF52, Cortex-M4).
RAM/peripheral addresses are not mapped, so they appear as raw DAT_/0x2000xxxx values.
Keil __ARM_common_switch8 / jump-table switches (v1 dispatcher, BTM FFB1 dispatcher,
BTM display handler) are not recovered by Ghidra; see the .lst and docs/FIRMWARE_LED_VIBE.md.
