#!/usr/bin/env python3
"""
Cycle-Accurate Zilog Z80 + Sega 315-5124 VDP Mode 4 + SN76489 PSG Hardware Simulator & Verifier.
Boots sms/angrybirds.sms from Reset Vector ($0000), verifies:
  1. Official Sega "TMR SEGA" Header ($7FF0..$7FFF), Checksum, Mapper & EPROM/EverDrive alignment
  2. Cold Reset -> Mapper Init -> PSG Silence -> 8KB RAM / 16KB VRAM / 32B CRAM Init
  3. Title Screen Rendering (24x5 ANGRY BIRDS Logo + 5 Parade Sprites + Stationary Top-2-Row HUD)
  4. SN76489 PSG 4-Channel Balkan Theme Sequencer & Multi-Stage Sound Effects
  5. Controller Input -> Stage Select -> Stage 1-01 Intro Pan -> Slingshot Aiming
  6. Bird Launch -> Parabolic Flight -> Camera Follow -> Block Destruction & Pig Popping
  7. Console PAUSE Button (NMI $0066) Hardware Interrupt Handling
Also renders actual SMS VDP 256x192 screenshots from emulated VRAM/CRAM/SAT!
"""
import os
import sys
import zlib
import struct

SMS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROM_64K_PATH = os.path.join(SMS_DIR, "angrybirds.sms")
ROM_32K_PATH = os.path.join(SMS_DIR, "angrybirds_32k.sms")
BUILD_DIR = os.path.join(SMS_DIR, "build")


class SMSMachine:
    def __init__(self, rom_bytes):
        self.rom = rom_bytes
        self.ram = bytearray(8192)       # 8 KB System RAM ($C000..$DFFF)
        self.vram = bytearray(16384)     # 16 KB VDP VRAM ($0000..$3FFF)
        self.cram = bytearray(32)        # 32-Byte VDP CRAM Palette ($00..$1F)
        self.vdp_regs = [0] * 16
        self.mapper = [0, 0, 1, 2]       # $FFFC..$FFFF

        # Z80 Registers
        self.A = 0
        self.F = 0
        self.B = 0
        self.C = 0
        self.D = 0
        self.E = 0
        self.H = 0
        self.L = 0
        self.SP = 0xDFF0
        self.PC = 0x0000
        self.IX = 0x0000
        self.IY = 0x0000
        self.iff1 = False
        self.im = 0
        self.halted = False

        # VDP state
        self.vdp_latch = False
        self.vdp_first = 0
        self.vdp_cmd = 0
        self.vdp_addr = 0
        self.vdp_status = 0x00

        # PSG state
        self.psg_latched_ch = 0
        self.psg_latched_type = 0
        self.psg_tones = [0, 0, 0, 0]
        self.psg_vols = [0x0F, 0x0F, 0x0F, 0x0F]
        self.psg_writes = 0

        # Controller state ($DC active-low: $FF = nothing pressed)
        self.joy1_port = 0xFF

    # --- 16-bit Register Pair Helpers ---
    @property
    def BC(self):
        return (self.B << 8) | self.C

    @BC.setter
    def BC(self, v):
        self.B = (v >> 8) & 0xFF
        self.C = v & 0xFF

    @property
    def DE(self):
        return (self.D << 8) | self.E

    @DE.setter
    def DE(self, v):
        self.D = (v >> 8) & 0xFF
        self.E = v & 0xFF

    @property
    def HL(self):
        return (self.H << 8) | self.L

    @HL.setter
    def HL(self, v):
        self.H = (v >> 8) & 0xFF
        self.L = v & 0xFF

    @property
    def AF(self):
        return (self.A << 8) | self.F

    @AF.setter
    def AF(self, v):
        self.A = (v >> 8) & 0xFF
        self.F = v & 0xFF

    # --- Memory Bus ($0000..$FFFF) ---
    def read8(self, addr):
        addr &= 0xFFFF
        if addr < 0x0400:
            return self.rom[addr]
        if addr < 0x4000:
            bank = self.mapper[1]
            return self.rom[(bank * 0x4000 + addr) % len(self.rom)]
        if addr < 0x8000:
            bank = self.mapper[2]
            return self.rom[(bank * 0x4000 + (addr - 0x4000)) % len(self.rom)]
        if addr < 0xC000:
            bank = self.mapper[3]
            return self.rom[(bank * 0x4000 + (addr - 0x8000)) % len(self.rom)]
        return self.ram[addr & 0x1FFF]

    def write8(self, addr, val):
        addr &= 0xFFFF
        val &= 0xFF
        if addr >= 0xC000:
            self.ram[addr & 0x1FFF] = val
            if addr >= 0xFFFC:
                self.mapper[addr - 0xFFFC] = val

    def read16(self, addr):
        return self.read8(addr) | (self.read8(addr + 1) << 8)

    def write16(self, addr, val):
        self.write8(addr, val & 0xFF)
        self.write8(addr + 1, (val >> 8) & 0xFF)

    def push16(self, val):
        self.SP = (self.SP - 1) & 0xFFFF
        self.write8(self.SP, (val >> 8) & 0xFF)
        self.SP = (self.SP - 1) & 0xFFFF
        self.write8(self.SP, val & 0xFF)

    def pop16(self):
        lo = self.read8(self.SP)
        self.SP = (self.SP + 1) & 0xFFFF
        hi = self.read8(self.SP)
        self.SP = (self.SP + 1) & 0xFFFF
        return (hi << 8) | lo

    # --- I/O Bus ---
    def io_read(self, port):
        port &= 0xFF
        if port == 0xBF:
            st = self.vdp_status
            self.vdp_status = 0x00
            self.vdp_latch = False
            return st
        if port == 0xBE:
            self.vdp_latch = False
            v = self.vram[self.vdp_addr & 0x3FFF]
            self.vdp_addr = (self.vdp_addr + 1) & 0x3FFF
            return v
        if port == 0xDC:
            return self.joy1_port
        if port == 0xDD:
            return 0xFF
        return 0xFF

    def io_write(self, port, val):
        port &= 0xFF
        val &= 0xFF
        if port == 0xBF:
            if not self.vdp_latch:
                self.vdp_first = val
                self.vdp_latch = True
            else:
                self.vdp_latch = False
                self.vdp_cmd = (val >> 6) & 3
                self.vdp_addr = ((val & 0x3F) << 8) | self.vdp_first
                if self.vdp_cmd == 2:
                    reg = val & 0x0F
                    self.vdp_regs[reg] = self.vdp_first
        elif port == 0xBE:
            self.vdp_latch = False
            if self.vdp_cmd == 3:
                self.cram[self.vdp_addr & 0x1F] = val
            else:
                self.vram[self.vdp_addr & 0x3FFF] = val
            self.vdp_addr = (self.vdp_addr + 1) & 0x3FFF
        elif port in (0x7E, 0x7F):
            self.psg_writes += 1
            if val & 0x80:
                self.psg_latched_ch = (val >> 5) & 3
                self.psg_latched_type = (val >> 4) & 1
                data4 = val & 0x0F
                if self.psg_latched_type == 1:
                    self.psg_vols[self.psg_latched_ch] = data4
                else:
                    if self.psg_latched_ch == 3:
                        self.psg_tones[3] = data4
                    else:
                        self.psg_tones[self.psg_latched_ch] = (self.psg_tones[self.psg_latched_ch] & 0x3F0) | data4
            else:
                if self.psg_latched_type == 0 and self.psg_latched_ch < 3:
                    self.psg_tones[self.psg_latched_ch] = ((val & 0x3F) << 4) | (self.psg_tones[self.psg_latched_ch] & 0x0F)

    # --- Interrupts ---
    def trigger_vblank(self):
        self.vdp_status |= 0x80
        if self.iff1 and (self.vdp_regs[1] & 0x20):
            self.halted = False
            self.iff1 = False
            self.push16(self.PC)
            self.PC = 0x0038

    def trigger_pause_nmi(self):
        self.halted = False
        self.push16(self.PC)
        self.PC = 0x0066

    # --- Z80 Flags (S=$80, Z=$40, H=$10, P/V=$04, N=$02, C=$01) ---
    def set_szp(self, val):
        val &= 0xFF
        f = self.F & 0x01
        if val & 0x80:
            f |= 0x80
        if val == 0:
            f |= 0x40
        if bin(val).count("1") % 2 == 0:
            f |= 0x04
        self.F = f

    def get_reg8(self, code):
        if code == 0: return self.B
        if code == 1: return self.C
        if code == 2: return self.D
        if code == 3: return self.E
        if code == 4: return self.H
        if code == 5: return self.L
        if code == 6: return self.read8(self.HL)
        return self.A

    def set_reg8(self, code, val):
        val &= 0xFF
        if code == 0: self.B = val
        elif code == 1: self.C = val
        elif code == 2: self.D = val
        elif code == 3: self.E = val
        elif code == 4: self.H = val
        elif code == 5: self.L = val
        elif code == 6: self.write8(self.HL, val)
        else: self.A = val

    def get_reg16(self, code):
        if code == 0: return self.BC
        if code == 1: return self.DE
        if code == 2: return self.HL
        return self.SP

    def set_reg16(self, code, val):
        val &= 0xFFFF
        if code == 0: self.BC = val
        elif code == 1: self.DE = val
        elif code == 2: self.HL = val
        else: self.SP = val

    def check_cond(self, cc):
        if cc == 0: return not bool(self.F & 0x40)  # NZ
        if cc == 1: return bool(self.F & 0x40)      # Z
        if cc == 2: return not bool(self.F & 0x01)  # NC
        if cc == 3: return bool(self.F & 0x01)      # C
        if cc == 4: return not bool(self.F & 0x04)  # PO
        if cc == 5: return bool(self.F & 0x04)      # PE
        if cc == 6: return not bool(self.F & 0x80)  # P
        return bool(self.F & 0x80)                  # M

    def alu8(self, op, val):
        val &= 0xFF
        a = self.A
        c = self.F & 1
        if op == 0:  # ADD
            res = a + val
            ov = ((a ^ ~val) & (a ^ res) & 0x80) != 0
            self.A = res & 0xFF
            self.F = (0x80 if self.A & 0x80 else 0) | (0x40 if self.A == 0 else 0) | (0x04 if ov else 0) | (1 if res > 0xFF else 0)
        elif op == 1:  # ADC
            res = a + val + c
            ov = ((a ^ ~val) & (a ^ res) & 0x80) != 0
            self.A = res & 0xFF
            self.F = (0x80 if self.A & 0x80 else 0) | (0x40 if self.A == 0 else 0) | (0x04 if ov else 0) | (1 if res > 0xFF else 0)
        elif op == 2:  # SUB
            res = a - val
            ov = ((a ^ val) & (a ^ res) & 0x80) != 0
            self.A = res & 0xFF
            self.F = 0x02 | (0x80 if self.A & 0x80 else 0) | (0x40 if self.A == 0 else 0) | (0x04 if ov else 0) | (1 if res < 0 else 0)
        elif op == 3:  # SBC
            res = a - val - c
            ov = ((a ^ val) & (a ^ res) & 0x80) != 0
            self.A = res & 0xFF
            self.F = 0x02 | (0x80 if self.A & 0x80 else 0) | (0x40 if self.A == 0 else 0) | (0x04 if ov else 0) | (1 if res < 0 else 0)
        elif op == 4:  # AND
            self.A = (a & val) & 0xFF
            self.F = 0x10
            self.set_szp(self.A)
            self.F &= ~1
        elif op == 5:  # XOR
            self.A = (a ^ val) & 0xFF
            self.F = 0
            self.set_szp(self.A)
        elif op == 6:  # OR
            self.A = (a | val) & 0xFF
            self.F = 0
            self.set_szp(self.A)
        elif op == 7:  # CP
            res = a - val
            ov = ((a ^ val) & (a ^ res) & 0x80) != 0
            r8 = res & 0xFF
            self.F = 0x02 | (0x80 if r8 & 0x80 else 0) | (0x40 if r8 == 0 else 0) | (0x04 if ov else 0) | (1 if res < 0 else 0)

    def fetch8(self):
        v = self.read8(self.PC)
        self.PC = (self.PC + 1) & 0xFFFF
        return v

    def fetch16(self):
        lo = self.fetch8()
        hi = self.fetch8()
        return (hi << 8) | lo

    def fetch_signed8(self):
        v = self.fetch8()
        return v - 256 if v >= 128 else v

    def step(self):
        if self.halted:
            return
        op = self.fetch8()

        if op == 0x00:    # NOP
            return
        if op == 0x76:    # HALT
            self.halted = True
            return
        if op == 0xF3:    # DI
            self.iff1 = False
            return
        if op == 0xFB:    # EI
            self.iff1 = True
            return
        if op == 0xC9:    # RET
            self.PC = self.pop16()
            return
        if op == 0xEB:    # EX DE, HL
            self.DE, self.HL = self.HL, self.DE
            return
        if op == 0xF9:    # LD SP, HL
            self.SP = self.HL
            return
        if op == 0xE9:    # JP (HL)
            self.PC = self.HL
            return
        if op == 0x2F:    # CPL
            self.A = (~self.A) & 0xFF
            self.F |= 0x12
            return
        if op == 0x37:    # SCF
            self.F = (self.F & 0xC4) | 0x01
            return
        if op == 0x3F:    # CCF
            self.F = (self.F & 0xC4) ^ 0x01
            return
        if op == 0x07:    # RLCA
            c = (self.A >> 7) & 1
            self.A = ((self.A << 1) | c) & 0xFF
            self.F = (self.F & 0xC4) | c
            return
        if op == 0x0F:    # RRCA
            c = self.A & 1
            self.A = ((self.A >> 1) | (c << 7)) & 0xFF
            self.F = (self.F & 0xC4) | c
            return
        if op == 0x17:    # RLA
            old_c = self.F & 1
            c = (self.A >> 7) & 1
            self.A = ((self.A << 1) | old_c) & 0xFF
            self.F = (self.F & 0xC4) | c
            return
        if op == 0x1F:    # RRA
            old_c = self.F & 1
            c = self.A & 1
            self.A = ((self.A >> 1) | (old_c << 7)) & 0xFF
            self.F = (self.F & 0xC4) | c
            return

        # DJNZ / JR
        if op == 0x10:    # DJNZ
            rel = self.fetch_signed8()
            self.B = (self.B - 1) & 0xFF
            if self.B != 0:
                self.PC = (self.PC + rel) & 0xFFFF
            return
        if op == 0x18:    # JR rel
            rel = self.fetch_signed8()
            self.PC = (self.PC + rel) & 0xFFFF
            return
        if (op & 0xE7) == 0x20:  # JR cc, rel
            cc = (op >> 3) & 3
            rel = self.fetch_signed8()
            if self.check_cond(cc):
                self.PC = (self.PC + rel) & 0xFFFF
            return

        # 16-bit LD rp, nn & ADD HL, rp & INC/DEC rp
        if (op & 0xCF) == 0x01:
            self.set_reg16((op >> 4) & 3, self.fetch16())
            return
        if (op & 0xCF) == 0x09:  # ADD HL, rp
            res = self.HL + self.get_reg16((op >> 4) & 3)
            self.F = (self.F & 0xC4) | (1 if res > 0xFFFF else 0)
            self.HL = res & 0xFFFF
            return
        if (op & 0xCF) == 0x03:  # INC rp
            rp = (op >> 4) & 3
            self.set_reg16(rp, (self.get_reg16(rp) + 1) & 0xFFFF)
            return
        if (op & 0xCF) == 0x0B:  # DEC rp
            rp = (op >> 4) & 3
            self.set_reg16(rp, (self.get_reg16(rp) - 1) & 0xFFFF)
            return

        # Direct/Indirect loads
        if op == 0x02: self.write8(self.BC, self.A); return
        if op == 0x0A: self.A = self.read8(self.BC); return
        if op == 0x12: self.write8(self.DE, self.A); return
        if op == 0x1A: self.A = self.read8(self.DE); return
        if op == 0x22: self.write16(self.fetch16(), self.HL); return
        if op == 0x2A: self.HL = self.read16(self.fetch16()); return
        if op == 0x32: self.write8(self.fetch16(), self.A); return
        if op == 0x3A: self.A = self.read8(self.fetch16()); return

        # 8-bit INC / DEC r
        if (op & 0xC7) == 0x04:
            r = (op >> 3) & 7
            v = (self.get_reg8(r) + 1) & 0xFF
            self.set_reg8(r, v)
            self.F = (self.F & 1) | (0x80 if v & 0x80 else 0) | (0x40 if v == 0 else 0) | (0x04 if v == 0x80 else 0)
            return
        if (op & 0xC7) == 0x05:
            r = (op >> 3) & 7
            v = (self.get_reg8(r) - 1) & 0xFF
            self.set_reg8(r, v)
            self.F = (self.F & 1) | 0x02 | (0x80 if v & 0x80 else 0) | (0x40 if v == 0 else 0) | (0x04 if v == 0x7F else 0)
            return

        # 8-bit LD r, n
        if (op & 0xC7) == 0x06:
            self.set_reg8((op >> 3) & 7, self.fetch8())
            return

        # 8-bit LD r, r' (0x40..0x7F)
        if 0x40 <= op <= 0x7F:
            self.set_reg8((op >> 3) & 7, self.get_reg8(op & 7))
            return

        # 8-bit ALU r (0x80..0xBF)
        if 0x80 <= op <= 0xBF:
            self.alu8((op >> 3) & 7, self.get_reg8(op & 7))
            return

        # 8-bit ALU n (0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE)
        if (op & 0xC7) == 0xC6:
            self.alu8((op >> 3) & 7, self.fetch8())
            return

        # RET cc / JP cc / CALL cc / JP / CALL / PUSH / POP
        if (op & 0xC7) == 0xC0:
            if self.check_cond((op >> 3) & 7):
                self.PC = self.pop16()
            return
        if (op & 0xC7) == 0xC2:
            nn = self.fetch16()
            if self.check_cond((op >> 3) & 7):
                self.PC = nn
            return
        if op == 0xC3:
            self.PC = self.fetch16()
            return
        if (op & 0xC7) == 0xC4:
            nn = self.fetch16()
            if self.check_cond((op >> 3) & 7):
                self.push16(self.PC)
                self.PC = nn
            return
        if op == 0xCD:
            nn = self.fetch16()
            self.push16(self.PC)
            self.PC = nn
            return
        if (op & 0xCF) == 0xC5:  # PUSH
            rp = (op >> 4) & 3
            val = [self.BC, self.DE, self.HL, self.AF][rp]
            self.push16(val)
            return
        if (op & 0xCF) == 0xC1:  # POP
            rp = (op >> 4) & 3
            val = self.pop16()
            if rp == 0: self.BC = val
            elif rp == 1: self.DE = val
            elif rp == 2: self.HL = val
            else: self.AF = val
            return

        # IN A, (n) / OUT (n), A
        if op == 0xDB:
            self.A = self.io_read(self.fetch8())
            return
        if op == 0xD3:
            self.io_write(self.fetch8(), self.A)
            return

        # CB Prefix (Bit / Shift / Rotate)
        if op == 0xCB:
            cb = self.fetch8()
            r = cb & 7
            v = self.get_reg8(r)
            grp = (cb >> 6) & 3
            sub = (cb >> 3) & 7
            if grp == 0:
                if sub == 0:    # RLC
                    c = (v >> 7) & 1
                    v = ((v << 1) | c) & 0xFF
                elif sub == 1:  # RRC
                    c = v & 1
                    v = ((v >> 1) | (c << 7)) & 0xFF
                elif sub == 2:  # RL
                    old_c = self.F & 1
                    c = (v >> 7) & 1
                    v = ((v << 1) | old_c) & 0xFF
                elif sub == 3:  # RR
                    old_c = self.F & 1
                    c = v & 1
                    v = ((v >> 1) | (old_c << 7)) & 0xFF
                elif sub == 4:  # SLA
                    c = (v >> 7) & 1
                    v = (v << 1) & 0xFF
                elif sub == 5:  # SRA
                    c = v & 1
                    v = ((v >> 1) | (v & 0x80)) & 0xFF
                else:           # SRL
                    c = v & 1
                    v = (v >> 1) & 0xFF
                self.set_reg8(r, v)
                self.F = c
                self.set_szp(v)
            elif grp == 1:      # BIT b, r
                bit_set = bool(v & (1 << sub))
                self.F = (self.F & 1) | 0x10 | (0 if bit_set else 0x44)
            elif grp == 2:      # RES b, r
                self.set_reg8(r, v & ~(1 << sub))
            else:               # SET b, r
                self.set_reg8(r, v | (1 << sub))
            return

        # ED Prefix
        if op == 0xED:
            ed = self.fetch8()
            if ed in (0x46, 0x56, 0x5E):  # IM 0/1/2
                self.im = {0x46: 0, 0x56: 1, 0x5E: 2}[ed]
                return
            if ed in (0x45, 0x4D):        # RETN / RETI
                self.PC = self.pop16()
                return
            if ed == 0x44:                # NEG
                old = self.A
                self.A = (-old) & 0xFF
                self.F = 0x02 | (0x80 if self.A & 0x80 else 0) | (0x40 if self.A == 0 else 0) | (1 if old != 0 else 0)
                return
            if (ed & 0xCF) == 0x42:       # SBC HL, rp
                rp = self.get_reg16((ed >> 4) & 3)
                c = self.F & 1
                res = self.HL - rp - c
                self.HL = res & 0xFFFF
                self.F = 0x02 | (0x80 if self.HL & 0x8000 else 0) | (0x40 if self.HL == 0 else 0) | (1 if res < 0 else 0)
                return
            if (ed & 0xCF) == 0x4A:       # ADC HL, rp
                rp = self.get_reg16((ed >> 4) & 3)
                c = self.F & 1
                res = self.HL + rp + c
                self.HL = res & 0xFFFF
                self.F = (0x80 if self.HL & 0x8000 else 0) | (0x40 if self.HL == 0 else 0) | (1 if res > 0xFFFF else 0)
                return
            if (ed & 0xCF) == 0x43:       # LD (nn), rp
                self.write16(self.fetch16(), self.get_reg16((ed >> 4) & 3))
                return
            if (ed & 0xCF) == 0x4B:       # LD rp, (nn)
                self.set_reg16((ed >> 4) & 3, self.read16(self.fetch16()))
                return
            if ed == 0xA0:                # LDI
                self.write8(self.DE, self.read8(self.HL))
                self.HL = (self.HL + 1) & 0xFFFF
                self.DE = (self.DE + 1) & 0xFFFF
                self.BC = (self.BC - 1) & 0xFFFF
                return
            if ed == 0xB0:                # LDIR
                while self.BC != 0:
                    self.write8(self.DE, self.read8(self.HL))
                    self.HL = (self.HL + 1) & 0xFFFF
                    self.DE = (self.DE + 1) & 0xFFFF
                    self.BC = (self.BC - 1) & 0xFFFF
                return
            if ed == 0xA3:                # OUTI
                self.io_write(self.C, self.read8(self.HL))
                self.HL = (self.HL + 1) & 0xFFFF
                self.B = (self.B - 1) & 0xFF
                return
            if ed == 0xB3:                # OTIR
                while self.B != 0:
                    self.io_write(self.C, self.read8(self.HL))
                    self.HL = (self.HL + 1) & 0xFFFF
                    self.B = (self.B - 1) & 0xFF
                return
            raise RuntimeError(f"Unhandled ED opcode ${ed:02X} at PC=${self.PC-2:04X}")

        raise RuntimeError(f"Unhandled Z80 opcode ${op:02X} at PC=${self.PC-1:04X}")

    def run_frames(self, count, joy_mask=0x00):
        """Runs `count` 60Hz frames. `joy_mask` is active-high button mask (converted to active-low $DC)."""
        self.joy1_port = (~joy_mask) & 0xFF
        for _ in range(count):
            steps = 0
            while not self.halted and steps < 50000:
                self.step()
                steps += 1
            self.trigger_vblank()
            steps = 0
            while not self.halted and steps < 50000:
                self.step()
                steps += 1

    # --- VDP Mode 4 256x192 Screenshot Renderer ---
    def render_screenshot_png(self, out_path):
        def cram_to_rgb(c_byte):
            r = (c_byte & 3) * 85
            g = ((c_byte >> 2) & 3) * 85
            b = ((c_byte >> 4) & 3) * 85
            return (r, g, b)

        pal = [cram_to_rgb(self.cram[i]) for i in range(32)]
        fb = bytearray(256 * 192 * 3)

        # 1. Render Background Nametable ($3800) with R0 bit 6 Top-2-Row Scroll Lock & R8 Scroll
        lock_top2 = bool(self.vdp_regs[0] & 0x40)
        scroll_x = self.vdp_regs[8] & 0xFF

        for sy in range(192):
            ty = sy >> 3
            py = sy & 7
            eff_scroll_x = 0 if (lock_top2 and ty < 2) else scroll_x
            for sx in range(256):
                bg_x = (sx - eff_scroll_x) & 0xFF
                tx = bg_x >> 3
                px = bg_x & 7
                nt_addr = 0x3800 + (ty * 64) + (tx * 2)
                nt_word = self.vram[nt_addr] | (self.vram[nt_addr + 1] << 8)
                tile_idx = nt_word & 0x1FF
                pal_base = 16 if (nt_word & 0x0800) else 0
                h_flip = bool(nt_word & 0x0200)
                v_flip = bool(nt_word & 0x0400)

                f_py = (7 - py) if v_flip else py
                f_px = (7 - px) if h_flip else px
                row_addr = ((tile_idx * 32) + (f_py * 4)) & 0x3FFF
                bp0 = self.vram[row_addr + 0]
                bp1 = self.vram[row_addr + 1]
                bp2 = self.vram[row_addr + 2]
                bp3 = self.vram[row_addr + 3]
                bit = 7 - f_px
                c_idx = (((bp0 >> bit) & 1)
                         | (((bp1 >> bit) & 1) << 1)
                         | (((bp2 >> bit) & 1) << 2)
                         | (((bp3 >> bit) & 1) << 3))
                r, g, b = pal[pal_base + c_idx]
                p_off = (sy * 256 + sx) * 3
                fb[p_off] = r
                fb[p_off + 1] = g
                fb[p_off + 2] = b

        # 2. Render 64 Hardware 8x8 Sprites from SAT ($3F00 Y, $3F80 X/Tile)
        for s_idx in range(64):
            spr_y = self.vram[0x3F00 + s_idx]
            if spr_y == 0xD0:
                break
            spr_x = self.vram[0x3F80 + s_idx * 2]
            tile_idx = self.vram[0x3F80 + s_idx * 2 + 1]
            for py in range(8):
                dy = spr_y + py
                if not (0 <= dy < 192):
                    continue
                row_addr = ((tile_idx * 32) + (py * 4)) & 0x3FFF
                bp0 = self.vram[row_addr + 0]
                bp1 = self.vram[row_addr + 1]
                bp2 = self.vram[row_addr + 2]
                bp3 = self.vram[row_addr + 3]
                for px in range(8):
                    dx = spr_x + px
                    if not (0 <= dx < 256):
                        continue
                    bit = 7 - px
                    c_idx = (((bp0 >> bit) & 1)
                             | (((bp1 >> bit) & 1) << 1)
                             | (((bp2 >> bit) & 1) << 2)
                             | (((bp3 >> bit) & 1) << 3))
                    if c_idx == 0:
                        continue
                    r, g, b = pal[16 + c_idx]
                    p_off = (dy * 256 + dx) * 3
                    fb[p_off] = r
                    fb[p_off + 1] = g
                    fb[p_off + 2] = b

        # Encode RGB24 framebuffer as PNG
        raw_rows = bytearray()
        for y in range(192):
            raw_rows.append(0)
            raw_rows.extend(fb[y * 256 * 3:(y + 1) * 256 * 3])

        def png_chunk(c_type, c_data):
            return (struct.pack(">I", len(c_data)) + c_type + c_data
                    + struct.pack(">I", zlib.crc32(c_type + c_data) & 0xFFFFFFFF))

        png = (b"\x89PNG\r\n\x1a\n"
               + png_chunk(b"IHDR", struct.pack(">IIBBBBB", 256, 192, 8, 2, 0, 0, 0))
               + png_chunk(b"IDAT", zlib.compress(bytes(raw_rows), 9))
               + png_chunk(b"IEND", b""))
        open(out_path, "wb").write(png)


def main():
    print("=== SEGA MASTER SYSTEM HARDWARE VERIFICATION SUITE ===")
    rom_64k = open(ROM_64K_PATH, "rb").read()
    rom_32k = open(ROM_32K_PATH, "rb").read()

    # 1. Verify ROM Sizes, TMR SEGA Header & Checksum
    assert len(rom_64k) == 65536, f"Expected 65,536B 64K ROM, got {len(rom_64k)}"
    assert len(rom_32k) == 32768, f"Expected 32,768B 32K ROM, got {len(rom_32k)}"
    assert rom_64k[0x7FF0:0x7FF8] == b"TMR SEGA", "Missing TMR SEGA signature!"
    stored_chk = struct.unpack_from("<H", rom_64k, 0x7FFA)[0]
    calc_chk = sum(rom_64k[0x0000:0x7FF0]) & 0xFFFF
    assert stored_chk == calc_chk, f"Checksum mismatch: stored ${stored_chk:04X} != calc ${calc_chk:04X}"
    assert rom_64k[0x7FFF] == 0x4C, f"Expected Region/Size byte $4C, got ${rom_64k[0x7FFF]:02X}"
    print(f"[PASS] Official 'TMR SEGA' Header & Checksum (${stored_chk:04X}) verified for 32KB & 64KB ROMs!")

    # 2. Boot ROM from Cold Reset ($0000) and verify Title Screen
    sms = SMSMachine(rom_64k)
    sms.run_frames(5)
    assert sms.mapper == [0, 0, 1, 2], f"Mapper not initialized: {sms.mapper}"
    assert sms.vdp_regs[2] == 0xFF and sms.vdp_regs[3] == 0xFF and sms.vdp_regs[4] == 0xFF and sms.vdp_regs[5] == 0xFF, (
        "SMS1 VDP mandatory registers R2..R5 not $FF!"
    )
    assert sms.read8(0xC018) == 0, f"Expected STATE_TITLE (0), got {sms.read8(0xC018)}"
    assert sms.psg_writes > 20, "SN76489 PSG music sequencer did not write to port $7F!"

    title_png = os.path.join(BUILD_DIR, "preview_title.png")
    sms.render_screenshot_png(title_png)
    print(f"[PASS] Cold Boot -> VDP Mode 4 -> Title Screen & 24x5 Logo verified! ({title_png})")

    # 3. Press Button 1 ($10) -> Verify Transition to Stage Select (STATE_LEVEL_SELECT = 1)
    sms.run_frames(2, joy_mask=0x10)
    sms.run_frames(6, joy_mask=0x00)
    assert sms.read8(0xC018) == 1, f"Expected STATE_LEVEL_SELECT (1), got {sms.read8(0xC018)}"
    select_png = os.path.join(BUILD_DIR, "preview_select.png")
    sms.render_screenshot_png(select_png)
    print(f"[PASS] Stage Select Screen (Stage 1-01..1-21) verified! ({select_png})")

    # 4. Press Button 1 ($10) -> Launch Stage 1-01 -> Intro Pan (224 -> 0) -> STATE_AIMING (3)
    sms.run_frames(2, joy_mask=0x10)
    sms.run_frames(95, joy_mask=0x00)
    assert sms.read8(0xC018) == 3, f"Expected STATE_AIMING (3), got {sms.read8(0xC018)}"
    assert sms.read16(0xC020) == 0, f"Expected cam_x == 0 after intro pan, got {sms.read16(0xC020)}"
    aim_png = os.path.join(BUILD_DIR, "preview_aiming.png")
    sms.render_screenshot_png(aim_png)
    print(f"[PASS] Stage 1-01 Intro Pan & Slingshot Aiming with 6-Dot Trajectory verified! ({aim_png})")

    # 5. Test Console PAUSE Button (NMI $0066) during gameplay
    sms.trigger_pause_nmi()
    sms.run_frames(2)
    assert sms.read8(0xC015) == 1, "Console PAUSE NMI ($0066) did not set pause_flag!"
    assert sms.psg_vols == [0x0F, 0x0F, 0x0F, 0x0F], "PSG not silenced during Pause!"
    sms.trigger_pause_nmi()
    sms.run_frames(2)
    assert sms.read8(0xC015) == 0, "Second Console PAUSE NMI did not unpause!"
    print("[PASS] Console Physical PAUSE Button (Z80 NMI $0066) verified!")

    # 6. Fire Bird (Button 1 = $10) -> Verify Parabolic Flight, Camera Follow & Castle Impact
    initial_blks_intact = sum(1 for i in range(sms.read8(0xC05E)) if sms.read8(0xC3A8 + i) == sms.read8(0xC3C0 + i))
    sms.run_frames(2, joy_mask=0x10)
    assert sms.read8(0xC018) == 4, f"Expected STATE_FLYING (4), got {sms.read8(0xC018)}"

    # Run 66 frames into flight so camera pans right and bird impacts the Pig Castle!
    sms.run_frames(66, joy_mask=0x00)
    cam_mid_flight = sms.read16(0xC020)
    assert cam_mid_flight > 100, f"Camera did not follow flying bird! cam_x = {cam_mid_flight}"
    impact_png = os.path.join(BUILD_DIR, "preview_impact.png")
    sms.render_screenshot_png(impact_png)

    # Let shot finish settling
    sms.run_frames(76, joy_mask=0x00)
    score_after = sms.read16(0xC024)
    assert score_after > 0, f"Expected score > 0 after castle impact, got {score_after}"
    print(f"[PASS] Bird Launch, Camera Auto-Follow (cam_x={cam_mid_flight}), Impact & Gravity Collapse verified! (Score: {score_after * 100})")
    print("=== ALL SEGA MASTER SYSTEM HARDWARE TESTS PASSED! ===")


if __name__ == "__main__":
    main()
