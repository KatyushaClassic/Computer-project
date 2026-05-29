; [改动 1] UpdateInputs: readKeys 后用 c（边沿），不用 b（按住）→ 每按一次方向键只走一格
; [改动 2] CheckMove Y 上界 + 下列常量 → 底部 UI_ROWS 行留给 UI，笑脸不可进入
; [改动 3] 所有 tilemap 读写改为 WRAM 影子地图 (ShadowTilemap)，仅在 VBlank 同步到 VRAM
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

DEF LEVEL_W     EQU 32
DEF LEVEL_H     EQU 18
DEF LEVEL_SIZE  EQU LEVEL_W * LEVEL_H

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
  call   ResetBG              ; [改动 3] 现在清空的是 ShadowTilemap
  ld hl, ShadowTilemap        ; [改动 3] 标题文字写入 ShadowTilemap（原 TILEMAP0）
  ld de, PressStr
  ld b, PressStr.end - PressStr
.copy:
  ld a,[de]
  inc de
  ld [hl+],a
  dec b
  jr nz, .copy

  ; [改动 3] 修复白屏：去掉了这里的 WaitVBlank（LCD 关闭时 rLY 不递增会死循环）
  ; LCD 已关闭，此时写 VRAM 绝对安全，直接同步即可
  call CopyShadowTilemapToVRAM

  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a


  call WaitKey

  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  call   LoadLevel            ; [改动 3] 关卡数据加载到 ShadowTilemap
  call CopyShadowTilemapToVRAM; [改动 3] 开屏前同步到 VRAM
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a


MainLoop:
  call UpdateInputs           ; [改动 3] 逻辑操作 ShadowTilemap（WRAM，随时安全）
  call RockCheck              ; [改动 3] 逻辑操作 ShadowTilemap（WRAM，随时安全）
  call WaitVBlank
  call CopyShadowOAMtoOAM
  ; [改动 4] 删除了耗时极长的全量复制 call CopyShadowTilemapToVRAM，改为按需局部更新
  jp MainLoop


SECTION "Functions", ROM0
WaitKey:
 call readKeys
 ld a,[current]
 or a
 jr z, WaitKey
 ret

ResetBG:
  ld hl,ShadowTilemap         ; [改动 3] 清空 ShadowTilemap（原 TILEMAP0）
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

; [改动 3] 新增：将 ShadowTilemap (WRAM) 整体复制到 VRAM TILEMAP0
CopyShadowTilemapToVRAM:
  ld hl, ShadowTilemap
  ld de, TILEMAP0
  ld bc, 1024
.loop:
  ld a, [hl+]
  ld [de], a
  inc de
  dec bc
  ld a, b
  or c
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
  cp 160+4
  jr nc,.WithdrawMove
  cp 8
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
  push hl             ; [改动 3] 保存 tilemap 索引到栈
  ld bc, ShadowTilemap  ; [改动 3] 碰撞检测读 ShadowTilemap（原 TILEMAP0）
  add hl, bc
  ld a, [hl]          ; a = tile value
  pop hl              ; [改动 3] 恢复索引到 hl（供后续写入使用）
  pop bc

  cp TILE_EMPTY
  jr z, .MoveAllowed

  cp TILE_START
  jr z, .MoveAllowed
  cp TILE_MONEY
  ;待添加：金币计数器
  jr z, .MoveAllowedAndChangeBG
  cp TILE_DIRT
  jr z, .MoveAllowedAndChangeBG
  
  jr .TileBlocked
 

.MoveAllowed
  pop hl
  ld a, 0
  ret
  
.MoveAllowedAndChangeBG    ;改成空
  push bc                  ; [改动 3] 保护 bc
  ld bc, ShadowTilemap     ; [改动 3] hl(索引) + bc(基址) = WRAM 地址
  add hl, bc
  ld a, TILE_EMPTY
  ld [hl],a                ; [改动 3] 修复白屏/吃土失效：现在正确写入 ShadowTilemap

  ; [改动 4] 新增：将改动局部同步更新至 VRAM
  push hl
  ld bc, TILEMAP0 - ShadowTilemap
  add hl, bc
  call WriteVRAMSafe
  pop hl
  ; [改动 4] 结束

  pop bc                  ; [改动 3] 恢复 bc
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

; [改动 4] 彻底重构了 RockCheck 逻辑，极大优化指令周期并按需更新 VRAM
RockCheck:
  ; 只扫描实际游戏区域，跳过无用的底层内存。从倒数第二行开始扫描
  ld hl, ShadowTilemap + LEVEL_SIZE - 1 - LEVEL_W 
  ld bc, LEVEL_SIZE - LEVEL_W

.SearchRockLoop:
  ld a, [hld]        ; 利用 hld 自动递减
  cp TILE_ROCK
  jr nz, .NextTile

.MoveRock:
  inc hl             ; 补回 hld 多减的 1
  ld d, h            ; de 保存原石头地址
  ld e, l

  push bc            ; 保护主循环计数器

  ld bc, LEVEL_W
  add hl, bc         ; hl 现在是正下方的地址

  call CheckRockMove
  cp 0               ; 0 表示可以移动（CheckRockMove 内部已将其变成石头）
  jr z, .RockMoved

  ; 检测左下 (hl - 1)
  dec hl
  call CheckRockMove
  cp 0
  jr z, .RockMoved

  ; 检测右下 (刚才减了1，现在要加2才能到右边)
  inc hl
  inc hl
  call CheckRockMove
  cp 0
  jr z, .RockMoved

  ; 都不行，石头不能动
  ld h, d            ; 恢复 hl 指向原石头
  ld l, e
  pop bc             ; 恢复计数器
  dec hl             ; 移到前一个 tile 以继续循环
  jp .NextTile       ; [改动 4] 距离可能过长，采用 jp 确保不越界

.RockMoved:
  ; 石头已经掉下去了，把老位置清空
  ld h, d
  ld l, e
  ld a, TILE_EMPTY
  ld [hl], a         ; [改动 4] 更新 WRAM 原位置为空

  ; [改动 4] 新增：同步更新 VRAM 的老位置为空
  push hl
  push bc
  ld bc, TILEMAP0 - ShadowTilemap
  add hl, bc
  call WriteVRAMSafe
  pop bc
  pop hl
  ; [改动 4] 结束

  pop bc             ; 恢复计数器
  dec hl             ; 移到前一个 tile 以继续循环

.NextTile:
  dec bc
  ld a, b
  or c
  jp nz, .SearchRockLoop
  ret
  
; [改动 4] 优化了 CheckRockMove，精简冗余判断并按需更新 VRAM
CheckRockMove:        
  ld a, [hl]
  
  cp TILE_EMPTY
  jr z, .MoveAllowedAndChangeBG
  
  cp PLAYER_TILE_ID
  jr z, .Die
  
  ; 不是空地和玩家，统统视为阻挡
  ld a, 1            
  ret

.MoveAllowedAndChangeBG:
  ld a, TILE_ROCK
  ld [hl], a         ; [改动 4] 写入 WRAM 新位置为石头

  ; [改动 4] 新增：同步更新 VRAM 新位置为石头
  push hl
  ld bc, TILEMAP0 - ShadowTilemap
  add hl, bc
  call WriteVRAMSafe
  pop hl
  ; [改动 4] 结束

  xor a              ; 相当于 ld a, 0
  ret

.Die:
  ld a, 1            
  ret
  
LoadLevel:
  ld hl, Level1Map
  ld de, ShadowTilemap       ; [改动 3] 关卡加载到 ShadowTilemap（原 TILEMAP0）
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
  inc b
  ld a, b
  cp LEVEL_H
  jr nz, .row

  ld hl, ShadowTilemap + LEVEL_SIZE  ; [改动 3] 填充剩余（原 TILEMAP0）
  ld bc, 1024 - LEVEL_SIZE
.fillRest:
  ld a, TILE_EMPTY
  ld [hl+], a
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

; [改动 4] 新增：安全写入 VRAM 的辅助函数
WriteVRAMSafe:
  push af
.waitSTAT
  ldh a, [rSTAT]
  and 2             ; 检测 LCD 是否在读取 VRAM (Mode 2 或 3)
  jr nz, .waitSTAT  ; 如果是，则等待安全周期
  pop af
  ld [hl], a        ; 抓准时机，安全写入
  ret


SECTION "Data", ROM0
PressStr:
  DB "PRESS ANY KEY"
.end


Level1Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,0,0,0,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,3,3,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,3,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,6,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7


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
ShadowTilemap: DS 1024       ; [改动 3] 新增：tilemap 的 WRAM 影子（1024 字节）