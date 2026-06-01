INCLUDE "hardware.inc"

; print_level2.asm
; Only prints Level2Map from ROCK_SLIDE.asm

DEF LEVEL_W    EQU 20
DEF LEVEL_H    EQU 16
DEF LEVEL_SIZE EQU LEVEL_W * LEVEL_H

DEF TILE_START EQU 6
DEF TILE_EMPTY EQU 5
DEF TILE_PLAYER EQU 8

SECTION "Header", ROM0[$100]
  jp EntryPoint
  ds $150 - @, 0

SECTION "Code", ROM0
EntryPoint:
  call WaitVBlank
  xor a
  ld [rLCDC], a

  ld a, %11100100
  ld [rBGP], a
  ld a, %11111100
  ld [rOBP0], a

  call CopyTilesToVRAM
  call ClearTilemap
  call DrawLevel2

  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

MainLoop:
  call WaitNextFrame
  jr MainLoop

DrawLevel2:
  ld hl, Level2Map
  ld de, TILEMAP0
  ld b, LEVEL_H
.row:
  ld c, LEVEL_W
.col:
  ld a, [hl+]
  cp TILE_START
  jr nz, .store
  ld a, TILE_PLAYER
.store:
  ld [de], a
  inc de
  dec c
  jr nz, .col
  ; Skip padding columns (32 - 20 = 12)
  ld a, e
  add 12
  ld e, a
  jr nc, .noCarry
  inc d
.noCarry:
  dec b
  jr nz, .row
  call ClearUiRows
  ret

ClearUiRows:
  ; Clear row 16 and row 17 explicitly.
  ld hl, TILEMAP0 + (16 * 32)
  ld b, 2
.uiRow:
  ld c, 20
.uiCol:
  ld a, 7
  ld [hl+], a
  dec c
  jr nz, .uiCol
  ; Skip padding (32 - 20)
  ld a, l
  add 12
  ld l, a
  jr nc, .uiNoCarry
  inc h
.uiNoCarry:
  dec b
  jr nz, .uiRow
  ret

CopyTilesToVRAM:
  ld de, Tiles
  ld hl, STARTOF(VRAM)
  ld bc, TilesEnd - Tiles
.ct:
  ld a, [de]
  inc de
  ld [hl+], a
  ld [hl], a
  inc hl
  dec bc
  ld a, b
  or c
  jr nz, .ct
  ret

ClearTilemap:
  ld hl, TILEMAP0
  ld bc, 32 * 32
  ld a, TILE_EMPTY
.cl:
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .cl
  ret

WaitVBlank:
  ld a, [rLY]
  cp 144
  jr nz, WaitVBlank
  ret

WaitNextFrame:
  call WaitVBlank
.loop:
  ld a, [rLY]
  cp 144
  jr nc, .loop
  ret

SECTION "Data", ROM0
Level2Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,6,5,5,5,0,0,1,5,5,5,3,5,1,0,0,5,5,3,4
  DB 4,5,4,4,5,5,4,0,5,4,5,0,4,1,5,4,2,4,5,4
  DB 4,5,5,4,5,0,4,0,3,4,3,0,4,0,5,4,5,5,5,4
  DB 4,0,5,4,4,5,4,4,5,4,5,4,4,5,4,4,2,4,5,4
  DB 4,0,5,5,5,5,5,4,1,1,1,4,5,5,5,5,5,4,5,4
  DB 4,0,4,4,4,4,5,4,3,0,0,4,5,4,2,4,5,4,5,4
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
; 0 = Dirt
  DB %10101011,%01010111,%10101011,%01010111,%10101011,%00000000,%00000000,%00000000
; 1 = Rock
  DB %00111100,%01111110,%11011111,%11111111,%11111111,%01111110,%00111100,%00000000
; 2 = NPC
  DB %01111110,%10000001,%10100101,%10000001,%10100101,%10011001,%10000001,%01111110
; 3 = Money
  DB %00000000,%00001110,%00111110,%01111100,%01111000,%00011110,%00001110,%00000000
; 4 = Wall
  DB %11111111,%10011001,%11111111,%10011001,%11111111,%10011001,%11111111,%00000000
; 5 = Empty
  DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; 6 = Start
  DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; 7 = Blank
  DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; 8 = Player (smiley)
  DB %00111100,%01000010,%10100101,%10000001,%10100101,%10011001,%01000010,%00111100
TilesEnd:
