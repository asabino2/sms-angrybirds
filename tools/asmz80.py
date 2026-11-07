#!/usr/bin/env python3
"""
Two-Pass Zilog Z80 Assembler & Sega Master System (SMS) ROM Linker / Checksum Builder.
Supports full Z80 instruction set, local labels (@label), arithmetic expressions,
binary includes (.incbin), and official Sega "TMR SEGA" header checksum generation
at $7FF0..$7FFF for 100% compatibility with SMS BIOS, Emulators, EverDrive & EPROMs.
"""
import os
import re
import sys
import struct

REG8 = {"B": 0, "C": 1, "D": 2, "E": 3, "H": 4, "L": 5, "(HL)": 6, "A": 7}
REG16 = {"BC": 0, "DE": 1, "HL": 2, "SP": 3}
REG16_PUSH = {"BC": 0, "DE": 1, "HL": 2, "AF": 3}
COND = {"NZ": 0, "Z": 1, "NC": 2, "C": 3, "PO": 4, "PE": 5, "P": 6, "M": 7}
ALU_OP = {"ADD": 0, "ADC": 1, "SUB": 2, "SBC": 3, "AND": 4, "XOR": 5, "OR": 6, "CP": 7}
ROT_OP = {"RLC": 0, "RRC": 1, "RL": 2, "RR": 3, "SLA": 4, "SRA": 5, "SLL": 6, "SRL": 7}

IMPLIED = {
    "NOP": b"\x00", "RLCA": b"\x07", "RRCA": b"\x0F", "RLA": b"\x17", "RRA": b"\x1F",
    "DAA": b"\x27", "CPL": b"\x2F", "SCF": b"\x37", "CCF": b"\x3F", "HALT": b"\x76",
    "RET": b"\xC9", "EXX": b"\xD9", "DI": b"\xF3", "EI": b"\xFB",
    "NEG": b"\xED\x44", "RETN": b"\xED\x45", "RETI": b"\xED\x4D",
    "LDI": b"\xED\xA0", "CPI": b"\xED\xA1", "INI": b"\xED\xA2", "OUTI": b"\xED\xA3",
    "LDD": b"\xED\xA8", "CPD": b"\xED\xA9", "IND": b"\xED\xAA", "OUTD": b"\xED\xAB",
    "LDIR": b"\xED\xB0", "CPIR": b"\xED\xB1", "INIR": b"\xED\xB2", "OTIR": b"\xED\xB3",
    "LDDR": b"\xED\xB8", "CPDR": b"\xED\xB9", "INDR": b"\xED\xBA", "OTDR": b"\xED\xBB",
}


class AssemblerZ80:
    def __init__(self, base_dir):
        self.base_dir = base_dir
        self.rom = bytearray(b"\xFF" * 32768)  # 32 KB base linear image ($0000..$7FFF)
        self.symbols = {}
        self.lines = []
        self.scope = "global"

    def preprocess(self, filepath):
        full_path = os.path.abspath(filepath)
        cur_dir = os.path.dirname(full_path)
        out = []
        with open(full_path, "r", encoding="utf-8") as f:
            for line_no, raw in enumerate(f, 1):
                # Strip comments (but preserve ';' inside double quotes)
                in_q = False
                clean_chars = []
                for ch in raw:
                    if ch == '"':
                        in_q = not in_q
                    if ch == ';' and not in_q:
                        break
                    clean_chars.append(ch)
                line = "".join(clean_chars).strip()
                if not line:
                    continue
                if line.lower().startswith(".include"):
                    m = re.match(r'\.include\s+"([^"]+)"', line, re.I)
                    if not m:
                        raise SyntaxError(f"{full_path}:{line_no}: Invalid .include: {line}")
                    inc_path = os.path.join(cur_dir, m.group(1))
                    out.extend(self.preprocess(inc_path))
                else:
                    out.append((full_path, line_no, line))
        return out

    def eval_expr(self, expr, pc, pass_num):
        expr = expr.strip()
        prefix = None
        if expr.startswith("<"):
            prefix = "lo"
            expr = expr[1:].strip()
        elif expr.startswith(">"):
            prefix = "hi"
            expr = expr[1:].strip()

        def repl_token(m):
            tok = m.group(0)
            if tok == "$":
                return str(pc)
            if tok.startswith("$"):
                return str(int(tok[1:], 16))
            if tok.upper().startswith("0X"):
                return str(int(tok[2:], 16))
            if tok.startswith("%"):
                return str(int(tok[1:], 2))
            if tok.startswith("'") and tok.endswith("'") and len(tok) >= 3:
                return str(ord(tok[1]))
            if tok.isdigit():
                return tok
            sym_name = f"{self.scope}.{tok}" if tok.startswith("@") else tok
            if sym_name in self.symbols:
                return str(self.symbols[sym_name])
            if pass_num == 1:
                return "0x1000"
            raise NameError(f"Undefined symbol '{sym_name}' in expression '{expr}'")

        py_expr = re.sub(
            r"\$[0-9A-Fa-f]+|0[xX][0-9A-Fa-f]+|%[01]+|'[^']'|@[A-Za-z0-9_]+|[A-Za-z_][A-Za-z0-9_]*|\d+|\$",
            repl_token,
            expr,
        )
        val = int(eval(py_expr, {"__builtins__": None}, {}))
        if prefix == "lo":
            return val & 0xFF
        if prefix == "hi":
            return (val >> 8) & 0xFF
        return val

    @staticmethod
    def split_args(arg_str):
        args = []
        cur = []
        depth = 0
        in_q = False
        for ch in arg_str:
            if ch == '"':
                in_q = not in_q
            elif not in_q:
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                elif ch == ',' and depth == 0:
                    args.append("".join(cur).strip())
                    cur = []
                    continue
            cur.append(ch)
        if cur:
            args.append("".join(cur).strip())
        return [a for a in args if a != ""]

    @staticmethod
    def is_indirect(op_str):
        """Returns True if op_str is a top-level parenthesized memory/port reference '(...)'."""
        if not (op_str.startswith("(") and op_str.endswith(")")):
            return False
        depth = 0
        for i, ch in enumerate(op_str):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and i < len(op_str) - 1:
                    return False
        return depth == 0

    def parse_ix_iy(self, op_str, pc, pass_num):
        """Checks if op_str is (IX+d) or (IY+d); returns (prefix_byte, disp) or None."""
        if not self.is_indirect(op_str):
            return None
        inner = op_str[1:-1].strip()
        u = inner.upper()
        if u == "IX":
            return (0xDD, 0)
        if u == "IY":
            return (0xFD, 0)
        if u.startswith("IX+") or u.startswith("IX-") or u.startswith("IX ") or u.startswith("IY+") or u.startswith("IY-") or u.startswith("IY "):
            pfx = 0xDD if u.startswith("IX") else 0xFD
            rest = inner[2:].strip()
            disp = self.eval_expr(rest, pc, pass_num)
            return (pfx, disp & 0xFF)
        return None

    def run_pass(self, pass_num):
        pc = 0x0000
        self.scope = "global"

        def emit(b_seq):
            nonlocal pc
            if pass_num == 2:
                assert pc + len(b_seq) <= len(self.rom), f"ROM overflow at ${pc:04X} (+{len(b_seq)} bytes)"
                self.rom[pc:pc + len(b_seq)] = b_seq
            pc += len(b_seq)

        for fpath, lno, text in self.lines:
            try:
                # Equate: NAME = EXPR
                if "=" in text and not text.startswith(".") and not re.match(r'^\S+\s+\S+\s*=', text):
                    name, rhs = [x.strip() for x in text.split("=", 1)]
                    self.symbols[name] = self.eval_expr(rhs, pc, pass_num)
                    continue

                # Label definition(s)
                while ":" in text:
                    lbl_part, rest = text.split(":", 1)
                    lbl = lbl_part.strip()
                    if " " not in lbl and "\t" not in lbl and not lbl.startswith(".") and not lbl.startswith('"'):
                        if lbl.startswith("@"):
                            full_lbl = f"{self.scope}.{lbl}"
                        else:
                            self.scope = lbl
                            full_lbl = lbl
                        self.symbols[full_lbl] = pc
                        text = rest.strip()
                    else:
                        break
                if not text:
                    continue

                parts = text.split(None, 1)
                mnem = parts[0].upper()
                arg_str = parts[1].strip() if len(parts) > 1 else ""
                args = self.split_args(arg_str) if arg_str else []

                # Directives
                if mnem == ".ORG":
                    pc = self.eval_expr(arg_str, pc, 1) & 0xFFFF
                    continue
                if mnem in (".DB", ".BYTE"):
                    items = []
                    for item in args:
                        if item.startswith('"') and item.endswith('"'):
                            items.extend(item[1:-1].encode("ascii"))
                        else:
                            items.append(self.eval_expr(item, pc, pass_num) & 0xFF)
                    emit(bytes(items))
                    continue
                if mnem in (".DW", ".WORD"):
                    out = bytearray()
                    for item in args:
                        v = self.eval_expr(item, pc, pass_num) & 0xFFFF
                        out += struct.pack("<H", v)
                    emit(out)
                    continue
                if mnem == ".INCBIN":
                    m = re.match(r'"([^"]+)"', arg_str)
                    bin_path = os.path.join(os.path.dirname(fpath), m.group(1))
                    emit(open(bin_path, "rb").read())
                    continue
                if mnem in (".DS", ".FILL"):
                    cnt = self.eval_expr(args[0], pc, 1)
                    fill_val = self.eval_expr(args[1], pc, pass_num) & 0xFF if len(args) > 1 else 0x00
                    emit(bytes([fill_val] * cnt))
                    continue

                # Implied instructions
                if not args and mnem in IMPLIED:
                    emit(IMPLIED[mnem])
                    continue

                # IM 0 / 1 / 2
                if mnem == "IM":
                    m_val = self.eval_expr(args[0], pc, pass_num)
                    emit( {0: b"\xED\x46", 1: b"\xED\x56", 2: b"\xED\x5E"}[m_val] )
                    continue

                # RST p
                if mnem == "RST":
                    p = self.eval_expr(args[0], pc, pass_num) & 0x38
                    emit(bytes([0xC7 | p]))
                    continue

                # EX instructions
                if mnem == "EX":
                    a0, a1 = args[0].upper(), args[1].upper()
                    if a0 == "DE" and a1 == "HL":
                        emit(b"\xEB")
                    elif a0 == "AF" and a1 in ("AF'", "AF"):
                        emit(b"\x08")
                    elif a0 == "(SP)" and a1 == "HL":
                        emit(b"\xE3")
                    else:
                        raise ValueError(f"Unsupported EX: {arg_str}")
                    continue

                # PUSH / POP
                if mnem in ("PUSH", "POP"):
                    r = args[0].upper()
                    if r in REG16_PUSH:
                        base = 0xC5 if mnem == "PUSH" else 0xC1
                        emit(bytes([base | (REG16_PUSH[r] << 4)]))
                    elif r in ("IX", "IY"):
                        pfx = 0xDD if r == "IX" else 0xFD
                        op = 0xE5 if mnem == "PUSH" else 0xE1
                        emit(bytes([pfx, op]))
                    else:
                        raise ValueError(f"Invalid {mnem} register: {r}")
                    continue

                # DJNZ rel
                if mnem == "DJNZ":
                    target = self.eval_expr(args[0], pc, pass_num) & 0xFFFF
                    rel = target - (pc + 2)
                    if pass_num == 2 and not (-128 <= rel <= 127):
                        raise ValueError(f"DJNZ out of range ({rel}) to {args[0]}")
                    emit(bytes([0x10, rel & 0xFF]))
                    continue

                # JR [cc,] rel
                if mnem == "JR":
                    if len(args) == 1:
                        target = self.eval_expr(args[0], pc, pass_num) & 0xFFFF
                        rel = target - (pc + 2)
                        if pass_num == 2 and not (-128 <= rel <= 127):
                            raise ValueError(f"JR out of range ({rel}) to {args[0]}")
                        emit(bytes([0x18, rel & 0xFF]))
                    else:
                        cc = args[0].upper()
                        assert cc in ("NZ", "Z", "NC", "C"), f"Invalid JR condition: {cc}"
                        target = self.eval_expr(args[1], pc, pass_num) & 0xFFFF
                        rel = target - (pc + 2)
                        if pass_num == 2 and not (-128 <= rel <= 127):
                            raise ValueError(f"JR {cc} out of range ({rel}) to {args[1]}")
                        emit(bytes([0x20 | (COND[cc] << 3), rel & 0xFF]))
                    continue

                # JP [cc,] nn / JP (HL)
                if mnem == "JP":
                    if len(args) == 1:
                        a0 = args[0].upper()
                        if a0 == "(HL)":
                            emit(b"\xE9")
                        elif a0 == "(IX)":
                            emit(b"\xDD\xE9")
                        elif a0 == "(IY)":
                            emit(b"\xFD\xE9")
                        else:
                            nn = self.eval_expr(args[0], pc, pass_num) & 0xFFFF
                            emit(struct.pack("<BH", 0xC3, nn))
                    else:
                        cc = args[0].upper()
                        nn = self.eval_expr(args[1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0xC2 | (COND[cc] << 3), nn))
                    continue

                # CALL [cc,] nn
                if mnem == "CALL":
                    if len(args) == 1:
                        nn = self.eval_expr(args[0], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0xCD, nn))
                    else:
                        cc = args[0].upper()
                        nn = self.eval_expr(args[1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0xC4 | (COND[cc] << 3), nn))
                    continue

                # RET cc
                if mnem == "RET":
                    cc = args[0].upper()
                    emit(bytes([0xC0 | (COND[cc] << 3)]))
                    continue

                # IN / OUT
                if mnem == "IN":
                    dst, src = args[0].upper(), args[1]
                    if src.upper() == "(C)":
                        emit(bytes([0xED, 0x40 | (REG8[dst] << 3)]))
                    elif dst == "A" and self.is_indirect(src):
                        port = self.eval_expr(src[1:-1], pc, pass_num) & 0xFF
                        emit(bytes([0xDB, port]))
                    else:
                        raise ValueError(f"Unsupported IN: {arg_str}")
                    continue

                if mnem == "OUT":
                    dst, src = args[0], args[1].upper()
                    if dst.upper() == "(C)":
                        emit(bytes([0xED, 0x41 | (REG8[src] << 3)]))
                    elif src == "A" and self.is_indirect(dst):
                        port = self.eval_expr(dst[1:-1], pc, pass_num) & 0xFF
                        emit(bytes([0xD3, port]))
                    else:
                        raise ValueError(f"Unsupported OUT: {arg_str}")
                    continue

                # INC / DEC
                if mnem in ("INC", "DEC"):
                    a0 = args[0].strip()
                    u0 = a0.upper()
                    is_dec = (mnem == "DEC")
                    if u0 in REG8:
                        emit(bytes([(0x05 if is_dec else 0x04) | (REG8[u0] << 3)]))
                        continue
                    if u0 in REG16:
                        emit(bytes([(0x0B if is_dec else 0x03) | (REG16[u0] << 4)]))
                        continue
                    if u0 in ("IX", "IY"):
                        pfx = 0xDD if u0 == "IX" else 0xFD
                        emit(bytes([pfx, 0x2B if is_dec else 0x23]))
                        continue
                    ixy = self.parse_ix_iy(a0, pc, pass_num)
                    if ixy:
                        emit(bytes([ixy[0], 0x35 if is_dec else 0x34, ixy[1]]))
                        continue
                    raise ValueError(f"Unsupported {mnem}: {arg_str}")

                # BIT / RES / SET b, r
                if mnem in ("BIT", "RES", "SET"):
                    b_num = self.eval_expr(args[0], pc, pass_num) & 7
                    r_str = args[1].upper()
                    base = {"BIT": 0x40, "RES": 0x80, "SET": 0xC0}[mnem]
                    if r_str in REG8:
                        emit(bytes([0xCB, base | (b_num << 3) | REG8[r_str]]))
                    else:
                        ixy = self.parse_ix_iy(args[1], pc, pass_num)
                        assert ixy, f"Unsupported {mnem} target: {args[1]}"
                        emit(bytes([ixy[0], 0xCB, ixy[1], base | (b_num << 3) | 6]))
                    continue

                # CB-prefix Shifts & Rotates: RLC, RRC, RL, RR, SLA, SRA, SLL, SRL
                if mnem in ROT_OP:
                    r_str = args[0].upper()
                    op_code = ROT_OP[mnem]
                    if r_str in REG8:
                        emit(bytes([0xCB, (op_code << 3) | REG8[r_str]]))
                    else:
                        ixy = self.parse_ix_iy(args[0], pc, pass_num)
                        assert ixy, f"Unsupported {mnem} target: {args[0]}"
                        emit(bytes([ixy[0], 0xCB, ixy[1], (op_code << 3) | 6]))
                    continue

                # ALU operations: ADD, ADC, SUB, SBC, AND, XOR, OR, CP
                if mnem in ALU_OP:
                    # 16-bit HL arithmetic: ADD HL, rp / ADC HL, rp / SBC HL, rp
                    if len(args) == 2 and args[0].upper() in ("HL", "IX", "IY"):
                        dst16 = args[0].upper()
                        src16 = args[1].upper()
                        if dst16 == "HL":
                            assert src16 in REG16, f"Invalid 16-bit register: {src16}"
                            rp = REG16[src16]
                            if mnem == "ADD":
                                emit(bytes([0x09 | (rp << 4)]))
                            elif mnem == "ADC":
                                emit(bytes([0xED, 0x4A | (rp << 4)]))
                            elif mnem == "SBC":
                                emit(bytes([0xED, 0x42 | (rp << 4)]))
                            else:
                                raise ValueError(f"Unsupported 16-bit ALU: {mnem} HL, {src16}")
                        else:
                            pfx = 0xDD if dst16 == "IX" else 0xFD
                            rp_map = {"BC": 0, "DE": 1, dst16: 2, "SP": 3}
                            emit(bytes([pfx, 0x09 | (rp_map[src16] << 4)]))
                        continue

                    # 8-bit ALU: allow both "ADD A, X" and "ADD X"
                    src = args[1].strip() if (len(args) == 2 and args[0].upper() == "A") else args[0].strip()
                    src_u = src.upper()
                    alu_idx = ALU_OP[mnem]
                    if src_u in REG8:
                        emit(bytes([0x80 | (alu_idx << 3) | REG8[src_u]]))
                        continue
                    ixy = self.parse_ix_iy(src, pc, pass_num)
                    if ixy:
                        emit(bytes([ixy[0], 0x86 | (alu_idx << 3), ixy[1]]))
                        continue
                    imm = self.eval_expr(src, pc, pass_num) & 0xFF
                    emit(bytes([0xC6 | (alu_idx << 3), imm]))
                    continue

                # LD dst, src
                if mnem == "LD":
                    dst, src = args[0].strip(), args[1].strip()
                    du, su = dst.upper(), src.upper()

                    # 1. LD r, r' (both in REG8)
                    if du in REG8 and su in REG8:
                        assert not (du == "(HL)" and su == "(HL)"), "LD (HL), (HL) is HALT"
                        emit(bytes([0x40 | (REG8[du] << 3) | REG8[su]]))
                        continue

                    # 2. LD r, (IX+d) / LD (IX+d), r / LD (IX+d), n
                    ixy_d = self.parse_ix_iy(dst, pc, pass_num)
                    ixy_s = self.parse_ix_iy(src, pc, pass_num)
                    if ixy_d:
                        if su in REG8 and su != "(HL)":
                            emit(bytes([ixy_d[0], 0x70 | REG8[su], ixy_d[1]]))
                        else:
                            n = self.eval_expr(src, pc, pass_num) & 0xFF
                            emit(bytes([ixy_d[0], 0x36, ixy_d[1], n]))
                        continue
                    if ixy_s and du in REG8 and du != "(HL)":
                        emit(bytes([ixy_s[0], 0x46 | (REG8[du] << 3), ixy_s[1]]))
                        continue

                    # 3. LD A, (BC)/(DE)/(nn) and LD (BC)/(DE)/(nn), A
                    if du == "A" and su == "(BC)":
                        emit(b"\x0A")
                        continue
                    if du == "A" and su == "(DE)":
                        emit(b"\x1A")
                        continue
                    if du == "(BC)" and su == "A":
                        emit(b"\x02")
                        continue
                    if du == "(DE)" and su == "A":
                        emit(b"\x12")
                        continue
                    if du == "A" and self.is_indirect(src):
                        nn = self.eval_expr(src[1:-1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0x3A, nn))
                        continue
                    if su == "A" and self.is_indirect(dst):
                        nn = self.eval_expr(dst[1:-1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0x32, nn))
                        continue

                    # 4. LD SP, HL / IX / IY
                    if du == "SP" and su == "HL":
                        emit(b"\xF9")
                        continue
                    if du == "SP" and su in ("IX", "IY"):
                        emit(bytes([0xDD if su == "IX" else 0xFD, 0xF9]))
                        continue

                    # 5. LD rp, (nn) and LD (nn), rp
                    if du in REG16 and self.is_indirect(src):
                        nn = self.eval_expr(src[1:-1], pc, pass_num) & 0xFFFF
                        if du == "HL":
                            emit(struct.pack("<BH", 0x2A, nn))
                        else:
                            emit(struct.pack("<BBH", 0xED, 0x4B | (REG16[du] << 4), nn))
                        continue
                    if su in REG16 and self.is_indirect(dst):
                        nn = self.eval_expr(dst[1:-1], pc, pass_num) & 0xFFFF
                        if su == "HL":
                            emit(struct.pack("<BH", 0x22, nn))
                        else:
                            emit(struct.pack("<BBH", 0xED, 0x43 | (REG16[su] << 4), nn))
                        continue
                    if du in ("IX", "IY") and self.is_indirect(src):
                        pfx = 0xDD if du == "IX" else 0xFD
                        nn = self.eval_expr(src[1:-1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BBH", pfx, 0x2A, nn))
                        continue
                    if su in ("IX", "IY") and self.is_indirect(dst):
                        pfx = 0xDD if su == "IX" else 0xFD
                        nn = self.eval_expr(dst[1:-1], pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BBH", pfx, 0x22, nn))
                        continue

                    # 6. LD rp, nn (16-bit immediate)
                    if du in REG16:
                        nn = self.eval_expr(src, pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BH", 0x01 | (REG16[du] << 4), nn))
                        continue
                    if du in ("IX", "IY"):
                        pfx = 0xDD if du == "IX" else 0xFD
                        nn = self.eval_expr(src, pc, pass_num) & 0xFFFF
                        emit(struct.pack("<BBH", pfx, 0x21, nn))
                        continue

                    # 7. LD r, imm8
                    if du in REG8:
                        n = self.eval_expr(src, pc, pass_num) & 0xFF
                        emit(bytes([0x06 | (REG8[du] << 3), n]))
                        continue

                    # 8. LD I, A / LD R, A / LD A, I / LD A, R
                    if (du, su) == ("I", "A"):
                        emit(b"\xED\x47")
                        continue
                    if (du, su) == ("R", "A"):
                        emit(b"\xED\x4F")
                        continue
                    if (du, su) == ("A", "I"):
                        emit(b"\xED\x57")
                        continue
                    if (du, su) == ("A", "R"):
                        emit(b"\xED\x5F")
                        continue

                    raise ValueError(f"Unsupported LD operands: {arg_str}")

                raise ValueError(f"Unknown Z80 instruction: {mnem} {arg_str}")

            except Exception as e:
                raise RuntimeError(f"{fpath}:{lno}: Error in '{text}' -> {e}") from e

    def assemble(self, entry_file):
        self.lines = self.preprocess(entry_file)
        self.run_pass(1)
        self.run_pass(2)

        # Verify TMR SEGA signature at $7FF0..$7FF7 and compute official SMS Checksum at $7FFA..$7FFB
        assert self.rom[0x7FF0:0x7FF8] == b"TMR SEGA", (
            f"Missing 'TMR SEGA' header at $7FF0..$7FF7: got {self.rom[0x7FF0:0x7FF8]!r}"
        )
        chk = sum(self.rom[0x0000:0x7FF0]) & 0xFFFF
        struct.pack_into("<H", self.rom, 0x7FFA, chk)

        rom_32k = bytes(self.rom)
        # Create 64 KB image (Bank 0 = $0000..$3FFF, Bank 1 = $4000..$7FFF, Bank 2 & 3 = mirrored)
        # Compatible with 27C512 (64 KB) EPROMs, Sega Mapper carts, Master EverDrive, and all emulators
        rom_64k = rom_32k + rom_32k
        return rom_64k, rom_32k, chk
