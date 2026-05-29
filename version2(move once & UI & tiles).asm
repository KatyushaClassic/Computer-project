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

CHARMAP " ", 7          ; 空格 → tile 7 (blank)
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
  call UpdateInputs
  call WaitVBlank
  call CopyShadowOAMtoOAM
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
  ld a,c                ; [改动 1] 原版: ld a,b
  bit 5,a               ; 左键
  jr nz, .moveLeft
  bit 6,a               ; 上键
  jr nz, .moveUp
  bit 4,a               ; 右键
  jr nz, .moveRight
  bit 7,a               ; 下键
  jr nz, .moveDown

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
  jr nz,.next

  call DigIfDirtAtPlayerTile
  cp 0
  jr z,.next

  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]
  dec [hl]

  jr .next

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
  jr nz,.next

  call DigIfDirtAtPlayerTile
  cp 0
  jr z,.next

  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]

  jr .next

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

  call DigIfDirtAtPlayerTile
  cp 0
  jr z,.next

  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]
  inc [hl]

  jr .next

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

  call DigIfDirtAtPlayerTile
  cp 0
  jr z,.next

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
  ld a,[hl]
  cp TILE_DIRT
  jr nz,.fail
  ld a,TILE_EMPTY
  ld [hl],a
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
  ld a, [hl]
  pop bc

  cp TILE_EMPTY
  jr z, .MoveAllowed
  cp TILE_START
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

LoadLevel:
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
current: DS 1
previous: DS 1
