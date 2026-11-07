; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/macros.inc
; Hardware I/O Ports, VDP/PSG Definitions, Sega Mapper & Z80 RAM Memory Map
; ============================================================================

; --- Sega Master System Hardware I/O Ports ---
PSG_PORT            = $7F   ; Texas Instruments SN76489 PSG port
VDP_DATA            = $BE   ; Sega 315-5124 VDP Data port (VRAM / CRAM read/write)
VDP_CTRL            = $BF   ; Sega 315-5124 VDP Control / Status / Address port
IO_JOY1             = $DC   ; Controller 1 & 2 I/O port A/B
IO_JOY2             = $DD   ; Controller 2 & Reset button port

; --- Sega Standard Mapper Registers ($FFFC..$FFFF) ---
MAPPER_CTRL         = $FFFC ; $00 = ROM banking enabled, cart RAM disabled
MAPPER_SLOT0        = $FFFD ; Bank for $0400..$3FFF (default $00)
MAPPER_SLOT1        = $FFFE ; Bank for $4000..$7FFF (default $01)
MAPPER_SLOT2        = $FFFF ; Bank for $8000..$BFFF (default $02)

; --- VDP Command Prefixes (High Byte of Control Word) ---
VDP_CMD_VRAM        = $40   ; Write to VRAM ($4000 | addr)
VDP_CMD_REG         = $80   ; Write to VDP Register ($8000 | (reg << 8) | val)
VDP_CMD_CRAM        = $C0   ; Write to CRAM Palette ($C000)

; --- VRAM Layout Constants ($0000..$3FFF = 16 KB) ---
VRAM_TILES          = $0000 ; 376 4bpp 8x8 tiles ($0000..$2EFF, 12,032 bytes)
VRAM_NAMETABLE      = $3800 ; 32x28 Tilemap ($3800..$3EFF, 1,792 bytes)
VRAM_SAT_Y          = $3F00 ; 64 Sprite Y coordinates ($3F00..$3F3F)
VRAM_SAT_XT         = $3F80 ; 64 Sprite (X, Tile) pairs ($3F80..$3FFF)

; --- Playfield Geometry Constants (256x192 Mode 4) ---
GROUND_TY           = 21    ; Grass ground top tile row (Row 21)
GROUND_PY           = 168   ; Grass ground top pixel Y (21 * 8 = 168)
BIRD_GROUND_Y       = 152   ; Bird Y when resting on ground (168 - 16 = 152)

; --- SMS Controller Button Masks (Active-High in joy_cur / joy_trig) ---
BTN_UP              = $01
BTN_DOWN            = $02
BTN_LEFT            = $04
BTN_RIGHT           = $08
BTN_1               = $10   ; Button 1 (Start / Fire / Launch / Special Ability)
BTN_2               = $20   ; Button 2 (Camera Peek / Special Ability / Start)
BTN_BOTH            = $30   ; Button 1 | Button 2

; --- Game States ---
STATE_TITLE         = 0
STATE_LEVEL_SELECT  = 1
STATE_INTRO_PAN     = 2
STATE_AIMING        = 3
STATE_FLYING        = 4
STATE_SETTLING      = 5
STATE_VICTORY       = 6
STATE_FAILED        = 7

; --- Sound Effect IDs (for PSG_PlaySFX) ---
SFX_BIRD_FLY        = 6
SFX_PIG_POP         = 7
SFX_WOOD_HIT        = 8
SFX_EXPLODE         = 9
SFX_SLINGSHOT       = 10
SFX_VICTORY         = 11
SFX_DEFEAT          = 12

; ============================================================================
; Z80 SYSTEM RAM MEMORY MAP ($C000..$DFFF = 8 KB)
; ============================================================================
tmp0                = $C000 ; 2B scratch
tmp1                = $C002 ; 2B scratch
tmp2                = $C004 ; 2B scratch
tmp3                = $C006 ; 2B scratch
tmp4                = $C008 ; 2B scratch
tmp5                = $C00A ; 2B scratch
ptr0                = $C00C ; 2B pointer
ptr1                = $C00E ; 2B pointer

vdp_ready           = $C010 ; 1B flag: 1 = frame ready for VBlank VDP transfer
frame_cnt           = $C011 ; 1B 60 Hz frame counter
joy_cur             = $C012 ; 1B current joypad buttons (active high)
joy_prev            = $C013 ; 1B previous joypad buttons
joy_trig            = $C014 ; 1B newly pressed joypad buttons
pause_flag          = $C015 ; 1B toggled by Console PAUSE button (NMI $0066)
pause_trig          = $C016 ; 1B 1 = Console PAUSE button was just pressed

game_state          = $C018 ; 1B current STATE_*
state_timer         = $C019 ; 1B state timer
cur_level           = $C01A ; 1B current stage index (0..20)
max_unlocked        = $C01B ; 1B highest unlocked stage (0..20)
hud_dirty           = $C01C ; 1B flag: 1 = stream HUD_BUF to VRAM $3800
logo_dirty          = $C01D ; 1B flag: 1 = draw 24x5 Title Logo to VRAM $3800

cam_x               = $C020 ; 2B current camera X scroll (0..224)
cam_target_x        = $C022 ; 2B target camera X scroll (0..224)
score_val           = $C024 ; 2B current score (in multiples of 100)
high_score          = $C026 ; 2B best score (in multiples of 100)

; Slingshot & Bird State
aim_angle           = $C028 ; 1B launch angle index (0..16)
aim_power           = $C029 ; 1B pull power (6..16)
birds_left          = $C02A ; 1B remaining birds in queue (0..6)
bird_queue          = $C02B ; 6B types of remaining birds ($C02B..$C030)
active_bird_type    = $C031 ; 1B 0=Red, 1=Blue, 2=Yellow, 3=Bomb
ability_used        = $C032 ; 1B 0=ready, 1=triggered
bird_active         = $C033 ; 1B 0=in sling, 1=flying, 2=bouncing
bird_timer          = $C034 ; 1B flight/bounce timeout
prev_cam_tile       = $C035 ; 1B previous (cam_x >> 3)

bird_x_sub          = $C036 ; 1B fractional X
bird_x              = $C037 ; 2B world X (0..511)
bird_y_sub          = $C039 ; 1B fractional Y
bird_y              = $C03A ; 2B world Y (0..191)
bird_vx             = $C03C ; 2B signed 8.8 fixed-point VX
bird_vy             = $C03E ; 2B signed 8.8 fixed-point VY

; Extra Split Birds (The Blues 3-way split: 2 extra birds)
split0_active       = $C040 ; 1B
split0_x            = $C041 ; 2B
split0_y            = $C043 ; 2B
split0_vx           = $C045 ; 2B
split0_vy           = $C047 ; 2B

split1_active       = $C049 ; 1B
split1_x            = $C04A ; 2B
split1_y            = $C04C ; 2B
split1_vx           = $C04E ; 2B
split1_vy           = $C050 ; 2B

; Effects & Progress
exp_timer           = $C054 ; 1B explosion / smoke puff timer
exp_x               = $C055 ; 2B world X of effect
exp_y               = $C057 ; 1B world Y of effect
exp_type            = $C058 ; 1B 0=Fireball ($7C), 1=Smoke Puff ($9C)

num_pigs_lvl        = $C05C ; 1B total pigs in level
pigs_alive          = $C05D ; 1B remaining pigs alive
num_blks_lvl        = $C05E ; 1B total blocks in level
stars_earned        = $C05F ; 1B 1..3 stars on clear
settle_timer        = $C060 ; 1B physics settle countdown
sat_cnt             = $C061 ; 1B current hardware sprite count (0..64)

; SN76489 PSG Audio Engine State ($C064..$C07F)
psg_subtick         = $C064 ; 1B sub-frame tick counter (0..10)
psg_step            = $C065 ; 1B current 128-step sequence index (0..127)
psg_env0            = $C066 ; 1B Ch0 Lead attenuation (0..15)
psg_env1            = $C067 ; 1B Ch1 Harmony/Mandolin attenuation (0..15)
psg_env2            = $C068 ; 1B Ch2 Bass attenuation (0..15)
psg_env3            = $C069 ; 1B Ch3 Percussion Noise attenuation (0..15)
sfx_active_id       = $C06A ; 1B currently playing SFX ID (0 = none)
sfx_timer           = $C06B ; 1B remaining frames of current SFX
sfx_tick            = $C06C ; 1B elapsed frames of current SFX

; --- VDP Transfer Buffers ($C100..$C2FF) ---
SAT_Y               = $C100 ; 64B Sprite Y table ($C100..$C13F)
SAT_XT              = $C180 ; 128B Sprite (X, Tile) table ($C180..$C1FF)
HUD_BUF             = $C200 ; 128B Stationary Top-2-Row HUD Nametable ($C200..$C27F)
COL_DIRTY           = $C280 ; 32B Dirty flags for VDP Nametable columns 0..31

; --- Level Entity Arrays ($C300..$C4FF) ---
pig_x_lo            = $C300 ; 8B
pig_x_hi            = $C308 ; 8B
pig_y               = $C310 ; 8B
pig_type            = $C318 ; 8B (0=Small, 1=Med, 2=Big, 3=Helmet, 4=King)
pig_hp              = $C320 ; 8B (0 = popped)
pig_vy              = $C328 ; 8B current vertical falling speed in px/frame

blk_tx              = $C330 ; 21B TileX (33..60)
blk_ty              = $C348 ; 21B TileY (3..20)
blk_w               = $C360 ; 21B Width in tiles (1..5)
blk_h               = $C378 ; 21B Height in tiles (1..5)
blk_mat             = $C390 ; 21B Material (1=Glass, 2=Wood, 3=Stone, 4=Estrade, 5=TNT)
blk_hp              = $C3A8 ; 21B Current HP (0 = destroyed)
blk_max_hp          = $C3C0 ; 21B Initial HP

blk_py              = $C400 ; 21B Exact pixel Y of top of block (blk_ty * 8)
blk_vy              = $C418 ; 21B Current falling speed in px/frame (0..5)
blk_px_off          = $C430 ; 21B Sub-tile pixel X offset (0..7)
blk_push_vx         = $C448 ; 21B Remaining horizontal push pixels when knocked
blk_falling         = $C460 ; 21B 0 = static on BG, 1 = actively falling via SAT sprites

; --- 64x24 World Tilemap Buffer ($C800..$CDFF = 1,536 bytes) ---
; Stored in column-major order: 64 columns x 24 rows (1 byte per tile)
WORLD_MAP           = $C800
