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
  call   ResetBG
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
  ld [hl],1 ; blank
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

  jr .next
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

CheckMove:
  cp 1
  jr nz,.XCoordinate
.YCoordinate     ; 检测 Y 边界
  ld a,[hl]

  cp PLAY_Y_MAX + 1       ; [改动 2] 原版: cp 144+12
  jr nc,.WithdrawMove

  cp PLAY_Y_MIN
  jr c,.WithdrawMove

  jr .Boundarydetectioncompleted

.XCoordinate     ; 检测 X 边界
  ld a,[hl]

  cp 160+4
  jr nc,.WithdrawMove

  cp 8
  jr c,.WithdrawMove

.Boundarydetectioncompleted

.RockDetection



.IllegalMove
  ld a,0
  ret

.WithdrawMove
  ld a,1
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


Tiles:
;0 = Dirt
  DB %11111111
  DB %10100101
  DB %11011011
  DB %10000001
  DB %11011011
  DB %10100101
  DB %11111111
  DB %01011010

;1 = Rock
  DB %00111100
  DB %01111110
  DB %11111111
  DB %11100111
  DB %11000011
  DB %11100111
  DB %01111110
  DB %00111100

;2 = NPC(smiling face)
 DB %01111110
 DB %10000001
 DB %10100101
 DB %10000001
 DB %10100101
 DB %10011001
 DB %10000001
 DB %01111110

;3 = Money
  DB %00011000
  DB %00111100
  DB %01111110
  DB %11111111
  DB %11111111
  DB %01111110
  DB %00111100
  DB %00011000

;4 = Solid wall
  DB %11111111
  DB %10000001
  DB %10111101
  DB %10100101
  DB %10111101
  DB %10000001
  DB %11111111
  DB %11111111

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
 DB 0,0,0,0,0,0,0,0

; blank
DB 0,0,0,0,0,0,0,0
DB 0,0,0,0,0,0,0,0
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
