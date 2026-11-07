#!/usr/bin/env python3
"""
Master Build Script for Angry Birds Classic — Sega Master System (SMS) Edition.
1. Extracts & converts APK assets (sprites, logo, blocks, levels, SN76489 music).
2. Assembles Zilog Z80 source files (sms/src/main.asm) into SMS ROM images.
3. Outputs:
   - sms/angrybirds.sms     (65,536 bytes / 64 KB — Emulators, Master EverDrive & 27C512 EPROM)
   - sms/angrybirds_32k.sms (32,768 bytes / 32 KB — Linear 27C256 EPROM without mapper IC)
"""
import os
import sys

SMS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(SMS_DIR, "tools"))

import extract_assets_sms
import asmz80


def main():
    print("=== [1/2] Extracting & Converting Angry Birds APK Assets for SMS ===")
    extract_assets_sms.main()

    print("\n=== [2/2] Assembling Zilog Z80 Source Code (sms/src/main.asm) ===")
    assembler = asmz80.AssemblerZ80(os.path.join(SMS_DIR, "src"))
    rom_64k, rom_32k, chk = assembler.assemble(os.path.join(SMS_DIR, "src", "main.asm"))

    sms_64k_path = os.path.join(SMS_DIR, "angrybirds.sms")
    sms_32k_path = os.path.join(SMS_DIR, "angrybirds_32k.sms")
    open(sms_64k_path, "wb").write(rom_64k)
    open(sms_32k_path, "wb").write(rom_32k)

    assets_end = assembler.symbols["TilesBin"] + 12032
    print(f"ROM Size (64K) : {len(rom_64k):,} bytes (64 KB / 512 Kbit Standard SMS + 27C512 EPROM)")
    print(f"ROM Size (32K) : {len(rom_32k):,} bytes (32 KB / 256 Kbit Linear 27C256 EPROM)")
    print(f"SEGA Header    : {rom_32k[0x7FF0:0x7FF8].decode('ascii')} at $7FF0..$7FFF")
    print(f"SMS Checksum   : ${chk:04X} (stored at $7FFA..$7FFB)")
    print(f"Reset Vector   : ${assembler.symbols['Reset']:04X}")
    print(f"VBlank Vector  : ${assembler.symbols['VBlankVector']:04X}")
    print(f"Pause NMI Vec  : ${assembler.symbols['PauseNmiVector']:04X}")
    print(f"ROM Usage End  : ${assets_end:04X} (limit $7FF0, free: {0x7FF0 - assets_end:,} bytes)")
    print(f"Written Output : {sms_64k_path}")
    print(f"Written Output : {sms_32k_path}")


if __name__ == "__main__":
    main()
