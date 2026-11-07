; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/psg_driver.asm
; Texas Instruments SN76489 PSG 4-Channel Music Sequencer (128-Step Balkan Theme)
; & 7 Multi-Stage Sound Effects Engine (60 Hz VBlank Tick)
; ============================================================================

; ----------------------------------------------------------------------------
; PSG_Init: Resets music sequencer & envelope state
; ----------------------------------------------------------------------------
PSG_Init:
    XOR A
    LD (psg_subtick), A
    LD (psg_step), A
    LD (sfx_active_id), A
    LD (sfx_timer), A
    LD (sfx_tick), A
    LD A, $0F
    LD (psg_env0), A
    LD (psg_env1), A
    LD (psg_env2), A
    LD (psg_env3), A
    RET


; ----------------------------------------------------------------------------
; PSG_Silence: Silences all 4 SN76489 channels immediately
; ----------------------------------------------------------------------------
PSG_Silence:
    LD A, $9F
    OUT (PSG_PORT), A
    LD A, $BF
    OUT (PSG_PORT), A
    LD A, $DF
    OUT (PSG_PORT), A
    LD A, $FF
    OUT (PSG_PORT), A
    RET


; ----------------------------------------------------------------------------
; PSG_PlaySFX: Triggers sound effect in A (SFX_BIRD_FLY..SFX_DEFEAT = 6..12)
; ----------------------------------------------------------------------------
PSG_PlaySFX:
    LD (sfx_active_id), A
    XOR A
    LD (sfx_tick), A
    LD A, (sfx_active_id)
    CP SFX_VICTORY
    JR Z, @long_sfx
    CP SFX_DEFEAT
    JR Z, @long_sfx
    CP SFX_EXPLODE
    JR Z, @med_sfx
    LD A, 18                ; 18 frames (~300ms) for standard SFX
    LD (sfx_timer), A
    RET
@med_sfx:
    LD A, 28                ; 28 frames (~460ms) for Explosion
    LD (sfx_timer), A
    RET
@long_sfx:
    LD A, 48                ; 48 frames (~800ms) for Victory / Defeat fanfare
    LD (sfx_timer), A
    RET


; ----------------------------------------------------------------------------
; PSG_Update: Called once per 60 Hz VBlank to step music & sound effects
; ----------------------------------------------------------------------------
PSG_Update:
    ; If game is paused via Console PAUSE button, keep PSG silent
    LD A, (pause_flag)
    OR A
    JP NZ, PSG_Silence

    ; --- 1. Advance Music Sub-Tick (11 frames per 8th-note step = ~130 BPM) ---
    LD A, (psg_subtick)
    OR A
    JR Z, @trigger_step

    ; On intermediate frames, apply gentle instrument volume decay
    INC A
    CP 11
    JR C, @store_subtick
    XOR A
@store_subtick:
    LD (psg_subtick), A

    ; Decay Mandolin/Harmony (Ch1) & Bass (Ch2) & Drums (Ch3) on intermediate ticks
    AND $03
    JP NZ, @apply_envelopes

    ; Ch0 Accordion slight sustain decay down to 4
    LD A, (psg_env0)
    CP 4
    JR NC, @chk_env1
    INC A
    LD (psg_env0), A
@chk_env1:
    ; Ch1 Mandolin/Strings pluck decay down to 9
    LD A, (psg_env1)
    CP 9
    JR NC, @chk_env2
    INC A
    LD (psg_env1), A
@chk_env2:
    ; Ch2 Upright Bass decay down to 10
    LD A, (psg_env2)
    CP 10
    JR NC, @chk_env3
    INC A
    INC A
    LD (psg_env2), A
@chk_env3:
    ; Ch3 Percussion fast decay to 15 (silent)
    LD A, (psg_env3)
    CP 14
    JR NC, @mute_env3
    ADD A, 3
    LD (psg_env3), A
    JP @apply_envelopes
@mute_env3:
    LD A, 15
    LD (psg_env3), A
    JP @apply_envelopes

@trigger_step:
    ; Advance subtick to 1 for next frame
    LD A, 1
    LD (psg_subtick), A

    ; Load current step index E = psg_step (0..127), D = 0
    LD A, (psg_step)
    LD E, A
    LD D, 0

    ; --- CHANNEL 0: BALKAN ACCORDION LEAD (MusicBin + $000 / + $080) ---
    LD HL, MusicBin
    ADD HL, DE
    LD A, (HL)
    OR A
    JR Z, @ch0_rest
    CP $FF
    JR Z, @ch0_tie
    ; Output Ch0 tone latch & data
    OUT (PSG_PORT), A
    LD BC, $0080
    ADD HL, BC
    LD A, (HL)
    OUT (PSG_PORT), A
    LD A, 1                 ; Crisp accordion attack attenuation = 1
    LD (psg_env0), A
    JR @do_ch1
@ch0_rest:
    LD A, 15
    LD (psg_env0), A
@ch0_tie:

@do_ch1:
    ; --- CHANNEL 1: HARMONY & MANDOLIN ARPEGGIOS (MusicBin + $100 / + $180) ---
    LD HL, MusicBin + $0100
    ADD HL, DE
    LD A, (HL)
    OR A
    JR Z, @ch1_rest
    CP $FF
    JR Z, @ch1_tie
    OUT (PSG_PORT), A
    LD BC, $0080
    ADD HL, BC
    LD A, (HL)
    OUT (PSG_PORT), A
    LD A, 3                 ; Balanced harmony/mandolin attack = 3
    LD (psg_env1), A
    JR @do_ch2
@ch1_rest:
    LD A, 15
    LD (psg_env1), A
@ch1_tie:

@do_ch2:
    ; --- CHANNEL 2: TUBA / BASS + PERCUSSION FLAGS (MusicBin + $200 / + $280) ---
    ; Only write Ch2 & Ch3 music if no sound effect is overriding them
    LD A, (sfx_timer)
    OR A
    JR NZ, @advance_step_idx

    LD HL, MusicBin + $0200
    ADD HL, DE
    LD A, (HL)
    OR A
    JR Z, @ch2_rest
    OUT (PSG_PORT), A
    LD BC, $0080
    ADD HL, BC
    LD A, (HL)
    AND $3F
    OUT (PSG_PORT), A
    LD A, 2                 ; Punchy tuba bass attack = 2
    LD (psg_env2), A
    JR @do_drums
@ch2_rest:
    LD A, 15
    LD (psg_env2), A

@do_drums:
    LD HL, MusicBin + $0280
    ADD HL, DE
    LD A, (HL)
    BIT 7, A                ; Snare / Hi-Hat ($80)?
    JR NZ, @drum_snare
    BIT 6, A                ; Kick Drum ($40)?
    JR NZ, @drum_kick
    JR @advance_step_idx
@drum_snare:
    LD A, $E5               ; White noise, medium clock (crisp snare)
    OUT (PSG_PORT), A
    LD A, 5
    LD (psg_env3), A
    JR @advance_step_idx
@drum_kick:
    LD A, $E2               ; Periodic low noise (punchy kick thud)
    OUT (PSG_PORT), A
    LD A, 4
    LD (psg_env3), A

@advance_step_idx:
    LD A, (psg_step)
    INC A
    AND $7F                 ; Wrap 0..127 (16 bars)
    LD (psg_step), A

@apply_envelopes:
    ; Output Ch0 & Ch1 volume attenuations ($90|env0, $B0|env1)
    LD A, (psg_env0)
    AND $0F
    OR $90
    OUT (PSG_PORT), A

    LD A, (psg_env1)
    AND $0F
    OR $B0
    OUT (PSG_PORT), A

    ; Check if a Sound Effect is active on Ch2 / Ch3
    LD A, (sfx_timer)
    OR A
    JR NZ, @update_sfx

    ; Otherwise output normal music Ch2 & Ch3 volume attenuations
    LD A, (psg_env2)
    AND $0F
    OR $D0
    OUT (PSG_PORT), A

    LD A, (psg_env3)
    AND $0F
    OR $F0
    OUT (PSG_PORT), A
    RET


; ----------------------------------------------------------------------------
; Multi-Stage Sound Effects Synthesizer on Ch2 ($C0/$D0) & Ch3 Noise ($E0/$F0)
; ----------------------------------------------------------------------------
@update_sfx:
    DEC A
    LD (sfx_timer), A
    JR NZ, @sfx_running
    ; SFX finished: silence Ch3 noise and restore Ch2 bass
    LD A, $FF
    OUT (PSG_PORT), A
    LD A, $DF
    OUT (PSG_PORT), A
    RET

@sfx_running:
    LD A, (sfx_tick)
    LD C, A                 ; C = elapsed frame of SFX
    INC A
    LD (sfx_tick), A

    LD A, (sfx_active_id)
    CP SFX_BIRD_FLY
    JR Z, @sfx_bird
    CP SFX_PIG_POP
    JR Z, @sfx_pig
    CP SFX_WOOD_HIT
    JR Z, @sfx_wood
    CP SFX_EXPLODE
    JR Z, @sfx_explode
    CP SFX_VICTORY
    JR Z, @sfx_victory
    CP SFX_DEFEAT
    JR Z, @sfx_defeat

    ; Default: SFX_SLINGSHOT (rising elastic creak)
    LD A, 28
    SUB C
    JR @set_ch2_div_a

@sfx_bird:
    ; Warbling bird battle cry pitch sweep (high expressive arc)
    LD A, C
    RRCA
    AND $07
    LD E, A
    LD D, 0
    LD HL, SfxBirdPitchTable
    ADD HL, DE
    LD A, (HL)
    JR @set_ch2_div_a

@sfx_pig:
    ; Pig Pop: Oink grunt followed by rising pop bubble + white noise burst
    LD A, C
    CP 6
    JR C, @pig_grunt
    ; Pop bubble (fast rising pitch)
    LD A, 18
    SUB C
    JR NC, @pig_pop_ok
    LD A, 4
@pig_pop_ok:
    LD B, A
    LD A, $E4               ; Crisp pop noise
    OUT (PSG_PORT), A
    LD A, $F4
    OUT (PSG_PORT), A
    LD A, B
    JR @set_ch2_div_a
@pig_grunt:
    LD A, 26
    ADD A, C
    JR @set_ch2_div_a

@sfx_wood:
    ; Crunchy wood/block impact: low woody thud + white noise crack
    LD A, $E5
    OUT (PSG_PORT), A
    LD A, C
    SRL A
    AND $0F
    OR $F0
    OUT (PSG_PORT), A
    LD A, 22
    ADD A, C
    JR @set_ch2_div_a

@sfx_explode:
    ; Bomb / TNT Explosion: deep rumble on Ch2 + roaring white noise shockwave on Ch3
    LD A, $E6               ; White noise low clock (heavy boom)
    OUT (PSG_PORT), A
    LD A, C
    SRL A
    AND $0F
    OR $F0
    OUT (PSG_PORT), A
    LD A, 36
    ADD A, C
    JR @set_ch2_div_a

@sfx_victory:
    ; Triumphant 4-note brass fanfare (E4 -> G#4 -> B4 -> E5)
    LD A, C
    SRL A
    SRL A
    SRL A                   ; / 8 -> note index 0..5
    CP 4
    JR C, @vic_idx_ok
    LD A, 3
@vic_idx_ok:
    LD E, A
    LD D, 0
    LD HL, SfxVictoryTable
    ADD HL, DE
    LD A, (HL)
    JR @set_ch2_div_a

@sfx_defeat:
    ; Sad descending trombone (B3 -> A#3 -> A3 -> G3 with pitch droop)
    LD A, C
    SRL A
    SRL A
    SRL A                   ; / 8 -> note index 0..5
    CP 4
    JR C, @def_idx_ok
    LD A, 3
@def_idx_ok:
    LD E, A
    LD D, 0
    LD HL, SfxDefeatTable
    ADD HL, DE
    LD A, (HL)

@set_ch2_div_a:
    ; A = high 6 bits of divider (4..60); output Ch2 tone + full volume ($D1)
    AND $3F
    LD B, A
    LD A, $C8               ; Ch2 Tone Latch (low 4 bits = 8)
    OUT (PSG_PORT), A
    LD A, B                 ; Ch2 Tone Data (high 6 bits)
    OUT (PSG_PORT), A
    LD A, $D1               ; Ch2 Volume = 1 (loud & clear)
    OUT (PSG_PORT), A
    RET

; --- SFX High-Byte Divider Tables (Divider = val * 16 + 8) ---
SfxBirdPitchTable:
    .db 13, 10, 8, 7, 8, 9, 11, 14

SfxVictoryTable:
    .db 21, 17, 14, 10      ; E4 (~330Hz), G#4 (~415Hz), B4 (~494Hz), E5 (~659Hz)

SfxDefeatTable:
    .db 28, 30, 32, 36      ; B3 (~247Hz), A#3 (~233Hz), A3 (~220Hz), G3 (~196Hz)
