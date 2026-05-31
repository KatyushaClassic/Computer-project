; [改动 1] UpdateInputs: readKeys 后用 c（边沿），不用 b（按住）→ 每按一次方向键只走一格
; [改动 2] CheckMove Y 上界 + 下列常量 → 底部 UI_ROWS 行留给 UI，笑脸不可进入
; [改动 3] 所有 tilemap 读写改为 WRAM 影子地图 (ShadowTilemap)，仅在 VBlank 同步到 VRAM
; [改动 4] 增加脏区，改善vblank
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
  
  ld a, 3                     ;初始化生命值
  ld [PlayerLives], a

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
  
  xor a                       ; [改动 4] 开屏前初始化脏区队列为空
  ld [DirtyQueueCount], a
  
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a


MainLoop:
  call UpdateInputs           ; [改动 3] 逻辑操作 ShadowTilemap（WRAM，随时安全）
  call RockCheck              ; [改动 3] 逻辑操作 ShadowTilemap（WRAM，随时安全）
  call CheckPlayerDeath
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call ProcessDirtyQueue      ; [改动 4] VBlank 中一次性仅将发生变化的 Tile 刷入 VRAM
  
  jp MainLoop


SECTION "Functions", ROM0

WaitKey:
  ; 【第一步】安全防抖：先等待当前按下的所有按键全部释放
  ; 防止走入格子砸死时，玩家还没来得及松开的方向键直接触发解除冻结
.waitRelease:
  call WaitVBlank           ; 降速到帧率（1/60秒），杜绝 CPU 级别的超高速按键抖动
  call readKeys
  ld a, [previous]          ; 检查当前是否有任何按键正被按住
  or a
  jr nz, .waitRelease       ; 如果还有键没松开，继续等待

  ; 【第二步】真正等待玩家按下任意新按键
.waitPress:
  call WaitVBlank
  call readKeys
  ld a, [current]           ; 检查是否有新的按键边沿触发
  or a
  jr z, .waitPress          ; 没有按键按下则继续死循环等待

  ; 【第三步】核心修复：退出前强行清空上一帧按键映射
  xor a
  ld [previous], a          ; 擦除历史记录！
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

; [改动 3]：将 ShadowTilemap (WRAM) 整体复制到 VRAM TILEMAP0
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

; [改动 4] 将更新的 Tile 加入脏区队列
; 约定: 调用前 hl 为 ShadowTilemap 内的绝对地址, a 为新写入的 TileID
QueueTileUpdate:
  push hl
  push de
  push bc
  push af

  ld a, [DirtyQueueCount]
  cp 64                      ; [改动 4] 限制最大入队 64 个，防止队列溢出破坏 WRAM
  jr nc, .skipQueueAdd

  ; 计算出对等在 VRAM 的目标地址 (de = hl - ShadowTilemap + TILEMAP0)
  ld de, ShadowTilemap
  ld a, l
  sub e
  ld c, a
  ld a, h
  sbc d
  ld b, a                    ; bc = 在 Map 里的偏移量

  ld hl, TILEMAP0
  add hl, bc
  ld d, h
  ld e, l                    ; de = 最终算出的 VRAM 目标写入地址

  ; 获取当前队列尾部写入指针
  ld a, [DirtyQueueCount]
  ld c, a
  ld b, 0
  ld hl, DirtyQueueData
  add hl, bc                 ; 每项占 3 字节，所以需要加三次 bc
  add hl, bc
  add hl, bc

  ; 写入队列 (格式: VRAM高位, VRAM低位, TileID)
  ld [hl], d                 ; 存高位
  inc hl
  ld [hl], e                 ; 存低位
  inc hl
  pop af                     ; 临时弹回刚才要存的 TileID
  push af                    ; 再压回，防止影响调用者
  ld [hl], a                 ; 存 TileID

  ; 计数器 +1
  ld a, [DirtyQueueCount]
  inc a
  ld [DirtyQueueCount], a

.skipQueueAdd
  pop af
  pop bc
  pop de
  pop hl
  ret

; [改动 4] 消耗脏区队列：在 VBlank 时把队列中的元素真正刷到 VRAM
ProcessDirtyQueue:
  ld a, [DirtyQueueCount]
  and a
  ret z                      ; 如果队列空，直接返回，不消耗周期

  ld b, a                    ; b 作为循环倒数计数
  ld hl, DirtyQueueData
.loop:
  ld d, [hl]                 ; 提取 VRAM 高地址
  inc hl
  ld e, [hl]                 ; 提取 VRAM 低地址
  inc hl
  ld a, [hl]                 ; 提取新 TileID
  inc hl
  ld [de], a                 ; 快速写入真正的 VRAM
  dec b
  jr nz, .loop

  xor a
  ld [DirtyQueueCount], a    ; 一次性将队列清空
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
  push bc                 ; [改动 3] 保护 bc
  ld bc, ShadowTilemap    ; [改动 3] hl(索引) + bc(基址) = WRAM 地址
  add hl, bc
  ld a, TILE_EMPTY
  ld [hl],a               ; [改动 3] 修复白屏/吃土失效：现在正确写入 ShadowTilemap
  call QueueTileUpdate    ; [改动 4] 玩家走过的地方变更为了空地，推入队列中
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

RockCheck:
.SearchForRock
  ld hl, ShadowTilemap + 1024 - 1  ; [改动 3] 扫描 ShadowTilemap（原 TILEMAP0）
  ld bc, 1024
  
.SearchRockLoop
  ld a, [hl]                   ; 读取当前 tile 编号
  cp TILE_ROCK                 
  jp nz, .skip
  
  ;检测到石头
.MoveRock
  ld   d,h          ; hl = 原地址
  ld   e,l
  ld   a,l
  add  LEVEL_W        ; 加上 32
  ld   l, a
  ld   a, h
  adc  0              ; 处理进位
  ld   h, a           ; hl 现在是正下方的地址
  
  call CheckRockMove
  cp 1
  jr z,.CheckMoveRight
  
  ;将石头这格设为空（此时已经可以移动）
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       ; [改动 4] 坠落产生空位，入队
  jr .RockSkip
  
.CheckMoveRight
  
  ;[改动 5]下方是石头才进行左右检测
  ld a,[hl]
  cp TILE_ROCK
  jr nz,.RockSkip

  .ContinueCheckMoveRight
  ;检测向左下移动是否可以（不清楚先左还是右,无需检测玩家死亡）
  ;往上再往左,检测左边
  dec hl
  
  ld   a,l               ;hl-32
  sub  LEVEL_W 
  ld   l, a
  ld   a, h
  sbc  0              
  ld   h, a
  
  ld a,[hl]
  cp TILE_ROCK
  jr z, .CheckMoveLeft
  cp TILE_DIRT
  jr z, .CheckMoveLeft
  cp TILE_MONEY
  jr z, .CheckMoveLeft
  cp TILE_WALL
  jr z, .CheckMoveLeft
 
  ;左下方检测
  ld   a,l               ;hl+32
  add  LEVEL_W 
  ld   l, a
  ld   a, h
  adc  0              
  ld   h, a   

  
  call CheckRockMove
  cp 1
  jr z,.ReturnHL
  
  ;将石头这格设为空（此时已经可以移动）
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       ; [改动 4] 产生空位，入队
  jr .RockSkip
  
.ReturnHL
  ld   a,l               ;hl-32
  sub  LEVEL_W 
  ld   l, a
  ld   a, h
  sbc  0              
  ld   h, a     
  
.CheckMoveLeft
  ;右方检测
  inc hl
  inc hl
  
  ld a,[hl]
  cp TILE_ROCK
  jr z, .RockSkip
  cp TILE_DIRT
  jr z, .RockSkip
  cp TILE_MONEY
  jr z, .RockSkip
  cp TILE_WALL
  jr z, .RockSkip
  
  ;右下方检测
  ld   a,l               ;hl+32
  add  LEVEL_W 
  ld   l, a
  ld   a, h
  adc  0              
  ld   h, a   
  
  call CheckRockMove
  cp 1
  jr z,.RockSkip
  
  ;将石头这格设为空（此时已经可以移动）
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       ; [改动 4] 产生空位，入队
  jr .RockSkip              ; [改动 3] 统一跳 .RockSkip（原 .skip）

.RockSkip                    ;因为石头会改hl值，所以需要重新赋值
  ld h,d
  ld l,e
  
.skip
  dec hl                       ; 地址 -1 → 向左移动一格（到上一行末尾）
  dec bc                       
  ld a, b
  or c
  jp nz, .SearchRockLoop
  ret
  
CheckRockMove:        ;返回0就是可以移动，1就是不可以移动
.CheckRockMoveStart
  push de             ; 保护 OAM 指针，供移动撤销 dec [hl] 使用
  push hl
  

.Boundarydetectioncompleted
  ;检测该格是什么，empty就继续
  
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
  
.MoveAllowedAndChangeBG    ;改成石头
  ld a, TILE_ROCK
  ld [hl],a               ; [改动 3] 现在写的是 ShadowTilemap（安全）
  call QueueTileUpdate    ; [改动 4] 新位置变成了石头，将修改推入同步队列
  pop hl
  pop de
  ld a, 0
  ret


.Skip
  pop hl
  pop de
  ld a, 1
  ret
  
CheckPlayerDeath:
  ; 【第一步】计算玩家当前的 Tilemap 索引 (复用你 CheckMove 里的逻辑)
  ld de, ShadowOAM
  ld a, [de]
  sub OAM_Y_BIAS
  srl a
  srl a
  srl a
  ld b, a            ; b = 玩家 Y 坐标 (Tile)

  inc de
  ld a, [de]
  sub 8
  srl a
  srl a
  srl a
  ld c, a            ; c = 玩家 X 坐标 (Tile)

  ; 算出 hl = ShadowTilemap + (Y * 32) + X
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
  ld de, ShadowTilemap
  add hl, de         ; 此时 hl 指向玩家当前所在的 Tile 地址

  ; 【第二步】检测玩家头上是不是石头
  ld a, [hl]
  cp TILE_ROCK
  ret nz            ; 如果不是石头，说明没被砸，直接 ret 返回继续游戏

  ; =========================================
  ; 下方为被砸死后的处理逻辑
  ; =========================================

  ; 【第三步】将这颗石头重新上移一格
  ld a, TILE_EMPTY
  ld [hl], a
  call QueueTileUpdate
  
  ; hl 往上一行 (hl - 32)
  ld a, l
  sub LEVEL_W
  ld l, a
  ld a, h
  sbc 0
  ld h, a
  
  ld a, TILE_ROCK
  ld [hl], a
  call QueueTileUpdate   ; 正上方一格变回石头

  ; 【第四步】扣除生命值
  ld a, [PlayerLives]
  dec a
  ld [PlayerLives], a
  jr z, .GameOver        ; 如果生命值为 0，跳转到 Game Over
  
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call ProcessDirtyQueue

  ; 【第五步】冻结并等待玩家按键
  call WaitKey           
  ; 玩家按键后，回归
  ret

.GameOver
  ; 命用完的处理：目前暂时做成死循环冻结
.deadLoop
  call WaitVBlank
  jr .deadLoop
  
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
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,0,0,0,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,3,3,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,3,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,5,5,5,5,4
  DB 4,5,6,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,5,5,5,5,4
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
PlayerLives: DS 1        ; 玩家生命值
ShadowTilemap: DS 1024       ; [改动 3] tilemap 的 WRAM 影子（1024 字节）
DirtyQueueCount: DS 1        ; [改动 4] 脏区队列当前更新计数 (0~64)
DirtyQueueData: DS 64 * 3    ; [改动 4] 脏区队列缓存，最大支持 64 次 Tile 更新，每组占据 3 字节 (VRAM H, VRAM L, TileID)