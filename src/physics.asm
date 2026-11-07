; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/physics.asm
; Slingshot Kinematics, Bird Special Abilities, Block Destruction &
; Real-Time 60 FPS Pixel-Accurate Gravity Engine
; ============================================================================

; ----------------------------------------------------------------------------
; Physics_LoadLevel: Unpacks 128-byte level entry for cur_level (0..20)
;   from LevelsBin into Z80 RAM arrays.
; ----------------------------------------------------------------------------
Physics_LoadLevel:
    ; Compute HL = LevelsBin + (cur_level * 128)
    LD A, (cur_level)
    LD L, A
    LD H, 0
    ADD HL, HL              ; * 2
    ADD HL, HL              ; * 4
    ADD HL, HL              ; * 8
    ADD HL, HL              ; * 16
    ADD HL, HL              ; * 32
    ADD HL, HL              ; * 64
    ADD HL, HL              ; * 128
    LD DE, LevelsBin
    ADD HL, DE
    LD (ptr0), HL

    ; +0: birds_left (1..6)
    LD A, (HL)
    LD (birds_left), A
    INC HL

    ; +1..+6: bird_queue[0..5]
    LD DE, bird_queue
    LD BC, 6
    LDIR

    LD A, (bird_queue)
    LD (active_bird_type), A

    ; +7: num_pigs_lvl
    LD A, (HL)
    LD (num_pigs_lvl), A
    LD (pigs_alive), A
    INC HL

    ; +8..+39: 8 pigs (4 bytes each: wx_lo, wx_hi, wy, (type<<4)|hp)
    LD C, 0
@copy_pigs:
    LD B, 0
    LD A, (HL)
    INC HL
    PUSH HL
    LD HL, pig_x_lo
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)
    INC HL
    PUSH HL
    LD HL, pig_x_hi
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)
    INC HL
    PUSH HL
    LD HL, pig_y
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)
    INC HL
    PUSH HL
    LD E, A
    SRL A
    SRL A
    SRL A
    SRL A
    AND $07
    LD HL, pig_type
    ADD HL, BC
    LD (HL), A
    LD A, E
    AND $0F
    LD HL, pig_hp
    ADD HL, BC
    LD (HL), A
    LD HL, pig_vy
    ADD HL, BC
    LD (HL), 0
    POP HL

    INC C
    LD A, C
    CP 8
    JR C, @copy_pigs

    ; Mask out pig slots >= num_pigs_lvl
    LD C, 0
@mask_pigs:
    LD A, (num_pigs_lvl)
    CP C
    JR Z, @zero_pig
    JR NC, @next_mask_pig
@zero_pig:
    LD B, 0
    PUSH HL
    LD HL, pig_hp
    ADD HL, BC
    LD (HL), 0
    POP HL
@next_mask_pig:
    INC C
    LD A, C
    CP 8
    JR C, @mask_pigs

    ; +40: num_blks_lvl (max 21)
    LD A, (HL)
    LD (num_blks_lvl), A
    INC HL

    ; +41..+124: 21 blocks (4 bytes each: tx, ty, (w<<4)|h, (mat<<5)|hp)
    LD C, 0
@copy_blks:
    LD B, 0
    LD A, (HL)              ; tx
    INC HL
    PUSH HL
    LD HL, blk_tx
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)              ; ty
    INC HL
    PUSH HL
    LD HL, blk_ty
    ADD HL, BC
    LD (HL), A
    ADD A, A
    ADD A, A
    ADD A, A                ; py = ty * 8
    LD HL, blk_py
    ADD HL, BC
    LD (HL), A
    XOR A
    LD HL, blk_vy
    ADD HL, BC
    LD (HL), A
    LD HL, blk_px_off
    ADD HL, BC
    LD (HL), A
    LD HL, blk_push_vx
    ADD HL, BC
    LD (HL), A
    LD HL, blk_falling
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)              ; (w<<4)|h
    INC HL
    PUSH HL
    LD E, A
    SRL A
    SRL A
    SRL A
    SRL A
    AND $0F
    LD HL, blk_w
    ADD HL, BC
    LD (HL), A
    LD A, E
    AND $0F
    LD HL, blk_h
    ADD HL, BC
    LD (HL), A
    POP HL

    LD A, (HL)              ; (mat<<5)|hp
    INC HL
    PUSH HL
    LD E, A
    RLCA
    RLCA
    RLCA
    AND $07
    LD HL, blk_mat
    ADD HL, BC
    LD (HL), A
    LD A, E
    AND $1F
    LD HL, blk_hp
    ADD HL, BC
    LD (HL), A
    LD HL, blk_max_hp
    ADD HL, BC
    LD (HL), A
    POP HL

    INC C
    LD A, C
    CP 21
    JP C, @copy_blks

    ; Mask out block slots >= num_blks_lvl
    LD C, 0
@mask_blks:
    LD A, (num_blks_lvl)
    CP C
    JR Z, @zero_blk
    JR NC, @next_mask_blk
@zero_blk:
    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD (HL), 0
@next_mask_blk:
    INC C
    LD A, C
    CP 21
    JR C, @mask_blks

    ; Reset score & active bird in slingshot
    LD HL, 0
    LD (score_val), HL
    XOR A
    LD (split0_active), A
    LD (split1_active), A
    LD (exp_timer), A

    LD A, 7
    LD (aim_angle), A
    LD A, 13
    LD (aim_power), A
    CALL Physics_PositionBirdInSling

    ; Start camera at 224 (showing Pig Fortress), pan back to 0 after intro pause
    LD HL, 224
    LD (cam_x), HL
    LD (cam_target_x), HL
    LD A, 50
    LD (state_timer), A
    LD A, STATE_INTRO_PAN
    LD (game_state), A
    RET


; ----------------------------------------------------------------------------
; Physics_PositionBirdInSling: Places active bird at slingshot pouch
; ----------------------------------------------------------------------------
Physics_PositionBirdInSling:
    XOR A
    LD (bird_active), A
    LD (ability_used), A
    LD (split0_active), A
    LD (split1_active), A
    LD (bird_x_sub), A
    LD (bird_y_sub), A

    ; bird_x = 68 - (aim_power >> 1)
    LD A, (aim_power)
    SRL A
    LD B, A
    LD A, 68
    SUB B
    LD (bird_x), A
    XOR A
    LD (bird_x+1), A

    ; bird_y = 126 + (aim_angle >> 1)
    LD A, (aim_angle)
    SRL A
    ADD A, 126
    LD (bird_y), A
    XOR A
    LD (bird_y+1), A
    RET


; ----------------------------------------------------------------------------
; Physics_UpdateCamera: Smoothly scrolls cam_x toward cam_target_x (0..224)
;   and marks newly exposed VDP columns dirty in COL_DIRTY.
; ----------------------------------------------------------------------------
Physics_UpdateCamera:
    LD HL, (cam_x)
    LD DE, (cam_target_x)
    OR A
    SBC HL, DE
    JR Z, @check_tile_change
    JR C, @move_right

    ; cam_x > cam_target_x: move left by up to 6 px/frame
    LD HL, (cam_x)
    LD BC, 6
    OR A
    SBC HL, BC
    JR NC, @chk_left_lim
    LD HL, 0
@chk_left_lim:
    PUSH HL
    OR A
    SBC HL, DE
    POP HL
    JR NC, @store_cam
    LD H, D
    LD L, E
    JR @store_cam

@move_right:
    ; cam_x < cam_target_x: move right by up to 8 px/frame
    LD HL, (cam_x)
    LD BC, 8
    ADD HL, BC
    PUSH HL
    OR A
    SBC HL, DE
    POP HL
    JR C, @store_cam
    LD H, D
    LD L, E

@store_cam:
    ; Clamp to 0..224
    BIT 7, H
    JR NZ, @clamp0
    LD A, H
    OR A
    JR NZ, @clamp224
    LD A, L
    CP 225
    JR C, @cam_ok
@clamp224:
    LD HL, 224
    JR @cam_ok
@clamp0:
    LD HL, 0
@cam_ok:
    LD (cam_x), HL

@check_tile_change:
    ; If (cam_x >> 3) != prev_cam_tile, mark newly exposed columns dirty!
    LD A, (cam_x)
    SRL A
    SRL A
    SRL A
    LD B, A                 ; B = new cam_tile
    LD A, (prev_cam_tile)
    CP B
    RET Z
    LD A, B
    LD (prev_cam_tile), A
    JP Render_MarkAllColsDirty


; ----------------------------------------------------------------------------
; Physics_UpdateAim: Handles Slingshot Aiming, Camera Peek & Bird Launch
; ----------------------------------------------------------------------------
Physics_UpdateAim:
    ; Hold Button 2 (BTN_2) to peek at the Pig Fortress on the right (cam_target_x = 224)
    LD A, (joy_cur)
    AND BTN_2
    JR Z, @cam_at_sling
    LD HL, 224
    LD (cam_target_x), HL
    JR @check_dpad
@cam_at_sling:
    LD HL, 0
    LD (cam_target_x), HL

@check_dpad:
    ; Throttle aim adjustments to every 4 frames for smooth precision
    LD A, (frame_cnt)
    AND $03
    JR NZ, @check_fire

    ; D-Pad UP: Increase launch angle (0..16)
    LD A, (joy_cur)
    AND BTN_UP
    JR Z, @chk_down
    LD A, (aim_angle)
    CP 16
    JR NC, @chk_down
    INC A
    LD (aim_angle), A

@chk_down:
    ; D-Pad DOWN: Decrease launch angle (0..16)
    LD A, (joy_cur)
    AND BTN_DOWN
    JR Z, @chk_left
    LD A, (aim_angle)
    OR A
    JR Z, @chk_left
    DEC A
    LD (aim_angle), A

@chk_left:
    ; D-Pad LEFT: Pull slingshot back harder (increase power up to 16)
    LD A, (joy_cur)
    AND BTN_LEFT
    JR Z, @chk_right
    LD A, (aim_power)
    CP 16
    JR NC, @chk_right
    INC A
    LD (aim_power), A

@chk_right:
    ; D-Pad RIGHT: Relax slingshot pull (decrease power down to 6)
    LD A, (joy_cur)
    AND BTN_RIGHT
    JR Z, @update_pouch
    LD A, (aim_power)
    CP 7
    JR C, @update_pouch
    DEC A
    LD (aim_power), A

@update_pouch:
    CALL Physics_PositionBirdInSling

@check_fire:
    ; Press Button 1 (BTN_1) to launch the bird!
    LD A, (joy_trig)
    AND BTN_1
    RET Z

    ; Load initial 8.8 velocity from LaunchVXTable[aim_angle] and LaunchVYTable[aim_angle]
    LD A, (aim_angle)
    ADD A, A                ; Word offset
    LD E, A
    LD D, 0
    LD HL, LaunchVXTable
    ADD HL, DE
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A
    LD (bird_vx), HL

    LD HL, LaunchVYTable
    ADD HL, DE
    LD A, (HL)
    INC HL
    LD H, (HL)
    LD L, A
    LD (bird_vy), HL

    ; Scale by (16 - aim_power)
    LD A, (aim_power)
    LD B, A
    LD A, 16
    SUB B
    JR Z, @power_done
    LD B, A
@scale_loop:
    LD HL, (bird_vx)
    LD DE, $0030
    OR A
    SBC HL, DE
    LD (bird_vx), HL

    LD HL, (bird_vy)
    LD DE, $0020
    ADD HL, DE
    LD (bird_vy), HL
    DJNZ @scale_loop
@power_done:

    LD A, 1
    LD (bird_active), A
    LD A, 190
    LD (bird_timer), A
    LD A, STATE_FLYING
    LD (game_state), A

    LD A, SFX_BIRD_FLY
    JP PSG_PlaySFX


; ----------------------------------------------------------------------------
; Physics_UpdateFlight: Steps bird kinematics, special abilities & collisions
; ----------------------------------------------------------------------------
Physics_UpdateFlight:
    ; 1. Check Button 1 or Button 2 press for Bird Special Ability in mid-air!
    LD A, (ability_used)
    OR A
    JP NZ, @step_motion
    LD A, (bird_active)
    CP 1
    JP NZ, @step_motion
    LD A, (joy_trig)
    AND BTN_BOTH
    JP Z, @step_motion

    ; Trigger Special Ability!
    LD A, 1
    LD (ability_used), A

    LD A, (active_bird_type)
    CP 1
    JR Z, @abil_blues
    CP 2
    JR Z, @abil_chuck
    CP 3
    JR Z, @abil_bomb

    ; Type 0 (Red Bird): Battle Cry + slight forward surge
    LD HL, (bird_vx)
    LD DE, $0080
    ADD HL, DE
    LD (bird_vx), HL
    LD A, SFX_BIRD_FLY
    CALL PSG_PlaySFX
    JR @step_motion

@abil_blues:
    ; Type 1 (The Blues): Split into 3 birds!
    LD A, 1
    LD (split0_active), A
    LD (split1_active), A
    LD HL, (bird_x)
    LD (split0_x), HL
    LD (split1_x), HL
    LD HL, (bird_y)
    LD (split0_y), HL
    LD (split1_y), HL
    LD HL, (bird_vx)
    LD (split0_vx), HL
    LD (split1_vx), HL
    LD HL, (bird_vy)
    LD DE, $0160
    OR A
    SBC HL, DE
    LD (split0_vy), HL
    LD HL, (bird_vy)
    ADD HL, DE
    LD (split1_vy), HL
    LD A, SFX_BIRD_FLY
    CALL PSG_PlaySFX
    JR @step_motion

@abil_chuck:
    ; Type 2 (Chuck Yellow Bird): Supersonic Horizontal Speed Dash!
    LD HL, $0680
    LD (bird_vx), HL
    LD HL, $0030
    LD (bird_vy), HL
    LD A, SFX_BIRD_FLY
    CALL PSG_PlaySFX
    JR @step_motion

@abil_bomb:
    ; Type 3 (Black Bomb Bird): Mid-Air Detonation!
    LD HL, (bird_x)
    LD (exp_x), HL
    LD A, (bird_y)
    LD (exp_y), A
    CALL Physics_TriggerExplosion
    JP Physics_EnterSettling

@step_motion:
    ; 2. Step Main Bird 8.8 Fixed-Point Position & Gravity
    ; Add VX to bird_x:bird_x_sub
    LD A, (bird_x_sub)
    LD HL, bird_vx
    ADD A, (HL)
    LD (bird_x_sub), A
    INC HL
    LD B, (HL)              ; B = bird_vx+1 (signed integer part)
    LD A, (bird_x)
    ADC A, B
    LD (bird_x), A
    LD A, (bird_x+1)
    BIT 7, B                ; Check sign bit of B without altering Carry!
    JR NZ, @vx_neg
    ADC A, 0
    JR @vx_done
@vx_neg:
    ADC A, $FF
@vx_done:
    LD (bird_x+1), A

    ; Add VY to bird_y:bird_y_sub
    LD A, (bird_y_sub)
    LD HL, bird_vy
    ADD A, (HL)
    LD (bird_y_sub), A
    INC HL
    LD B, (HL)              ; B = bird_vy+1 (signed integer part)
    LD A, (bird_y)
    ADC A, B
    LD (bird_y), A
    LD A, (bird_y+1)
    BIT 7, B                ; Check sign bit of B without altering Carry!
    JR NZ, @vy_neg
    ADC A, 0
    JR @vy_done
@vy_neg:
    ADC A, $FF
@vy_done:
    LD (bird_y+1), A

    ; Apply gravity: bird_vy += $0020
    LD HL, (bird_vy)
    LD DE, $0020
    ADD HL, DE
    LD (bird_vy), HL

    ; Update camera target to follow flying bird: clamp(bird_x - 88, 0, 224)
    LD HL, (bird_x)
    LD DE, 88
    OR A
    SBC HL, DE
    BIT 7, H
    JR Z, @cam_pos
    LD HL, 0
    JR @cam_set
@cam_pos:
    LD A, H
    OR A
    JR NZ, @cam_max
    LD A, L
    CP 224
    JR C, @cam_set
@cam_max:
    LD HL, 224
@cam_set:
    LD (cam_target_x), HL

    ; 3. Step Split Blue Birds if active
    CALL Physics_StepSplitBirds

    ; 4. Check Main Bird Collision at center (bird_x + 8, bird_y + 8)
    LD HL, (bird_x)
    LD DE, 8
    ADD HL, DE
    LD (tmp0), HL           ; tmp0 = Collision X (16-bit)
    LD A, (bird_y)
    ADD A, 8
    LD (tmp1), A            ; tmp1 = Collision Y (8-bit)
    CALL Physics_CheckPointHit
    JR NC, @check_bounds

    ; Main bird hit a block!
    ; If Bomb Bird, explode immediately on impact!
    LD A, (active_bird_type)
    CP 3
    JR NZ, @check_chuck_pierce
    LD HL, (bird_x)
    LD (exp_x), HL
    LD A, (bird_y)
    LD (exp_y), A
    CALL Physics_TriggerExplosion
    JP Physics_EnterSettling

@check_chuck_pierce:
    ; If Chuck is dashing, pierce right through with minimal slowdown!
    CP 2
    JR NZ, @normal_bounce
    LD A, (ability_used)
    OR A
    JR Z, @normal_bounce
    LD HL, (bird_vx)
    LD DE, $0120
    OR A
    SBC HL, DE
    BIT 7, H
    JR Z, @keep_chuck_vx
    LD HL, $0100
@keep_chuck_vx:
    LD (bird_vx), HL
    JR @check_bounds

@normal_bounce:
    ; Dampen VX on impact and mark bird as bouncing (state 2)
    LD A, 2
    LD (bird_active), A
    LD HL, (bird_vx)
    BIT 7, H
    JR NZ, @rebound_left
    LD A, H
    OR A
    JR NZ, @halve_vx
    LD A, L
    CP $80
    JR C, @rebound_left
@halve_vx:
    SRL H
    RR L
    LD (bird_vx), HL
    JR @bounce_done
@rebound_left:
    LD HL, $FF90
    LD (bird_vx), HL
@bounce_done:
    LD A, (bird_timer)
    CP 38
    JR C, @check_bounds
    LD A, 38
    LD (bird_timer), A

@check_bounds:
    ; Step real-time world gravity for blocks & pigs during bird flight!
    CALL Physics_StepWorldGravity

    ; Check Ground Collision (bird_y >= BIRD_GROUND_Y = 152)
    LD A, (bird_y+1)
    BIT 7, A
    JR NZ, @keep_flying     ; Above top of screen
    LD A, (bird_y)
    CP BIRD_GROUND_Y
    JR C, @check_right_edge

    ; Hit Ground at Y = 152!
    LD A, BIRD_GROUND_Y
    LD (bird_y), A
    LD A, 2
    LD (bird_active), A

    ; If Bomb Bird hits ground, detonate!
    LD A, (active_bird_type)
    CP 3
    JR NZ, @ground_bounce
    LD HL, (bird_x)
    LD (exp_x), HL
    LD A, (bird_y)
    LD (exp_y), A
    CALL Physics_TriggerExplosion
    JP Physics_EnterSettling

@ground_bounce:
    LD HL, $FF20
    LD (bird_vy), HL
    LD HL, (bird_vx)
    BIT 7, H
    JR NZ, @stop_vx
    SRL H
    RR L
    LD (bird_vx), HL
    JR @cap_ground_timer
@stop_vx:
    LD HL, 0
    LD (bird_vx), HL
@cap_ground_timer:
    LD A, (bird_timer)
    CP 24
    JR C, @check_right_edge
    LD A, 24
    LD (bird_timer), A

@check_right_edge:
    ; Check if bird flew past right edge of world (bird_x >= 496)
    LD HL, (bird_x)
    LD DE, 496
    OR A
    SBC HL, DE
    JR NC, Physics_EnterSettling

@keep_flying:
    LD A, (bird_timer)
    DEC A
    LD (bird_timer), A
    JR Z, Physics_EnterSettling
    RET

Physics_EnterSettling:
    XOR A
    LD (split0_active), A
    LD (split1_active), A
    LD A, 42
    LD (settle_timer), A
    LD A, STATE_SETTLING
    LD (game_state), A
    RET


; ----------------------------------------------------------------------------
; Physics_StepSplitBirds: Updates the 2 extra Blue birds from The Blues ability
; ----------------------------------------------------------------------------
Physics_StepSplitBirds:
    LD A, (split0_active)
    OR A
    JR Z, @do_split1
    LD A, (split0_vx+1)
    LD E, A
    LD D, 0
    LD HL, (split0_x)
    ADD HL, DE
    LD (split0_x), HL
    LD (tmp0), HL

    LD HL, (split0_vy)
    LD DE, $0022
    ADD HL, DE
    LD (split0_vy), HL
    LD A, (split0_y)
    ADD A, H
    LD (split0_y), A
    LD (tmp1), A
    CP 156
    JR C, @hit0
    XOR A
    LD (split0_active), A
    JR @do_split1
@hit0:
    CALL Physics_CheckPointHit
    JR NC, @do_split1
    XOR A
    LD (split0_active), A

@do_split1:
    LD A, (split1_active)
    OR A
    RET Z
    LD A, (split1_vx+1)
    LD E, A
    LD D, 0
    LD HL, (split1_x)
    ADD HL, DE
    LD (split1_x), HL
    LD (tmp0), HL

    LD HL, (split1_vy)
    LD DE, $0022
    ADD HL, DE
    LD (split1_vy), HL
    LD A, (split1_y)
    ADD A, H
    LD (split1_y), A
    LD (tmp1), A
    CP 156
    JR C, @hit1
    XOR A
    LD (split1_active), A
    RET
@hit1:
    CALL Physics_CheckPointHit
    RET NC
    XOR A
    LD (split1_active), A
    RET


; ----------------------------------------------------------------------------
; Physics_CheckPointHit: Checks point (tmp0 = 16-bit X, tmp1 = 8-bit Y)
;   against all living Pigs and Blocks.
;   Returns Carry = 1 if a solid block was hit, Carry = 0 otherwise.
; ----------------------------------------------------------------------------
Physics_CheckPointHit:
    ; --- 1. Check against all living Pigs (0..num_pigs_lvl-1) ---
    LD C, 0
@pig_loop:
    LD A, (num_pigs_lvl)
    CP C
    JR Z, @check_blocks
    JR C, @check_blocks

    LD B, 0
    LD HL, pig_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_pig

    ; Check Y overlap: pig_y - 6 <= tmp1 < pig_y + 20
    LD HL, pig_y
    ADD HL, BC
    LD A, (HL)
    SUB 6
    LD E, A
    LD A, (tmp1)
    CP E
    JR C, @next_pig
    LD A, E
    ADD A, 26
    LD E, A
    LD A, (tmp1)
    CP E
    JR NC, @next_pig

    ; Check X overlap: pig_x - 6 <= tmp0 < pig_x + 20
    LD HL, pig_x_lo
    ADD HL, BC
    LD E, (HL)
    LD HL, pig_x_hi
    ADD HL, BC
    LD D, (HL)
    EX DE, HL               ; HL = pig_x
    LD DE, 6
    OR A
    SBC HL, DE              ; HL = pig_x - 6
    LD DE, (tmp0)
    PUSH HL
    OR A
    SBC HL, DE              ; (pig_x - 6) - tmp0
    POP HL
    JR Z, @x_min_ok
    JR NC, @next_pig
@x_min_ok:
    LD DE, 26
    ADD HL, DE              ; HL = pig_x + 20
    LD DE, (tmp0)
    OR A
    SBC HL, DE              ; (pig_x + 20) - tmp0
    JR C, @next_pig
    JR Z, @next_pig

    ; Direct hit on Pig C! Pop the pig!
    PUSH BC
    CALL Physics_PopPigC
    POP BC

@next_pig:
    INC C
    JR @pig_loop

@check_blocks:
    ; --- 2. Check against all living Blocks (0..num_blks_lvl-1) ---
    ; Convert pixel (tmp0, tmp1) to tile coordinates (tmp2 = TileX, tmp3 = TileY)
    LD HL, (tmp0)
    SRL H
    RR L
    SRL H
    RR L
    SRL H
    RR L
    LD A, L
    LD (tmp2), A            ; tmp2 = TileX

    LD A, (tmp1)
    SRL A
    SRL A
    SRL A
    LD (tmp3), A            ; tmp3 = TileY

    LD C, 0
@blk_loop:
    LD A, (num_blks_lvl)
    CP C
    JP Z, @no_block_hit
    JP C, @no_block_hit

    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_blk

    ; Check blk_tx - 1 <= tmp2 <= blk_tx + blk_w
    LD HL, blk_tx
    ADD HL, BC
    LD A, (HL)
    DEC A
    LD E, A
    LD A, (tmp2)
    CP E
    JP C, @next_blk

    LD HL, blk_tx
    ADD HL, BC
    LD A, (HL)
    LD HL, blk_w
    ADD HL, BC
    ADD A, (HL)
    LD E, A
    LD A, (tmp2)
    CP E
    JR Z, @chk_blk_y
    JP NC, @next_blk

@chk_blk_y:
    ; Check blk_ty - 1 <= tmp3 <= blk_ty + blk_h
    LD HL, blk_ty
    ADD HL, BC
    LD A, (HL)
    DEC A
    LD E, A
    LD A, (tmp3)
    CP E
    JP C, @next_blk

    LD HL, blk_ty
    ADD HL, BC
    LD A, (HL)
    LD HL, blk_h
    ADD HL, BC
    ADD A, (HL)
    LD E, A
    LD A, (tmp3)
    CP E
    JR Z, @hit_blk_now
    JP NC, @next_blk

@hit_blk_now:
    ; --- HIT BLOCK C! ---
    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 4                    ; Estrade?
    JR NZ, @check_tnt
    SCF
    RET

@check_tnt:
    CP 5                    ; TNT Crate?
    JR NZ, @damage_normal_blk
    LD HL, blk_hp
    ADD HL, BC
    LD (HL), 0
    LD HL, (tmp0)
    LD (exp_x), HL
    LD A, (tmp1)
    LD (exp_y), A
    CALL Physics_TriggerExplosion
    SCF
    RET

@damage_normal_blk:
    ; Compute impact damage: base 14, +16 if bird matches material weakness!
    LD D, 14                ; D = damage
    LD A, (active_bird_type)
    CP 1                    ; Blues vs Glass (mat 1)
    JR NZ, @chk_chuck_wood
    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 1
    JR NZ, @apply_dmg
    LD D, 30
    JR @apply_dmg
@chk_chuck_wood:
    CP 2                    ; Chuck vs Wood (mat 2)
    JR NZ, @apply_dmg
    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 2
    JR NZ, @apply_dmg
    LD D, 30

@apply_dmg:
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    SUB D
    JR NC, @still_alive
    XOR A
@still_alive:
    LD (HL), A
    OR A
    JR NZ, @cracked_only

    ; Block destroyed! +500 points (score_val += 5)
    LD HL, blk_falling
    ADD HL, BC
    LD (HL), 0
    LD HL, (score_val)
    LD DE, 5
    ADD HL, DE
    LD (score_val), HL
    JR @rebuild_now

@cracked_only:
    ; Block cracked & knocked sideways! Push it 8px right over 4 frames!
    LD HL, blk_push_vx
    ADD HL, BC
    LD (HL), 8
    LD HL, blk_falling
    ADD HL, BC
    LD (HL), 1
    ; +100 points (score_val += 1)
    LD HL, (score_val)
    INC HL
    LD (score_val), HL

@rebuild_now:
    LD A, SFX_WOOD_HIT
    CALL PSG_PlaySFX
    CALL Render_RebuildCastle
    CALL Render_BuildHUD
    SCF
    RET

@next_blk:
    INC C
    JP @blk_loop

@no_block_hit:
    OR A                    ; Clear Carry
    RET


; ----------------------------------------------------------------------------
; Physics_PopPigC: Pops pig at index C, awards 5000 pts, triggers smoke puff
; ----------------------------------------------------------------------------
Physics_PopPigC:
    LD B, 0
    LD HL, pig_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    RET Z
    LD (HL), 0

    LD A, (pigs_alive)
    DEC A
    LD (pigs_alive), A

    ; Spawn Smoke Puff at pig position
    LD HL, pig_x_lo
    ADD HL, BC
    LD E, (HL)
    LD HL, pig_x_hi
    ADD HL, BC
    LD D, (HL)
    LD (exp_x), DE
    LD HL, pig_y
    ADD HL, BC
    LD A, (HL)
    LD (exp_y), A
    LD A, 1                 ; Smoke puff
    LD (exp_type), A
    LD A, 20
    LD (exp_timer), A

    ; Award 5000 points (score_val += 50)
    LD HL, (score_val)
    LD DE, 50
    ADD HL, DE
    LD (score_val), HL

    LD A, SFX_PIG_POP
    CALL PSG_PlaySFX
    JP Render_BuildHUD


; ----------------------------------------------------------------------------
; Physics_TriggerExplosion: Bomb / TNT shockwave centered at (exp_x, exp_y)
; ----------------------------------------------------------------------------
Physics_TriggerExplosion:
    XOR A
    LD (exp_type), A        ; Fireball sprite ($7C)
    LD A, 24
    LD (exp_timer), A

    LD A, SFX_EXPLODE
    CALL PSG_PlaySFX

    ; Convert exp_x, exp_y to tile center (tmp2 = TileX, tmp3 = TileY)
    LD HL, (exp_x)
    SRL H
    RR L
    SRL H
    RR L
    SRL H
    RR L
    LD A, L
    LD (tmp2), A

    LD A, (exp_y)
    SRL A
    SRL A
    SRL A
    LD (tmp3), A

    ; 1. Destroy all non-Estrade blocks within +/- 5 tiles of (tmp2, tmp3)
    LD C, 0
@exp_blk_loop:
    LD A, (num_blks_lvl)
    CP C
    JR Z, @exp_pigs
    JR C, @exp_pigs

    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_exp_blk

    LD HL, blk_mat
    ADD HL, BC
    LD A, (HL)
    CP 4
    JR Z, @next_exp_blk

    ; |blk_tx - tmp2| <= 5
    LD HL, blk_tx
    ADD HL, BC
    LD A, (tmp2)
    SUB (HL)
    JP P, @dx_pos
    NEG
@dx_pos:
    CP 6
    JR NC, @next_exp_blk

    ; |blk_ty - tmp3| <= 5
    LD HL, blk_ty
    ADD HL, BC
    LD A, (tmp3)
    SUB (HL)
    JP P, @dy_pos
    NEG
@dy_pos:
    CP 6
    JR NC, @next_exp_blk

    ; Destroy block C!
    LD HL, blk_hp
    ADD HL, BC
    LD (HL), 0
    LD HL, (score_val)
    LD DE, 5
    ADD HL, DE
    LD (score_val), HL

@next_exp_blk:
    INC C
    JR @exp_blk_loop

@exp_pigs:
    ; 2. Pop all pigs within +/- 44 px of (exp_x, exp_y)
    LD C, 0
@exp_pig_loop:
    LD A, (num_pigs_lvl)
    CP C
    JR Z, @exp_done
    JR C, @exp_done

    LD B, 0
    LD HL, pig_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_exp_pig

    ; |pig_y - exp_y| <= 44
    LD HL, pig_y
    ADD HL, BC
    LD A, (exp_y)
    SUB (HL)
    JP P, @pdy_pos
    NEG
@pdy_pos:
    CP 44
    JR NC, @next_exp_pig

    ; |pig_x - exp_x| <= 44
    LD HL, pig_x_lo
    ADD HL, BC
    LD E, (HL)
    LD HL, pig_x_hi
    ADD HL, BC
    LD D, (HL)
    EX DE, HL
    LD DE, (exp_x)
    OR A
    SBC HL, DE
    BIT 7, H
    JR Z, @pdx_pos
    XOR A
    SUB L
    LD L, A
    SBC A, A
    SUB H
    LD H, A
@pdx_pos:
    LD A, H
    OR A
    JR NZ, @next_exp_pig
    LD A, L
    CP 44
    JR NC, @next_exp_pig

    PUSH BC
    CALL Physics_PopPigC
    POP BC
    XOR A
    LD (exp_type), A        ; Keep fireball icon

@next_exp_pig:
    INC C
    JR @exp_pig_loop

@exp_done:
    CALL Render_RebuildCastle
    JP Render_BuildHUD


; ----------------------------------------------------------------------------
; Physics_StepWorldGravity: Smooth 60 FPS pixel-by-pixel gravity, horizontal
;   impact slide, landing damage & pig crushing for all blocks and pigs.
;   Sets tmp5 = 1 if any block or pig is still moving, 0 when completely at rest.
; ----------------------------------------------------------------------------
Physics_StepWorldGravity:
    XOR A
    LD (tmp4), A            ; Flag: 1 if static castle tilemap needs rebuild
    LD (tmp5), A            ; Flag: 1 if any block or pig is actively falling/sliding

    ; --- 1. Step all living blocks (0..num_blks_lvl-1) ---
    LD C, 0
@grav_blk_loop:
    LD A, (num_blks_lvl)
    CP C
    JP Z, @done_grav_blks
    JP C, @done_grav_blks

    LD B, 0
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_grav_blk

    ; A. Handle horizontal knockback slide if blk_push_vx[C] > 0
    LD HL, blk_push_vx
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @check_vert_sup

    LD A, 1
    LD (tmp5), A            ; Motion active!
    LD HL, blk_falling
    ADD HL, BC
    LD A, (HL)
    OR A
    JR NZ, @do_horiz_step
    LD (HL), 1
    LD A, 1
    LD (tmp4), A            ; Detach from BG into SAT sprites
@do_horiz_step:
    LD HL, blk_push_vx
    ADD HL, BC
    LD A, (HL)
    SUB 2
    JR NC, @store_push_vx
    XOR A
@store_push_vx:
    LD (HL), A

    LD HL, blk_px_off
    ADD HL, BC
    LD A, (HL)
    ADD A, 2
    CP 8
    JR C, @store_px_off
    SUB 8
    LD (HL), A
    LD HL, blk_tx
    ADD HL, BC
    LD A, (HL)
    CP 55
    JR NC, @check_vert_sup
    INC (HL)
    JR @check_vert_sup
@store_px_off:
    LD (HL), A

@check_vert_sup:
    ; B. Compute block pixel height (tmp0 = blk_h * 8) and bottom Y (tmp1 = blk_py + tmp0)
    LD HL, blk_h
    ADD HL, BC
    LD A, (HL)
    ADD A, A
    ADD A, A
    ADD A, A
    LD (tmp0), A            ; Height in pixels
    LD HL, blk_py
    ADD HL, BC
    ADD A, (HL)
    LD (tmp1), A            ; Current bottom pixel Y of block C

    ; Find highest support surface (tmp2 = support_py, default GROUND_PY = 168)
    LD A, GROUND_PY
    LD (tmp2), A

    ; Cache block C's tx and tx+w in ptr0 and ptr0+1
    LD HL, blk_tx
    ADD HL, BC
    LD A, (HL)
    LD (ptr0), A            ; ptr0 = blk_tx[C]
    LD HL, blk_w
    ADD HL, BC
    ADD A, (HL)
    LD (ptr0+1), A          ; ptr0+1 = blk_tx[C] + blk_w[C]

    LD E, 0                 ; E = support candidate block index 0..num_blks_lvl-1
@sup_loop:
    LD A, (num_blks_lvl)
    CP E
    JR Z, @sup_search_done
    JR C, @sup_search_done

    LD A, E
    CP C
    JR Z, @next_sup         ; Don't self-support

    LD D, 0
    LD HL, blk_hp
    ADD HL, DE
    LD A, (HL)
    OR A
    JR Z, @next_sup

    ; Does block E's top (blk_py[E]) lie at or below (cur_bot - 4)?
    LD HL, blk_py
    ADD HL, DE
    LD A, (tmp1)
    SUB 4
    CP (HL)
    JR Z, @chk_sup_x
    JR C, @chk_sup_x
    JR @next_sup

@chk_sup_x:
    ; Horizontal overlap: blk_tx[E] + blk_w[E] > blk_tx[C] AND blk_tx[C] + blk_w[C] > blk_tx[E]
    LD HL, blk_tx
    ADD HL, DE
    LD A, (HL)
    LD HL, blk_w
    ADD HL, DE
    ADD A, (HL)             ; A = blk_tx[E] + blk_w[E]
    LD HL, ptr0             ; (ptr0) = blk_tx[C]
    CP (HL)
    JR C, @next_sup
    JR Z, @next_sup

    LD HL, blk_tx
    ADD HL, DE
    LD A, (ptr0+1)          ; A = blk_tx[C] + blk_w[C]
    CP (HL)
    JR C, @next_sup
    JR Z, @next_sup

    ; Block E supports Block C! Keep minimum blk_py[E] in tmp2
    LD HL, blk_py
    ADD HL, DE
    LD A, (HL)
    LD HL, tmp2
    CP (HL)
    JR NC, @next_sup
    LD (HL), A

@next_sup:
    INC E
    JR @sup_loop

@sup_search_done:
    ; Compare current bottom (tmp1) with support_py (tmp2)
    LD A, (tmp1)
    LD HL, tmp2
    CP (HL)
    JR C, @blk_in_air
    JP @blk_is_supported

@blk_in_air:
    ; --- BLOCK C IS UNSUPPORTED IN MID-AIR (cur_bot < support_py)! ---
    LD A, 1
    LD (tmp5), A            ; Motion active!
    LD B, 0
    LD HL, blk_falling
    ADD HL, BC
    LD A, (HL)
    OR A
    JR NZ, @accel_blk_vy
    LD (HL), 1
    LD HL, blk_vy
    ADD HL, BC
    LD (HL), 1
    LD A, 1
    LD (tmp4), A            ; Detach from BG so SAT renders smooth fall
    JR @step_blk_py

@accel_blk_vy:
    LD A, (frame_cnt)
    AND $03
    JR NZ, @step_blk_py
    LD HL, blk_vy
    ADD HL, BC
    LD A, (HL)
    CP 4
    JR NC, @step_blk_py
    INC (HL)

@step_blk_py:
    LD HL, blk_vy
    ADD HL, BC
    LD A, (HL)
    LD HL, blk_py
    ADD HL, BC
    ADD A, (HL)
    LD (HL), A              ; blk_py[C] += blk_vy[C]
    LD HL, tmp0
    ADD A, (HL)             ; New bottom pixel Y
    LD HL, tmp2
    CP (HL)                 ; Reached or passed support_py?
    JR C, @still_in_air

    ; --- BLOCK C JUST LANDED ON SUPPORT_PY! ---
    LD A, (tmp2)
    LD HL, tmp0
    SUB (HL)
    LD HL, blk_py
    ADD HL, BC
    LD (HL), A
    SRL A
    SRL A
    SRL A
    LD HL, blk_ty
    ADD HL, BC
    LD (HL), A

    ; Apply impact damage on hard landing (blk_vy >= 2)
    LD HL, blk_vy
    ADD HL, BC
    LD A, (HL)
    CP 2
    JR C, @land_lock
    ADD A, A                ; Damage = blk_vy * 2
    LD D, A
    LD HL, blk_hp
    ADD HL, BC
    LD A, (HL)
    SUB D
    JR NC, @land_hp_ok
    XOR A
@land_hp_ok:
    LD (HL), A
    LD HL, (score_val)
    INC HL
    LD (score_val), HL

@land_lock:
    LD HL, blk_vy
    ADD HL, BC
    LD (HL), 0
    LD HL, blk_push_vx
    ADD HL, BC
    LD A, (HL)
    OR A
    JR NZ, @next_grav_blk
    LD HL, blk_falling
    ADD HL, BC
    LD (HL), 0
    LD HL, blk_px_off
    ADD HL, BC
    LD (HL), 0
    LD A, 1
    LD (tmp4), A            ; Re-attach to static BG!
    JR @next_grav_blk

@still_in_air:
    LD HL, blk_py
    ADD HL, BC
    LD A, (HL)
    SRL A
    SRL A
    SRL A
    LD HL, blk_ty
    ADD HL, BC
    LD (HL), A
    JR @next_grav_blk

@blk_is_supported:
    LD B, 0
    LD A, (tmp2)
    LD HL, tmp0
    SUB (HL)
    LD HL, blk_py
    ADD HL, BC
    LD (HL), A
    SRL A
    SRL A
    SRL A
    LD HL, blk_ty
    ADD HL, BC
    LD (HL), A
    LD HL, blk_push_vx
    ADD HL, BC
    LD A, (HL)
    OR A
    JR NZ, @next_grav_blk
    LD HL, blk_falling
    ADD HL, BC
    LD A, (HL)
    OR A
    JR Z, @next_grav_blk
    LD (HL), 0
    LD HL, blk_vy
    ADD HL, BC
    LD (HL), 0
    LD HL, blk_px_off
    ADD HL, BC
    LD (HL), 0
    LD A, 1
    LD (tmp4), A

@next_grav_blk:
    INC C
    JP @grav_blk_loop

@done_grav_blks:
    LD A, (tmp4)
    OR A
    CALL NZ, Render_RebuildCastle

    ; --- 2. Smoothly fall unsupported Pigs & crush Pigs hit by falling blocks ---
    LD C, 0
@grav_pig_loop:
    LD A, (num_pigs_lvl)
    CP C
    RET Z
    RET C

    LD B, 0
    LD HL, pig_hp
    ADD HL, BC
    LD A, (HL)
    OR A
    JP Z, @next_grav_pig

    ; Compute pig center TileX: tmp2 = (pig_x + 8) >> 3
    LD HL, pig_x_lo
    ADD HL, BC
    LD E, (HL)
    LD HL, pig_x_hi
    ADD HL, BC
    LD D, (HL)
    EX DE, HL
    LD DE, 8
    ADD HL, DE
    SRL H
    RR L
    SRL H
    RR L
    SRL H
    RR L
    LD A, L
    LD (tmp2), A            ; Pig center TileX

    ; Find highest support pixel Y under pig (tmp3 = GROUND_PY = 168)
    LD A, GROUND_PY
    LD (tmp3), A

    LD HL, pig_y
    ADD HL, BC
    LD A, (HL)
    LD (tmp0), A            ; tmp0 = pig_y[C]

    LD E, 0                 ; Block index E = 0..num_blks_lvl-1
@pig_sup_loop:
    LD A, (num_blks_lvl)
    CP E
    JR Z, @pig_sup_done
    JR C, @pig_sup_done

    LD D, 0
    LD HL, blk_hp
    ADD HL, DE
    LD A, (HL)
    OR A
    JR Z, @next_pig_sup

    ; Check horizontal overlap: blk_tx[E] - 1 <= tmp2 <= blk_tx[E] + blk_w[E]
    LD HL, blk_tx
    ADD HL, DE
    LD A, (HL)
    DEC A
    LD L, A
    LD A, (tmp2)
    CP L
    JR C, @next_pig_sup

    LD HL, blk_tx
    ADD HL, DE
    LD A, (HL)
    LD HL, blk_w
    ADD HL, DE
    ADD A, (HL)
    LD L, A
    LD A, (tmp2)
    CP L
    JR Z, @px_ok
    JR NC, @next_pig_sup
@px_ok:

    ; Compute block E bottom pixel Y: A = blk_py[E] + blk_h[E] * 8
    LD HL, blk_h
    ADD HL, DE
    LD A, (HL)
    ADD A, A
    ADD A, A
    ADD A, A
    LD HL, blk_py
    ADD HL, DE
    ADD A, (HL)
    LD (ptr0), A            ; ptr0 = block bottom pixel Y

    ; Check if block E overlaps pig body vertically (blk_py[E] < pig_y + 12 AND blk_bot > pig_y + 2)
    LD A, (tmp0)
    ADD A, 12
    CP (HL)                 ; Compare (pig_y + 12) with blk_py[E]
    JR C, @check_pig_floor
    JR Z, @check_pig_floor

    LD A, (tmp0)
    ADD A, 2
    LD HL, ptr0
    CP (HL)                 ; Compare (pig_y + 2) with blk_bot
    JR NC, @next_pig_sup

    ; A falling or shifted block is crushing Pig C! Pop Pig C!
    PUSH BC
    CALL Physics_PopPigC
    POP BC
    JP @next_grav_pig

@check_pig_floor:
    ; Block E is below Pig C: update highest floor (minimum blk_py[E])
    LD HL, blk_py
    ADD HL, DE
    LD A, (HL)
    LD HL, tmp3
    CP (HL)
    JR NC, @next_pig_sup
    LD (HL), A

@next_pig_sup:
    INC E
    JR @pig_sup_loop

@pig_sup_done:
    ; Compare pig bottom (pig_y + 16) with support floor tmp3
    LD B, 0
    LD HL, pig_y
    ADD HL, BC
    LD A, (HL)
    ADD A, 16
    LD HL, tmp3
    CP (HL)
    JR NC, @pig_on_floor

    ; --- PIG C IS IN MID-AIR! Accelerate smoothly (1..4 px/frame) ---
    LD A, 1
    LD (tmp5), A            ; Motion active!
    LD HL, pig_vy
    ADD HL, BC
    LD A, (HL)
    OR A
    JR NZ, @accel_pig_vy
    LD (HL), 1
    JR @step_pig_y
@accel_pig_vy:
    LD A, (frame_cnt)
    AND $03
    JR NZ, @step_pig_y
    LD A, (HL)
    CP 4
    JR NC, @step_pig_y
    INC (HL)

@step_pig_y:
    LD HL, pig_vy
    ADD HL, BC
    LD A, (HL)
    LD HL, pig_y
    ADD HL, BC
    ADD A, (HL)
    LD (HL), A
    ADD A, 16
    LD HL, tmp3
    CP (HL)
    JR C, @next_grav_pig

    ; Pig C just landed on floor tmp3!
    LD A, (tmp3)
    SUB 16
    LD HL, pig_y
    ADD HL, BC
    LD (HL), A

    LD HL, pig_vy
    ADD HL, BC
    LD A, (HL)
    LD (HL), 0
    CP 2                    ; Fell fast enough to pop?
    JR C, @next_grav_pig
    PUSH BC
    CALL Physics_PopPigC
    POP BC
    JR @next_grav_pig

@pig_on_floor:
    LD A, (tmp3)
    SUB 16
    LD HL, pig_y
    ADD HL, BC
    LD (HL), A
    LD HL, pig_vy
    ADD HL, BC
    LD (HL), 0

@next_grav_pig:
    INC C
    JP @grav_pig_loop


; ----------------------------------------------------------------------------
; Physics_UpdateSettling: Steps world gravity until all blocks/pigs come to rest,
;   then evaluates Win / Next Bird / Retry condition.
; ----------------------------------------------------------------------------
Physics_UpdateSettling:
    CALL Physics_StepWorldGravity

    ; If any block or pig is still falling/sliding (tmp5 != 0), keep settle_timer >= 14
    LD A, (tmp5)
    OR A
    JR Z, @check_settle_end
    LD A, (settle_timer)
    CP 14
    JR NC, @check_settle_end
    LD A, 14
    LD (settle_timer), A

@check_settle_end:
    LD A, (settle_timer)
    DEC A
    LD (settle_timer), A
    RET NZ

    ; Evaluate turn: check if all pigs are popped!
    LD A, (pigs_alive)
    OR A
    JR NZ, @check_more_birds

    ; --- VICTORY! ALL PIGS POPPED! ---
    ; Award 10,000 pts (score_val += 100) for each unused bird in queue
    LD A, (birds_left)
    DEC A
    LD (birds_left), A
    JR Z, @calc_stars
    LD B, A
    LD HL, (score_val)
    LD DE, 100
@bonus_loop:
    ADD HL, DE
    DJNZ @bonus_loop
    LD (score_val), HL

@calc_stars:
    LD A, 1
    LD (stars_earned), A
    LD HL, (score_val)
    LD DE, 120
    OR A
    SBC HL, DE
    JR C, @stars_done
    LD A, 2
    LD (stars_earned), A
    LD HL, (score_val)
    LD DE, 220
    OR A
    SBC HL, DE
    JR C, @stars_done
    LD A, 3
    LD (stars_earned), A
@stars_done:

    ; Update high_score if score_val > high_score
    LD HL, (score_val)
    LD DE, (high_score)
    OR A
    SBC HL, DE
    JR C, @unlock_next
    LD HL, (score_val)
    LD (high_score), HL
@unlock_next:
    LD A, (cur_level)
    LD HL, max_unlocked
    CP (HL)
    JR C, @go_victory
    CP 20
    JR NC, @go_victory
    INC A
    LD (max_unlocked), A

@go_victory:
    LD A, SFX_VICTORY
    CALL PSG_PlaySFX
    LD A, STATE_VICTORY
    LD (game_state), A
    JP Render_BuildHUD

@check_more_birds:
    LD A, (birds_left)
    DEC A
    LD (birds_left), A
    JR Z, @level_failed

    ; Shift bird_queue down by 1 and load next bird into slingshot!
    LD HL, bird_queue + 1
    LD DE, bird_queue
    LD BC, 5
    LDIR

    LD A, (bird_queue)
    LD (active_bird_type), A
    CALL Physics_PositionBirdInSling
    LD HL, 0
    LD (cam_target_x), HL
    LD A, STATE_AIMING
    LD (game_state), A
    JP Render_BuildHUD

@level_failed:
    LD A, SFX_DEFEAT
    CALL PSG_PlaySFX
    LD A, STATE_FAILED
    LD (game_state), A
    JP Render_BuildHUD


; --- Launch Velocity Lookup Tables (17 angles at full power=16, 8.8 signed fixed-point) ---
LaunchVXTable:
    .dw $05B0, $05A0, $0588, $0570, $0558, $0540, $0520, $0500
    .dw $04D8, $04B0, $0480, $0450, $0418, $03E0, $03A0, $0358, $0310

LaunchVYTable:
    .dw $FE40, $FDE0, $FD80, $FD20, $FCC0, $FC60, $FC00, $FBA0
    .dw $FB40, $FAE0, $FA80, $FA20, $F9C0, $F960, $F900, $F8A0, $F840
