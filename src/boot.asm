; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/boot.asm
; Z80 Reset Vector ($0000), VBlank ISR ($0038), Pause NMI ($0066),
; Sega Mapper Initialization, SN76489 PSG Silence, VDP Mode 4 & VRAM/CRAM Init
; ============================================================================

    .org $0000
Reset:
    DI                      ; Disable interrupts immediately on cold/warm boot
    IM 1                    ; Z80 Interrupt Mode 1 (VDP IRQ -> $0038)
    LD SP, $DFF0            ; Stack at top of 8KB System RAM (below $FFFC mapper)
    JP Boot_InitHardware

; --- Z80 Maskable Interrupt Vector ($0038: VDP VBlank 60 Hz) ---
    .org $0038
VBlankVector:
    JP VBlankHandler

; --- Z80 Non-Maskable Interrupt Vector ($0066: Console PAUSE Button) ---
    .org $0066
PauseNmiVector:
    PUSH AF
    LD A, (pause_flag)
    XOR $01
    LD (pause_flag), A
    LD A, $01
    LD (pause_trig), A
    POP AF
    RETN


; ----------------------------------------------------------------------------
; Boot_InitHardware: Initializes Mapper, PSG, System RAM, VDP, CRAM & VRAM
; ----------------------------------------------------------------------------
Boot_InitHardware:
    ; 1. Initialize Sega Standard Mapper ($FFFC..$FFFF) for EverDrive / EPROM / BIOS
    XOR A
    LD (MAPPER_CTRL), A     ; $FFFC = $00 (ROM banking, no cart RAM)
    LD (MAPPER_SLOT0), A    ; $FFFD = $00 (Bank 0 at $0000..$3FFF)
    INC A
    LD (MAPPER_SLOT1), A    ; $FFFE = $01 (Bank 1 at $4000..$7FFF)
    INC A
    LD (MAPPER_SLOT2), A    ; $FFFF = $02 (Bank 2 at $8000..$BFFF)

    ; 2. Immediately silence all 4 SN76489 PSG channels ($9F, $BF, $DF, $FF)
    LD A, $9F
    OUT (PSG_PORT), A
    LD A, $BF
    OUT (PSG_PORT), A
    LD A, $DF
    OUT (PSG_PORT), A
    LD A, $FF
    OUT (PSG_PORT), A

    ; 3. Clear 8 KB System RAM ($C000..$DFEF)
    LD HL, $C000
    LD DE, $C001
    LD BC, $1FEF
    LD (HL), $00
    LDIR

    ; 4. Read VDP Status Port ($BF) to clear pending interrupt & latch
    IN A, (VDP_CTRL)

    ; 5. Initialize Sega VDP Mode 4 Registers (R0..R10)
    LD HL, VdpInitTable
    LD B, 22                ; 11 registers * 2 bytes
    LD C, VDP_CTRL
    OTIR

    ; 6. Clear all 16 KB of VRAM ($0000..$3FFF)
    XOR A
    OUT (VDP_CTRL), A
    LD A, VDP_CMD_VRAM
    OUT (VDP_CTRL), A
    LD BC, $4000
@clear_vram:
    XOR A
    OUT (VDP_DATA), A
    DEC BC
    LD A, B
    OR C
    JR NZ, @clear_vram

    ; 7. Upload 32-Byte Palette (16 BG + 16 Sprite colors) to CRAM ($C000)
    XOR A
    OUT (VDP_CTRL), A
    LD A, VDP_CMD_CRAM
    OUT (VDP_CTRL), A
    LD HL, PalettesBin
    LD B, 32
    LD C, VDP_DATA
    OTIR

    ; 8. Upload 376 4bpp Tiles (12,032 bytes = $2F00 bytes) to VRAM $0000
    XOR A
    OUT (VDP_CTRL), A
    LD A, VDP_CMD_VRAM
    OUT (VDP_CTRL), A
    LD HL, TilesBin
    LD DE, 12032
@upload_tiles:
    LD A, (HL)
    OUT (VDP_DATA), A
    INC HL
    DEC DE
    LD A, D
    OR E
    JR NZ, @upload_tiles

    ; 9. Terminate Hardware Sprite Attribute Table at VRAM $3F00 with $D0
    XOR A
    OUT (VDP_CTRL), A
    LD A, $7F               ; $40 | ($3F00 >> 8) = $7F
    OUT (VDP_CTRL), A
    LD A, $D0
    OUT (VDP_DATA), A

    ; 10. Initialize PSG Music Sequencer State
    CALL PSG_Init

    JP Main_Start


; --- Sega 315-5124 VDP Mode 4 Register Initialization Table ---
; Note: R2=$FF, R3=$FF, R4=$FF, R5=$FF, R6=$FB are mandatory for SMS1 hardware!
VdpInitTable:
    .db $46, $80            ; R0: Mode 4, Lock Top 2 Rows (0..1) Horizontal Scroll ($40)
    .db $A0, $81            ; R1: Display OFF during setup, VBlank IRQ enabled, 8x8 sprites
    .db $FF, $82            ; R2: Nametable at VRAM $3800 ($FF)
    .db $FF, $83            ; R3: Color table ($FF required for SMS1 VDP Mode 4)
    .db $FF, $84            ; R4: Pattern base ($FF required for SMS1 VDP Mode 4)
    .db $FF, $85            ; R5: Sprite Attribute Table at VRAM $3F00 ($FF)
    .db $FB, $86            ; R6: Sprite tiles at VRAM $0000 ($FB required for SMS1)
    .db $00, $87            ; R7: Backdrop color = Sprite Palette Color 0 (Sky Blue)
    .db $00, $88            ; R8: Horizontal scroll = 0
    .db $00, $89            ; R9: Vertical scroll = 0
    .db $FF, $8A            ; R10: Line interrupt disabled ($FF)
