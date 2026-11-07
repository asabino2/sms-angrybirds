; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/render.asm
; VDP Mode 4 Tilemap Engine, 64x24 World Map, Stationary Top-2-Row HUD,
; Destructible Castle Renderer & 64-Sprite SAT Builder
; ============================================================================

; ----------------------------------------------------------------------------
; Render_ClearSAT: Hides all 64 hardware sprites in SAT_Y ($C100..$C13F)
; ----------------------------------------------------------------------------
Render_ClearSAT:
    XOR A
    LD (sat_cnt), A
    LD HL, SAT_Y
    LD B, 64
    LD A, $D0               ; $D0 terminates / hides sprites on SMS VDP
@loop:
    LD (HL), A
    INC HL
    DJNZ @loop
    RET


; ----------------------------------------------------------------------------
; Render_AppendSprite8x8: Adds an 8x8 sprite to SAT_Y / SAT_XT
;   Input: B = Screen X (0..255), C = Screen Y (0..191), D = Tile ID
;   Clobbers: AF, HL, E
; ----------------------------------------------------------------------------
Render_AppendSprite8x8:
    LD A, (sat_cnt)
    CP 64
    RET NC                  ; SAT full (64 sprites max)
    LD E, A
    INC A
    LD (sat_cnt), A

    ; Avoid Y = $D0 (208), which is VDP sprite terminator
    LD A, C
    CP $D0
    JR NZ, @y_ok
    DEC A
@y_ok:
    LD HL, SAT_Y
    LD C, E
    PUSH BC
    LD B, 0
    ADD HL, BC
    LD (HL), A              ; SAT_Y[idx] = Screen Y
    POP BC

    ; SAT_XT[idx * 2] = Screen X, SAT_XT[idx * 2 + 1] = Tile ID
    LD A, E
    ADD A, A                ; * 2
    LD E, A
    LD A, D                 ; Save Tile ID in A
    LD D, 0
    LD HL, SAT_XT
    ADD HL, DE
    LD (HL), B              ; Screen X
    INC HL
    LD (HL), A              ; Tile ID
    RET


; ----------------------------------------------------------------------------
; Render_AppendSprite16x16: Adds a 16x16 metasprite (4 8x8 tiles: D, D+1, D+2, D+3)
;   Input: B = Screen X (0..239), C = Screen Y (0..175), D = Base Tile ID
; ----------------------------------------------------------------------------
Render_AppendSprite16x16:
    ; Top-Left (X, Y, D)
    PUSH BC
    PUSH DE
    CALL Render_AppendSprite8x8
    POP DE
    POP BC

    ; Top-Right (X+8, Y, D+1)
    PUSH BC
    PUSH DE
    LD A, B
    ADD A, 8
    LD B, A
    INC D
    CALL Render_AppendSprite8x8
    POP DE
    POP BC

    ; Bottom-Left (X, Y+8, D+2)
    PUSH BC
    PUSH DE
    LD A, C
    ADD A, 8
    LD C, A
    INC D
    INC D
    CALL Render_AppendSprite8x8
    POP DE
    POP BC

    ; Bottom-Right (X+8, Y+8, D+3)
    LD A, B
    ADD A, 8
    LD B, A
    LD A, C
    ADD A, 8
    LD C, A
    LD A, D
    ADD A, 3
    LD D, A
    JP Render_AppendSprite8x8


; ----------------------------------------------------------------------------
; Render_GetColPtr: Returns HL = WORLD_MAP + (A * 24) for column A (0..63)
;   Preserves: BC
; ----------------------------------------------------------------------------
Render_GetColPtr:
    LD L, A
    LD H, 0
    ADD HL, HL              ; * 2
    ADD HL, HL              ; * 4
    ADD HL, HL              ; * 8
    LD D, H
    LD E, L                 ; DE = A * 8
    ADD HL, HL              ; HL = A * 16
    ADD HL, DE              ; HL = A * 24
    LD DE, WORLD_MAP
    ADD HL, DE
    RET


; ----------------------------------------------------------------------------
; Render_ClearColScenery: Fills column C (0..63) of WORLD_MAP with Sky,
; Distant Hills (rows 17..20), Grass (row 21) & Soil (rows 22..23).
; ----------------------------------------------------------------------------
Render_ClearColScenery:
    LD A, C
    CALL Render_GetColPtr   ; HL = column pointer (24 bytes)

    ; Rows 0..16: Sky ($00)
    LD B, 17
    XOR A
@sky_loop:
    LD (HL), A
    INC HL
    DJNZ @sky_loop

    ; Row 17: Distant hill peak/slope ($06, $07, or $08)
    LD A, C
    AND $03
    JR Z, @hill_up
    CP $01
    JR Z, @hill_dn
    LD A, $08
    JR @set_r17
@hill_up:
    LD A, $06
    JR @set_r17
@hill_dn:
    LD A, $07
@set_r17:
    LD (HL), A
    INC HL

    ; Rows 18..20: Dark foliage / forest ($09)
    LD A, $09
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL

    ; Row 21 (GROUND_TY): Lush Grass Top ($0A / $0B)
    LD A, C
    AND $01
    ADD A, $0A
    LD (HL), A
    INC HL

    ; Rows 22..23: Underground Soil ($0C / $0D)
    LD A, C
    AND $01
    ADD A, $0C
    LD (HL), A
    INC HL
    XOR $01
    LD (HL), A
    RET


; ----------------------------------------------------------------------------
; Render_PutCloudAtCol: Places a 2x2 fluffy cloud ($02..$05) at column A, row B
; ----------------------------------------------------------------------------
Render_PutCloudAtCol:
    PUSH BC
    PUSH AF
    CALL Render_GetColPtr
    LD E, B
    LD D, 0
    ADD HL, DE
    LD (HL), $02
    INC HL
    LD (HL), $04
    POP AF
    POP BC
    INC A
    CALL Render_GetColPtr
    LD E, B
    LD D, 0
    ADD HL, DE
    LD (HL), $03
    INC HL
    LD (HL), $05
    RET


; ----------------------------------------------------------------------------
; Render_MarkAllColsDirty: Marks all 32 VDP nametable columns for refresh
; ----------------------------------------------------------------------------
Render_MarkAllColsDirty:
    LD HL, COL_DIRTY
    LD B, 32
    LD A, $01
@loop:
    LD (HL), A
    INC HL
    DJNZ @loop
    RET


; ----------------------------------------------------------------------------
; Render_InitLeftWorld: Clears columns 0..31 of WORLD_MAP with Clouds, Hills,
; Grass, and Soil.
; ----------------------------------------------------------------------------
Render_InitLeftWorld:
    LD C, 0
@col_loop:
    CALL Render_ClearColScenery
    INC C
    LD A, C
    CP 32
    JR C, @col_loop

    ; Add 3 fluffy clouds in Left World (cols 4, 15, 25)
    LD A, 4
    LD B, 3
    CALL Render_PutCloudAtCol
    LD A, 15
    LD B, 2
    CALL Render_PutCloudAtCol
    LD A, 25
    LD B, 4
    CALL Render_PutCloudAtCol
    RET


; ----------------------------------------------------------------------------
; Render_WriteWorldStr: Writes null-terminated string (DE) into WORLD_MAP
;   starting at World Column C (0..63), Row B (2..23)
; ----------------------------------------------------------------------------
Render_WriteWorldStr:
    LD A, (DE)
    OR A
    RET Z
    PUSH DE
    PUSH BC
    PUSH AF
    LD A, C
    AND 63
    CALL Render_GetColPtr
    LD E, B
    LD D, 0
    ADD HL, DE
    POP AF
    LD (HL), A
    POP BC
    POP DE
    INC DE
    INC C
    JR Render_WriteWorldStr


; ----------------------------------------------------------------------------
; Render_ClearHUD: Clears HUD_BUF ($C200..$C27F, 2 rows x 32 cols x 2B)
; ----------------------------------------------------------------------------
Render_ClearHUD:
    LD HL, HUD_BUF
    LD B, 64                ; 64 words = 128 bytes
@loop:
    LD (HL), $20            ; Space ASCII $20
    INC HL
    LD (HL), $00            ; High byte = $00 (BG Pal 0)
    INC HL
    DJNZ @loop
    LD A, $01
    LD (hud_dirty), A
    RET


; ----------------------------------------------------------------------------
; Render_PrintHUDStr: Writes null-terminated ASCII string at (DE) to HUD_BUF (HL)
; ----------------------------------------------------------------------------
Render_PrintHUDStr:
    LD A, (DE)
    OR A
    RET Z
    LD (HL), A
    INC HL
    LD (HL), $00
    INC HL
    INC DE
    JR Render_PrintHUDStr


; ----------------------------------------------------------------------------
; Render_PrintHUDDec2: Prints 8-bit value A (0..99) as 2 digits at HUD_BUF (HL)
; ----------------------------------------------------------------------------
Render_PrintHUDDec2:
    LD C, 0
@div10:
    CP 10
    JR C, @write
    SUB 10
    INC C
    JR @div10
@write:
    LD B, A
    LD A, C
    ADD A, $30
    LD (HL), A
    INC HL
    LD (HL), $00
    INC HL
    LD A, B
    ADD A, $30
    LD (HL), A
    INC HL
    LD (HL), $00
    INC HL
    RET


; ----------------------------------------------------------------------------
; Render_PrintHUDScore6: Prints 16-bit score_val as 5 digits + '0' at HUD_BUF (HL)
; ----------------------------------------------------------------------------
Render_PrintHUDScore6:
    PUSH HL
    LD HL, (score_val)
    LD (tmp0), HL
    POP HL

    ; 10000s digit
    LD BC, 10000
    CALL @sub_digit
    ; 1000s digit
    LD BC, 1000
    CALL @sub_digit
    ; 100s digit
    LD BC, 100
    CALL @sub_digit

    ; 10s & 1s digits
    LD A, (tmp0)
    CALL Render_PrintHUDDec2

    ; Trailing '0'
    LD (HL), $30
    INC HL
    LD (HL), $00
    INC HL
    RET

@sub_digit:
    PUSH HL
    LD HL, (tmp0)
    LD D, 0
@sub_loop:
    OR A
    SBC HL, BC
    JR C, @sub_done
    INC D
    JR @sub_loop
@sub_done:
    ADD HL, BC
    LD (tmp0), HL
    POP HL
    LD A, D
    ADD A, $30
    LD (HL), A
    INC HL
    LD (HL), $00
    INC HL
    RET


; ----------------------------------------------------------------------------
; Render_InitTitleScreen: Sets up Title Screen with 24x5 ANGRY BIRDS Logo,
; Sky, Clouds, Hills, Grass, Soil & Title Screen Prompts
; ----------------------------------------------------------------------------
Render_InitTitleScreen:
    ; Blank display during full VRAM nametable setup
    LD A, $A0
    OUT (VDP_CTRL), A
    LD A, $81
    OUT (VDP_CTRL), A

    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    XOR A
    LD (prev_cam_tile), A

    CALL Render_InitLeftWorld

    ; Write Title Screen text prompts onto WORLD_MAP rows 10, 12, 14
    LD C, 4
    LD B, 10
    LD DE, Str_Ep1Title
    CALL Render_WriteWorldStr

    LD C, 4
    LD B, 12
    LD DE, Str_PressStart
    CALL Render_WriteWorldStr

    LD C, 2
    LD B, 14
    LD DE, Str_ControlsHint
    CALL Render_WriteWorldStr

    CALL Render_BuildHUD
    CALL Render_MarkAllColsDirty
    CALL Render_FlushAllToVDP

    ; Draw 24x5 ANGRY BIRDS Title Logo (Tiles $100..$177) at Col 4..27, Row 3..7
    CALL Render_WriteLogoToVDP

    ; Enable VDP Display + VBlank Interrupts ($E0 -> Reg 1)
    LD A, $E0
    OUT (VDP_CTRL), A
    LD A, $81
    OUT (VDP_CTRL), A
    RET


; ----------------------------------------------------------------------------
; Render_WriteLogoToVDP: Writes 24x5 ANGRY BIRDS Logo ($0100..$0177) to VRAM
;   at Nametable Rows 3..7, Columns 4..27
; ----------------------------------------------------------------------------
Render_WriteLogoToVDP:
    LD DE, $0100            ; Starting 9-bit Tile ID = $0100
    LD C, 3                 ; Start at Row 3
@row_loop:
    ; Compute VRAM address = $3800 + (Row * 64) + (4 * 2)
    LD L, C
    LD H, 0
    ADD HL, HL              ; * 2
    ADD HL, HL              ; * 4
    ADD HL, HL              ; * 8
    ADD HL, HL              ; * 16
    ADD HL, HL              ; * 32
    ADD HL, HL              ; * 64
    LD A, L
    ADD A, 8                ; + Col 4 * 2
    OUT (VDP_CTRL), A
    LD A, H
    OR $78                  ; $40 (VRAM Write) | $38 ($3800 base) = $78
    OUT (VDP_CTRL), A

    LD B, 24                ; 24 columns wide
@col_loop:
    LD A, E
    OUT (VDP_DATA), A       ; Low byte of tile index
    LD A, D
    OUT (VDP_DATA), A       ; High byte ($01 = bit 8 of tile index, BG Pal 0)
    INC DE
    DJNZ @col_loop

    INC C
    LD A, C
    CP 8                    ; Rows 3..7 (5 rows)
    JR C, @row_loop
    RET


; ----------------------------------------------------------------------------
; Render_InitPlayfield: Sets up Left World (Slingshot) & Right World (Castle),
; streams full initial nametable to VDP, and turns display ON.
; ----------------------------------------------------------------------------
Render_InitPlayfield:
    LD A, $A0
    OUT (VDP_CTRL), A
    LD A, $81
    OUT (VDP_CTRL), A

    CALL Render_InitLeftWorld

    ; Draw Wooden Slingshot Fork & Post at World Cols 8..9, Rows 17..20
    LD A, 8
    CALL Render_GetColPtr
    LD DE, 17
    ADD HL, DE
    LD (HL), $0E            ; Row 17: Left Fork
    INC HL
    LD (HL), $10            ; Row 18: Post
    INC HL
    LD (HL), $10            ; Row 19: Post
    INC HL
    LD (HL), $10            ; Row 20: Post

    LD A, 9
    CALL Render_GetColPtr
    LD DE, 17
    ADD HL, DE
    LD (HL), $0F            ; Row 17: Right Fork
    INC HL
    LD (HL), $11            ; Row 18: Post
    INC HL
    LD (HL), $11            ; Row 19: Post
    INC HL
    LD (HL), $11            ; Row 20: Post

    ; Build Right World (Cols 32..63) with Destructible Pig Fortress
    CALL Render_RebuildCastle

    ; Build HUD and flush all 32 visible columns to VDP Nametable
    CALL Render_BuildHUD
    LD A, (cam_x)
    SRL A
    SRL A
    SRL A
    LD (prev_cam_tile), A
    CALL Render_MarkAllColsDirty
    CALL Render_FlushAllToVDP

    ; Turn display ON ($E0 -> Reg 1)
    LD A, $E0
    OUT (VDP_CTRL), A
    LD A, $81
    OUT (VDP_CTRL), A
    RET


; ----------------------------------------------------------------------------
; Render_RebuildCastle: Clears Right World (Cols 32..63) and draws all active
;   static blocks (0..num_blks_lvl-1) into WORLD_MAP.
; ----------------------------------------------------------------------------
Render_RebuildCastle:
    ; 1. Reset Columns 32..63 to clean Sky, Hills, Grass & Soil
    LD C, 32
@clr_loop:
    CALL Render_ClearColScenery
    INC C
    LD A, C
    CP 64
    JR C, @clr_loop

    ; Add 3 fluffy clouds in Right World (cols 36, 46, 56)
    LD A, 36
    LD B, 3
    CALL Render_PutCloudAtCol
    LD A, 46
    LD B, 2
    CALL Render_PutCloudAtCol
    LD A, 56
    LD B, 4
    CALL Render_PutCloudAtCol

    ; 2. Draw all living, non-falling blocks (0..num_blks_lvl-1)
    LD A, (num_blks_lvl)
    OR A
    JP Z, Render_MarkAllColsDirty

    LD C, 0                 ; C = block index 0..num_blks_lvl-1
@blk_loop:
    LD A, (num_blks_lvl)
    CP C
    JP Z, Render_MarkAllColsDirty
    JP C, Render_MarkAllColsDirty

    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_blk         ; Destroyed block

    LD HL, blk_falling
    ADD HL, BC
    LD A, (HL)
    OR A
    JP NZ, @next_blk        ; Falling block (drawn smoothly via SAT sprites!)

    ; Determine static BG tile ($12..$1C) from blk_mat and damage state
    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 1
    JR Z, @mat_glass
    CP 2
    JR Z, @mat_wood
    CP 3
    JR Z, @mat_stone
    CP 4
    JR Z, @mat_estrade
    ; Material 5: TNT Crate ($1C)
    LD D, $1C
    JR @damage_done
@mat_estrade:
    LD D, $1B
    JR @damage_done
@mat_glass:
    LD D, $12
    JR @check_crack
@mat_wood:
    LD D, $15
    JR @check_crack
@mat_stone:
    LD D, $18

@check_crack:
    ; Compare blk_hp with blk_max_hp / 2 and blk_max_hp / 4
    LD HL, blk_hp
    ADD HL, BC
    LD E, (HL)              ; E = current HP
    LD HL, blk_max_hp
    ADD HL, BC
    LD A, (HL)              ; A = max HP
    SRL A
    CP E
    JR C, @damage_done
    INC D                   ; Cracked state 1
    SRL A
    CP E
    JR C, @damage_done
    INC D                   ; Cracked state 2

@damage_done:
    ; D = Tile ID. Load tx, ty, w, h for block C
    LD A, D
    LD (tmp0), A            ; tmp0 = Tile ID

    LD HL, blk_tx
    ADD HL, BC
    LD A, (HL)
    LD (tmp1), A            ; tmp1 = cur_tx

    LD HL, blk_ty
    ADD HL, BC
    LD A, (HL)
    LD (tmp2), A            ; tmp2 = start_ty

    LD HL, blk_w
    ADD HL, BC
    LD A, (HL)
    LD (tmp3), A            ; tmp3 = remaining width

    LD HL, blk_h
    ADD HL, BC
    LD A, (HL)
    LD (tmp4), A            ; tmp4 = height

    PUSH BC
@col_fill:
    LD A, (tmp1)
    AND 63
    CALL Render_GetColPtr
    LD A, (tmp2)
    LD E, A
    LD D, 0
    ADD HL, DE              ; HL = &WORLD_MAP[cur_tx][start_ty]

    LD A, (tmp4)
    LD B, A                 ; B = height rows
    LD A, (tmp0)            ; A = Tile ID
@row_fill:
    LD (HL), A
    INC HL
    DJNZ @row_fill

    LD A, (tmp1)
    INC A
    LD (tmp1), A
    LD A, (tmp3)
    DEC A
    LD (tmp3), A
    JR NZ, @col_fill
    POP BC

@next_blk:
    INC C
    JP @blk_loop


; ----------------------------------------------------------------------------
; Render_BuildHUD: Updates stationary Top-2-Row HUD_BUF ($C200..$C27F)
;   and writes Level Select / Victory / Failed overlays onto WORLD_MAP
; ----------------------------------------------------------------------------
Render_BuildHUD:
    CALL Render_ClearHUD

    LD A, (game_state)
    CP STATE_TITLE
    JR NZ, @chk_lvl_sel

    ; --- TITLE SCREEN TOP BAR ---
    LD HL, HUD_BUF + 4
    LD DE, Str_SmsEdition
    CALL Render_PrintHUDStr

    LD HL, HUD_BUF + 64 + 8
    LD DE, Str_AngryClassic
    CALL Render_PrintHUDStr
    RET

@chk_lvl_sel:
    CP STATE_LEVEL_SELECT
    JR NZ, @in_game_hud

    ; --- LEVEL SELECT SCREEN ---
    LD HL, HUD_BUF + 8
    LD DE, Str_Ep1Title
    CALL Render_PrintHUDStr

    LD HL, HUD_BUF + 64 + 4
    LD DE, Str_SelectUnlockAll
    CALL Render_PrintHUDStr

    ; Write Stage Selector onto Left World Map
    CALL Render_InitLeftWorld

    LD C, 6
    LD B, 6
    LD DE, Str_SelectStage
    CALL Render_WriteWorldStr

    LD C, 9
    LD B, 10
    LD DE, Str_StageArrowL
    CALL Render_WriteWorldStr

    ; Write 2-digit stage number (cur_level + 1) at Col 19, Row 10
    LD A, (cur_level)
    INC A
    LD C, 0
@ls_div10:
    CP 10
    JR C, @ls_digits
    SUB 10
    INC C
    JR @ls_div10
@ls_digits:
    PUSH AF
    LD A, C
    ADD A, $30
    LD (tmp0), A
    LD A, 19
    CALL Render_GetColPtr
    LD DE, 10
    ADD HL, DE
    LD A, (tmp0)
    LD (HL), A
    POP AF
    ADD A, $30
    LD (tmp0), A
    LD A, 20
    CALL Render_GetColPtr
    LD DE, 10
    ADD HL, DE
    LD A, (tmp0)
    LD (HL), A

    LD C, 21
    LD B, 10
    LD DE, Str_StageArrowR
    CALL Render_WriteWorldStr

    LD C, 3
    LD B, 13
    LD DE, Str_PressBPlay
    CALL Render_WriteWorldStr

    JP Render_MarkAllColsDirty

@in_game_hud:
    ; --- IN-GAME TOP BAR (Rows 0 & 1) ---
    ; Row 0: "STAGE 1-XX  PIGS:XX  SCR:XXXXXX"
    LD HL, HUD_BUF + 2
    LD DE, Str_StagePrefix
    CALL Render_PrintHUDStr
    LD A, (cur_level)
    INC A
    CALL Render_PrintHUDDec2

    LD HL, HUD_BUF + 24
    LD DE, Str_PigsPrefix
    CALL Render_PrintHUDStr
    LD A, (pigs_alive)
    CALL Render_PrintHUDDec2

    LD HL, HUD_BUF + 42
    LD DE, Str_ScorePrefix
    CALL Render_PrintHUDStr
    CALL Render_PrintHUDScore6

    ; Row 1: Active Bird Name & Ability Prompt
    LD HL, HUD_BUF + 64 + 2
    LD A, (active_bird_type)
    CP 1
    JR Z, @hud_blue
    CP 2
    JR Z, @hud_yellow
    CP 3
    JR Z, @hud_bomb
    LD DE, Str_BirdRed
    JR @print_bird_hud
@hud_blue:
    LD DE, Str_BirdBlue
    JR @print_bird_hud
@hud_yellow:
    LD DE, Str_BirdYellow
    JR @print_bird_hud
@hud_bomb:
    LD DE, Str_BirdBomb
@print_bird_hud:
    CALL Render_PrintHUDStr

    ; Check if Victory or Failed Banner should be drawn over Playfield
    LD A, (game_state)
    CP STATE_VICTORY
    JR Z, @draw_victory_banner
    CP STATE_FAILED
    JR Z, @draw_failed_banner
    RET

@draw_victory_banner:
    ; Snap camera to 8px tile boundary so banner columns align cleanly
    LD A, (cam_x)
    AND $F8
    LD (cam_x), A
    LD (cam_target_x), A
    SRL A
    SRL A
    SRL A
    LD (tmp5), A            ; tmp5 = base world column of screen left

    ADD A, 5
    LD C, A
    LD B, 7
    LD DE, Str_StageClear
    CALL Render_WriteWorldStr

    ; Draw earned Golden Stars (* * *) on Row 9
    LD A, (stars_earned)
    LD B, A
    LD A, (tmp5)
    ADD A, 13
    LD C, A
@star_loop:
    PUSH BC
    LD A, C
    AND 63
    CALL Render_GetColPtr
    LD DE, 9
    ADD HL, DE
    LD (HL), $2A            ; '*' Golden Star tile
    POP BC
    INC C
    INC C
    DJNZ @star_loop

    LD A, (tmp5)
    ADD A, 3
    LD C, A
    LD B, 11
    LD DE, Str_NextStagePrompt
    CALL Render_WriteWorldStr
    JP Render_MarkAllColsDirty

@draw_failed_banner:
    LD A, (cam_x)
    AND $F8
    LD (cam_x), A
    LD (cam_target_x), A
    SRL A
    SRL A
    SRL A
    LD (tmp5), A

    ADD A, 6
    LD C, A
    LD B, 8
    LD DE, Str_LevelFailed
    CALL Render_WriteWorldStr

    LD A, (tmp5)
    ADD A, 4
    LD C, A
    LD B, 10
    LD DE, Str_RetryPrompt
    CALL Render_WriteWorldStr
    JP Render_MarkAllColsDirty


; ----------------------------------------------------------------------------
; Render_UploadColumnVDP: Streams VDP column C (0..31) Rows 2..23 from WORLD_MAP
;   to VRAM Nametable ($3880 + C*2, stride 64 bytes per row)
; ----------------------------------------------------------------------------
Render_UploadColumnVDP:
    ; Map vdp_col C (0..31) to world_col A (0..63) using cam_tile = (cam_x >> 3)
    LD A, (cam_x)
    SRL A
    SRL A
    SRL A
    LD B, A                 ; B = cam_tile (0..28)
    LD A, C
    CP B
    JR NC, @world_col_ok
    ADD A, 32
@world_col_ok:
    CALL Render_GetColPtr   ; HL = &WORLD_MAP[world_col][0]
    INC HL
    INC HL                  ; Advance to Row 2 (&WORLD_MAP[world_col][2])

    ; Initial VRAM write address = $3880 + (C * 2)
    LD A, C
    ADD A, A
    ADD A, $80
    LD E, A
    LD A, $78               ; $40 (VRAM Write) | $38 ($3800)
    ADC A, 0
    LD D, A                 ; DE = VRAM command word for Row 2, Col C

    LD B, 22                ; 22 rows (Rows 2..23)
@row_loop:
    LD A, E
    OUT (VDP_CTRL), A
    LD A, D
    OUT (VDP_CTRL), A

    LD A, (HL)
    OUT (VDP_DATA), A       ; Tile Index (0..255)
    XOR A
    OUT (VDP_DATA), A       ; High attribute byte ($00 = BG Pal 0)
    INC HL

    ; Advance DE by 64 bytes (1 nametable row)
    LD A, E
    ADD A, 64
    LD E, A
    LD A, D
    ADC A, 0
    LD D, A
    DJNZ @row_loop
    RET


; ----------------------------------------------------------------------------
; Render_FlushAllToVDP: Immediately uploads HUD_BUF and all 32 columns to VDP
;   (Called while display is blanked during screen transitions)
; ----------------------------------------------------------------------------
Render_FlushAllToVDP:
    ; 1. Upload HUD_BUF (128 bytes) to VRAM $3800
    XOR A
    LD (hud_dirty), A
    OUT (VDP_CTRL), A
    LD A, $78               ; $40 | $38
    OUT (VDP_CTRL), A
    LD HL, HUD_BUF
    LD B, 128
    LD C, VDP_DATA
    OTIR

    ; 2. Upload all 32 columns (Rows 2..23)
    LD C, 0
@col_loop:
    LD B, 0
    LD HL, COL_DIRTY
    ADD HL, BC
    LD (HL), 0
    PUSH BC
    CALL Render_UploadColumnVDP
    POP BC
    INC C
    LD A, C
    CP 32
    JR C, @col_loop
    RET


; ----------------------------------------------------------------------------
; Render_BuildSAT: Populates SAT_Y ($C100) and SAT_XT ($C180) for current frame
; ----------------------------------------------------------------------------
Render_BuildSAT:
    CALL Render_ClearSAT

    LD A, (game_state)
    CP STATE_TITLE
    JR NZ, @check_lvl_sel

    ; --- TITLE SCREEN PARADE SPRITES (4 Birds on Grass Y=152, King Pig at Y=134) ---
    ; Max 4 16x16 sprites (8 8x8 tiles) on scanlines 152..167 -> 100% within SMS 8-sprite/line limit!
    ; Red Bird at (40, 152)
    LD B, 40
    LD C, 152
    LD D, $60
    CALL Render_AppendSprite16x16

    ; Blue Bird at (84, 152)
    LD B, 84
    LD C, 152
    LD D, $68
    CALL Render_AppendSprite16x16

    ; Yellow Bird at (128, 152)
    LD B, 128
    LD C, 152
    LD D, $6C
    CALL Render_AppendSprite16x16

    ; Bomb Bird at (172, 152)
    LD B, 172
    LD C, 152
    LD D, $74
    CALL Render_AppendSprite16x16

    ; King Pig at (212, 134)
    LD B, 212
    LD C, 134
    LD D, $98
    JP Render_AppendSprite16x16

@check_lvl_sel:
    CP STATE_LEVEL_SELECT
    JR NZ, @gameplay_sat

    ; Show preview of level birds on Level Select screen (up to 4 birds)
    LD C, 0                 ; Bird queue index 0..3
@ls_loop:
    LD A, (birds_left)
    CP C
    RET Z
    RET C
    LD A, C
    CP 4
    RET NC

    PUSH BC
    ; Screen X = 64 + C * 36
    LD A, C
    ADD A, A                ; * 2
    ADD A, A                ; * 4
    LD E, A
    ADD A, A                ; * 8
    ADD A, A                ; * 16
    ADD A, A                ; * 32
    ADD A, E                ; * 36
    ADD A, 64
    LD B, A                 ; B = Screen X

    ; Lookup bird tile from bird_queue[C]
    LD D, 0
    LD E, C
    LD HL, bird_queue
    ADD HL, DE
    LD E, (HL)
    LD HL, BirdIdleTileTable
    ADD HL, DE
    LD D, (HL)              ; D = Base Tile ID
    LD C, 144               ; C = Screen Y
    CALL Render_AppendSprite16x16
    POP BC
    INC C
    JR @ls_loop

@gameplay_sat:
    ; --- 1. ACTIVE BIRD ---
    LD HL, (bird_x)
    LD DE, (cam_x)
    OR A
    SBC HL, DE              ; HL = Screen X = bird_x - cam_x
    LD A, H
    OR A
    JR NZ, @skip_active_bird
    LD A, L
    CP 240
    JR NC, @skip_active_bird
    LD B, A                 ; B = Screen X
    LD A, (bird_y)
    LD C, A                 ; C = Screen Y

    LD A, (active_bird_type)
    LD E, A
    LD D, 0
    LD A, (bird_active)
    OR A
    JR NZ, @act_bird_fly
    LD HL, BirdIdleTileTable
    JR @act_bird_draw
@act_bird_fly:
    LD HL, BirdFlyTileTable
@act_bird_draw:
    ADD HL, DE
    LD D, (HL)
    CALL Render_AppendSprite16x16
@skip_active_bird:

    ; --- 2. QUEUED BIRDS WAITING BEHIND SLINGSHOT (Up to 3 visible queued birds) ---
    LD C, 1                 ; Queue index 1..3
@queue_loop:
    LD A, (birds_left)
    CP C
    JR Z, @done_queue
    JR C, @done_queue
    LD A, C
    CP 4
    JR NC, @done_queue

    ; WorldX = 60 - C * 16
    ADD A, A
    ADD A, A
    ADD A, A
    ADD A, A                ; * 16
    LD E, A
    LD A, 60
    SUB E
    LD L, A
    LD H, 0
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @next_queued
    LD A, L
    CP 240
    JR NC, @next_queued

    PUSH BC
    LD B, A                 ; B = Screen X
    LD D, 0
    LD E, C
    LD HL, bird_queue
    ADD HL, DE
    LD E, (HL)
    LD HL, BirdIdleTileTable
    ADD HL, DE
    LD D, (HL)
    LD C, 152               ; C = Ground Y (168 - 16 = 152)
    CALL Render_AppendSprite16x16
    POP BC
@next_queued:
    INC C
    JR @queue_loop
@done_queue:

    ; --- 3. LIVING GREEN PIGS (0..num_pigs_lvl-1) ---
    LD C, 0
@pig_loop:
    LD A, (num_pigs_lvl)
    CP C
    JR Z, @done_pigs
    JR C, @done_pigs

    LD B, 0
    LD HL, pig_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_pig

    ; Compute ScreenX = pig_x - cam_x
    LD HL, pig_x_lo
    ADD HL, BC
    LD E, (HL)
    LD HL, pig_x_hi
    ADD HL, BC
    LD D, (HL)
    EX DE, HL               ; HL = pig_x
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @next_pig
    LD A, L
    CP 240
    JR NC, @next_pig

    PUSH BC
    LD E, C                 ; E = pig index
    LD D, 0
    LD B, A                 ; B = Screen X
    LD HL, pig_y
    ADD HL, DE
    LD C, (HL)              ; C = Screen Y

    LD HL, pig_type
    ADD HL, DE
    LD A, (HL)
    OR A
    JR NZ, @normal_pig_tile
    ; Periodic blink on SmallPig every 64 frames
    LD A, (frame_cnt)
    AND $38
    CP $38
    JR NZ, @small_pig_norm
    LD D, $84               ; Small Pig Blink/Smile
    JR @draw_pig_now
@small_pig_norm:
    XOR A
@normal_pig_tile:
    LD E, A
    LD D, 0
    LD HL, PigTileTable
    ADD HL, DE
    LD D, (HL)
@draw_pig_now:
    CALL Render_AppendSprite16x16
    POP BC

@next_pig:
    INC C
    JR @pig_loop
@done_pigs:

    ; --- 4. EXPLOSION / SMOKE POP EFFECT ---
    LD A, (exp_timer)
    OR A
    JR Z, @done_exp
    LD HL, (exp_x)
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @done_exp
    LD A, L
    CP 240
    JR NC, @done_exp
    LD B, A
    LD A, (exp_y)
    LD C, A
    LD A, (exp_type)
    OR A
    LD D, $7C               ; Fireball 16x16
    JR Z, @draw_exp
    LD D, $9C               ; Smoke Puff 16x16
@draw_exp:
    CALL Render_AppendSprite16x16
@done_exp:

    ; --- 5. SPLIT BLUE BIRDS (8x8 Sprites) ---
    LD A, (split0_active)
    OR A
    JR Z, @chk_split1
    LD HL, (split0_x)
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @chk_split1
    LD A, L
    CP 248
    JR NC, @chk_split1
    LD B, A
    LD A, (split0_y)
    LD C, A
    LD D, $A3
    CALL Render_AppendSprite8x8

@chk_split1:
    LD A, (split1_active)
    OR A
    JR Z, @chk_aim_dots
    LD HL, (split1_x)
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @chk_aim_dots
    LD A, L
    CP 248
    JR NC, @chk_aim_dots
    LD B, A
    LD A, (split1_y)
    LD C, A
    LD D, $A3
    CALL Render_AppendSprite8x8

@chk_aim_dots:
    ; --- 6. AIM TRAJECTORY DOTS & CROSSHAIR (6 8x8 Sprites in STATE_AIMING) ---
    LD A, (game_state)
    CP STATE_AIMING
    JP NZ, @render_falling_blks

    LD A, (aim_angle)
    LD E, A
    LD D, 0
    LD HL, AimDotDXTable
    ADD HL, DE
    LD A, (HL)
    LD HL, aim_power
    ADD A, (HL)
    SUB 8
    LD (tmp0), A            ; tmp0 = Step DX (pixels per dot)
    XOR A
    LD (tmp0+1), A

    LD HL, AimDotDYTable
    ADD HL, DE
    LD A, (HL)
    LD (tmp1), A            ; tmp1 = Step DY (signed 8-bit)

    ; Start at (bird_x + 4, bird_y + 4)
    LD HL, (bird_x)
    LD DE, 4
    ADD HL, DE
    LD (tmp2), HL           ; tmp2 = dot WorldX (16-bit)

    LD A, (bird_y)
    ADD A, 4
    LD (tmp3), A            ; tmp3 = dot WorldY (8-bit)

    LD C, 0                 ; Dot index 0..5
@dot_loop:
    PUSH BC
    ; tmp2 += tmp0
    LD HL, (tmp2)
    LD DE, (tmp0)
    ADD HL, DE
    LD (tmp2), HL

    ; tmp3 += tmp1; tmp1 += 3 (gravity)
    LD A, (tmp3)
    LD B, A
    LD A, (tmp1)
    ADD A, B
    LD (tmp3), A
    LD A, (tmp1)
    ADD A, 3
    LD (tmp1), A

    ; Compute ScreenX = tmp2 - cam_x
    LD HL, (tmp2)
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @next_dot
    LD A, L
    CP 248
    JR NC, @next_dot
    LD B, A                 ; B = Screen X

    LD A, (tmp3)
    CP GROUND_PY            ; Above grass ground (168)?
    JR NC, @next_dot

    POP DE                  ; E = dot index 0..5
    PUSH DE
    LD C, A                 ; C = Screen Y
    LD A, E
    CP 5
    LD D, $A0               ; Trajectory dot ($A0)
    JR NZ, @emit_dot
    LD D, $A1               ; Crosshair ($A1) on last dot
@emit_dot:
    CALL Render_AppendSprite8x8
@next_dot:
    POP BC
    INC C
    LD A, C
    CP 6
    JR C, @dot_loop

@render_falling_blks:
    ; --- 7. SMOOTH PIXEL-BY-PIXEL FALLING BLOCKS (8x8 Sprites $B2..$BC) ---
    LD C, 0                 ; Block index 0..num_blks_lvl-1
@fall_blk_loop:
    LD A, (num_blks_lvl)
    CP C
    RET Z
    RET C

    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_fall_blk

    LD HL, blk_falling
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_fall_blk

    ; Determine falling sprite tile ($B2..$BC)
    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 1
    JR Z, @fmat_glass
    CP 2
    JR Z, @fmat_wood
    CP 3
    JR Z, @fmat_stone
    CP 4
    JR Z, @fmat_estrade
    LD D, $BC               ; TNT ($BC)
    JR @fcrack_done
@fmat_estrade:
    LD D, $BB               ; Estrade ($BB)
    JR @fcrack_done
@fmat_glass:
    LD D, $B2
    JR @fcheck_crack
@fmat_wood:
    LD D, $B5
    JR @fcheck_crack
@fmat_stone:
    LD D, $B8
@fcheck_crack:
    LD HL, blk_hp
    ADD HL, BC
    LD E, (HL)
    LD HL, blk_max_hp
    ADD HL, BC
    LD A, (HL)
    SRL A
    CP E
    JR C, @fcrack_done
    INC D
    SRL A
    CP E
    JR C, @fcrack_done
    INC D
@fcrack_done:
    LD A, D
    LD (tmp0), A            ; tmp0 = Falling Block Sprite Tile ID

    ; Compute base WorldX = (blk_tx * 8) + blk_px_off
    LD HL, blk_tx
    ADD HL, BC
    LD L, (HL)
    LD H, 0
    ADD HL, HL
    ADD HL, HL
    ADD HL, HL              ; * 8
    PUSH HL
    LD HL, blk_px_off
    ADD HL, BC
    LD E, (HL)
    LD D, 0
    POP HL
    ADD HL, DE
    LD (tmp1), HL           ; tmp1 = Base WorldX (16-bit)

    LD HL, blk_py
    ADD HL, BC
    LD A, (HL)
    LD (tmp2), A            ; tmp2 = Current Row Pixel Y

    LD HL, blk_w
    ADD HL, BC
    LD A, (HL)
    LD (tmp3), A            ; tmp3 = Block width in tiles

    LD HL, blk_h
    ADD HL, BC
    LD A, (HL)
    LD (tmp4), A            ; tmp4 = Remaining height rows

    PUSH BC
@fall_row:
    LD HL, (tmp1)
    LD (ptr0), HL           ; ptr0 = Current Col WorldX
    LD A, (tmp3)
    LD (tmp5), A            ; tmp5 = Remaining cols

@fall_col:
    LD HL, (ptr0)
    LD DE, (cam_x)
    OR A
    SBC HL, DE
    LD A, H
    OR A
    JR NZ, @next_fall_col
    LD A, L
    CP 248
    JR NC, @next_fall_col
    LD B, A                 ; B = Screen X
    LD A, (tmp2)
    LD C, A                 ; C = Exact Pixel Y
    LD A, (tmp0)
    LD D, A                 ; D = Sprite Tile ID
    CALL Render_AppendSprite8x8

@next_fall_col:
    LD HL, (ptr0)
    LD DE, 8
    ADD HL, DE
    LD (ptr0), HL
    LD A, (tmp5)
    DEC A
    LD (tmp5), A
    JR NZ, @fall_col

    LD A, (tmp2)
    ADD A, 8
    LD (tmp2), A
    LD A, (tmp4)
    DEC A
    LD (tmp4), A
    JR NZ, @fall_row
    POP BC

@next_fall_blk:
    INC C
    JP @fall_blk_loop


; --- Sprite Tile Lookup Tables ---
BirdIdleTileTable:
    .db $60, $68, $6C, $74  ; Red, Blue, Yellow, Bomb

BirdFlyTileTable:
    .db $64, $68, $70, $78  ; Red Yell, Blue, Yellow Dash, Bomb Armed

PigTileTable:
    .db $80, $88, $8C, $90, $98 ; Small, Medium, Large, Helmet, King

AimDotDXTable:
    .db 18, 18, 17, 17, 16, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5
AimDotDYTable:
    .db $FE, $FC, $FA, $F9, $F7, $F6, $F4, $F3, $F1, $F0, $EE, $ED, $EC, $EB, $EA, $E9, $E8

; --- UI Text Strings ---
Str_SmsEdition:
    .db "SEGA MASTER SYSTEM EDITION", 0
Str_AngryClassic:
    .db "ANGRY BIRDS CLASSIC", 0
Str_Ep1Title:
    .db "EPISODE 1: POACHED EGGS", 0
Str_PressStart:
    .db "PRESS BTN 1 OR 2 TO PLAY", 0
Str_ControlsHint:
    .db "DPAD:AIM  1:FIRE/POW  2:PEEK", 0
Str_SelectStage:
    .db "SELECT STAGE (1-21)", 0
Str_StageArrowL:
    .db "< STAGE 1-", 0
Str_StageArrowR:
    .db " >", 0
Str_PressBPlay:
    .db "PRESS BTN 1 OR 2 TO LAUNCH", 0
Str_SelectUnlockAll:
    .db "ALL 21 STAGES UNLOCKED!", 0
Str_StagePrefix:
    .db "STAGE 1-", 0
Str_PigsPrefix:
    .db "PIGS:", 0
Str_ScorePrefix:
    .db "SCR:", 0
Str_BirdRed:
    .db "RED BIRD  [1/2: BATTLE CRY]", 0
Str_BirdBlue:
    .db "THE BLUES [1/2: 3X SPLIT!]", 0
Str_BirdYellow:
    .db "CHUCK     [1/2: SPEED DASH]", 0
Str_BirdBomb:
    .db "BOMB BIRD [1/2: DETONATE!]", 0
Str_StageClear:
    .db "*** STAGE CLEARED! ***", 0
Str_NextStagePrompt:
    .db "PRESS BTN 1/2: NEXT STAGE", 0
Str_LevelFailed:
    .db "--- LEVEL FAILED ---", 0
Str_RetryPrompt:
    .db "PRESS BTN 1/2: TRY AGAIN", 0
