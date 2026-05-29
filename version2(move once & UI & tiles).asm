; UpdateInputs: readKeys 后用 c（边沿）→ 每按一次方向键只走一格；b=按住（连续走）
; [改动 2] CheckMove Y 上界 + 下列常量 → 底部 UI_ROWS 行留给 UI，笑脸不可进入
INCLUDE "hardware.inc"

; 背景/窗口图块数据须在 $8000（与 CopyTilesToVRAM 一致）；缺 bit4 时 BG 读 $8800 → 整屏空/浅绿
IF !DEF(LCDC_BG8000)
  DEF LCDC_BG8000 EQU LCDC_BLOCK01
ENDC
DEF LCDC_GAME EQU LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BG8000

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
DEF UI_TEXT_ROW EQU LEVEL_H - 1
DEF PRIZE_DIGIT_COL EQU 10
DEF SHADOW_MAP_BYTES EQU LEVEL_H * MAP_STRIDE
DEF MAX_DIRTY_TILES  EQU 64
DEF SETTLE_MAX_STEPS EQU 32
DEF PRESS_ROW        EQU 8           ; 标题行（屏幕垂直居中附近）
DEF PRESS_COL        EQU 3           ; (LEVEL_W - 13) / 2，居中 "PRESS ANY KEY"
DEF PRESS_STR_LEN    EQU 13

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

SECTION "Header", ROM0[$100]
  jp EntryPoint

  ds $143 - @, 0
  db $00              ; $0143：仅 DMG
  ds $150 - @, 0

EntryPoint:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  call InitGameState

  ld a,%11111100 ; 精灵调色（保持笑脸可见）
  ld [rOBP0], a
  ld a,%11111000 ; 背景：像素0=最深色(空地近黑)
  ld [rBGP], a
  xor a
  ld [rSCX], a
  ld [rSCY], a

  call   SetVRAMBank0
  call   ClearBGAttributes
  call   CopyTilesToVRAM
  ld     hl, STARTOF(OAM)
  call   ResetOAM
  ld     hl, ShadowOAM
  xor a
  ld b, 4
.clearShadowOam:
  ld [hl+], a
  dec b
  jr nz, .clearShadowOam
  call   InitializeObjects
  call   DrawTitleScreen
  call   PositionTitleSprite

  ld a, LCDC_GAME
  ld [rLCDC], a
  call   CopyShadowOAMtoOAM

  call WaitKey
  call FlushKeyState

  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  call   SetVRAMBank0
  call   ClearBGAttributes
  call   LoadLevel
  call   CopyShadowOAMtoOAM
  ld a, LCDC_GAME
  ld [rLCDC], a
  call   PresentFrame


MainLoop:
  call UpdateInputs
  call CopyShadowOAMtoOAM
  call UpdateRocksFall
  call PresentFrame
  jp MainLoop


SECTION "Functions", ROM0

; WRAM 上电为随机值；须清零，否则 Flush 会把乱码坐标/图块号写进 VRAM
InitGameState:
  xor a
  ld [current], a
  ld [previous], a
  ld [prizeLeft], a
  ld [fallMoved], a
  ld [fallSrcRow], a
  ld [fallCol], a
  call ClearDirtyList
  ld hl, dirtyList
  ld bc, MAX_DIRTY_TILES * 2
.clearDirty:
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearDirty
  ret

WaitKey:
 call readKeys
 ld a,[current]
 or a
 jr z, WaitKey
 ret

; 清按键边沿状态，避免标题屏按键“粘住”导致进关后首帧无输入
FlushKeyState:
  xor a
  ld [previous], a
  ld [current], a
  ret

SetVRAMBank0:
  xor a
  ldh [rVBK], a
  ret

ResetBG:
  call SetVRAMBank0
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

; 标题屏：黑底 + 上下墙线 + 居中 "PRESS ANY KEY"
DrawTitleScreen:
  call ResetBG
  ld a, TILE_WALL
  ld hl, TILEMAP0 + (PRESS_ROW - 1) * MAP_STRIDE
  ld b, LEVEL_W
.borderTop:
  ld [hl+], a
  dec b
  jr nz, .borderTop
  ld hl, TILEMAP0 + (PRESS_ROW + 1) * MAP_STRIDE
  ld b, LEVEL_W
.borderBot:
  ld [hl+], a
  dec b
  jr nz, .borderBot
  ld hl, TILEMAP0 + PRESS_ROW * MAP_STRIDE + PRESS_COL
  ld de, PressStr
  ld b, PRESS_STR_LEN
.copyPress:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyPress
  call ClearBGAttributes
  ret

; 标题屏把笑脸放在文字行中央（Y>=16 才可见，避免左上角残影）
PositionTitleSprite:
  ld a, PRESS_ROW * TILE_PX + OAM_Y_BIAS
  ld [ShadowOAM], a
  ld a, (LEVEL_W / 2) * TILE_PX + 8
  ld [ShadowOAM + 1], a
  ld a, PLAYER_TILE_ID
  ld [ShadowOAM + 2], a
  xor a
  ld [ShadowOAM + 3], a
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
  xor a
  ld [hl], a           ; OAM flags=0 → CGB 精灵也用 VRAM bank 0
  ret

; 将 ShadowOAM 同步到硬件 OAM（显式 $FE00，d 必须为 $FE）
CopyShadowOAMtoOAM:
  ld hl, ShadowOAM
  ld d, $FE
  xor a
  ld e, a
  ld b, 4
.loop:
  ld a, [hl+]
  ld [de], a
  inc e
  dec b
  jr nz, .loop
  ret

UpdateInputs:
  call readKeys
  ld a, c
  bit 5, a                ; 左
  jp nz, .moveLeft
  bit 6, a                ; 上
  jp nz, .moveUp
  bit 4, a                ; 右
  jp nz, .moveRight
  bit 7, a                ; 下
  jp nz, .moveDown
  ret

.moveDown
  ld a, [ShadowOAM]
  add a, TILE_PX
  ld [ShadowOAM], a
  ld a, 1
  call CheckMove
  cp 1
  jr z, .blockedDown
  call TryCollectMoneyAtPlayerTile
  ret

.blockedDown:
  call DigIfDirtAtPlayerTile
  cp 0
  ret z
  ld a, [ShadowOAM]
  sub a, TILE_PX
  ld [ShadowOAM], a
  ret

.moveUp
  ld a, [ShadowOAM]
  sub a, TILE_PX
  ld [ShadowOAM], a
  ld a, 1
  call CheckMove
  cp 1
  jr z, .blockedUp
  call TryCollectMoneyAtPlayerTile
  ret

.blockedUp:
  call DigIfDirtAtPlayerTile
  cp 0
  ret z
  ld a, [ShadowOAM]
  add a, TILE_PX
  ld [ShadowOAM], a
  ret

.moveLeft
  ld a, [ShadowOAM + 1]
  sub a, TILE_PX
  ld [ShadowOAM + 1], a
  xor a
  call CheckMove
  cp 1
  jr z, .blockedLeft
  call TryCollectMoneyAtPlayerTile
  ret

.blockedLeft:
  call TryPushRockLeftAtPlayerTile
  cp 0
  ret z
.notPushedLeft:
  call DigIfDirtAtPlayerTile
  cp 0
  ret z
  ld a, [ShadowOAM + 1]
  add a, TILE_PX
  ld [ShadowOAM + 1], a
  ret

.moveRight
  ld a, [ShadowOAM + 1]
  add a, TILE_PX
  ld [ShadowOAM + 1], a
  xor a
  call CheckMove
  cp 1
  jr z, .blockedRight
  call TryCollectMoneyAtPlayerTile
  ret

.blockedRight:
  call TryPushRockRightAtPlayerTile
  cp 0
  ret z
.notPushedRight:
  call DigIfDirtAtPlayerTile
  cp 0
  ret z
  ld a, [ShadowOAM + 1]
  sub a, TILE_PX
  ld [ShadowOAM + 1], a
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
  sub PLAY_X_MIN
  srl a
  srl a
  srl a
  ld c,a
  ret

; 把 OAM 对齐到当前格中心（避免推石/移动后像素偏移）
SnapPlayerOAMToTile:
  push bc
  call GetPlayerTilePos
  ld a, b
  add a, a
  add a, a
  add a, a
  add OAM_Y_BIAS
  ld [ShadowOAM], a
  ld a, c
  add a, a
  add a, a
  add a, a
  add PLAY_X_MIN
  ld [ShadowOAM + 1], a
  pop bc
  ret

; 输入 b=行 c=列，输出 hl -> ShadowMap 对应格
GetShadowMapPtrBC:
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
  ld de,ShadowMap
  add hl,de
  ret

; 写 ShadowMap 格；a=tile，b=行，c=列（并记入脏格列表）
SetMapTileBC:
  push bc
  push af
  call GetShadowMapPtrBC
  pop af
  ld [hl],a
  pop bc
  push bc
  call MarkDirtyBC
  pop bc
  ret

; 仅写 ShadowMap（推石/落石内部用，不走脏格队列）
WriteShadowTileBC:
  push bc
  push af
  call GetShadowMapPtrBC
  pop af
  ld [hl], a
  pop bc
  ret

; b=行 c=列，记入脏格（供 VBlank 刷 VRAM）
MarkDirtyBC:
  push af
  push hl
  push de
  ld a, [dirtyCount]
  cp MAX_DIRTY_TILES
  jr nc, .done
  ld e, a
  ld d, 0
  ld hl, dirtyList
  add hl, de
  add hl, de
  ld a, b
  ld [hl+], a
  ld a, c
  ld [hl], a
  ld a, [dirtyCount]
  inc a
  ld [dirtyCount], a
.done:
  pop de
  pop hl
  pop af
  ret

; b=行 c=列，输出 hl -> TILEMAP0 对应格
GetVRAMTilemapPtrBC:
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

ClearDirtyList:
  xor a
  ld [dirtyCount], a
  ret

; 单格 ShadowMap -> VRAM（b=行 c=列）
RefreshVRAMTileBC:
  push bc
  call GetShadowMapPtrBC
  ld a, [hl]
  ld e, a
  pop bc
  push bc
  push de
  call GetVRAMTilemapPtrBC
  pop de
  ld a, e
  ld [hl], a
  pop bc
  ret

; 先把脏格列表刷进 VRAM，再整图同步（与 rock.asm PresentFrame 一致）
FlushDirtyMapCells:
  ld a, [dirtyCount]
  or a
  ret z
  ld b, a
  xor a
  ld c, a
.loop:
  push bc
  push hl
  ld hl, dirtyList
  ld a, c
  add a, a
  ld e, a
  ld d, 0
  add hl, de
  ld a, [hl+]
  ld b, a
  ld a, [hl]
  ld c, a
  call SetVRAMBank0
  call RefreshVRAMTileBC
  pop hl
  pop bc
  inc c
  dec b
  jr nz, .loop
  ret

; VBlank 呈现：整图同步 + OAM（每帧清空脏格，避免脏队列写坏 VRAM）
PresentFrame:
  call WaitVBlank
  call SyncShadowMapToVRAM
  call CopyShadowOAMtoOAM
  jp ClearDirtyList

FlushDirtyTilesToVRAM:
  call SyncShadowMapToVRAM
  jp ClearDirtyList

; 将 ShadowMap 同步到 VRAM（576 字节游玩区 + UI 行）
SyncShadowMapToVRAM:
  call SetVRAMBank0
  ld hl,ShadowMap
  ld de,TILEMAP0
  ld bc,SHADOW_MAP_BYTES
.loop:
  ld a,[hl+]
  ld [de],a
  inc de
  dec bc
  ld a,b
  or c
  jr nz,.loop
  ret

; 进关时：同步 ShadowMap 并清空 tilemap 剩余区域
SyncShadowMapFull:
  call SyncShadowMapToVRAM
  call SetVRAMBank0
  ld hl, TILEMAP0
  ld bc, SHADOW_MAP_BYTES
  add hl, bc
  ld d, h
  ld e, l
  ld bc, 1024 - SHADOW_MAP_BYTES
  ld a, TILE_EMPTY
.fillRest:
  ld [de], a
  inc de
  dec bc
  ld a, b
  or c
  jr nz, .fillRest
  call ClearBGAttributes
  jp ClearDirtyList

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
  call GetShadowMapPtrBC
  ld a,[hl]
  cp TILE_DIRT
  jr nz,.fail
  ld a,TILE_EMPTY
  call SetMapTileBC
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
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_MONEY
  jr nz, .done
  ld a, TILE_EMPTY
  call SetMapTileBC
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

; 玩家已挤入石头格时向左推：d=行 e=石头列，dest=e-1
; 成功 a=0（玩家留在该格，该格变为空地）
TryPushRockLeftAtPlayerTile:
  push bc
  push hl
  push de
  call GetPlayerTilePos
  ld d, b
  ld e, c
  ld a, d
  cp PLAY_ROWS
  jr nc, .fail
  ld a, e
  and a
  jr z, .fail
  ld b, d
  ld c, e
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .fail
  ld a, e
  dec a
  ld c, a
  ld b, d
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_EMPTY
  jr nz, .fail
  ld b, d
  ld c, e
  ld a, TILE_EMPTY
  call SetMapTileBC
  ld a, e
  dec a
  ld c, a
  ld b, d
  ld a, TILE_ROCK
  call SetMapTileBC
  xor a
  jr .done
.fail
  ld a, 1
.done
  pop de
  pop hl
  pop bc
  ret

; 玩家已挤入石头格时向右推：d=行 e=石头列，dest=e+1
TryPushRockRightAtPlayerTile:
  push bc
  push hl
  push de
  call GetPlayerTilePos
  ld d, b
  ld e, c
  ld a, d
  cp PLAY_ROWS
  jr nc, .fail
  ld a, e
  cp LEVEL_W - 1
  jr nc, .fail
  ld b, d
  ld c, e
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .fail
  ld a, e
  inc a
  ld c, a
  ld b, d
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_EMPTY
  jr nz, .fail
  ld b, d
  ld c, e
  ld a, TILE_EMPTY
  call SetMapTileBC
  ld a, e
  inc a
  ld c, a
  ld b, d
  ld a, TILE_ROCK
  call SetMapTileBC
  xor a
  jr .done
.fail
  ld a, 1
.done
  pop de
  pop hl
  pop bc
  ret

; 落石：每帧每列最多下落一格（多帧叠满），避免 stableLoop 卡死主循环
UpdateRocksFall:
  ld c, 0
.colLoop:
  push bc
  call FallRocksColumn
  pop bc
  inc c
  ld a, c
  cp LEVEL_W
  jr nz, .colLoop
  ret

; 单列落石：C=列，自上而下；正下方为 TILE_EMPTY 则下落一格（与 rock.asm 一致）
FallRocksColumn:
  ld a, c
  ld [fallCol], a
  ld b, PLAY_ROWS
.rowLoop:
  dec b
  ld a, b
  cp $FF
  ret z
  push bc
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .popRow
  ld a, b
  ld [fallSrcRow], a
  inc a
  cp PLAY_ROWS
  jr nc, .popRow
  ld d, a
  ld a, [fallCol]
  ld c, a
  ld b, d
  call GetShadowMapPtrBC
  ld a, [hl]
  cp TILE_EMPTY
  jr nz, .popRow
  ld a, [fallCol]
  ld c, a
  ld b, d
  push bc
  call GetShadowMapPtrBC
  ld a, TILE_ROCK
  ld [hl], a
  pop bc
  ld a, [fallSrcRow]
  ld b, a
  ld a, [fallCol]
  ld c, a
  push bc
  call GetShadowMapPtrBC
  ld a, TILE_EMPTY
  ld [hl], a
  pop bc
  ld a, 1
  ld [fallMoved], a
.popRow:
  pop bc
  jr .rowLoop

CheckMove:
  cp 1
  jr nz, .XCoordinate
.YCoordinate
  ld a, [ShadowOAM]
  cp PLAY_Y_MAX + 1
  jr nc, .WithdrawMove
  cp PLAY_Y_MIN
  jr c, .WithdrawMove
  jr .Boundarydetectioncompleted

.XCoordinate
  ld a, [ShadowOAM + 1]
  cp PLAY_X_MAX + 1
  jr nc, .WithdrawMove
  cp PLAY_X_MIN
  jr c, .WithdrawMove

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
  sub PLAY_X_MIN
  srl a
  srl a
  srl a
  ld c, a

  call GetShadowMapPtrBC
  ld a, [hl]
  pop bc

  cp TILE_EMPTY
  jr z, .MoveAllowed
  cp TILE_START
  jr z, .MoveAllowed
  cp TILE_MONEY
  jr z, .MoveAllowed
  jr .TileBlocked

.MoveAllowed
  ld a, 0
  ret

.TileBlockedUI
  pop bc
  jr .TileBlocked

.TileBlocked
  ld a, 1
  ret

.WithdrawMove
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
  push bc
  ld a, [prizeLeft]
  add a, 9
  ld b, UI_TEXT_ROW
  ld c, PRIZE_DIGIT_COL
  call SetMapTileBC
  pop bc
  ret

DrawPrizeUI:
  ld hl, ShadowMap
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

LoadLevel:
  call ClearDirtyList
  call CountMoneyInLevel
  ld hl, Level1Map
  ld de, ShadowMap
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
  add PLAY_X_MIN
  ld [ShadowOAM + 1], a
  ld a, b
  add a
  add a
  add a
  add OAM_Y_BIAS
  ld [ShadowOAM], a
  ld a, PLAYER_TILE_ID
  ld [ShadowOAM + 2], a
  xor a
  ld [ShadowOAM + 3], a
  pop bc
  ld a, TILE_EMPTY
.writeTile:
  ld [de], a
  inc de
  inc c
  ld a, c
  cp LEVEL_W
  jr nz, .col
  ; 不可用 ld d,...：d 是 de 的高字节，会破坏 ShadowMap 写指针
  push bc
  ld bc, MAP_STRIDE - LEVEL_W
.pad:
  ld a, TILE_EMPTY
  ld [de], a
  inc de
  dec bc
  ld a, b
  or c
  jr nz, .pad
  pop bc
  inc b
  ld a, b
  cp LEVEL_H
  jr nz, .row

  call DrawPrizeUI
  call SyncShadowMapFull
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
  xor [hl]
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

; CGB 下 $9C00 为 BG 属性表；须清零，否则背景去 VRAM bank 1 取图（全空=整屏浅绿）
ClearBGAttributes:
  call SetVRAMBank0
  ld hl, TILEMAP1
  ld bc, TILEMAP_AREA
  xor a
.loop:
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .loop
  ret

; 图块写入 bank 0；再复制一份到 bank 1，防止属性位误指 bank 1 时图块全空
CopyTilesToVRAM:
  call SetVRAMBank0
  ld de, Tiles
  ld hl, $8000
  ld bc, TilesEnd - Tiles
.copyB0:
  ld a,[de]
  inc de
  ld [hl],a
  inc hl
  ld [hl],a
  inc hl
  dec bc
  ld a,b
  or c
  jr nz, .copyB0
  ld a, $01
  ldh [rVBK], a
  ld de, Tiles
  ld hl, $8000
  ld bc, TilesEnd - Tiles
.copyB1:
  ld a,[de]
  inc de
  ld [hl],a
  inc hl
  ld [hl],a
  inc hl
  dec bc
  ld a,b
  or c
  jr nz, .copyB1
  jp SetVRAMBank0

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


; 关卡 20 列满宽（无左右墙列）；竖垛列 4/8/12/16：dirt→rock→money→wall
; 行 0/15 顶底墙；行 16–17 UI
Level1Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,6,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,0,5,5,5,0,5,5,5,0,5,5,5,0,5,5,5
  DB 5,5,5,5,1,5,5,5,1,5,5,5,1,5,5,5,1,5,5,5
  DB 5,5,5,5,3,5,5,5,3,5,5,5,3,5,5,5,3,5,5,5
  DB 5,5,5,5,4,5,5,5,4,5,5,5,4,5,5,5,4,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
  DB 5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
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
 DB $00,$00,$00,$00,$00,$60,$60,$00  ; .
 DB $00,$00,$00,$3C,$3C,$00,$00,$00  ; -
TilesEnd:

SECTION "Variables", WRAM0
ShadowOAM: DS 160
ShadowMap: DS SHADOW_MAP_BYTES
current: DS 1
previous: DS 1
prizeLeft: DS 1
fallMoved: DS 1
fallSrcRow: DS 1
fallCol: DS 1
dirtyCount: DS 1
dirtyList: DS MAX_DIRTY_TILES * 2
