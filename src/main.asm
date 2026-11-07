; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/main.asm
; Master Bank Layout, 60 Hz VBlank ISR, Controller Polling & State Machine
; ============================================================================

    .include "macros.inc"
    .include "boot.asm"
    .include "psg_driver.asm"
    .include "render.asm"
    .include "physics.asm"

; ----------------------------------------------------------------------------
; Main_Start: Entry point after hardware reset & VRAM asset upload
; ----------------------------------------------------------------------------
Main_Start:
    XOR A
    LD (cur_level), A
    LD A, 20
    LD (max_unlocked), A
    LD HL, 0
    LD (high_score), HL
    LD A, STATE_TITLE
    LD (game_state), A

    CALL Render_InitTitleScreen
    EI

; ============================================================================
; MAIN 60 FPS GAME LOOP
; ============================================================================
Main_Loop:
    ; Signal frame ready for VBlank ISR and wait for VBlank
    LD A, 1
    LD (vdp_ready), A
@wait_vblank:
    HALT
    LD A, (vdp_ready)
    OR A
    JR NZ, @wait_vblank

    ; Poll Controller 1 ($DC) & Console PAUSE Button
    CALL Main_ReadJoypad

    ; If in gameplay and paused via Console PAUSE button, freeze state updates
    LD A, (game_state)
    CP STATE_INTRO_PAN
    JR C, @not_paused
    LD A, (pause_flag)
    OR A
    JR NZ, @rebuild_sat
@not_paused:
    XOR A
    LD (pause_flag), A

    ; Decrement explosion/smoke effect timer if active
    LD A, (exp_timer)
    OR A
    JR Z, @dispatch_state
    DEC A
    LD (exp_timer), A

@dispatch_state:
    LD A, (game_state)
    CP STATE_TITLE
    JR Z, @do_title
    CP STATE_LEVEL_SELECT
    JR Z, @do_level_select
    CP STATE_INTRO_PAN
    JR Z, @do_intro_pan
    CP STATE_AIMING
    JR Z, @do_aiming
    CP STATE_FLYING
    JR Z, @do_flying
    CP STATE_SETTLING
    JR Z, @do_settling
    CP STATE_VICTORY
    JR Z, @do_victory
    CP STATE_FAILED
    JR Z, @do_failed
    JR @rebuild_sat

@do_title:
    CALL State_UpdateTitle
    JR @rebuild_sat

@do_level_select:
    CALL State_UpdateLevelSelect
    JR @rebuild_sat

@do_intro_pan:
    CALL State_UpdateIntroPan
    JR @rebuild_sat

@do_aiming:
    CALL Physics_UpdateAim
    JR @rebuild_sat

@do_flying:
    CALL Physics_UpdateFlight
    JR @rebuild_sat

@do_settling:
    CALL Physics_UpdateSettling
    JR @rebuild_sat

@do_victory:
    CALL State_UpdateVictory
    JR @rebuild_sat

@do_failed:
    CALL State_UpdateFailed

@rebuild_sat:
    CALL Physics_UpdateCamera
    CALL Render_BuildSAT
    JP Main_Loop


; ----------------------------------------------------------------------------
; State_UpdateTitle: Waits for Button 1 / Button 2 / Console PAUSE on Title
; ----------------------------------------------------------------------------
State_UpdateTitle:
    LD A, (joy_trig)
    AND BTN_BOTH
    RET Z

    LD A, SFX_BIRD_FLY
    CALL PSG_PlaySFX

    CALL Physics_LoadLevel
    LD A, STATE_LEVEL_SELECT
    LD (game_state), A
    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    XOR A
    LD (prev_cam_tile), A
    JP Render_BuildHUD


; ----------------------------------------------------------------------------
; State_UpdateLevelSelect: Stage 1-01..1-21 selector
; ----------------------------------------------------------------------------
State_UpdateLevelSelect:
    ; D-Pad Left or Down: Previous Stage
    LD A, (joy_trig)
    AND (BTN_LEFT | BTN_DOWN)
    JR Z, @check_right
    LD A, (cur_level)
    OR A
    JR Z, @check_right
    DEC A
    LD (cur_level), A
    CALL Physics_LoadLevel
    LD A, STATE_LEVEL_SELECT
    LD (game_state), A
    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    CALL Render_BuildHUD

@check_right:
    ; D-Pad Right or Up: Next Stage
    LD A, (joy_trig)
    AND (BTN_RIGHT | BTN_UP)
    JR Z, @check_launch
    LD A, (cur_level)
    LD HL, max_unlocked
    CP (HL)
    JR NC, @check_launch
    CP 20
    JR NC, @check_launch
    INC A
    LD (cur_level), A
    CALL Physics_LoadLevel
    LD A, STATE_LEVEL_SELECT
    LD (game_state), A
    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    CALL Render_BuildHUD

@check_launch:
    LD A, (joy_trig)
    AND BTN_BOTH
    RET Z

    LD A, SFX_BIRD_FLY
    CALL PSG_PlaySFX
    CALL Physics_LoadLevel
    JP Render_InitPlayfield


; ----------------------------------------------------------------------------
; State_UpdateIntroPan: Shows the Pig Fortress briefly, then pans to Slingshot
; ----------------------------------------------------------------------------
State_UpdateIntroPan:
    ; Allow skipping intro pan with Button 1 or Button 2
    LD A, (joy_trig)
    AND BTN_BOTH
    JR NZ, @skip_pan

    LD A, (state_timer)
    OR A
    JR Z, @pan_to_zero
    DEC A
    LD (state_timer), A
    RET

@pan_to_zero:
    LD HL, 0
    LD (cam_target_x), HL
    LD HL, (cam_x)
    LD A, H
    OR L
    RET NZ
    LD A, STATE_AIMING
    LD (game_state), A
    RET

@skip_pan:
    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    LD A, STATE_AIMING
    LD (game_state), A
    JP Render_MarkAllColsDirty


; ----------------------------------------------------------------------------
; State_UpdateVictory: Advances to the next stage after Stage Clear
; ----------------------------------------------------------------------------
State_UpdateVictory:
    LD A, (joy_trig)
    AND BTN_BOTH
    RET Z

    LD A, (cur_level)
    CP 20
    JR NC, @wrap_to_select
    INC A
    LD (cur_level), A
    CALL Physics_LoadLevel
    JP Render_InitPlayfield

@wrap_to_select:
    LD A, STATE_LEVEL_SELECT
    LD (game_state), A
    LD HL, 0
    LD (cam_x), HL
    LD (cam_target_x), HL
    JP Render_BuildHUD


; ----------------------------------------------------------------------------
; State_UpdateFailed: Retries current stage after Level Failed
; ----------------------------------------------------------------------------
State_UpdateFailed:
    LD A, (joy_trig)
    AND BTN_BOTH
    RET Z
    CALL Physics_LoadLevel
    JP Render_InitPlayfield


; ----------------------------------------------------------------------------
; Main_ReadJoypad: Reads Controller 1 ($DC) & computes newly pressed buttons
; ----------------------------------------------------------------------------
Main_ReadJoypad:
    LD A, (joy_cur)
    LD (joy_prev), A

    IN A, (IO_JOY1)         ; Active-low: 0 = pressed, 1 = released
    CPL                     ; Invert so 1 = pressed
    AND $3F                 ; Keep Up, Down, Left, Right, Btn1, Btn2
    LD B, A

    ; Also allow Console PAUSE button to act as Btn1 on menus!
    LD A, (pause_trig)
    OR A
    JR Z, @store_joy
    XOR A
    LD (pause_trig), A
    LD A, (game_state)
    CP STATE_INTRO_PAN
    JR NC, @store_joy
    LD A, B
    OR BTN_1
    LD B, A

@store_joy:
    LD A, B
    LD (joy_cur), A
    LD HL, joy_prev
    XOR (HL)
    AND B
    LD (joy_trig), A
    RET


; ============================================================================
; VBLANK INTERRUPT HANDLER ($0038 - 60 Hz NTSC / 50 Hz PAL)
; ============================================================================
VBlankHandler:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    ; 1. Read VDP Status Port ($BF) to acknowledge VBlank IRQ
    IN A, (VDP_CTRL)

    LD HL, frame_cnt
    INC (HL)

    LD A, (vdp_ready)
    OR A
    JR Z, @vblank_audio

    ; 2. Update VDP Horizontal Scroll Register R8 ($88) = (-cam_x) & $FF
    LD A, (cam_x)
    NEG
    OUT (VDP_CTRL), A
    LD A, $88
    OUT (VDP_CTRL), A

    ; 3. Upload Sprite Attribute Table: SAT_Y (64B -> $3F00) & SAT_XT (128B -> $3F80)
    XOR A
    OUT (VDP_CTRL), A
    LD A, $7F               ; $40 | $3F ($3F00)
    OUT (VDP_CTRL), A
    LD HL, SAT_Y
    LD B, 64
    LD C, VDP_DATA
    OTIR

    LD A, $80
    OUT (VDP_CTRL), A
    LD A, $7F               ; $40 | $3F ($3F80)
    OUT (VDP_CTRL), A
    LD HL, SAT_XT
    LD B, 128
    LD C, VDP_DATA
    OTIR

    ; 4. If hud_dirty != 0, stream HUD_BUF (128B) to VRAM $3800
    LD A, (hud_dirty)
    OR A
    JR Z, @check_dirty_cols
    XOR A
    LD (hud_dirty), A
    OUT (VDP_CTRL), A
    LD A, $78               ; $40 | $38 ($3800)
    OUT (VDP_CTRL), A
    LD HL, HUD_BUF
    LD B, 128
    LD C, VDP_DATA
    OTIR

@check_dirty_cols:
    ; 5. Stream up to 8 dirty columns per VBlank from WORLD_MAP to VRAM Nametable
    LD E, 8                 ; Max 8 columns per VBlank to stay well inside VBlank budget
    LD C, 0                 ; Column index 0..31
@col_scan:
    LD B, 0
    LD HL, COL_DIRTY
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_col_scan
    LD (HL), 0              ; Clear dirty flag
    PUSH BC
    PUSH DE
    CALL Render_UploadColumnVDP
    POP DE
    POP BC
    DEC E
    JR Z, @done_vdp_dma
@next_col_scan:
    INC C
    LD A, C
    CP 32
    JR C, @col_scan

@done_vdp_dma:
    XOR A
    LD (vdp_ready), A

@vblank_audio:
    ; 6. Tick 4-Channel SN76489 PSG Music & SFX Sequencer
    CALL PSG_Update

    POP HL
    POP DE
    POP BC
    POP AF
    EI
    RETI


; ============================================================================
; BINARY ASSETS IN ROM ($0000..$7FEF)
; ============================================================================
PalettesBin:
    .incbin "../build/palettes.bin"

LevelsBin:
    .incbin "../build/levels.bin"

MusicBin:
    .incbin "../build/music.bin"

TilesBin:
    .incbin "../build/tiles.bin"

    ; --- Official Sega Master System "TMR SEGA" Header ($7FF0..$7FFF) ---
    .include "header.asm"
