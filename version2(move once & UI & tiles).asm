; [改动 1] UpdateInputs: readKeys 后用 c（边沿），不用 b（按住）→ 每按一次方向键只走一格
; [改动 2] CheckMove Y 上界 + 下列常量 → 底部 UI_ROWS 行留给 UI，笑脸不可进入
INCLUDE "hardware.inc"

DEF OBJCOUNT EQU 1
DEF PLAYER_TILE_ID EQU 2

; [改动 2] 底部 2 行 UI 预留（见 PLAY_Y_MAX）
DEF SCR_H       EQU 144
DEF UI_ROWS     EQU 2
DEF TILE_PX     EQU 8
DEF SPRITE_PX   EQU 8
DEF OAM_Y_BIAS  EQU 16
DEF PLAY_Y_MAX  EQU SCR_H - (UI_ROWS * TILE_PX) - SPRITE_PX + OAM_Y_BIAS
DEF PLAY_Y_MIN  EQU OAM_Y_BIAS

; 可见 20 列 × 16 行游玩区，底部 2 行 UI（LEVEL_H - UI_ROWS）
DEF LEVEL_W     EQU 20
DEF LEVEL_H     EQU 18
DEF MAP_STRIDE  EQU 32          ; GB 背景 tilemap 每行 32 格（VRAM 行宽，关卡数据仍 20 列）
DEF LEVEL_SIZE  EQU LEVEL_W * LEVEL_H
DEF PLAY_X_MIN  EQU 8
DEF PLAY_X_MAX  EQU 8 + (LEVEL_W * TILE_PX)

DEF TILE_DIRT   EQU 0
DEF TILE_ROCK   EQU 1
DEF TILE_MONEY  EQU 3
DEF TILE_WALL   EQU 4
DEF TILE_EMPTY  EQU 5
DEF TILE_START  EQU 6
DEF TILE_UI     EQU 7
DEF PLAY_ROWS   EQU LEVEL_H - UI_ROWS
DEF LIFE_TEXT_ROW EQU LEVEL_H - 2
DEF UI_TEXT_ROW EQU LEVEL_H - 1
DEF LIFE_TENS_COL EQU 5
DEF LIFE_ONES_COL EQU 6
DEF PRIZE_DIGIT_COL EQU 10

CHARMAP " ", 7          ; 空格 → tile 7 (blank)
CHARMAP "0", 9
CHARMAP "1", 10
CHARMAP "2", 11
CHARMAP "3", 12
CHARMAP "4", 13
CHARMAP "5", 14
CHARMAP "6", 15
CHARMAP "7", 16
CHARMAP "8", 17
CHARMAP "9", 18
CHARMAP "A", 19         ; A → tile 19
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
CHARMAP "!", 45

SECTION "Header", ROM0[$100]
  jp EntryPoint

  ds $150 - @, 0

EntryPoint:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ld a,%11111100 ; black and white palette
  ld [rOBP0], a
  ld a,%11100100 ; 背景四色对比，否则墙/石/土在绿屏上看不见
  ld [rBGP], a

  call   CopyTilesToVRAM
  ld     hl, STARTOF(OAM)
  call   ResetOAM
  ld     hl, ShadowOAM
  call   ResetOAM
  call   InitializeObjects
  call   ResetBG
  ld hl, TILEMAP0
  ld de, PressStr
  ld b, PressStr.end - PressStr
.copy:
  ld a,[de]
  inc de
  ld [hl+],a
  dec b
  jr nz, .copy

  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a


  call WaitKey

  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  call   LoadLevel
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a


MainLoop:
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call SaveCheckpointState
  call UpdateInputs
  call UpdateFallingRocks
  call HandlePlayerDeath
  call HandleWinCondition
  jp MainLoop


SECTION "Functions", ROM0
WaitKey:
 call readKeys
 ld a,[current]
 or a
 jr z, WaitKey
 ret

ResetBG:
  ld hl,TILEMAP0
  ld bc,1024
.loop:
  ld [hl],5 ; tile 5 = 空地（黑底）
  inc hl
  dec bc
  ld a,b
  or c
  jr nz,.loop
  ret


InitializeObjects:
  ld hl,   ShadowOAM   ; hl points to first object entry
.init:
  ld a,32
  ld [hl], a           ; set Y coordinate
  inc      hl
  ld a,32
  ld [hl], a           ; set X coordinate
  inc      hl

  ld a,PLAYER_TILE_ID
  ld [hl], a

  inc      hl

  inc      hl
  ret

CopyShadowOAMtoOAM:
  ld hl, ShadowOAM
  ld de, STARTOF(OAM)
  ld b, OBJCOUNT
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

UpdateInputs:
  ld hl,ShadowOAM       ; 人物素材坐标
  push hl
  call readKeys
  ld a,b                ; 使用按住态，避免边沿丢失导致方向无响应
  bit 5,a               ; 左键
  jp nz, .moveLeft
  bit 6,a               ; 上键
  jp nz, .moveUp
  bit 4,a               ; 右键
  jp nz, .moveRight
  bit 7,a               ; 下键
  jp nz, .moveDown

  ; 待添加：reset 功能和换关功能

  jp .next
.moveDown
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]

  ld a,1             ; a=1:Y   a=0:X
  call CheckMove
  cp 1
  jr z,.blocked

  call TryCollectMoneyAtPlayerTile
  jp .next

.blocked:
  call DigIfDirtAtPlayerTile
  cp 0
  jp z,.next

  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  jp .next

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
  jr z,.blockedLeft

  call TryCollectMoneyAtPlayerTile
  jp .next

.blockedLeft:
  call TryPushRockLeftAtPlayerTile
  cp 0
  jp z,.next

  call DigIfDirtAtPlayerTile
  cp 0
  jp z,.next

  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  jp .next

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
  jr z,.blockedUp

  call TryCollectMoneyAtPlayerTile
  jp .next

.blockedUp:
  call DigIfDirtAtPlayerTile
  cp 0
  jp z,.next

  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  jp .next

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
  jr z,.blockedRight

  call TryCollectMoneyAtPlayerTile
  jp .next

.blockedRight:
  call TryPushRockRightAtPlayerTile
  cp 0
  jp z,.next

  call DigIfDirtAtPlayerTile
  cp 0
  jp z,.next

  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  jp .next

.next
  pop hl
  ret

; 输出 b=行 c=列（玩家脚下格）
GetPlayerTilePos:
  ld a,[ShadowOAM]
  sub OAM_Y_BIAS
  srl a
  srl a
  srl a
  ld b,a
  ld a,[ShadowOAM + 1]
  sub 8
  srl a
  srl a
  srl a
  ld c,a
  ret

; 输入 b=行 c=列，输出 hl -> TILEMAP0 对应格
GetTilemapPtrBC:
  ld a,b
  ld l,a
  ld h,0
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  add hl,hl
  ld a,c
  ld e,a
  ld d,0
  add hl,de
  ld de,TILEMAP0
  add hl,de
  ret

; 玩家 OAM 已在目标格时：若是土则挖掉并留在该格（a=0），否则 a=1
DigIfDirtAtPlayerTile:
  push hl
  push bc
  call GetPlayerTilePos
  ld a,b
  cp PLAY_ROWS
  jr nc,.fail
  ld a,c
  cp LEVEL_W
  jr nc,.fail
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_DIRT
  jr nz,.fail
  ld a,TILE_EMPTY
  call WriteTileHL
  ld a,0
  jr .done
.fail
  ld a,1
.done
  pop bc
  pop hl
  ret

; 站在金币格：清空背景格、prizeLeft--、刷新底部数字
TryCollectMoneyAtPlayerTile:
  push hl
  push bc
  call GetPlayerTilePos
  ld a, b
  cp PLAY_ROWS
  jr nc, .done
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_MONEY
  jr nz, .done
  ld a, TILE_EMPTY
  call WriteTileHL
  ld a, [prizeLeft]
  and a
  jr z, .done
  dec a
  ld [prizeLeft], a
  call UpdatePrizeDigit
.done
  pop bc
  pop hl
  ret

; 玩家已移动到目标格（该格被阻挡）时，尝试把该格 rock 向左推一格
; 成功 a=0（玩家保留当前位置），失败 a=1
TryPushRockLeftAtPlayerTile:
  push hl
  push bc
  call GetPlayerTilePos
  ld a,b
  cp PLAY_ROWS
  jr nc,.fail
  ld a,c
  cp LEVEL_W
  jr nc,.fail
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_ROCK
  jr nz,.fail

  ld a,c
  and a
  jr z,.fail            ; 已在最左列，不能再推
  dec c
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_EMPTY
  jr nz,.fail
  ld a,TILE_ROCK
  call WriteTileHL

  inc c
  call GetTilemapPtrBC
  ld a,TILE_EMPTY
  call WriteTileHL
  ld a,0
  jr .done
.fail
  ld a,1
.done
  pop bc
  pop hl
  ret

; 玩家已移动到目标格（该格被阻挡）时，尝试把该格 rock 向右推一格
; 成功 a=0（玩家保留当前位置），失败 a=1
TryPushRockRightAtPlayerTile:
  push hl
  push bc
  call GetPlayerTilePos
  ld a,b
  cp PLAY_ROWS
  jr nc,.fail
  ld a,c
  cp LEVEL_W
  jr nc,.fail
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_ROCK
  jr nz,.fail

  ld a,c
  cp LEVEL_W - 1
  jr nc,.fail           ; 已在最右列，不能再推
  inc c
  call GetTilemapPtrBC
  call ReadTileHL
  cp TILE_EMPTY
  jr nz,.fail
  ld a,TILE_ROCK
  call WriteTileHL

  dec c
  call GetTilemapPtrBC
  ld a,TILE_EMPTY
  call WriteTileHL
  ld a,0
  jr .done
.fail
  ld a,1
.done
  pop bc
  pop hl
  ret

CheckMove:
  push hl             ; 保护 OAM 指针，供移动撤销 dec [hl] 使用
  cp 1
  jr nz,.XCoordinate
.YCoordinate
  ld a,[hl]
  cp PLAY_Y_MAX + 1
  jr nc,.WithdrawMove
  cp PLAY_Y_MIN
  jr c,.WithdrawMove
  jr .Boundarydetectioncompleted

.XCoordinate
  ld a,[hl]
  cp PLAY_X_MAX
  jr nc,.WithdrawMove
  cp PLAY_X_MIN
  jr c,.WithdrawMove

.Boundarydetectioncompleted
  push bc
  ld de, ShadowOAM
  ld a, [de]
  sub OAM_Y_BIAS
  srl a
  srl a
  srl a
  ld b, a

  ld a, b
  cp PLAY_ROWS
  jr nc, .TileBlockedUI

  inc de
  ld a, [de]
  sub 8
  srl a
  srl a
  srl a
  ld c, a

  ld a, b
  ld l, a
  ld h, 0
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  add hl, hl
  ld a, c
  ld e, a
  ld d, 0
  add hl, de
  ld bc, TILEMAP0
  add hl, bc
  call ReadTileHL
  pop bc

  cp TILE_EMPTY
  jr z, .MoveAllowed
  cp TILE_START
  jr z, .MoveAllowed
  cp TILE_MONEY
  jr z, .MoveAllowed
  jr .TileBlocked

.MoveAllowed
  pop hl
  ld a, 0
  ret

.TileBlockedUI
  pop bc
  jr .TileBlocked

.TileBlocked
  pop hl
  ld a, 1
  ret

.WithdrawMove
  pop hl
  ld a, 1
  ret

CountMoneyInLevel:
  ld hl, Level1Map
  ld bc, LEVEL_SIZE
  ld d, 0
.loop:
  ld a, [hl+]
  cp TILE_MONEY
  jr nz, .skip
  inc d
.skip
  dec bc
  ld a, b
  or c
  jr nz, .loop
  ld a, d
  ld [prizeLeft], a
  ret

UpdatePrizeDigit:
  ld a, [prizeLeft]
  add a, 9
  ld hl, TILEMAP0
  ld bc, UI_TEXT_ROW * MAP_STRIDE + PRIZE_DIGIT_COL
  add hl, bc
  call WriteTileHL
  ret

UpdateLivesDigits:
  ld hl, TILEMAP0
  ld bc, LIFE_TEXT_ROW * MAP_STRIDE + LIFE_TENS_COL
  add hl, bc
  ld a, [livesLeft]
  cp 10
  jr nz, .singleDigit
  ld a, 10                  ; tile "1"
  call WriteTileHL
  inc hl
  ld a, 9                   ; tile "0"
  call WriteTileHL
  ret
.singleDigit:
  ld a, 7                   ; blank
  call WriteTileHL
  inc hl
  ld a, [livesLeft]
  add a, 9                  ; 0..9 -> tile 9..18
  call WriteTileHL
  ret

; 每帧统一更新所有可下落石头（同帧完成全部调整）
; 规则：若某 rock 的正下方是 empty，则下落一格
; 扫描顺序：自底向上，避免同一石头在同帧连续多次下落
UpdateFallingRocks:
  call GetPlayerTilePos
  ld a, b
  ld [playerRow], a
  ld a, c
  ld [playerCol], a

  ld a, PLAY_ROWS - 1
  and a
  ret z
  dec a
  ld b, a                   ; b = row，从 PLAY_ROWS-2 到 0
.rowLoop:
  ld c, 0                   ; c = col，从 0 到 LEVEL_W-1
.colLoop:
  call GetTilemapPtrBC      ; hl -> 当前格
  call ReadTileHL
  cp TILE_ROCK
  jr nz, .nextCol

  ; 检查正下方
  inc b
  call GetTilemapPtrBC      ; hl -> 下方格
  call ReadTileHL
  dec b
  cp TILE_EMPTY
  jr nz, .nextCol

  ; 若 rock 下落目标格正好是玩家所在格，则标记被砸中
  inc b
  ld a, [playerRow]
  cp b
  jr nz, .noHit
  ld a, [playerCol]
  cp c
  jr nz, .noHit
  ld a, 1
  ld [playerDead], a
.noHit:
  dec b

  ; 下方置 rock
  inc b
  call GetTilemapPtrBC
  ld a, TILE_ROCK
  call WriteTileHL
  dec b

  ; 原位置清空
  call GetTilemapPtrBC
  ld a, TILE_EMPTY
  call WriteTileHL

.nextCol:
  inc c
  ld a, c
  cp LEVEL_W
  jr nz, .colLoop

  ld a, b
  and a
  ret z
  dec b
  jr .rowLoop

SaveCheckpointState:
  ld a, [ShadowOAM]
  ld [checkpointY], a
  ld a, [ShadowOAM + 1]
  ld [checkpointX], a
  ld a, [prizeLeft]
  ld [checkpointPrize], a

  ; 保存游玩区地图快照（用于死亡后回到上一步）
  ld hl, TILEMAP0
  ld de, checkpointMap
  ld b, PLAY_ROWS
.row:
  ld c, LEVEL_W
.col:
  call ReadTileHL
  ld [de], a
  inc de
  inc hl
  dec c
  jr nz, .col
  ld a, MAP_STRIDE - LEVEL_W
.skip:
  inc hl
  dec a
  jr nz, .skip
  dec b
  jr nz, .row
  ret

RestoreCheckpointState:
  ; 先恢复地图
  ld hl, TILEMAP0
  ld de, checkpointMap
  ld b, PLAY_ROWS
.row:
  ld c, LEVEL_W
.col:
  ld a, [de]
  inc de
  call WriteTileHL
  inc hl
  dec c
  jr nz, .col
  ld a, MAP_STRIDE - LEVEL_W
.skip:
  inc hl
  dec a
  jr nz, .skip
  dec b
  jr nz, .row

  ; 再恢复玩家坐标与奖品计数
  ld a, [checkpointY]
  ld [ShadowOAM], a
  ld a, [checkpointX]
  ld [ShadowOAM + 1], a
  ld a, [checkpointPrize]
  ld [prizeLeft], a
  ret

HandlePlayerDeath:
  ld a, [playerDead]
  and a
  ret z
  xor a
  ld [playerDead], a

  ld a, [livesLeft]
  and a
  jp z, GameOverScreen
  dec a
  ld [livesLeft], a
  and a
  jp z, GameOverScreen

  ; 还有命：显示继续页面，按空格后回到死亡前一步（含地图复原）
  call ContinuePromptScreen
  call WaitVBlank
  xor a
  ld [rLCDC], a
  call ResetBG
  call RestoreCheckpointState
  call DrawLivesUI
  call DrawPrizeUI
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
  ret

ContinuePromptScreen:
  call WaitVBlank
  xor a
  ld [rLCDC], a
  call ResetBG

  ld hl, TILEMAP0 + (7 * MAP_STRIDE) + 6
  ld de, DeadStr
  ld b, DeadStr.end - DeadStr
.copyDead:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyDead

  ld hl, TILEMAP0 + (9 * MAP_STRIDE) + 4
  ld de, ContinueStr1
  ld b, ContinueStr1.end - ContinueStr1
.copyContinue1:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyContinue1

  ld hl, TILEMAP0 + (10 * MAP_STRIDE) + 4
  ld de, ContinueStr2
  ld b, ContinueStr2.end - ContinueStr2
.copyContinue2:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyContinue2

  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

.waitSpace:
  call readKeys
  ld a, b
  and a
  ret nz
  jr .waitSpace

GameOverScreen:
  call WaitVBlank
  xor a
  ld [rLCDC], a
  call ResetBG
  ld hl, TILEMAP0 + (8 * MAP_STRIDE) + 6
  ld de, GameOverStr
  ld b, GameOverStr.end - GameOverStr
.copy:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copy
  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
.halt:
  jp .halt

HandleWinCondition:
  ld a, [prizeLeft]
  and a
  ret nz
  jp WinScreen

WinScreen:
  call WaitVBlank
  xor a
  ld [rLCDC], a
  call ResetBG
  ld hl, TILEMAP0 + (8 * MAP_STRIDE) + 6
  ld de, WinStr
  ld b, WinStr.end - WinStr
.copy:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copy
  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
.halt:
  jp .halt

DrawPrizeUI:
  ld hl, TILEMAP0
  ld bc, UI_TEXT_ROW * MAP_STRIDE
  add hl, bc
  ld de, PrizeUiLine
  ld b, PrizeUiLine.end - PrizeUiLine
.copy:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copy
  call UpdatePrizeDigit
  ret

DrawLivesUI:
  ld hl, TILEMAP0
  ld bc, LIFE_TEXT_ROW * MAP_STRIDE
  add hl, bc
  ld de, LifeUiLine
  ld b, LifeUiLine.end - LifeUiLine
.copy:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copy
  call UpdateLivesDigits
  ret

LoadLevel:
  call CountMoneyInLevel
  ld a, 10
  ld [livesLeft], a
  xor a
  ld [playerDead], a
  ld hl, Level1Map
  ld de, TILEMAP0
  xor a
  ld b, a
.row:
  xor a
  ld c, a
.col:
  ld a, [hl+]
  cp TILE_START
  jr nz, .writeTile
  push bc
  ld a, c
  add a
  add a
  add a
  add 8
  ld [ShadowOAM + 1], a
  ld a, b
  add a
  add a
  add a
  add OAM_Y_BIAS
  ld [ShadowOAM], a
  pop bc
  ld a, TILE_EMPTY
.writeTile:
  ld [de], a
  inc de
  inc c
  ld a, c
  cp LEVEL_W
  jr nz, .col
  ld a, MAP_STRIDE - LEVEL_W
.pad:
  inc de
  dec a
  jr nz, .pad
  inc b
  ld a, b
  cp LEVEL_H
  jr nz, .row

  ld bc, 1024 - (LEVEL_H * MAP_STRIDE)
.fillRest:
  ld a, TILE_EMPTY
  ld [de], a
  inc de
  dec bc
  ld a, b
  or c
  jr nz, .fillRest
  call DrawLivesUI
  call DrawPrizeUI
  call SaveCheckpointState
  ret

Random2bits:
  push bc
  call RandomByte
  ld b,a

  swap a
  xor b
  ld b,a
  rrca
  rrca
  xor b

  and %00000011
  pop bc
  ret


RandomByte:
  ld a,[rDIV]
  xor b
  xor l
  push de
  ld d,a
  call ReadTileHL
  ld e,a
  ld a,d
  xor e
  pop de
  ret

WaitVRAMReady:
.loop:
  ldh a,[rSTAT]
  and %00000011
  cp 3
  jr z,.loop
  ret

ReadTileHL:
  call WaitVRAMReady
  ld a,[hl]
  ret

WriteTileHL:
  push bc
  ld b,a
  call WaitVRAMReady
  ld a,b
  ld [hl],a
  pop bc
  ret

WaitVBlank:
  ld a, [rLY]
  cp 144
  jr nz, WaitVBlank
  ret

ResetOAM:
  ld b,40*4
  ld a,0
.loop:
  ld [hl],a
  inc hl
  dec b
  jr nz,.loop
  ret

CopyTilesToVRAM:
  ld de, Tiles
  ld hl, STARTOF(VRAM)
  ld bc, TilesEnd - Tiles
.copy:
  ld a,[de]
  inc de
  ld [hl],a
  inc hl
  ld [hl],a
  inc hl
  dec bc
  ld a,b
  or c
  jr nz, .copy
  ret

readKeys:
  ld    a,$20
  ldh   [rP1],a
  ldh   a,[rP1] :: ldh a,[rP1]
  cpl
  and   $0F
  swap  a
  ld    b,a
  ld    a,$10
  ldh   [rP1],a
  ldh   a,[rP1] :: ldh a,[rP1] :: ldh a,[rP1]
  ldh   a,[rP1] :: ldh a,[rP1] :: ldh a,[rP1]
  cpl
  and   $0F
  or    b
  ld    b,a

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

PrizeUiLine:
  DB "PRIZELEFT "
.end

LifeUiLine:
  DB "LIFE  "
.end

DeadStr:
  DB "YOU DIED"
.end

ContinueStr1:
  DB "PRESS SPACE"
.end

ContinueStr2:
  DB "TO CONTINUE"
.end

GameOverStr:
  DB "GAME OVER"
.end

WinStr:
  DB "YOU WIN!"
.end


; 关卡 20 列满宽（无左右墙列）；竖垛列 4/8/12/16：dirt→rock→money→wall
; 行 0/15 顶底墙；行 16–17 UI
Level1Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,5,0,0,1,5,3,5,4,5,3,5,1,0,0,5,5,5,4
  DB 4,5,4,4,5,1,4,0,5,4,5,0,4,1,5,4,4,4,5,4
  DB 4,5,5,4,5,0,4,0,3,4,3,0,4,0,5,4,5,5,5,4
  DB 4,0,5,4,4,5,4,4,5,4,5,4,4,5,4,4,5,4,5,4
  DB 4,0,5,5,5,5,5,4,1,1,1,4,5,5,5,5,5,4,5,4
  DB 4,0,4,4,4,4,5,4,0,3,0,4,5,4,4,4,5,4,5,4
  DB 4,0,5,3,5,4,5,5,5,0,5,5,5,4,5,3,5,5,5,4
  DB 4,0,5,4,5,4,4,4,5,0,5,4,4,4,5,4,4,4,5,4
  DB 4,0,5,4,5,5,5,4,5,0,5,4,5,5,5,4,5,5,5,4
  DB 4,0,5,4,4,4,5,4,5,0,5,4,5,4,4,4,5,4,5,4
  DB 4,0,5,5,5,4,5,4,5,0,5,4,5,4,3,5,5,4,5,4
  DB 4,0,4,4,5,4,5,4,5,0,5,4,5,4,1,4,4,4,5,4
  DB 4,0,5,4,5,5,5,5,5,0,5,5,5,4,1,5,5,5,5,4
  DB 4,0,5,4,4,4,4,4,5,0,5,4,4,4,1,4,4,4,3,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7


Tiles:
;0 = Dirt
 DB %10101011
 DB %01010111
 DB %10101011
 DB %01010111
 DB %10101011
 DB %00000000
 DB %00000000
 DB %00000000

;1 = Rock
 DB %00111100
 DB %01111110
 DB %11011111
 DB %11111111
 DB %11111111
 DB %01111110
 DB %00111100
 DB %00000000

;2 = NPC
 DB %01111110
 DB %10000001
 DB %10100101
 DB %10000001
 DB %10100101
 DB %10011001
 DB %10000001
 DB %01111110

;3 = Money
 DB %00000000
 DB %00001110
 DB %00111110
 DB %01111100
 DB %01111000
 DB %00011110
 DB %00001110
 DB %00000000

;4 = Wall
 DB %11111111
 DB %10011001
 DB %11111111
 DB %10011001
 DB %11111111
 DB %10011001
 DB %11111111
 DB %00000000

;5 = Empty space
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000

;6 = Player start
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000
 DB %00000000

;7 = Blank — CHARMAP
DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
;8
DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; digits and letters
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
 DB $00,$3C,$4E,$4E,$7E,$4E,$4E,$00 ; A
 DB $00,$7C,$66,$7C,$66,$66,$7C,$00 ; B
 DB $00,$3C,$66,$60,$60,$66,$3C,$00 ; C
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
 DB $00,$46,$2C,$18,$38,$64,$42,$00  ; X
 DB $00,$66,$66,$3C,$18,$18,$18,$00  ; Y
 DB $00,$7E,$0E,$1C,$38,$70,$7E,$00  ; Z
 DB $00,$18,$18,$18,$18,$00,$18,$00  ; !
 DB $00,$00,$00,$3C,$3C,$00,$00,$00  ; -
TilesEnd:

SECTION "Variables", WRAM0
ShadowOAM: DS 160
current: DS 1
previous: DS 1
prizeLeft: DS 1
livesLeft: DS 1
playerDead: DS 1
playerRow: DS 1
playerCol: DS 1
checkpointY: DS 1
checkpointX: DS 1
checkpointPrize: DS 1
checkpointMap: DS PLAY_ROWS * LEVEL_W
