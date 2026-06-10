; Team members:
; 1) Yuhao Gong (999021488) 
; 2) Xuanshuo Liang (800013328) 
;
; -----------------------------------------------------------------------------
; Game rules
; 1) Objective:
;    - Collect all coins in the current level (prizeLeft -> 0).
; 2) Level flow:
;    - Automatically advance to the next level after clearing the current one.
;    - Show "YOU WIN!" after clearing level 10.
; 3) Manual level switching (current key mapping):
;    - Press A -> next level.
;    - Press B -> previous level.
; 4) Lives:
;    - New game starts with 9 lives.
;    - Switching levels does not reset lives.
; 5) Death:
;    - Being crushed by a rock costs 1 life; resume from checkpoint.
;    - Show "GAME OVER" when lives reach zero.
; -----------------------------------------------------------------------------

INCLUDE "hardware.inc"

DEF OBJCOUNT EQU 1
DEF PLAYER_TILE_ID EQU 2
DEF LEVEL_AMMOUNT EQU 10

; Reserve 2 bottom rows for UI (see PLAY_Y_MAX)
DEF SCR_H         EQU 144
DEF UI_ROWS       EQU 2
DEF TILE_PX       EQU 8
DEF SPRITE_PX     EQU 8
DEF OAM_Y_BIAS    EQU 16
DEF OAM_X_BIAS    EQU 8
DEF PLAY_Y_MAX    EQU SCR_H - (UI_ROWS * TILE_PX) - SPRITE_PX + OAM_Y_BIAS ; max playable Y = screen height - UI rows - sprite height + OAM bias
DEF PLAY_Y_MIN    EQU OAM_Y_BIAS                                           ; min playable Y = OAM Y bias

DEF MAP_W         EQU 20
DEF MAP_H         EQU 16
DEF MAP_SIZE      EQU MAP_W * MAP_H ; raw level map tile count = width * height
DEF SCR_STRIDE    EQU 32  ; tilemap row stride is fixed at 32

DEF TILE_DIRT     EQU 0
DEF TILE_ROCK     EQU 1
DEF TILE_MONEY    EQU 3
DEF TILE_WALL     EQU 4
DEF TILE_EMPTY    EQU 5
DEF TILE_START    EQU 6
DEF TILE_UI       EQU 7
DEF PLAY_ROWS     EQU MAP_H - UI_ROWS

CHARMAP " ", 7          ; space -> tile 7 (blank)
CHARMAP "A", 19         ; A -> tile 19
CHARMAP "B", 20
CHARMAP "C", 21
CHARMAP "D", 22
CHARMAP "E", 23
CHARMAP "F", 24
CHARMAP "G", 25
CHARMAP "H", 26
CHARMAP "I", 27
CHARMAP "J", 28
CHARMAP "K", 29
CHARMAP "L", 30
CHARMAP "M", 31
CHARMAP "N", 32
CHARMAP "O", 33
CHARMAP "P", 34
CHARMAP "Q", 35
CHARMAP "R", 36
CHARMAP "S", 37
CHARMAP "T", 38
CHARMAP "U", 39
CHARMAP "V", 40
CHARMAP "W", 41
CHARMAP "X", 42
CHARMAP "Y", 43
CHARMAP "Z", 44

SECTION "Header", ROM0[$100]
  jp EntryPoint

  ds $150 - @, 0

; -----------------------------------------------------------------------------
; EntryPoint — program entry; safely disable LCD before init
; Waits for VBlank then turns LCD off so VRAM/OAM writes do not tear
; -----------------------------------------------------------------------------
EntryPoint:
  call WaitVBlank             ; defined at L1444
  ld a, 0
  ld [rLCDC], a
; Safely disable LCD at entry so tile copy, OAM reset, and BG init can run without tearing

; -----------------------------------------------------------------------------
; TitleScreen — boot init, title display, wait for key
; Resets level/lives, loads tiles, clears OAM/BG, draws PRESS ANY KEY
; Falls through to InitLevelState after key release
; -----------------------------------------------------------------------------
TitleScreen:
  ; On fresh start, initialize current level to level 1 (index 0)
  xor a
  ld [CurrentLevel], a

  ld a, 9                     ; Initialize lives
  ld [PlayerLives], a

  ; Clear suspended-rock lock on restart
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a
  
  ; Initialize palettes
  ld a,%11111100 ; monochrome sprite palette
  ld [rOBP0], a
  ld a,%11100100 ; high-contrast background palette
  ld [rBGP], a

  call   CopyTilesToVRAM      ; defined at L1467
  ld     hl, STARTOF(OAM)
  call   ResetOAM             ; defined at L1454
  ld     hl, ShadowOAM
  call   ResetOAM             ; defined at L1454
  call   InitializeObjects    ; defined at L336
  call   ResetBG              ; defined at L320; clear ShadowTilemap
  
  ; Draw title-screen text
  ld hl, ShadowTilemap        
  ld de, PressStr
  ld b, PressStr.end - PressStr
.copyWelcome:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyWelcome

  call CopyShadowTilemapToVRAM ; defined at L379

  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitKey                ; defined at L273
  
.waitTitleKeyRelease:
  call WaitVBlank             ; defined at L1444
  call readKeys               ; defined at L1489
  ld a, [previous]
  or a
  jr nz, .waitTitleKeyRelease

  xor a
  ld [current], a
  ld [previous], a
  
; -----------------------------------------------------------------------------
; InitLevelState — initialize one level
; Load map, draw UI labels, count coins, refresh digits, enable LCD
; -----------------------------------------------------------------------------
InitLevelState:
  call WaitVBlank             ; defined at L1444
  ld a, 0
  ld [rLCDC], a
  call   LoadLevel            ; defined at L1257; load map into ShadowTilemap

  ; Draw MONEY label
  ld hl, ShadowTilemap + 17 * 32 + 2
  ld de, MoneyLabelStr
  ld b, 5
.drawMoneyStr:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawMoneyStr
  
  ; Draw HP label
  ld hl, ShadowTilemap + 17 * 32 + 11 
  ld de, HPLabelStr
  ld b, 2
.drawHPStr:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawHPStr
  
  ; Initialize level UI values (money/lives)
  call CountMoneyInLevel       ; defined at L1336; count coins in current level
  call UpdatePrizeDigit        ; defined at L1422; refresh prize digit
  call UpdateHPDigit           ; defined at L1433; refresh HP digit

  call CopyShadowTilemapToVRAM ; defined at L379
  
  xor a                        ;a=0
  ld [DirtyQueueCount], a      ; clear DirtyQueueCount
  
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
  
  call WaitVBlank             ; defined at L1444

; -----------------------------------------------------------------------------
; MainLoop — per-frame game update loop
; Input -> win check -> rocks -> death -> level keys -> render flush
; -----------------------------------------------------------------------------
MainLoop:
; ----- Game logic phase -----
  call UpdateInputs           ; defined at L489; handle input and move player
  
  ; each frame: if all coins collected, trigger win/level-advance flow
  ld a, [prizeLeft]
  and a
  jp z, TriggerYouWin
  
  call RockCheck              ; defined at L780; update rock gravity
  call CheckPlayerDeath       ; defined at L1124; check player death
  call LevelControl           ; defined at L235
; ----- Render phase (VBlank-safe VRAM/OAM writes) -----
  call WaitVBlank             ; defined at L1444
  call CopyShadowOAMtoOAM     ; defined at L354; update player sprite in OAM
  call ProcessDirtyQueue      ; defined at L458; flush DirtyQueue to tilemap
  jp MainLoop


SECTION "Functions", ROM0



; -----------------------------------------------------------------------------
; LevelControl — manual level switching (debug/cheat keys)
; Start = restart level, A = next level, B = previous level
; -----------------------------------------------------------------------------
LevelControl:
  ld a, [current]        ; read current-frame key presses

.checkStart:
  bit 3, a               ; check Start key (bit 3)
  jr z, .checkA
  jp InitLevelState      ; restart current level

.checkA:
  bit 0, a               ; check A key (bit 0)
  jr z, .checkB
  ld a, [CurrentLevel]
  inc a
  cp LEVEL_AMMOUNT       ; check if past last level
  jr nz, .saveNext
  dec a                  ; clamp to last level if overflow
.saveNext:
  ld [CurrentLevel], a
  jp InitLevelState

.checkB:
  bit 1, a               ; check B key
  ret z                  ; if B not pressed, return to main loop
  ld a, [CurrentLevel]
  and a                  ; check if already on first level
  jr z, .wrapToLast
  dec a                  ; otherwise decrement level
  jr .savePrev
.wrapToLast:
  ld a, 0                ; on first level, stay on first level
.savePrev:
  ld [CurrentLevel], a
  jp InitLevelState

; -----------------------------------------------------------------------------
; WaitKey — blocking wait for any key press
; Phase 1: wait until all keys released; Phase 2: wait until any key pressed
; -----------------------------------------------------------------------------
WaitKey:
; Phase 1: wait until no keys are held
.waitRelease:
  call WaitVBlank           
  call readKeys
  ld a, [previous]          
  or a
  jr nz, .waitRelease

; Phase 2: wait until any key is newly pressed
.waitPress:
  call WaitVBlank
  call readKeys
  ld a, [current]            
  or a
  jr z, .waitPress          

  xor a
  ld [previous], a          
  ret

; -----------------------------------------------------------------------------
; WaitActionKey — blocking wait for action keys only (A/B/Select/Start)
; Ignores direction keys (masks to low 4 bits of current)
; -----------------------------------------------------------------------------
WaitActionKey:
.waitReleaseAct:
  call WaitVBlank           
  call readKeys
  ld a, [previous]          
  or a
  jr nz, .waitReleaseAct       

.waitPressAct:
  call WaitVBlank
  call readKeys
  ld a, [current]            
  and $0F                   ; mask direction keys; keep low 4 action-key bits
  jr z, .waitPressAct          

  xor a
  ld [previous], a          
  ret

; -----------------------------------------------------------------------------
; ResetBG — fill entire ShadowTilemap (1024 bytes) with TILE_EMPTY
; -----------------------------------------------------------------------------
ResetBG:
  ld hl,ShadowTilemap         
  ld bc,1024
.loop:
  ld [hl],TILE_EMPTY
  inc hl
  dec bc
  ld a,b
  or c
  jr nz,.loop
  ret

; -----------------------------------------------------------------------------
; InitializeObjects — write first ShadowOAM sprite entry (player)
; Format: Y, X, tile ID, attr (attr left as prior zero from ResetOAM)
; -----------------------------------------------------------------------------
InitializeObjects:
  ld hl,   ShadowOAM   
.init:
  ld a,32
  ld [hl], a           ; OAM byte 0: sprite Y (screen pos + 16)
  inc      hl
  ld a,32
  ld [hl], a           ; OAM byte 1: sprite X (screen pos + 8)
  inc      hl
  ld a,PLAYER_TILE_ID
  ld [hl], a           ; OAM byte 2: tile index for player sprite
  inc      hl
  inc      hl          ; skip byte 3 (attributes); already zero from ResetOAM
  ret

; -----------------------------------------------------------------------------
; CopyShadowOAMtoOAM — copy OBJCOUNT sprites from ShadowOAM to hardware OAM
; -----------------------------------------------------------------------------
CopyShadowOAMtoOAM:
  ld hl, ShadowOAM
  ld de, STARTOF(OAM)
  ld b, OBJCOUNT
; ----- Copy 4 bytes per sprite (Y, X, tile, attr) -----
.loop:
  ld a,[hl+]
  ld [de],a
  inc e
  ld a,[hl+]
  ld [de],a
  inc e
  ld a,[hl+]
  ld [de],a
  inc e
  ld a,[hl+]
  ld [de],a
  inc e
  dec b
  jr nz, .loop
  ret

; -----------------------------------------------------------------------------
; CopyShadowTilemapToVRAM — bulk copy 1024-byte ShadowTilemap to TILEMAP0
; -----------------------------------------------------------------------------
CopyShadowTilemapToVRAM:
  ld hl, ShadowTilemap
  ld de, TILEMAP0
  ld bc, 1024
; ----- Bulk copy full 32x32 shadow map to hardware tilemap -----
.loop:
  ld a, [hl+]
  ld [de], a
  inc de
  dec bc
  ld a, b
  or c
  jr nz, .loop
  ret

; -----------------------------------------------------------------------------
; QueueTileUpdate — enqueue one tile change for VBlank flush
; Input: HL = ShadowTilemap cell address, A = new tile ID
; Converts HL to VRAM address; entry = [VRAM hi][VRAM lo][tile]
; Max 64 entries per frame
; -----------------------------------------------------------------------------
QueueTileUpdate:
  push hl
  push de
  push bc
  push af
  
; queue cap 64 entries to avoid VBlank overrun
  ld a, [DirtyQueueCount]
  cp 64                      
  jr nc, .skipQueueAdd
  
; convert ShadowTilemap ptr to VRAM addr: de = hl - ShadowTilemap + TILEMAP0
; formula: VRAM addr = shadow addr - shadow base + VRAM base
; de = VRAM address, hl = ShadowTilemap address
  ld de, ShadowTilemap
  ld a, l
  sub e
  ld c, a
  ld a, h
  sbc d
  ld b, a                    
  ld hl, TILEMAP0
  add hl, bc
  ld d, h
  ld e, l               
 
; entry format: 3 bytes = VRAM high, VRAM low, TileID
; a -> current queue length
  ld a, [DirtyQueueCount]
  ld c, a
  ld b, 0
  ld hl, DirtyQueueData  
; hl = DirtyQueueData + (entry count * 3)
  add hl, bc                 
  add hl, bc
  add hl, bc
  
; hl points to next free slot; write entry
  ld [hl], d                 ; VRAM high byte
  inc hl
  ld [hl], e                 ; VRAM low byte
  inc hl
  pop af                     ; restore tile ID
  push af                    
  ld [hl], a                 ; TileID
  ld a, [DirtyQueueCount]
  inc a                      ; queue length +1
  ld [DirtyQueueCount], a
.skipQueueAdd
  pop af
  pop bc
  pop de
  pop hl
  ret

; -----------------------------------------------------------------------------
; ProcessDirtyQueue — flush all dirty queue entries to VRAM, then clear count
; -----------------------------------------------------------------------------
ProcessDirtyQueue:
  ld a, [DirtyQueueCount]
  and a
  ret z                      ; return if queue empty
  
; queue non-empty; use b as remaining entry count
  ld b, a                    
  ld hl, DirtyQueueData
.loop:
  ld d, [hl]                 
  inc hl
  ld e, [hl]                 
  inc hl
  ld a, [hl]                 
  inc hl
 
; de = write address, a = tile value
  ld [de], a                 
  dec b
  jr nz, .loop
  
; after loop, reset count to zero
  xor a
  ld [DirtyQueueCount], a    
  ret

; -----------------------------------------------------------------------------
; UpdateInputs — read keys and move player sprite in ShadowOAM
; Calls CheckMove for validation; left/right also attempt rock push
; Returns A=0 allowed / A=1 blocked from CheckMove paths
; -----------------------------------------------------------------------------
UpdateInputs:
  ld hl,ShadowOAM        ; HL -> player Y byte in ShadowOAM
  push hl
  
  call readKeys
  ; ----- Direction dispatch (newly pressed keys in C) -----
  ld a,c
  bit 5,a                ; Left
  jr nz, .moveLeft
  bit 6,a                ; Up
  jr nz, .moveUp
  bit 4,a                ; Right
  jp nz, .moveRight
  bit 7,a                ; Down
  jp nz, .moveDown
  jp .next

; ----- Move down: Y += 8 pixels -----
.moveDown
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]

  ld a,1             
  call CheckMove
  cp 1
  jp nz,.next             ; if move allowed, CheckMove already handled suspend state
  
  dec [hl]                ; move blocked; roll back coordinates
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  jp .next

; ----- Move left: X -= 8, then try rock push -----
.moveLeft
  inc hl
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  ld a,0
  call CheckMove
  cp 1
  jp nz,.next
  
; Rock push left: player tile must be rock with empty cell to the left
  ld d,h
  ld e,l
  call CountPlayerTileAddress
  ld a, [hl]
  cp TILE_ROCK
  jr nz,.LeftCantMove

; check if adjacent tile is empty
  dec hl
  ld a,[hl]
  cp TILE_EMPTY
  jr nz,.LeftCantMove

; if empty, push rock into that cell
  ld a,TILE_ROCK
  ld [hl],a
  call QueueTileUpdate

; clear original rock cell
  inc hl
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate
  
  jr .next
  
.LeftCantMove
  ld h,d
  ld l,e
  
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  jr .next

; ----- Move up: Y -= 8 pixels -----
.moveUp
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  ld a,1
  call CheckMove
  cp 1
  jr nz,.next
  
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  jr .next

; ----- Move right: X += 8, then try rock push -----
.moveRight
  inc hl
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  ld a,0
  call CheckMove
  cp 1
  jr nz,.next
  
  ; push-rock-right check
  ld d,h
  ld e,l
  call CountPlayerTileAddress
  ld a, [hl]
  cp TILE_ROCK
  jr nz,.RightCantMove
  
  inc hl
  ld a,[hl]
  cp TILE_EMPTY
  jr nz,.RightCantMove
  
  ld a,TILE_ROCK
  ld [hl],a
  call QueueTileUpdate
  
  dec hl
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate
 
  jr .next
  
.RightCantMove
  ld h,d
  ld l,e
  
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  jr .next

.next
  pop hl
  ret

; -----------------------------------------------------------------------------
; CheckMove — validate player move against bounds and target tile
; Input: HL = Y or X byte in ShadowOAM, A = 1 vertical / 0 horizontal
; Returns A=0 move OK, A=1 blocked; handles dig, coin, RockSuspended
; -----------------------------------------------------------------------------
CheckMove:
  push hl
  ; ----- Boundary check: vertical (A=1) or horizontal (A=0) -----
  cp 1
  jr nz,.XCoordinate
  
.YCoordinate
  ld a,[hl]
  cp PLAY_Y_MAX + 1
  jp nc,.WithdrawMove
  cp PLAY_Y_MIN
  jp c,.WithdrawMove
  jr .Boundarydetectioncompleted
  
.XCoordinate
  ld a,[hl]
  cp 160+4                         ; horizontal upper bound (max valid OAM X)
  jp nc,.WithdrawMove
  cp 8                             ; horizontal lower bound (min X after OAM bias)
  jp c,.WithdrawMove
  
.Boundarydetectioncompleted
  ; ----- Target tile type check under player feet -----
  call CountPlayerTileAddress
  ld a, [hl]

  cp TILE_EMPTY
  jr z, .MoveAllowed
  cp TILE_START
  jr z, .MoveAllowed
  cp TILE_MONEY
  jr z, .MoveAllowedAndChangeBG
  cp TILE_DIRT
  jr z, .MoveAllowedAndChangeBG
  jr .WithdrawMove

; Walk onto empty/start: clear suspend lock
.MoveAllowed
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a

  pop hl
  ld a, 0
  ret

; Dig dirt or collect coin: may set suspend lock if rock is directly above
.MoveAllowedAndChangeBG
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a

; Check tile above player for rock -> set RockSuspended if found
  push hl                 
  ld de, -32
  add hl, de                   ; hl now points to tile directly above
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .noRockAbove
  
; if rock above: save its address as protected target
  ld a, h
  ld [RockSuspendedH], a
  ld a, l
  ld [RockSuspendedL], a
.noRockAbove:
  pop hl                  
  
  ; coin pickup and dirt-dig logic
  ld a, [hl]              
  cp TILE_MONEY
  jr nz, .notMoneyCollected
  ld a, [prizeLeft]       
  and a
  jr z, .notMoneyCollected
  dec a                    
  ld [prizeLeft], a
  push hl
  call UpdatePrizeDigit   
  pop hl
.notMoneyCollected:
  ld a, TILE_EMPTY
  ld [hl], a              
  call QueueTileUpdate    
  
  pop hl                  
  ld a, 0
  ret

; Move rejected
.WithdrawMove
  pop hl
  ld a, 1
  ret

; -----------------------------------------------------------------------------
; RockCheck — rock gravity (vertical fall only)
; Each frame, scan all rocks in ShadowTilemap from end to start:
;   1) Skip rocks protected by RockSuspended
;   2) Try falling straight down if cell below is empty
; Uses: CheckRockMove, QueueTileUpdate
; -----------------------------------------------------------------------------
RockCheck:
.SearchForRock
  ; Scan from last tile backward (reverse order avoids same-frame conflicts)
  ld hl, ShadowTilemap + 1024 - 1  ; HL points to tile index 1023 (last byte)
  ld bc, 1024                      ; BC = remaining tiles to scan
.SearchRockLoop
  ld a, [hl]
  cp TILE_ROCK
  jp nz, .skip                     ; not a rock, skip

; ----- Dig-suspend lock: rock locked after digging does not move this frame -----
.MoveRock
  ld a, [RockSuspendedH]
  cp h                             ; compare high byte
  jr nz, .NotSuspended
  ld a, [RockSuspendedL]
  cp l                             ; compare low byte
  jr nz, .NotSuspended
  jp .skip                         ; address match, rock is protected

.NotSuspended:
; ----- Vertical gravity: fall only if cell directly below is empty -----
  ld   d,h                         ; save current rock position in DE
  ld   e,l
  ld   a,l
  add  SCR_STRIDE                  ; L += 32, same column next row down
  ld   l, a
  ld   a, h
  adc  0                           ; handle carry
  ld   h, a                        ; HL = tile directly below rock

  call CheckRockMove               ; can enter below? A=0 yes, A=1 no
  cp 1
  jr z, .RockSkip                  ; blocked, leave rock in place

  ; Can fall: clear original cell (CheckRockMove writes rock into cell below)
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate

; ----- Continue scan: restore rock address, move to previous tile -----
.RockSkip
  ld h,d                           ; restore current rock position to HL
  ld l,e
.skip
  dec hl                           ; scan previous tile
  dec bc                           ; decrement counter
  ld a, b
  or c
  jp nz, .SearchRockLoop           ; continue if not finished
  ret                              ; full map scan complete
  
; -----------------------------------------------------------------------------
; CheckRockMove — test if HL cell can accept a falling rock
; Returns A=0 moved rock into HL, A=1 blocked (rock/dirt/money/wall)
; -----------------------------------------------------------------------------
CheckRockMove:
.CheckRockMoveStart
  push de
  push hl

  ; Blocked by solid tiles; only TILE_EMPTY accepts the rock
  ld a,[hl]
  cp TILE_ROCK
  jr z, .Skip
  cp TILE_DIRT
  jr z, .Skip
  cp TILE_MONEY
  jr z, .Skip
  cp TILE_WALL
  jr z, .Skip
  cp TILE_EMPTY
  jr z, .MoveAllowedAndChangeBG
  jr .Skip

; Place rock into target cell and enqueue VRAM update
.MoveAllowedAndChangeBG
  ld a, TILE_ROCK
  ld [hl],a                
  call QueueTileUpdate    
  pop hl
  pop de
  ld a, 0
  ret
.Skip
  pop hl
  pop de
  ld a, 1
  ret
  
; -----------------------------------------------------------------------------
; CountPlayerTileAddress — convert player OAM coords to ShadowTilemap address
; Returns HL = ShadowTilemap + tile under player feet
; -----------------------------------------------------------------------------
CountPlayerTileAddress:   
  push bc
  push de
  
  ld de, ShadowOAM
  ld a, [de]
  sub OAM_Y_BIAS
  srl a
  srl a
  srl a
  ld b, a            ; b = player tile Y: tileY = (oamY - 16) / 8

  inc de
  ld a, [de]
  sub OAM_X_BIAS 
  srl a
  srl a
  srl a
  ld c, a            ; c = player tile X: tileX = (oamX - 8) / 8

  ld a, b
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl            ; hl = tileY * 32 (screen row stride)
  ld a, c
  ld e, a
  ld d, 0
  add hl, de            ; hl = tileY * 32 + tileX
  ld de, ShadowTilemap
  add hl, de            ; hl = ShadowTilemap + (tileY * 32 + tileX)
  pop de
  pop bc
  ret
  
; -----------------------------------------------------------------------------
; CheckPlayerDeath — detect rock crush, decrement lives, show death/game over
; Restores rock above player, sets RockSuspended, updates HP UI
; -----------------------------------------------------------------------------
CheckPlayerDeath:
  call CountPlayerTileAddress

  ld a, [hl]
  cp TILE_ROCK
  ret nz                 ; not crushed by rock; return

; ----- Player crushed: restore map and decrement lives -----
; Clear player cell, put rock back on tile above
  ld a, TILE_EMPTY
  ld [hl], a
  ld a, l
  sub SCR_STRIDE                     
  ld l, a
  ld a, h
  sbc 0
  ld h, a
  ld a, TILE_ROCK
  ld [hl], a
  
  ld a, h                ; suspend lock
  ld [RockSuspendedH], a
  ld a, l
  ld [RockSuspendedL], a

; decrement lives and update UI
  ld a, [PlayerLives]
  dec a
  ld [PlayerLives], a
  call UpdateHPDigit
  
; check if lives reached zero
  ld a, [PlayerLives]
  and a
  jr z, .TriggerGameOver

  ; Lives remain: flush sprites/tiles then show death overlay
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call ProcessDirtyQueue

; ----- Death overlay: YOU ARE DEAD -----
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  
; clear entire VRAM tilemap to empty
  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAM1:
  ld a, TILE_EMPTY            
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAM1

; draw "YOU ARE DEAD" centered on screen
  ld hl, TILEMAP0 + 8 * 32 + 4  
  ld de, YouAreDeadStr
  ld b, 12
.drawDeadText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawDeadText
  

; enable LCD (sprites hidden)
  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitActionKey

; before returning to map: disable LCD again
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

; write restored ShadowTilemap (fixed rock + HP) back to VRAM
  call CopyShadowTilemapToVRAM
  
; clear stale dirty queue from overlay phase
  xor a
  ld [DirtyQueueCount], a

; re-enable LCD and sprites; restore map view
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
  
  call WaitKey
  
  ret

; ----- Game over: lives reached zero -----
.TriggerGameOver:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ld hl, TILEMAP0
  ld bc, 1024
  
.clearVRAM2:
  ld a, TILE_EMPTY            
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAM2

  ld hl, TILEMAP0 + 8 * 32 + 5  
  ld de, GameOverStr
  ld b, 9
  
.drawGameOverText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawGameOverText

  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitKey
  jp EntryPoint

; -----------------------------------------------------------------------------
; LoadLevel — copy 20x16 level ROM data into 32x32 ShadowTilemap
; Sets spawn from TILE_START, pads right/bottom with TILE_UI
; -----------------------------------------------------------------------------
LoadLevel:
  call GetLevelMapAddress
  ld de, ShadowTilemap        ; DE = write cursor into ShadowTilemap
  xor a
  ld b, a                     ; B = row counter (0..MAP_H-1)

; ----- Copy MAP_W x MAP_H level tiles from ROM -----
.row:
  xor a
  ld c, a                 ; c = column counter (0..19)
  
.col:
  ld a, [hl+]
  cp TILE_START
  jr nz, .writeTile
 
; set spawn point
  push bc
  
; compute and set player X coordinate
  ld a, c
  add a
  add a
  add a
  add 8
  ld [ShadowOAM + 1], a   ; player X pixels = column*8 + 8 (OAM X bias)
  
; compute and set player Y coordinate
  ld a, b
  add a
  add a
  add a
  add OAM_Y_BIAS
  ld [ShadowOAM], a       ; player Y pixels = row*8 + 16 (OAM Y bias)
  
  pop bc
  ld a, TILE_EMPTY
  
; write tile
.writeTile:
  ld [de], a
  inc de
  inc c                   ; column count +1
  ld a, c
  cp MAP_W                    
  jr nz, .col

  push bc
  ld b, SCR_STRIDE - MAP_W; b = 32 - 20 = 12
; pad row end with UI tiles
.padLoop:
  ld a, TILE_UI
  ld [de], a
  inc de
  dec b
  jr nz, .padLoop
  pop bc
  
  inc b                   ; row count +1
  ld a, b
  cp MAP_H                    
  jr nz, .row

; ----- Fill rows below playable area with UI tiles -----
  ld hl, ShadowTilemap + (MAP_H * SCR_STRIDE)
  ld bc, 1024 - (MAP_H * SCR_STRIDE)

.fillRest:
  ld a, TILE_UI
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .fillRest
  ret

; -----------------------------------------------------------------------------
; CountMoneyInLevel — scan level ROM for TILE_MONEY, store count in prizeLeft
; -----------------------------------------------------------------------------
CountMoneyInLevel:           
  call GetLevelMapAddress     
  ld bc, MAP_SIZE            
  ld d, 0
.countLoop:
  ld a, [hl+]
  cp TILE_MONEY
  jr nz, .skipCount
  inc d
.skipCount:
  dec bc
  ld a, b
  or c
  jr nz, .countLoop
  ld a, d
  ld [prizeLeft], a          
  ret

; -----------------------------------------------------------------------------
; GetLevelMapAddress — lookup current level map pointer from LevelPointers
; Returns HL = address of LevelNMap in ROM
; -----------------------------------------------------------------------------
GetLevelMapAddress:
  ld a, [CurrentLevel]     ; a = current level index
  add a                    ; a = CurrentLevel * 2 (each pointer is 2 bytes)
  ld e, a
  ld d, 0                  ; de = a (zero-extended to 16-bit)
  ld hl, LevelPointers     
  add hl, de               ; hl = LevelPointers + CurrentLevel * 2
  
  ld a, [hl+]              ; read low byte
  ld h, [hl]               ; read high byte
  ld l, a                    
  ret

; -----------------------------------------------------------------------------
; TriggerYouWin — level cleared; advance or show ending screen
; -----------------------------------------------------------------------------
TriggerYouWin:
  ld a, [CurrentLevel]
  inc a
  cp LEVEL_AMMOUNT
  jr z, ShowEndingScreen    ; final level cleared -> ending screen

  ld [CurrentLevel], a      ; advance to next level
  jp InitLevelState


; -----------------------------------------------------------------------------
; ShowEndingScreen — clear VRAM, draw YOU WIN, wait for key, restart at EntryPoint
; -----------------------------------------------------------------------------
ShowEndingScreen:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

; ----- Clear VRAM tilemap and draw YOU WIN -----
  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAMEnding:
  ld a, TILE_EMPTY
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAMEnding

  ld hl, TILEMAP0 + 8 * 32 + 6
  ld de, YouWinStr
  ld b, 7
.drawEndingText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawEndingText

  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitKey
  jp EntryPoint               ; restart game from boot entry

; -----------------------------------------------------------------------------
; UpdatePrizeDigit — write prizeLeft as digit tile in UI row, enqueue update
; -----------------------------------------------------------------------------
UpdatePrizeDigit:
  ld a, [prizeLeft]
  add a, 9                      ; digit tile index: char '0' maps to tile 9
  ld hl, ShadowTilemap + 17 * 32 + 8 
  ld [hl], a
  call QueueTileUpdate       
  ret

; -----------------------------------------------------------------------------
; UpdateHPDigit — write PlayerLives as digit tile in UI row, enqueue update
; -----------------------------------------------------------------------------
UpdateHPDigit:
  ld a, [PlayerLives]
  add a, 9                    ; digit tile index: char '0' maps to tile 9
  ld hl, ShadowTilemap + 17 * 32 + 14 
  ld [hl], a
  call QueueTileUpdate
  ret

; -----------------------------------------------------------------------------
; WaitVBlank — spin until LCD line register reaches 144 (VBlank period)
; -----------------------------------------------------------------------------
WaitVBlank:
  ld a, [rLY]
  cp 144
  jr nz, WaitVBlank
  ret

; -----------------------------------------------------------------------------
; ResetOAM — zero 160 bytes (40 sprites x 4) starting at HL
; Caller sets HL to OAM or ShadowOAM base before call
; -----------------------------------------------------------------------------
ResetOAM:
  ld b,40*4                 ; 40 sprites x 4 bytes each
  ld a,0
.loop:
  ld [hl],a
  inc hl
  dec b
  jr nz,.loop
  ret

; -----------------------------------------------------------------------------
; CopyTilesToVRAM — copy Tiles from ROM to VRAM, doubling each byte (1bpp->2bpp)
; -----------------------------------------------------------------------------
CopyTilesToVRAM:
  ld de, Tiles
  ld hl, STARTOF(VRAM)
  ld bc, TilesEnd - Tiles
; ----- Each ROM byte is 1bpp; duplicate to two VRAM bytes for 2bpp tiles -----
.copy:
  ld a,[de]
  inc de
  ld [hl],a                 ; low tile plane
  inc hl
  ld [hl],a                 ; high tile plane (same data = monochrome)
  inc hl
  dec bc
  ld a,b
  or c
  jr nz, .copy
  ret

; -----------------------------------------------------------------------------
; readKeys — poll joypad; edge-detect new presses into current
; previous = held keys; current = newly pressed this frame; also returned in C
; -----------------------------------------------------------------------------
readKeys:
  ; ----- Read direction keys (P14) into high nibble -----
  ld    a,$20
  ldh   [rP1],a
  ldh   a,[rP1] :: ldh a,[rP1]
  cpl
  and   $0F
  swap  a
  ld    b,a

  ; ----- Read buttons (P15) into low nibble, merge with directions -----
  ld    a,$10
  ldh   [rP1],a
  ldh   a,[rP1] :: ldh a,[rP1] :: ldh a,[rP1]
  ldh   a,[rP1] :: ldh a,[rP1] :: ldh a,[rP1]
  cpl
  and   $0F
  or    b
  ld    b,a

  ; ----- Edge detect: current = newly pressed; previous = held state -----
  ld    a,[previous]
  xor   b
  and   b
  ld    [current],a
  ld    c,a
  ld    a,b
  ld    [previous],a

  ld    a,$30
  ldh   [rP1],a
  ret

SECTION "Data", ROM0
PressStr:
  DB "PRESS ANY KEY"
.end

MoneyLabelStr:
  DB "MONEY"
HPLabelStr:
  DB "HP"
YouAreDeadStr:
  DB "YOU ARE DEAD"
GameOverStr:
  DB "GAME OVER"
YouWinStr:
  DB "YOU WIN"

LevelPointers:      ; level map address table
  DW Level1Map
  DW Level2Map
  DW Level3Map
  DW Level4Map
  DW Level5Map
  DW Level6Map
  DW Level7Map
  DW Level8Map
  DW Level9Map
  DW Level10Map

Level1Map:
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 0,6,0,0,0,1,0,3,0,4,0,3,0,1,0,0,0,0,0,0
  DB 0,0,4,4,0,0,4,0,0,4,0,0,4,1,0,4,0,4,0,0
  DB 0,0,0,4,0,0,4,0,3,4,3,0,4,0,0,4,0,0,0,0
  DB 0,0,0,4,4,0,4,4,0,4,0,4,4,0,4,4,0,4,0,0
  DB 0,0,0,0,0,0,0,4,1,1,1,4,0,0,0,0,0,4,0,0
  DB 0,0,4,4,4,4,0,4,3,0,0,4,0,4,0,4,0,4,0,0
  DB 0,0,0,3,0,4,0,0,0,0,0,0,0,4,0,3,0,0,0,0
  DB 0,0,0,4,0,4,4,4,0,0,0,4,4,4,0,4,4,4,0,0
  DB 0,0,0,4,0,0,0,4,0,0,0,4,0,0,0,4,0,0,0,0
  DB 0,0,0,4,4,4,0,4,0,0,0,4,0,4,4,4,0,4,0,0
  DB 0,0,0,0,0,4,0,4,0,0,0,4,0,4,3,0,0,4,0,0
  DB 0,0,4,4,0,4,0,4,0,0,0,4,0,4,1,4,4,4,0,0
  DB 0,0,0,4,0,0,0,0,0,0,0,0,0,4,1,0,0,0,0,0
  DB 0,0,0,4,4,4,4,4,0,0,0,4,4,4,1,4,4,4,3,0
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0

Level2Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,0,0,4,0,0,0,3,4,0,0,0,3,4,0,0,1,0,4
  DB 4,0,0,0,4,0,1,0,0,4,0,1,0,0,4,0,0,0,0,4
  DB 4,0,1,0,4,0,0,0,0,0,0,0,0,0,4,0,0,3,0,4
  DB 4,0,0,0,4,4,4,0,4,4,4,0,4,4,4,0,0,0,0,4
  DB 4,3,0,0,0,0,4,0,0,0,0,0,4,0,0,0,0,0,1,4
  DB 4,0,0,0,0,0,4,0,1,0,3,0,4,0,1,0,0,0,0,4
  DB 4,0,1,0,0,0,4,0,0,0,0,0,4,0,0,0,0,3,0,4
  DB 4,0,0,0,0,0,4,4,4,0,4,4,4,0,0,0,1,0,0,4
  DB 4,0,0,0,1,0,0,0,0,0,0,0,0,0,0,4,0,0,0,4
  DB 4,4,4,0,0,0,4,0,0,0,1,0,4,0,0,4,0,0,0,4
  DB 4,0,0,0,0,0,4,0,1,0,0,0,4,0,0,4,0,0,0,4
  DB 4,0,1,0,0,0,0,0,0,0,0,0,4,0,0,4,0,1,0,4
  DB 4,0,0,0,0,4,4,4,0,4,4,4,4,0,0,4,0,0,0,4
  DB 4,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  
Level3Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,4
  DB 4,0,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,4
  DB 4,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,0,4,4,4,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,4,0,3,0,4,0,0,0,0,0,0,4
  DB 4,0,0,1,0,0,0,0,4,0,0,0,4,0,0,0,1,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,4,4,0,4,4,4,0,4,4,0,0,0,0,4
  DB 4,0,0,0,0,0,4,3,0,4,3,4,0,3,4,0,0,0,0,4
  DB 4,0,0,0,0,0,4,0,0,4,0,4,0,0,4,0,0,0,0,4
  DB 4,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level4Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,4,4,4,0,4,1,4,0,0,4,1,4,0,4,4,4,0,4
  DB 4,0,4,3,4,0,0,0,0,0,0,0,0,0,0,4,3,4,0,4
  DB 4,0,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,0,4
  DB 4,0,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,4
  DB 4,0,0,0,0,0,0,0,4,4,4,4,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,4,3,3,4,0,0,0,0,0,0,0,4
  DB 4,0,0,1,0,0,0,0,4,0,0,4,0,0,0,0,1,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,1,0,0,0,0,1,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,6,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level5Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,0,0,5,4,0,3,0,0,1,0,5,0,0,4,3,0,5,4
  DB 4,5,4,0,0,4,1,0,4,0,0,0,4,0,3,4,0,0,0,4
  DB 4,0,4,3,0,0,4,0,0,4,3,5,4,1,0,0,4,0,3,4
  DB 4,0,0,4,0,1,4,0,3,4,0,0,0,4,0,3,0,4,0,4
  DB 4,3,0,4,0,0,0,4,0,4,0,1,0,0,0,0,0,4,0,4
  DB 4,0,0,0,4,0,0,4,0,0,0,0,0,0,4,1,0,0,0,4
  DB 4,0,4,0,0,0,0,0,0,0,4,0,0,0,4,0,0,5,0,4
  DB 4,0,4,0,0,0,4,1,0,0,4,0,0,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,4,0,1,4,0,0,5,0,4,0,1,0,4
  DB 4,0,0,0,4,0,0,4,0,0,4,0,0,0,0,0,4,0,0,4
  DB 4,0,1,0,4,0,5,0,4,0,0,4,1,0,0,0,4,0,0,4
  DB 4,0,0,0,0,4,0,0,0,0,0,4,0,0,5,0,0,4,0,4
  DB 4,5,0,0,0,4,1,0,0,0,0,0,4,0,0,0,0,0,1,4
  DB 4,0,0,1,0,0,4,0,0,0,1,0,4,0,0,0,0,0,0,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level6Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,5,3,5,3,5,3,5,3,5,3,5,3,5,3,5,3,5,4
  DB 4,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,0,4
  DB 4,0,4,3,5,0,5,0,5,0,5,0,5,0,5,0,5,0,5,4
  DB 4,1,4,0,4,4,4,1,1,1,1,1,4,4,4,4,4,4,0,4
  DB 4,0,4,0,5,0,5,0,0,0,0,0,5,0,5,0,5,0,5,4
  DB 4,1,4,4,4,4,0,0,0,0,0,0,0,4,4,4,4,4,1,4
  DB 4,0,4,0,5,0,5,0,0,0,0,0,5,0,5,0,5,0,0,4
  DB 4,1,4,4,4,4,0,0,0,0,0,0,0,4,4,4,4,4,1,4
  DB 4,0,4,0,5,0,5,0,0,0,0,0,5,0,5,0,5,0,0,4
  DB 4,1,4,4,4,4,4,0,4,4,4,0,4,4,4,4,4,4,5,4
  DB 4,0,4,0,5,0,5,0,5,0,5,0,5,0,5,0,5,0,0,4
  DB 4,1,4,4,4,4,4,0,4,4,4,0,4,4,4,4,4,4,5,4
  DB 4,0,4,0,5,0,5,0,5,0,5,0,5,0,5,0,5,0,0,4
  DB 4,1,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,1,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level7Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,0,0,0,3,1,4,0,0,0,0,0,4,0,3,0,0,0,0,4
  DB 4,0,0,4,4,1,4,0,1,1,1,0,4,0,4,4,0,0,0,4
  DB 4,0,0,4,3,0,0,0,0,0,0,0,0,0,3,4,0,0,0,4
  DB 4,5,4,4,4,4,0,4,4,0,4,4,0,4,4,4,4,0,0,4
  DB 4,0,0,0,0,0,4,3,5,3,4,0,0,0,0,0,1,0,0,4
  DB 4,1,4,4,4,0,0,0,0,0,0,0,0,4,4,4,0,0,0,4
  DB 4,0,0,0,0,0,0,0,1,6,1,0,0,0,0,0,0,0,0,4
  DB 4,1,4,4,4,0,0,0,1,1,1,0,0,5,4,4,4,0,0,4
  DB 4,0,0,0,1,0,0,4,3,0,3,4,0,0,0,0,0,1,0,4
  DB 4,3,4,4,1,4,5,4,4,5,4,4,0,4,4,4,4,0,0,4
  DB 4,0,0,4,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,4
  DB 4,0,1,4,4,0,4,0,1,1,1,0,4,0,1,4,4,4,0,4
  DB 4,0,0,0,0,0,4,0,0,0,0,0,4,0,0,0,0,0,0,4
  DB 4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level8Map:
  DB 6,0,1,0,3,0,0,4,0,0,0,4,0,0,3,0,1,0,0,0
  DB 0,1,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,1,0,0
  DB 0,0,0,4,4,0,1,0,1,1,1,0,1,0,4,4,0,0,0,0
  DB 3,0,1,0,0,0,0,0,0,3,0,0,0,0,0,0,1,0,0,3
  DB 0,0,0,0,1,1,0,0,4,0,4,0,0,1,1,0,0,0,0,0
  DB 0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,4,0
  DB 0,0,0,0,0,1,0,3,0,0,0,3,0,1,0,0,0,0,0,0
  DB 0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0
  DB 0,0,0,0,0,1,0,3,0,0,0,0,0,1,0,0,0,0,0,0
  DB 0,4,4,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4,4,0
  DB 0,0,0,0,1,1,0,0,4,0,4,0,0,1,1,0,0,0,0,0
  DB 0,0,1,0,0,0,0,0,4,4,4,0,0,0,0,0,1,0,0,0
  DB 0,0,0,4,4,0,1,0,0,0,0,0,1,0,4,4,0,0,0,0
  DB 0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0,0
  DB 0,0,1,0,0,0,0,4,0,0,0,4,0,0,0,0,1,0,0,0
  DB 0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0,0

Level9Map:
  DB 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  DB 0,6,0,0,0,1,0,3,0,4,0,3,0,1,0,0,0,0,0,0
  DB 0,0,4,4,0,0,4,0,0,4,0,0,4,1,0,4,0,4,0,0
  DB 0,0,0,4,0,0,4,0,3,4,3,0,4,0,0,4,0,0,0,0
  DB 0,0,0,4,4,0,4,4,0,4,0,4,4,0,4,4,0,4,0,0
  DB 0,0,0,0,0,0,0,4,1,1,1,4,0,0,0,0,0,4,0,0
  DB 0,0,4,4,4,4,0,4,3,0,0,4,0,4,0,4,0,4,0,0
  DB 0,0,0,3,0,4,0,0,0,0,0,0,0,4,0,3,0,0,0,0
  DB 0,0,0,4,0,4,4,4,0,0,0,4,4,4,0,4,4,4,0,0
  DB 0,0,0,4,0,0,0,4,0,0,0,4,0,0,0,4,0,0,0,0
  DB 0,0,0,4,4,4,0,4,0,0,0,4,0,4,4,4,0,4,0,0
  DB 0,0,0,0,0,4,0,4,0,0,0,4,0,4,3,0,0,4,0,0
  DB 0,0,4,4,0,4,0,4,0,0,0,4,0,4,1,4,4,4,0,0
  DB 0,0,0,4,0,0,0,0,0,0,0,0,0,4,1,0,0,0,0,0
  DB 0,0,0,4,4,4,4,4,0,0,0,4,4,4,1,4,4,4,3,0
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4

Level10Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,0,0,4,0,0,0,3,4,0,0,0,3,4,0,0,1,0,4
  DB 4,0,0,0,4,0,1,0,0,4,0,1,0,0,4,0,0,0,0,4
  DB 4,0,1,0,4,0,0,0,0,0,0,0,0,0,4,0,0,3,0,4
  DB 4,0,0,0,4,4,4,0,4,4,4,0,4,4,4,0,0,0,0,4
  DB 4,3,0,0,0,0,4,0,0,0,0,0,4,0,0,0,0,0,1,4
  DB 4,0,0,0,0,0,4,0,1,0,3,0,4,0,1,0,0,0,0,4
  DB 4,0,1,0,0,0,4,0,0,0,0,0,4,0,0,0,0,3,0,4
  DB 4,0,0,0,0,0,4,4,4,0,4,4,4,0,0,0,1,0,0,4
  DB 4,0,0,0,1,0,0,0,0,0,0,0,0,0,0,4,0,0,0,4
  DB 4,4,4,0,0,0,4,0,0,0,1,0,4,0,0,4,0,0,0,4
  DB 4,0,0,0,0,0,4,0,1,0,0,0,4,0,0,4,0,0,0,4
  DB 4,0,1,0,0,0,0,0,0,0,0,0,4,0,0,4,0,1,0,4
  DB 4,0,0,0,0,4,4,4,0,4,4,4,4,0,0,4,0,0,0,4
  DB 4,0,0,3,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4



Tiles:
;0 = dirt
 DB %10101011, %01010111, %10101011, %01010111, %10101011, %00000000, %00000000, %00000000
;1 = rock
 DB %00111100, %01111110, %11011111, %11111111, %11111111, %01111110, %00111100, %00000000
;2 = player/NPC
 DB %01111110, %10000001, %10100101, %10000001, %10100101, %10011001, %10000001, %01111110
;3 = coin
 DB %00000000, %00001110, %00111110, %01111100, %01111000, %00011110, %00001110, %00000000
;4 = wall
 DB %11111111, %10011001, %11111111, %10011001, %11111111, %10011001, %11111111, %00000000
;5 = empty ground
 DB %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000
;6 = player spawn
 DB %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000
;7 = blank
 DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
;8
 DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; font glyphs
  DB $00,$3C,$66,$66,$66,$66,$3C,$00 ; 0
  DB $00,$18,$38,$18,$18,$18,$3C,$00 ; 1
  DB $00,$3C,$4E,$0E,$3C,$70,$7E,$00
  DB $00,$7C,$0E,$3C,$0E,$0E,$7C,$00
  DB $00,$3C,$6C,$4C,$4E,$7E,$0C,$00
  DB $00,$7C,$60,$7C,$0E,$4E,$3C,$00
  DB $00,$3C,$60,$7C,$66,$66,$3C,$00
  DB $00,$7E,$06,$0C,$18,$38,$38,$00
  DB $00,$3C,$4E,$3C,$4E,$4E,$3C,$00 ; 8
  DB $00,$3C,$4E,$4E,$3E,$0E,$3C,$00 ; 9
  DB $00,$3C,$4E,$4E,$7E,$4E,$4E,$00 ; letter A
  DB $00,$7C,$66,$7C,$66,$66,$7C,$00 ; letter B
  DB $00,$3C,$66,$60,$60,$66,$3C,$00 ; letter C
  DB $00,$7C,$4E,$4E,$4E,$4E,$7C,$00
  DB $00,$7E,$60,$7C,$60,$60,$7E,$00
  DB $00,$7E,$60,$60,$7C,$60,$60,$00
  DB $00,$3C,$66,$60,$6E,$66,$3E,$00
  DB $00,$46,$46,$7E,$46,$46,$46,$00
  DB $00,$3C,$18,$18,$18,$18,$3C,$00
  DB $00,$1E,$0C,$0C,$6C,$6C,$38,$00
  DB $00,$66,$6C,$78,$78,$6C,$66,$00
  DB $00,$60,$60,$60,$60,$60,$7E,$00
  DB $00,$46,$6E,$7E,$56,$46,$46,$00
  DB $00,$46,$66,$76,$5E,$4E,$46,$00
  DB $00,$3C,$66,$66,$66,$66,$3C,$00
  DB $00,$7C,$66,$66,$7C,$60,$60,$00
  DB $00,$3C,$62,$62,$6A,$64,$3A,$00
  DB $00,$7C,$66,$66,$7C,$68,$66,$00
  DB $00,$3C,$60,$3C,$0E,$4E,$3C,$00
  DB $00,$7E,$18,$18,$18,$18,$18,$00
  DB $00,$46,$46,$46,$46,$4E,$3C,$00
  DB $00,$46,$46,$46,$46,$2C,$18,$00
  DB $00,$46,$46,$56,$7E,$6E,$46,$00
  DB $00,$46,$2C,$18,$38,$64,$42,$00  ; letter X
  DB $00,$66,$66,$3C,$18,$18,$18,$00  ; letter Y
  DB $00,$7E,$0E,$1C,$38,$70,$7E,$00  ; letter Z
  DB $00,$00,$00,$00,$00,$60,$60,$00  ; .
  DB $00,$00,$00,$3C,$3C,$00,$00,$00  ; -
TilesEnd:

SECTION "Variables", WRAM0
ShadowOAM: DS 160
current: DS 1
previous: DS 1
PlayerLives: DS 1     
RockSuspendedH: DS 1  
RockSuspendedL: DS 1  
CurrentLevel:   DS 1  
ShadowTilemap: DS 1024       
DirtyQueueCount: DS 1        
DirtyQueueData: DS 64 * 3    
prizeLeft: DS 1

; -----------------------------------------------------------------------------
; Function call flow (with definition line numbers)
; 1) Boot flow
;    EntryPoint(L90)
;      -> WaitVBlank(L1444)
;      -> CopyTilesToVRAM(L1467)
;      -> ResetOAM(L1454)
;      -> InitializeObjects(L336)
;      -> ResetBG(L320)
;      -> CopyShadowTilemapToVRAM(L379)
;      -> WaitKey(L273)
;
; 2) Level init flow
;    InitLevelState(L161)
;      -> WaitVBlank(L1444)
;      -> LoadLevel(L1257)
;      -> CountMoneyInLevel(L1336)
;      -> UpdatePrizeDigit(L1422)
;      -> UpdateHPDigit(L1433)
;      -> CopyShadowTilemapToVRAM(L379)
;
; 3) Main loop flow
;    MainLoop(L208)
;      -> UpdateInputs(L489)
;          -> readKeys(L1489)
;          -> CheckMove(L677)
;              -> CountPlayerTileAddress(L1082)
;              -> UpdatePrizeDigit(L1422) [on coin pickup]
;              -> QueueTileUpdate(L400)
;          -> CountPlayerTileAddress(L1082) [rock push check]
;          -> QueueTileUpdate(L400) [enqueue map change]
;      -> RockCheck(L780)
;          -> CheckRockMove [vertical fall only]
;              -> QueueTileUpdate(L400)
;      -> CheckPlayerDeath(L1124)
;          -> CountPlayerTileAddress(L1082)
;          -> UpdateHPDigit(L1433)
;          -> WaitActionKey(L298) [death overlay]
;      -> LevelControl(L235)
;      -> WaitVBlank(L1444)
;      -> CopyShadowOAMtoOAM(L354)
;      -> ProcessDirtyQueue(L458)
;
; 4) Win flow
;    TriggerYouWin(L1374)
;      -> InitLevelState(L161) [not final level]
;      -> ShowEndingScreen(L1387) [final level]
;          -> WaitKey(L273)
