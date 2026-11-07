#!/usr/bin/env python3
"""
Extracts and converts authentic Angry Birds Classic 8.0.3 APK assets
(sprites, logo, block textures, palettes, 21 Episode 1 levels, and 128-step Balkan Theme)
into Sega Master System (SMS) VDP Mode 4 4bpp planar tiles, 6-bit CRAM palettes,
level tables, and SN76489 PSG music tables.
"""
import os
import sys
import json
import lzma
import zlib
import math
import struct
import subprocess

SMS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ROOT_DIR = os.path.abspath(os.path.join(SMS_DIR, "..", ".."))
ASSETS_DIR = os.path.join(ROOT_DIR, "decompiled", "apk", "assets", "data")
OUT_DIR = os.path.join(SMS_DIR, "build")
SRC_DIR = os.path.join(SMS_DIR, "src")

AES_KEY = "USCaPQpA4TSNVxMI1v9SK9UC0yZuAnb2"


def decrypt_and_decompress_apk_asset(rel_path):
    """Decrypts an AES-256-CBC (IV=0) asset from the APK and decompresses its LZMA payload."""
    full_path = os.path.join(ASSETS_DIR, rel_path)
    js_code = (
        "const c=require('crypto'),fs=require('fs');"
        f"const d=c.createDecipheriv('aes-256-cbc',Buffer.from('{AES_KEY}'),Buffer.alloc(16));"
        "process.stdout.write(Buffer.concat([d.update(fs.readFileSync(process.argv[1])),d.final()]));"
    )
    dec = subprocess.check_output(["node", "-e", js_code, full_path])
    if dec[:5] == b"\x89LZMA":
        return lzma.decompress(dec[9:])
    return dec


def extract_7z_stream(rel_path):
    """Extracts a .stream.7z archive into memory using system tar."""
    full_path = os.path.join(ASSETS_DIR, rel_path)
    return subprocess.check_output(["tar", "-xOf", full_path])


def decode_png_rgba(full_path):
    """Pure-Python PNG RGBA8888 decoder (supports 8-bit RGB, RGBA, and Palette PNGs)."""
    data = open(full_path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"Not a PNG: {full_path}"
    o = 8
    w = h = bd = ct = 0
    idat = bytearray()
    plte = b""
    trns = b""
    while o < len(data):
        length, chunk_type = struct.unpack(">I4s", data[o:o+8])
        chunk = data[o+8:o+8+length]
        o += 12 + length
        if chunk_type == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", chunk[:10])
        elif chunk_type == b"PLTE":
            plte = chunk
        elif chunk_type == b"tRNS":
            trns = chunk
        elif chunk_type == b"IDAT":
            idat.extend(chunk)
        elif chunk_type == b"IEND":
            break

    raw = zlib.decompress(idat)
    bpp = 4 if ct == 6 else (3 if ct == 2 else 1)
    stride = w * bpp
    recon = bytearray(h * stride)
    pos = 0
    for y in range(h):
        flt = raw[pos]
        pos += 1
        row_out = y * stride
        prev_out = (y - 1) * stride
        for i in range(stride):
            x = raw[pos + i]
            a = recon[row_out + i - bpp] if i >= bpp else 0
            b = recon[prev_out + i] if y > 0 else 0
            c = recon[prev_out + i - bpp] if (y > 0 and i >= bpp) else 0
            if flt == 0:
                val = x
            elif flt == 1:
                val = (x + a) & 0xFF
            elif flt == 2:
                val = (x + b) & 0xFF
            elif flt == 3:
                val = (x + ((a + b) >> 1)) & 0xFF
            elif flt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                val = (x + pr) & 0xFF
            else:
                val = x
            recon[row_out + i] = val
        pos += stride

    rgba = bytearray(w * h * 4)
    if ct == 6:
        rgba[:] = recon
    elif ct == 2:
        for i in range(w * h):
            rgba[4*i:4*i+3] = recon[3*i:3*i+3]
            rgba[4*i+3] = 255
    elif ct == 3:
        for i in range(w * h):
            idx = recon[i]
            rgba[4*i:4*i+3] = plte[3*idx:3*idx+3]
            rgba[4*i+3] = trns[idx] if idx < len(trns) else 255
    return w, h, rgba


def crop_rgba(w, h, rgba, cx, cy, cw, ch):
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        sy = min(h - 1, max(0, cy + y))
        for x in range(cw):
            sx = min(w - 1, max(0, cx + x))
            out[(y * cw + x) * 4:(y * cw + x + 1) * 4] = rgba[(sy * w + sx) * 4:(sy * w + sx + 1) * 4]
    return cw, ch, out


def decode_zstream_sprite(zstream_bytes, frame_info):
    """Extracts an RGBA8888 image from a Rovio .zstream (RGBA4444) using .sheet.json metadata."""
    st = frame_info["stream"]
    pos = st["position"] + 40
    w = st["width"]
    h = st["height"]
    rgba = bytearray(w * h * 4)
    for i in range(w * h):
        px = struct.unpack_from("<H", zstream_bytes, pos + i * 2)[0]
        r = ((px >> 12) & 0xF) * 17
        g = ((px >> 8) & 0xF) * 17
        b = ((px >> 4) & 0xF) * 17
        a = (px & 0xF) * 17
        rgba[4*i] = r
        rgba[4*i+1] = g
        rgba[4*i+2] = b
        rgba[4*i+3] = a
    return w, h, rgba


def scale_rgba(w, h, rgba, dst_w, dst_h, trim_alpha=True):
    """Area-averaging downsample with optional tight alpha bounding box."""
    min_x, min_y, max_x, max_y = 0, 0, w - 1, h - 1
    if trim_alpha:
        xs, ys = [], []
        for y in range(h):
            for x in range(w):
                if rgba[(y * w + x) * 4 + 3] > 32:
                    xs.append(x)
                    ys.append(y)
        if xs and ys:
            min_x, max_x = min(xs), max(xs)
            min_y, max_y = min(ys), max(ys)

    bw = max(1, max_x - min_x + 1)
    bh = max(1, max_y - min_y + 1)
    out = bytearray(dst_w * dst_h * 4)
    for dy in range(dst_h):
        sy0 = min_y + (dy * bh) / dst_h
        sy1 = min_y + ((dy + 1) * bh) / dst_h
        for dx in range(dst_w):
            sx0 = min_x + (dx * bw) / dst_w
            sx1 = min_x + ((dx + 1) * bw) / dst_w
            r_sum = g_sum = b_sum = a_sum = cnt = 0
            for sy in range(int(sy0), min(h, int(math.ceil(sy1)))):
                for sx in range(int(sx0), min(w, int(math.ceil(sx1)))):
                    idx = (sy * w + sx) * 4
                    a = rgba[idx + 3]
                    a_sum += a
                    cnt += 1
                    if a > 32:
                        r_sum += rgba[idx] * a
                        g_sum += rgba[idx + 1] * a
                        b_sum += rgba[idx + 2] * a
            d_idx = (dy * dst_w + dx) * 4
            avg_a = a_sum / max(1, cnt)
            if avg_a > 56 and a_sum > 0:
                out[d_idx] = min(255, int(r_sum / a_sum))
                out[d_idx + 1] = min(255, int(g_sum / a_sum))
                out[d_idx + 2] = min(255, int(b_sum / a_sum))
                out[d_idx + 3] = 255
            else:
                out[d_idx:d_idx+4] = b"\x00\x00\x00\x00"
    return out


def rgb_to_sms_cram(r, g, b):
    """Converts 8-bit RGB to Sega Master System 6-bit CRAM byte (00BBGGRR)."""
    r2 = min(3, int(round(r / 85.0)))
    g2 = min(3, int(round(g / 85.0)))
    b2 = min(3, int(round(b / 85.0)))
    return (b2 << 4) | (g2 << 2) | r2


def encode_sms_4bpp_tile(indices, stride, tx, ty):
    """
    Encodes an 8x8 pixel region at (tx*8, ty*8) into 32 bytes of Sega Master System
    VDP Mode 4 planar format (4 bytes per scanline: bp0, bp1, bp2, bp3).
    """
    tile = bytearray(32)
    for y in range(8):
        bp0 = bp1 = bp2 = bp3 = 0
        row_start = (ty * 8 + y) * stride + tx * 8
        for x in range(8):
            c = indices[row_start + x] & 0x0F
            bit = 7 - x
            bp0 |= ((c >> 0) & 1) << bit
            bp1 |= ((c >> 1) & 1) << bit
            bp2 |= ((c >> 2) & 1) << bit
            bp3 |= ((c >> 3) & 1) << bit
        tile[y * 4 + 0] = bp0
        tile[y * 4 + 1] = bp1
        tile[y * 4 + 2] = bp2
        tile[y * 4 + 3] = bp3
    return bytes(tile)


def quantize_to_palette(rgba, w, h, pal_rgb, allowed_indices=None, add_outline=False):
    """Maps an RGBA buffer to indices 0..15 of a 16-color RGB palette (0 = transparent)."""
    if allowed_indices is None:
        allowed_indices = list(range(1, len(pal_rgb)))
    indices = bytearray(w * h)
    for i in range(w * h):
        a = rgba[4*i + 3]
        if a < 80:
            indices[i] = 0
            continue
        r, g, b = rgba[4*i], rgba[4*i + 1], rgba[4*i + 2]
        best_idx = allowed_indices[0]
        best_dist = 10**9
        for p_idx in allowed_indices:
            pr, pg, pb = pal_rgb[p_idx]
            dist = (r - pr)**2 * 3 + (g - pg)**2 * 4 + (b - pb)**2 * 2
            if dist < best_dist:
                best_dist = dist
                best_idx = p_idx
        indices[i] = best_idx

    if add_outline:
        out_indices = bytearray(indices)
        for y in range(h):
            for x in range(w):
                if indices[y * w + x] != 0:
                    if x == 0 or x == w - 1 or y == 0 or y == h - 1:
                        out_indices[y * w + x] = 1
                    else:
                        for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                            if indices[ny * w + nx] == 0:
                                out_indices[y * w + x] = 1
                                break
        return out_indices
    return indices


# ============================================================================
# SEGA MASTER SYSTEM 32-COLOR CRAM PALETTE DEFINITIONS (16 BG + 16 SPRITE)
# ============================================================================
PAL_BG_RGB = [
    (85, 170, 255),   # 0: Sky Blue Backdrop ($39)
    (0, 0, 0),        # 1: Crisp Black Outline / Text Shadow ($00)
    (255, 255, 255),  # 2: Pure Bright White (Clouds, HUD Text, Logo Inner) ($3F)
    (255, 255, 0),    # 3: Bright Gold / Yellow (HUD Stars, Wood Highlight) ($0F)
    (85, 255, 0),     # 4: Lush Bright Grass Green ($0D)
    (0, 170, 85),     # 5: Medium Grass / Distant Hill Green ($18)
    (0, 85, 0),       # 6: Dark Forest / Foliage Green ($04)
    (255, 170, 85),   # 7: Light Wood Plank Fill ($1B)
    (170, 85, 0),     # 8: Medium Wood / Soil Brown ($06)
    (85, 0, 0),       # 9: Dark Soil / Slingshot Bark ($01)
    (255, 0, 0),      # 10: Bright Red (Angry Birds Logo, TNT Crate, Brick) ($03)
    (170, 0, 0),      # 11: Dark Red (Logo 3D Shadow, TNT Shade) ($02)
    (170, 255, 255),  # 12: Ice / Glass Light Cyan ($3E)
    (0, 170, 255),    # 13: Ice / Glass Medium Blue ($38)
    (170, 170, 170),  # 14: Stone Block Light Grey ($2A)
    (85, 85, 85),     # 15: Stone Block Dark Slate Grey ($15)
]

PAL_SPR_RGB = [
    (85, 170, 255),   # 0: Transparent / Sky Blue ($39)
    (0, 0, 0),        # 1: Crisp Black Outline / Bomb Dark Body ($00)
    (255, 255, 255),  # 2: Pure Bright White (Eyes, Belly, Smoke, Aim Dots) ($3F)
    (255, 0, 0),      # 3: Bright Angry Red (Red Bird, TNT, Fireball) ($03)
    (170, 0, 0),      # 4: Dark Crimson Red Shade ($02)
    (255, 255, 0),    # 5: Bright Yellow / Gold (Chuck, Beaks, King Crown, Stars) ($0F)
    (255, 170, 0),    # 6: Warm Orange / Amber (Beak Shade, Wood Block, Fireball) ($0B)
    (170, 85, 0),     # 7: Rich Brown (Wood Shade, Slingshot Pouch) ($06)
    (85, 170, 255),   # 8: Bright Sky Cyan (The Blues Body, Falling Glass) ($39)
    (0, 85, 170),     # 9: Deep Royal Blue (The Blues Shade, Glass Shade) ($24)
    (85, 255, 0),     # 10: Bright Pig Green (Green Pigs Body) ($0D)
    (0, 170, 0),      # 11: Medium Pig Green (Snout / Pig Shading) ($08)
    (0, 85, 0),       # 12: Dark Pig Green Shadow ($04)
    (170, 170, 170),  # 13: Light Stone Grey (Helmet Pig, Stone Block, Bomb Highlight) ($2A)
    (85, 85, 85),     # 14: Dark Slate Grey (Bomb Body, Stone Shade, Smoke) ($15)
    (255, 255, 170),  # 15: Warm Cream / Tan (Red Bird Belly, Wood Highlight) ($2F)
]


def build_palettes_bin():
    out = bytearray()
    for (r, g, b) in PAL_BG_RGB:
        out.append(rgb_to_sms_cram(r, g, b))
    for (r, g, b) in PAL_SPR_RGB:
        out.append(rgb_to_sms_cram(r, g, b))
    assert len(out) == 32
    return bytes(out)


def make_block_tile(border_col, fill_col, hi_col, sh_col, cracked=0, is_tnt=False, tnt_cols=(10, 3)):
    idx = bytearray(64)
    for y in range(8):
        for x in range(8):
            if x == 0 or y == 0 or x == 7 or y == 7:
                c = border_col
            elif x == 1 or y == 1:
                c = hi_col
            elif x == 6 or y == 6:
                c = sh_col
            else:
                c = fill_col
            if is_tnt and 2 <= x <= 5 and 2 <= y <= 5:
                c = tnt_cols[0] if (x == y or x + y == 7) else tnt_cols[1]
            if cracked >= 1 and ((x == y and 1 <= x <= 6) or (x == 4 and y == 2)):
                c = border_col
            if cracked >= 2 and ((x + y == 7 and 1 <= x <= 6) or (x == 2 and y == 5)):
                c = border_col
            idx[y * 8 + x] = c
    return encode_sms_4bpp_tile(idx, 8, 0, 0)


FONT_8X8 = {
    ' ': [0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00],
    '!': [0x18,0x3C,0x3C,0x18,0x18,0x00,0x18,0x00],
    '"': [0x66,0x66,0x24,0x00,0x00,0x00,0x00,0x00],
    '*': [0x18,0x7E,0xFF,0x3C,0x66,0xC3,0x00,0x00],  # Star icon
    '+': [0x00,0x18,0x18,0x7E,0x18,0x18,0x00,0x00],
    ',': [0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x30],
    '-': [0x00,0x00,0x00,0x7E,0x7E,0x00,0x00,0x00],
    '.': [0x00,0x00,0x00,0x00,0x00,0x18,0x18,0x00],
    '/': [0x06,0x0C,0x18,0x30,0x60,0xC0,0x00,0x00],
    '0': [0x3C,0x66,0x6E,0x76,0x66,0x66,0x3C,0x00],
    '1': [0x18,0x38,0x18,0x18,0x18,0x18,0x7E,0x00],
    '2': [0x3C,0x66,0x06,0x1C,0x30,0x66,0x7E,0x00],
    '3': [0x3C,0x66,0x06,0x1C,0x06,0x66,0x3C,0x00],
    '4': [0x0C,0x1C,0x3C,0x6C,0x7E,0x0C,0x1E,0x00],
    '5': [0x7E,0x60,0x7C,0x06,0x06,0x66,0x3C,0x00],
    '6': [0x1C,0x30,0x60,0x7C,0x66,0x66,0x3C,0x00],
    '7': [0x7E,0x66,0x06,0x0C,0x18,0x18,0x18,0x00],
    '8': [0x3C,0x66,0x66,0x3C,0x66,0x66,0x3C,0x00],
    '9': [0x3C,0x66,0x66,0x3E,0x06,0x0C,0x38,0x00],
    ':': [0x00,0x18,0x18,0x00,0x18,0x18,0x00,0x00],
    '<': [0x0C,0x18,0x30,0x60,0x30,0x18,0x0C,0x00],
    '=': [0x00,0x00,0x7E,0x00,0x7E,0x00,0x00,0x00],
    '>': [0x30,0x18,0x0C,0x06,0x0C,0x18,0x30,0x00],
    '?': [0x3C,0x66,0x06,0x1C,0x18,0x00,0x18,0x00],
    'A': [0x18,0x3C,0x66,0x66,0x7E,0x66,0x66,0x00],
    'B': [0x7C,0x66,0x66,0x7C,0x66,0x66,0x7C,0x00],
    'C': [0x3C,0x66,0x60,0x60,0x60,0x66,0x3C,0x00],
    'D': [0x78,0x6C,0x66,0x66,0x66,0x6C,0x78,0x00],
    'E': [0x7E,0x60,0x60,0x78,0x60,0x60,0x7E,0x00],
    'F': [0x7E,0x60,0x60,0x78,0x60,0x60,0x60,0x00],
    'G': [0x3C,0x66,0x60,0x6E,0x66,0x66,0x3E,0x00],
    'H': [0x66,0x66,0x66,0x7E,0x66,0x66,0x66,0x00],
    'I': [0x3C,0x18,0x18,0x18,0x18,0x18,0x3C,0x00],
    'J': [0x1E,0x0C,0x0C,0x0C,0x6C,0x6C,0x38,0x00],
    'K': [0x66,0x6C,0x78,0x70,0x78,0x6C,0x66,0x00],
    'L': [0x60,0x60,0x60,0x60,0x60,0x60,0x7E,0x00],
    'M': [0xC6,0xEE,0xFE,0xD6,0xC6,0xC6,0xC6,0x00],
    'N': [0x66,0x76,0x7E,0x7E,0x6E,0x66,0x66,0x00],
    'O': [0x3C,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
    'P': [0x7C,0x66,0x66,0x7C,0x60,0x60,0x60,0x00],
    'Q': [0x3C,0x66,0x66,0x66,0x6A,0x6C,0x36,0x00],
    'R': [0x7C,0x66,0x66,0x7C,0x6C,0x66,0x66,0x00],
    'S': [0x3C,0x66,0x60,0x3C,0x06,0x66,0x3C,0x00],
    'T': [0x7E,0x18,0x18,0x18,0x18,0x18,0x18,0x00],
    'U': [0x66,0x66,0x66,0x66,0x66,0x66,0x3C,0x00],
    'V': [0x66,0x66,0x66,0x66,0x66,0x3C,0x18,0x00],
    'W': [0xC6,0xC6,0xC6,0xD6,0xFE,0xEE,0xC6,0x00],
    'X': [0x66,0x66,0x3C,0x18,0x3C,0x66,0x66,0x00],
    'Y': [0x66,0x66,0x66,0x3C,0x18,0x18,0x18,0x00],
    'Z': [0x7E,0x06,0x0C,0x18,0x30,0x60,0x7E,0x00],
    '[': [0x3C,0x30,0x30,0x30,0x30,0x30,0x3C,0x00],
    ']': [0x3C,0x0C,0x0C,0x0C,0x0C,0x0C,0x3C,0x00],
}


def build_tiles_bin():
    """
    Builds the unified 376-tile (12,032-byte) SMS VDP Mode 4 4bpp tileset:
      $000..$01F: Background Scenery & Destructible Fortress Blocks (BG Pal 0)
      $020..$05F: ASCII HUD Font with crisp black drop shadow (BG Pal 0)
      $060..$0DF: 16x16 Birds, Pigs, Fireball, Smoke & 8x8 Sprite Helpers + Falling Blocks (SPR Pal 1)
      $100..$177: 24x5 ANGRY BIRDS Title Screen Logo (120 tiles, BG Pal 0)
    """
    print("Extracting APK sprites, logo & building 376 SMS 4bpp tiles...")
    tiles = [bytes(32) for _ in range(0x178)]  # 376 tiles = 12,032 bytes

    # --- 1. Scenery & Castle Block Tiles ($00..$1F) ---
    tiles[0x00] = bytes(32)  # Sky Blue (index 0)
    tiles[0x01] = bytes(32)

    # $02..$05: Fluffy Clouds (White=2, Light Cyan shadow=12)
    for t in range(4):
        c_idx = bytearray(64)
        for y in range(8):
            for x in range(8):
                gx = (t & 1) * 8 + x
                gy = (t >> 1) * 8 + y
                d = math.hypot((gx - 7.5) / 1.4, gy - 8.5)
                if d < 5.0:
                    c_idx[y * 8 + x] = 2
                elif d < 6.5:
                    c_idx[y * 8 + x] = 12 if gy > 8 else 2
        tiles[0x02 + t] = encode_sms_4bpp_tile(c_idx, 8, 0, 0)

    # $06..$09: Distant Hills & Foliage (Med Green=5, Dark Green=6)
    for t in range(4):
        h_idx = bytearray(64)
        for y in range(8):
            for x in range(8):
                if t == 0:
                    h_idx[y * 8 + x] = 5 if x + y >= 7 else 0
                elif t == 1:
                    h_idx[y * 8 + x] = 5 if (7 - x) + y >= 7 else 0
                elif t == 2:
                    h_idx[y * 8 + x] = 6 if (x + y) % 3 == 0 else 5
                else:
                    h_idx[y * 8 + x] = 6 if y > 2 else (5 if (x % 2 == 0) else 6)
        tiles[0x06 + t] = encode_sms_4bpp_tile(h_idx, 8, 0, 0)

    # $0A..$0B: Lush Grass Top (Black=1, Bright Green=4, Med Green=5, Dark Green=6)
    for t in range(2):
        g_idx = bytearray(64)
        for y in range(8):
            for x in range(8):
                if y == 0:
                    g_idx[y * 8 + x] = 1 if (x + t) % 2 == 0 else 0
                elif y == 1:
                    g_idx[y * 8 + x] = 4
                elif y < 5:
                    g_idx[y * 8 + x] = 5 if (x + y + t) % 2 == 0 else 4
                elif y < 7:
                    g_idx[y * 8 + x] = 6
                else:
                    g_idx[y * 8 + x] = 1
        tiles[0x0A + t] = encode_sms_4bpp_tile(g_idx, 8, 0, 0)

    # $0C..$0D: Underground Soil (Tan=7, Med Brown=8, Dark Brown=9)
    for t in range(2):
        s_idx = bytearray(64)
        for y in range(8):
            for x in range(8):
                v = (x * 3 + y * 5 + t * 7) & 7
                s_idx[y * 8 + x] = 7 if v == 0 else (9 if v == 3 else 8)
        tiles[0x0C + t] = encode_sms_4bpp_tile(s_idx, 8, 0, 0)

    # $0E..$11: Wooden Slingshot Fork & Post (Black=1, Tan=7, Brown=8, Dark Bark=9)
    for t in range(4):
        p_idx = bytearray(64)
        for y in range(8):
            for x in range(8):
                if t == 0:
                    if 2 <= x <= 6:
                        p_idx[y * 8 + x] = 1 if (x in (2, 6)) else (7 if x == 3 else 8)
                elif t == 1:
                    if 1 <= x <= 5:
                        p_idx[y * 8 + x] = 1 if (x in (1, 5)) else (7 if x == 2 else 9)
                else:
                    if 2 <= x <= 5:
                        p_idx[y * 8 + x] = 1 if (x in (2, 5)) else (7 if x == 3 else 8)
        tiles[0x0E + t] = encode_sms_4bpp_tile(p_idx, 8, 0, 0)

    # Static BG Blocks ($12..$1C, using PAL_BG_RGB):
    # Glass/Ice: $12..$14 (Black=1, Fill=13, Hi=2, Shade=12)
    tiles[0x12] = make_block_tile(1, 13, 2, 12, cracked=0)
    tiles[0x13] = make_block_tile(1, 13, 2, 12, cracked=1)
    tiles[0x14] = make_block_tile(1, 13, 2, 12, cracked=2)

    # Wood: $15..$17 (Black=1, Fill=7, Hi=3, Shade=8)
    tiles[0x15] = make_block_tile(1, 7, 3, 8, cracked=0)
    tiles[0x16] = make_block_tile(1, 7, 3, 8, cracked=1)
    tiles[0x17] = make_block_tile(1, 7, 3, 8, cracked=2)

    # Stone: $18..$1A (Black=1, Fill=14, Hi=2, Shade=15)
    tiles[0x18] = make_block_tile(1, 14, 2, 15, cracked=0)
    tiles[0x19] = make_block_tile(1, 14, 2, 15, cracked=1)
    tiles[0x1A] = make_block_tile(1, 14, 2, 15, cracked=2)

    # Estrade Platform: $1B (Black=1, Fill=11, Hi=3, Shade=9)
    tiles[0x1B] = make_block_tile(1, 11, 3, 9, cracked=0)

    # TNT Crate: $1C (Black=1, Fill=10, Hi=3, Shade=11)
    tiles[0x1C] = make_block_tile(1, 10, 3, 11, cracked=0, is_tnt=True, tnt_cols=(11, 2))

    # --- 2. ASCII HUD Font ($20..$5F) ---
    for ch, bitmap in FONT_8X8.items():
        code = ord(ch)
        if not (0x20 <= code <= 0x5F):
            continue
        idx = bytearray(64)
        for y in range(8):
            row_bits = bitmap[y]
            for x in range(8):
                if (row_bits >> (7 - x)) & 1:
                    idx[y * 8 + x] = 3 if ch == '*' else 2  # Gold for *, White for text
                    if x + 1 < 8 and idx[y * 8 + x + 1] == 0:
                        idx[y * 8 + x + 1] = 1
                    if y + 1 < 8 and idx[(y + 1) * 8 + x] == 0:
                        idx[(y + 1) * 8 + x] = 1
        tiles[code] = encode_sms_4bpp_tile(idx, 8, 0, 0)

    # --- 3. Hardware Sprites ($60..$DF, using PAL_SPR_RGB) ---
    birds_json = json.loads(decrypt_and_decompress_apk_asset("images/base/INGAME_BIRDS_1.sheet.json").decode("utf-8"))
    pigs0_json = json.loads(decrypt_and_decompress_apk_asset("images/base/INGAME_PIGS_NEW_SHEET_0_1.sheet.json").decode("utf-8"))
    pigs1_json = json.loads(decrypt_and_decompress_apk_asset("images/base/INGAME_PIGS_NEW_SHEET_1_1.sheet.json").decode("utf-8"))

    birds_z = extract_7z_stream("images/base/INGAME_BIRDS_1.stream.7z")
    pigs0_z = extract_7z_stream("images/base/INGAME_PIGS_NEW_SHEET_0_1.stream.7z")
    pigs1_z = extract_7z_stream("images/base/INGAME_PIGS_NEW_SHEET_1_1.stream.7z")

    birds_map = {f["filename"]: f for f in birds_json["frames"]}
    pigs0_map = {f["filename"]: f for f in pigs0_json["frames"]}
    pigs1_map = {f["filename"]: f for f in pigs1_json["frames"]}

    def put_16x16_spr(base_t, idx_16x16):
        # Consecutive 4-tile layout: +0=TL, +1=TR, +2=BL, +3=BR
        tiles[base_t + 0] = encode_sms_4bpp_tile(idx_16x16, 16, 0, 0)
        tiles[base_t + 1] = encode_sms_4bpp_tile(idx_16x16, 16, 1, 0)
        tiles[base_t + 2] = encode_sms_4bpp_tile(idx_16x16, 16, 0, 1)
        tiles[base_t + 3] = encode_sms_4bpp_tile(idx_16x16, 16, 1, 1)

    def extract_spr_16x16(z_buf, fmap, name, allowed):
        w, h, rgba = decode_zstream_sprite(z_buf, fmap[name])
        scaled = scale_rgba(w, h, rgba, 16, 16, trim_alpha=True)
        return quantize_to_palette(scaled, 16, 16, PAL_SPR_RGB, allowed_indices=allowed, add_outline=True)

    def extract_spr_8x8(z_buf, fmap, name, allowed):
        w, h, rgba = decode_zstream_sprite(z_buf, fmap[name])
        scaled = scale_rgba(w, h, rgba, 8, 8, trim_alpha=True)
        return quantize_to_palette(scaled, 8, 8, PAL_SPR_RGB, allowed_indices=allowed, add_outline=False)

    RED_ALLOWED = [1, 2, 3, 4, 5, 6, 7, 15]
    BLUE_ALLOWED = [1, 2, 5, 6, 8, 9, 13]
    YELLOW_ALLOWED = [1, 2, 5, 6, 7, 15]
    BOMB_ALLOWED = [1, 2, 3, 5, 6, 13, 14, 15]
    PIG_ALLOWED = [1, 2, 5, 6, 7, 10, 11, 12, 13, 14, 15]

    # $60: Red Bird Idle, $64: Red Bird Flying
    put_16x16_spr(0x60, extract_spr_16x16(birds_z, birds_map, "BIRD_RED", RED_ALLOWED))
    put_16x16_spr(0x64, extract_spr_16x16(birds_z, birds_map, "BIRD_RED_FLYING", RED_ALLOWED))
    # $68: The Blues
    put_16x16_spr(0x68, extract_spr_16x16(birds_z, birds_map, "BIRD_BLUE", BLUE_ALLOWED))
    # $6C: Chuck Idle, $70: Chuck Dash
    put_16x16_spr(0x6C, extract_spr_16x16(birds_z, birds_map, "BIRD_YELLOW", YELLOW_ALLOWED))
    put_16x16_spr(0x70, extract_spr_16x16(birds_z, birds_map, "BIRD_YELLOW_FLYING", YELLOW_ALLOWED))
    # $74: Bomb Idle, $78: Bomb Armed
    put_16x16_spr(0x74, extract_spr_16x16(birds_z, birds_map, "BIRD_GREY", BOMB_ALLOWED))
    put_16x16_spr(0x78, extract_spr_16x16(birds_z, birds_map, "BIRD_GREY_2", BOMB_ALLOWED))

    # $7C: Explosion Fireball 16x16
    exp_idx = bytearray(16 * 16)
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d < 3.2:
                exp_idx[y * 16 + x] = 2   # White core
            elif d < 5.2:
                exp_idx[y * 16 + x] = 5   # Bright yellow
            elif d < 6.8:
                exp_idx[y * 16 + x] = 6   # Orange flame
            elif d < 7.8:
                exp_idx[y * 16 + x] = 3   # Red ring
            elif d < 8.4:
                exp_idx[y * 16 + x] = 1   # Black edge
    put_16x16_spr(0x7C, exp_idx)

    # $80..$9B: Green Pigs (16x16)
    put_16x16_spr(0x80, extract_spr_16x16(pigs1_z, pigs1_map, "PIG_BASIC_SMALL_01", PIG_ALLOWED))
    put_16x16_spr(0x84, extract_spr_16x16(pigs1_z, pigs1_map, "PIG_BASIC_SMALL_02_SMILE", PIG_ALLOWED))
    put_16x16_spr(0x88, extract_spr_16x16(pigs1_z, pigs1_map, "PIG_BASIC_MEDIUM_01", PIG_ALLOWED))
    put_16x16_spr(0x8C, extract_spr_16x16(pigs0_z, pigs0_map, "PIG_BASIC_BIG_01", PIG_ALLOWED))
    put_16x16_spr(0x90, extract_spr_16x16(pigs0_z, pigs0_map, "PIG_HELMET_01", PIG_ALLOWED))
    put_16x16_spr(0x94, extract_spr_16x16(pigs0_z, pigs0_map, "PIG_MUSTACHE_01", PIG_ALLOWED))
    put_16x16_spr(0x98, extract_spr_16x16(pigs1_z, pigs1_map, "PIG_KING_01", PIG_ALLOWED))

    # $9C: Smoke Pop Puff 16x16
    puff_idx = bytearray(16 * 16)
    for y in range(16):
        for x in range(16):
            d1 = math.hypot(x - 5.5, y - 6.5)
            d2 = math.hypot(x - 10.5, y - 6.5)
            d3 = math.hypot(x - 8.0, y - 9.5)
            d = min(d1, d2, d3)
            if d < 3.2:
                puff_idx[y * 16 + x] = 2   # White cloud
            elif d < 4.5:
                puff_idx[y * 16 + x] = 13  # Light grey
            elif d < 5.3:
                puff_idx[y * 16 + x] = 1   # Black outline
    put_16x16_spr(0x9C, puff_idx)

    # $A0: Trajectory Aim Dot 8x8
    dot_idx = bytearray(64)
    for y in range(8):
        for x in range(8):
            d = math.hypot(x - 3.5, y - 3.5)
            if d < 1.8:
                dot_idx[y * 8 + x] = 2
            elif d < 2.8:
                dot_idx[y * 8 + x] = 1
    tiles[0xA0] = encode_sms_4bpp_tile(dot_idx, 8, 0, 0)

    # $A1: Aim Crosshair 8x8
    cross_idx = bytearray(64)
    for i in range(8):
        cross_idx[3 * 8 + i] = 5
        cross_idx[4 * 8 + i] = 5
        cross_idx[i * 8 + 3] = 5
        cross_idx[i * 8 + 4] = 5
    cross_idx[3 * 8 + 3] = 3
    cross_idx[3 * 8 + 4] = 3
    cross_idx[4 * 8 + 3] = 3
    cross_idx[4 * 8 + 4] = 3
    tiles[0xA1] = encode_sms_4bpp_tile(cross_idx, 8, 0, 0)

    # $A2: Slingshot Pouch 8x8
    tiles[0xA2] = encode_sms_4bpp_tile(extract_spr_8x8(birds_z, birds_map, "SLING_HOLDER", [1, 6, 7, 14]), 8, 0, 0)

    # $A3: Small Split Blue Bird 8x8
    tiles[0xA3] = encode_sms_4bpp_tile(extract_spr_8x8(birds_z, birds_map, "BIRD_BLUE", BLUE_ALLOWED), 8, 0, 0)

    # $B2..$BC: Falling Block 8x8 Sprites (quantized to PAL_SPR_RGB, exact BG block ID + $A0)
    # Glass/Ice ($B2..$B4): Black=1, Fill=8, Hi=2, Shade=9
    tiles[0xB2] = make_block_tile(1, 8, 2, 9, cracked=0)
    tiles[0xB3] = make_block_tile(1, 8, 2, 9, cracked=1)
    tiles[0xB4] = make_block_tile(1, 8, 2, 9, cracked=2)
    # Wood ($B5..$B7): Black=1, Fill=6, Hi=15, Shade=7
    tiles[0xB5] = make_block_tile(1, 6, 15, 7, cracked=0)
    tiles[0xB6] = make_block_tile(1, 6, 15, 7, cracked=1)
    tiles[0xB7] = make_block_tile(1, 6, 15, 7, cracked=2)
    # Stone ($B8..$BA): Black=1, Fill=13, Hi=2, Shade=14
    tiles[0xB8] = make_block_tile(1, 13, 2, 14, cracked=0)
    tiles[0xB9] = make_block_tile(1, 13, 2, 14, cracked=1)
    tiles[0xBA] = make_block_tile(1, 13, 2, 14, cracked=2)
    # Estrade Platform ($BB): Black=1, Fill=4, Hi=5, Shade=7
    tiles[0xBB] = make_block_tile(1, 4, 5, 7, cracked=0)
    # TNT ($BC): Black=1, Fill=3, Hi=5, Shade=4
    tiles[0xBC] = make_block_tile(1, 3, 5, 4, cracked=0, is_tnt=True, tnt_cols=(4, 2))

    # --- 4. Authentic 24x5 ANGRY BIRDS Title Logo ($100..$177, 120 tiles) ---
    menu_png = os.path.join(ASSETS_DIR, "images", "1024x768", "MENU_ELEMENTS_1_1.png")
    mw, mh, mrgba = decode_png_rgba(menu_png)
    cw, ch, crgba = crop_rgba(mw, mh, mrgba, 2, 2, 657, 148)
    logo_rgba = scale_rgba(cw, ch, crgba, 192, 40, trim_alpha=True)
    LOGO_ALLOWED = [1, 2, 3, 7, 10, 11, 14, 15]
    raw_logo_idx = quantize_to_palette(logo_rgba, 192, 40, PAL_BG_RGB, allowed_indices=LOGO_ALLOWED, add_outline=False)
    # Add vibrant Angry Birds Red outer border (color 10) & 3D drop shadow (color 11) around the logo
    logo_idx = bytearray(raw_logo_idx)
    for y in range(40):
        for x in range(192):
            if raw_logo_idx[y * 192 + x] == 0:
                # Check 1px neighborhood for Bright Red border (10)
                near_1 = False
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < 192 and 0 <= ny < 40 and raw_logo_idx[ny * 192 + nx] != 0:
                            near_1 = True
                            break
                    if near_1:
                        break
                if near_1:
                    logo_idx[y * 192 + x] = 10  # Bright Red outer outline
                elif x >= 2 and y >= 2 and raw_logo_idx[(y - 2) * 192 + (x - 2)] != 0:
                    logo_idx[y * 192 + x] = 11  # Dark Red 3D drop shadow
    tile_id = 0x100
    for ty in range(5):
        for tx in range(24):
            tiles[tile_id] = encode_sms_4bpp_tile(logo_idx, 192, tx, ty)
            tile_id += 1

    return b"".join(tiles)


# ============================================================================
# 21 EPISODE 1 (POACHED EGGS) LEVELS EXTRACTOR FOR SMS (GROUND AT TILE_Y = 21)
# ============================================================================
LEVEL_FILES = [
    "Level1.lua", "Level2.lua", "Level3.lua", "Level4.lua", "Level5.lua",
    "Level6.lua", "Level7.lua", "Level8.lua", "Level9.lua", "Level10.lua",
    "Level12.lua", "Level13.lua", "Level14.lua", "Level15.lua", "Level16.lua",
    "Level17.lua", "Level20.lua", "Level21.lua", "Level22.lua", "Level23.lua",
    "Level18.lua"
]

# Keep exact same level order as SNES
LEVEL_FILES = [
    "Level1.lua", "Level2.lua", "Level3.lua", "Level4.lua", "Level5.lua",
    "Level6.lua", "Level7.lua", "Level8.lua", "Level9.lua", "Level10.lua",
    "Level12.lua", "Level13.lua", "Level14.lua", "Level15.lua", "Level16.lua",
    "Level17.lua", "Level18.lua", "Level20.lua", "Level21.lua", "Level22.lua",
    "Level23.lua"
]

BIRD_TYPE_MAP = {
    "RedBird": 0,
    "SmallBlueBird": 1,
    "YellowBird": 2,
    "BlackBird": 3,
    "BasicWhiteBird": 3,
}


def parse_lua51_level(rel_path):
    """Parses a compiled Lua 5.1 level file from the APK and returns its world table."""
    b = decrypt_and_decompress_apk_asset(rel_path)
    assert b[:4] == b"\x1bLua", f"Not Lua bytecode: {rel_path}"
    o = 12

    def r_int():
        nonlocal o
        v = struct.unpack_from("<I", b, o)[0]
        o += 4
        return v

    def r_str():
        nonlocal o
        n = r_int()
        if n == 0:
            return ""
        s = b[o:o+n-1].decode("utf-8", "replace")
        o += n
        return s

    r_str()
    r_int()
    r_int()
    o += 4
    ncode = r_int()
    code = [r_int() for _ in range(ncode)]
    nk = r_int()
    k = []
    for _ in range(nk):
        t = b[o]
        o += 1
        if t == 0:
            k.append(None)
        elif t == 1:
            k.append(bool(b[o]))
            o += 1
        elif t == 3:
            k.append(struct.unpack_from("<f", b, o)[0])
            o += 4
        elif t == 4:
            k.append(r_str())

    R = {}
    G = {}

    def RK(x):
        return k[x & 255] if (x & 256) else R.get(x)

    for ins in code:
        op = ins & 63
        A = (ins >> 6) & 255
        C = (ins >> 14) & 511
        B = (ins >> 23) & 511
        Bx = ins >> 14
        if op == 0:
            R[A] = R.get(B)
        elif op == 1:
            R[A] = k[Bx]
        elif op == 2:
            R[A] = bool(B)
        elif op == 5:
            R[A] = G.get(k[Bx])
        elif op == 6:
            tbl = R.get(B)
            R[A] = tbl.get(RK(C)) if isinstance(tbl, dict) else None
        elif op == 7:
            G[k[Bx]] = R.get(A)
        elif op == 9:
            tbl = R.get(A)
            if isinstance(tbl, dict):
                tbl[RK(B)] = RK(C)
        elif op == 10:
            R[A] = {}

    return G


def classify_block(defn):
    if "Estrade" in defn or "StaticBlock" in defn:
        return (3, 1, 3, 34)
    if "ExtraBlockTNT" in defn or "TNT" in defn:
        return (2, 2, 5, 10)
    mat = 2
    hp = 26
    if defn.startswith("Light"):
        mat = 1
        hp = 16
    elif defn.startswith("Wood"):
        mat = 2
        hp = 26
    elif defn.startswith("Stone"):
        mat = 3
        hp = 42

    if any(defn.endswith(s) for s in ("Block1", "Block7")):
        w, h = 1, 1
    elif any(defn.endswith(s) for s in ("Block2", "Block8")):
        w, h = 2, 1
    elif defn.endswith("Block3"):
        w, h = 2, 2
    elif defn.endswith("Block4"):
        w, h = 3, 1
    elif defn.endswith("Block5"):
        w, h = 3, 2
    elif defn.endswith("Block6"):
        w, h = 4, 1
    elif defn.endswith("Block9"):
        w, h = 3, 3
    elif defn.endswith("Block10"):
        w, h = 4, 1
    else:
        w, h = 2, 2
    return (w, h, mat, hp)


def classify_pig(defn):
    if "Large" in defn or "Big" in defn:
        return (2, 32)
    if "Helmet" in defn:
        return (3, 40)
    if "Grandpa" in defn or "Mustache" in defn:
        return (4, 44)
    if "King" in defn:
        return (4, 56)
    if "Medium" in defn:
        return (1, 24)
    return (0, 14)


def build_levels_bin():
    """
    Extracts 21 Poached Eggs levels for the SMS 256x192 display (Ground at TileY = 21, WorldY = 168).
    All blocks and pigs are shifted up by 2 tiles (16 pixels) relative to SNES so the relative
    parabolic trajectories from the Slingshot (Y = 126) are 100% identical!
    """
    print("Extracting and converting 21 Poached Eggs levels for SMS 256x192 playfield...")
    levels_bin = bytearray()
    summary_lines = ["; Auto-generated summary of 21 extracted Poached Eggs levels (SMS 256x192)"]

    for idx, fname in enumerate(LEVEL_FILES):
        g = parse_lua51_level(f"levels/1_PoachedEggs/{fname}")
        world = g["world"]
        objs = list(world.values())

        bird_objs = sorted([o for o in objs if "startNumber" in o], key=lambda x: x["startNumber"])
        birds = [BIRD_TYPE_MAP.get(o.get("definition", "RedBird"), 0) for o in bird_objs][:6]
        if len(birds) < 4:
            while len(birds) < 4:
                birds.append(birds[-1] if birds else 0)

        castle_objs = [o for o in objs if "startNumber" not in o and o.get("definition") != "Ground"]
        pig_objs_all = [o for o in castle_objs if "Pig" in o.get("definition", "")]
        ref_objs = pig_objs_all if pig_objs_all else castle_objs
        ref_xs = [o.get("x", 40.0) for o in ref_objs] or [40.0]
        min_px, max_px = min(ref_xs), max(ref_xs)

        filtered_blks = [
            o for o in castle_objs
            if "Pig" not in o.get("definition", "")
            and (min_px - 14.0 <= o.get("x", 40.0) <= max_px + 14.0)
        ]
        if not filtered_blks:
            filtered_blks = [o for o in castle_objs if "Pig" not in o.get("definition", "")]

        all_xs = [o.get("x", 40.0) for o in (pig_objs_all + filtered_blks)] or [40.0]
        min_bx, max_bx = min(all_xs), max(all_xs)
        span_bx = max(6.0, max_bx - min_bx)

        def map_tile_x(bx):
            norm = (bx - min_bx) / span_bx
            return max(34, min(52, int(round(35 + norm * 16))))

        # SMS Ground is at TileY = 21 (WorldY = 168)
        def map_tile_y(by, h_tiles):
            ty = int(round(21 - abs(by) * 0.65)) - h_tiles
            return max(4, min(21 - h_tiles, ty))

        raw_blks = []
        for bo in filtered_blks:
            defn = bo.get("definition", "WoodBlock2")
            w, h, mat, hp = classify_block(defn)
            ang = bo.get("angle", 0.0) % math.pi
            if 0.7 < ang < 2.4:
                w, h = h, w
            bx = bo.get("x", 40.0)
            by = bo.get("y", -2.0)
            tx = map_tile_x(bx) - (w // 2)
            tx = max(34, min(54 - w, tx))
            ty = map_tile_y(by, h)
            dist_pig = min((abs(bx - po.get("x", 40.0)) for po in pig_objs_all), default=0.0)
            raw_blks.append({
                "tx": tx, "ty": ty, "w": w, "h": h, "mat": mat, "hp": hp,
                "by": abs(by), "dist_pig": dist_pig
            })

        raw_blks.sort(key=lambda b: (b["dist_pig"] > 8.0, b["by"]))
        chosen_blks = raw_blks[:21]
        chosen_blks.sort(key=lambda b: (-(b["ty"] + b["h"]), b["by"]))

        settled_blks = []
        for b in chosen_blks:
            tx, w, h, mat, hp = b["tx"], b["w"], b["h"], b["mat"], b["hp"]

            def find_support_y(cand_tx):
                best_y = 21  # SMS Ground row (TileY = 21)
                for sb in settled_blks:
                    if sb["tx"] < cand_tx + w and cand_tx < sb["tx"] + sb["w"]:
                        if sb["ty"] < best_y:
                            best_y = sb["ty"]
                return best_y

            sup_y = find_support_y(tx)
            if sup_y == 21 and b["by"] > 4.0:
                for dx in (-1, 1):
                    alt_y = find_support_y(tx + dx)
                    if alt_y < 21:
                        tx = tx + dx
                        sup_y = alt_y
                        break

            new_ty = max(3, sup_y - h)
            if any(sb["tx"] == tx and sb["ty"] == new_ty and sb["w"] == w and sb["h"] == h for sb in settled_blks):
                if new_ty >= 4 + h:
                    new_ty -= h
                else:
                    continue
            settled_blks.append({"tx": tx, "ty": new_ty, "w": w, "h": h, "mat": mat, "hp": hp})

        pig_objs = sorted(pig_objs_all, key=lambda p: p.get("x", 40.0))[:8]
        pigs_encoded = []
        used_pig_pos = set()
        for po in pig_objs:
            ptype, php = classify_pig(po.get("definition", "SmallPiglette"))
            ptx = map_tile_x(po.get("x", 40.0))
            orig_ty = map_tile_y(po.get("y", -2.0), 2)

            best_tx = ptx
            best_sup_ty = 21
            for dx in (0, -1, 1, -2, 2):
                cand_tx = ptx + dx
                cand_tops = [
                    sb["ty"] for sb in settled_blks
                    if (sb["tx"] - 1 <= cand_tx <= sb["tx"] + sb["w"])
                    and sb["ty"] >= orig_ty - 2
                ]
                if cand_tops:
                    top_ty = min(cand_tops)
                    if (cand_tx, top_ty) not in used_pig_pos:
                        best_tx = cand_tx
                        best_sup_ty = top_ty
                        break
                elif dx == 0 and (cand_tx, 21) not in used_pig_pos:
                    best_tx = cand_tx
                    best_sup_ty = 21

            pig_ty = max(2, best_sup_ty - 2)
            for sb in settled_blks:
                if sb["tx"] < best_tx + 2 and best_tx < sb["tx"] + sb["w"]:
                    if not (pig_ty + 2 <= sb["ty"] or pig_ty >= sb["ty"] + sb["h"]):
                        pig_ty = max(2, sb["ty"] - 2)

            used_pig_pos.add((best_tx, pig_ty + 2))
            wx = best_tx * 8
            wy = pig_ty * 8
            pigs_encoded.append((wx, wy, ptype, min(15, max(3, php // 4))))

        blks_encoded = []
        for sb in settled_blks[:21]:
            hp_code = min(31, max(4, sb["hp"] // 2))
            blks_encoded.append((
                sb["tx"],
                sb["ty"],
                (sb["w"] << 4) | sb["h"],
                (sb["mat"] << 5) | hp_code
            ))

        rec = bytearray(128)
        rec[0] = len(birds)
        for i, bt in enumerate(birds):
            rec[1 + i] = bt
        rec[7] = len(pigs_encoded)
        for i, (wx, wy, pt, php) in enumerate(pigs_encoded):
            base = 8 + i * 4
            rec[base] = wx & 0xFF
            rec[base + 1] = (wx >> 8) & 0xFF
            rec[base + 2] = wy & 0xFF
            rec[base + 3] = ((pt & 0x07) << 4) | (php & 0x0F)
        rec[40] = len(blks_encoded)
        for i, (tx, ty, wh, mhp) in enumerate(blks_encoded):
            base = 41 + i * 4
            rec[base] = tx
            rec[base + 1] = ty
            rec[base + 2] = wh
            rec[base + 3] = mhp

        levels_bin += rec
        summary_lines.append(
            f"; Stage 1-{idx+1:02d} ({fname}): {len(birds)} birds {birds}, {len(pigs_encoded)} pigs, {len(blks_encoded)} blocks"
        )

    with open(os.path.join(SRC_DIR, "levels_summary.inc"), "w", encoding="utf-8") as f:
        f.write("\n".join(summary_lines) + "\n")

    return bytes(levels_bin)


# ============================================================================
# SN76489 PSG 128-STEP (16-BAR) BALKAN THEME COMPILER
# ============================================================================
NOTE_FREQS = {
    "REST": 0.0, "TIE": -1.0,
    "A2": 110.00, "A#2": 116.54, "B2": 123.47,
    "C3": 130.81, "C#3": 138.59, "D3": 146.83, "D#3": 155.56, "E3": 164.81, "F3": 174.61,
    "F#3": 185.00, "G3": 196.00, "G#3": 207.65, "A3": 220.00, "A#3": 233.08, "B3": 246.94,
    "C4": 261.63, "C#4": 277.18, "D4": 293.66, "D#4": 311.13, "E4": 329.63, "F4": 349.23,
    "F#4": 369.99, "G4": 392.00, "G#4": 415.30, "A4": 440.00, "A#4": 466.16, "B4": 493.88,
    "C5": 523.25, "C#5": 554.37, "D5": 587.33, "D#5": 622.25, "E5": 659.25, "F5": 698.46,
    "F#5": 739.99, "G5": 783.99, "A5": 880.00, "B5": 987.77,
    # Map sub-110Hz bass notes up 1 octave into SN76489's sweet spot (123..196 Hz)
    "E2": 164.81, "F#2": 185.00, "G2": 196.00, "G#2": 207.65,
}


def encode_psg_note(chan, note_name):
    if note_name == "REST":
        return (0x00, 0x00)
    if note_name == "TIE":
        return (0xFF, 0x00)
    freq = NOTE_FREQS[note_name]
    div = max(1, min(1023, int(round(3579545.0 / (32.0 * freq)))))
    latch = 0x80 | ((chan & 3) << 5) | (div & 0x0F)
    data = (div >> 4) & 0x3F
    return (latch, data)


def build_music_bin():
    """
    Builds a 768-byte table for the 128-step (16-bar) Angry Birds Balkan Theme on SN76489 PSG:
      +0x000..+0x07F: Ch0 Lead Latch/Cmd ($00=REST, $FF=TIE, else $80..$8F)
      +0x080..+0x0FF: Ch0 Lead Data ($00..$3F)
      +0x100..+0x17F: Ch1 Harmony/Mandolin Latch/Cmd ($00=REST, $FF=TIE, else $A0..$AF)
      +0x180..+0x1FF: Ch1 Harmony/Mandolin Data ($00..$3F)
      +0x200..+0x27F: Ch2 Bass Latch/Cmd ($00=REST, else $C0..$CF)
      +0x280..+0x2FF: Ch2 Bass Data ($00..$3F) | Kick($40) | Snare($80)
    """
    melody_128 = [
        # Bars 1-4: Main Theme Statement A (E minor)
        "E4", "F#4", "G4", "E4",   "B4", "TIE", "B4", "TIE",
        "A4", "G4", "F#4", "E4",   "B4", "TIE", "G4", "E4",
        "E4", "F#4", "G4", "E4",   "B4", "C5", "B4", "A4",
        "G4", "F#4", "G4", "A4",   "F#4", "TIE", "D#4", "B3",
        # Bars 5-8: Main Theme Statement A' with High Variation
        "E4", "F#4", "G4", "E4",   "B4", "TIE", "D5", "C5",
        "B4", "A4", "G4", "F#4",   "G4", "A4", "B4", "TIE",
        "C5", "B4", "A4", "G4",    "F#4", "G4", "A4", "F#4",
        "G4", "E4", "D#4", "F#4",  "E4", "TIE", "E4", "REST",
        # Bars 9-12: Section B Soaring Chorus (G major / E minor / B7)
        "B4", "C5", "D5", "B4",    "E5", "TIE", "D5", "C5",
        "B4", "C5", "D5", "B4",    "A4", "TIE", "G4", "F#4",
        "G4", "A4", "B4", "G4",    "C5", "TIE", "B4", "A4",
        "G4", "F#4", "E4", "G4",   "F#4", "TIE", "B4", "REST",
        # Bars 13-16: Section C Climax & Balkan Turnaround
        "E5", "TIE", "D5", "C5",   "B4", "A4", "G4", "E4",
        "C5", "TIE", "B4", "A4",   "G4", "F#4", "E4", "B3",
        "E4", "F#4", "G4", "A4",   "B4", "C5", "D5", "B4",
        "G4", "F#4", "D#4", "B3",  "E4", "TIE", "E4", "REST",
    ]

    # Combine Strings Harmony & Balkan Mandolin Arpeggios on Channel 1
    harmony_128 = [
        # Bars 1-4
        "G3", "A3", "B3", "G3",    "G4", "B4", "G4", "E5",
        "F#4", "E4", "D#4", "C4",  "G4", "B4", "E4", "B3",
        "G3", "A3", "B3", "G3",    "G4", "A4", "G4", "F#4",
        "E4", "D#4", "E4", "F#4",  "D#4", "F#4", "B3", "F#3",
        # Bars 5-8
        "G3", "A3", "B3", "G3",    "G4", "B4", "B4", "A4",
        "G4", "F#4", "E4", "D#4",  "E4", "F#4", "G4", "B4",
        "A4", "G4", "F#4", "E4",   "D#4", "E4", "F#4", "D#4",
        "E4", "B3", "B3", "D#4",   "B3", "E4", "G3", "REST",
        # Bars 9-12
        "G4", "A4", "B4", "G4",    "C5", "G4", "B4", "A4",
        "G4", "A4", "B4", "G4",    "F#4", "A4", "E4", "D4",
        "E4", "F#4", "G4", "E4",    "A4", "E4", "G4", "F#4",
        "E4", "D#4", "C4", "E4",   "D#4", "F#4", "F#4", "REST",
        # Bars 13-16
        "G4", "B4", "F#4", "E4",   "D4", "C4", "B3", "G3",
        "E4", "G4", "D4", "C4",    "B3", "A3", "G3", "F#3",
        "G3", "A3", "B3", "C4",    "D4", "E4", "F#4", "G4",
        "E4", "D#4", "B3", "F#3",  "G3", "B3", "E4", "REST",
    ]

    bass_128 = [
        # Bars 1-4 (Oom-pah alternating root-fifth bass)
        "E3", "B2", "E3", "B2",    "E3", "B2", "G3", "B2",
        "A2", "E3", "B2", "F#3",   "E3", "B2", "E3", "B2",
        "E3", "B2", "E3", "B2",    "G3", "D3", "G3", "D3",
        "C3", "G3", "A2", "E3",    "B2", "F#3", "B2", "F#3",
        # Bars 5-8
        "E3", "B2", "E3", "B2",    "G3", "D3", "G3", "D3",
        "D3", "A2", "B2", "F#3",   "E3", "B2", "E3", "D3",
        "C3", "G3", "A2", "E3",    "B2", "F#3", "B2", "A2",
        "G3", "E3", "B2", "F#3",   "E3", "B2", "E3", "REST",
        # Bars 9-12
        "G3", "D3", "G3", "D3",    "C3", "G3", "C3", "G3",
        "G3", "D3", "G3", "D3",    "D3", "A2", "D3", "A2",
        "E3", "B2", "E3", "B2",    "A2", "E3", "A2", "E3",
        "C3", "G3", "A2", "E3",    "B2", "F#3", "B2", "F#3",
        # Bars 13-16
        "C3", "G3", "D3", "A2",    "E3", "B2", "E3", "D3",
        "A2", "E3", "A2", "E3",    "E3", "B2", "E3", "B2",
        "E3", "B2", "E3", "F#3",   "G3", "D3", "G3", "F#3",
        "E3", "B2", "B2", "F#3",   "E3", "B2", "E3", "REST",
    ]

    music = bytearray(0x300)  # 768 bytes
    for i in range(128):
        l0, d0 = encode_psg_note(0, melody_128[i])
        l1, d1 = encode_psg_note(1, harmony_128[i])
        l2, d2 = encode_psg_note(2, bass_128[i])

        snare_bit = 0x80 if (i % 2 == 1 or (i % 16 in (14, 15))) else 0x00
        kick_bit = 0x40 if (i % 2 == 0 or (i % 32 in (29, 30))) else 0x00

        music[0x000 + i] = l0
        music[0x080 + i] = d0
        music[0x100 + i] = l1
        music[0x180 + i] = d1
        music[0x200 + i] = l2
        music[0x280 + i] = (d2 & 0x3F) | kick_bit | snare_bit

    return bytes(music)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(SRC_DIR, exist_ok=True)

    pal_bin = build_palettes_bin()
    open(os.path.join(OUT_DIR, "palettes.bin"), "wb").write(pal_bin)

    tiles_bin = build_tiles_bin()
    open(os.path.join(OUT_DIR, "tiles.bin"), "wb").write(tiles_bin)

    lvl_bin = build_levels_bin()
    open(os.path.join(OUT_DIR, "levels.bin"), "wb").write(lvl_bin)

    mus_bin = build_music_bin()
    open(os.path.join(OUT_DIR, "music.bin"), "wb").write(mus_bin)

    print(f"Palettes : {len(pal_bin):,} bytes (32 CRAM entries)")
    print(f"Tiles    : {len(tiles_bin):,} bytes ({len(tiles_bin)//32} 4bpp SMS tiles)")
    print(f"Levels   : {len(lvl_bin):,} bytes (21 stages x 128B)")
    print(f"Music    : {len(mus_bin):,} bytes (128-step SN76489 Balkan Theme)")
    print("All APK assets successfully converted to SMS binary formats in sms/build/!")


if __name__ == "__main__":
    main()
