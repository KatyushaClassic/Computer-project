; [改动 1] UpdateInputs: readKeys 后用 c（边沿），不用 b（按住）→ 每按一次方向键只走一格
; [改动 2] CheckMove Y 上界 + 下列常量 → 底部 UI_ROWS 行留给 UI，笑脸不可进入
; [改动 3] 所有 tilemap 读写改为 WRAM 影子地图 (ShadowTilemap)，仅在 VBlank 同步到 VRAM
; [改动 4] 增加脏区，改善vblank
INCLUDE "hardware.inc"

DEF OBJCOUNT EQU 1
DEF PLAYER_TILE_ID EQU 2

; [改动 2] 底部 2 行 UI 预留（见 PLAY_Y_MAX）
DEF SCR_H        EQU 144
DEF UI_ROWS      EQU 2
DEF TILE_PX      EQU 8
DEF SPRITE_PX    EQU 8
DEF OAM_Y_BIAS   EQU 16
DEF OAM_X_BIAS   EQU 8
DEF PLAY_Y_MAX   EQU SCR_H - (UI_ROWS * TILE_PX) - SPRITE_PX + OAM_Y_BIAS
DEF PLAY_Y_MIN   EQU OAM_Y_BIAS

DEF LEVEL_W      EQU 32
DEF LEVEL_H      EQU 18
DEF LEVEL_SIZE   EQU LEVEL_W * LEVEL_H

DEF TILE_DIRT    EQU 0
DEF TILE_ROCK    EQU 1
DEF TILE_MONEY   EQU 3
DEF TILE_WALL    EQU 4
DEF TILE_EMPTY   EQU 5
DEF TILE_START   EQU 6
DEF TILE_UI      EQU 7
DEF PLAY_ROWS    EQU LEVEL_H - UI_ROWS

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

; =========================================================
; 游戏主入口（GAME OVER 后重新按键会重置到这里）
; =========================================================
EntryPoint:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  
  ld a, 3                     ; 初始化生命值
  ld [PlayerLives], a

  ; 游戏重新开始时，确保悬空锁存归零
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a
  
  ;初始化背景
  ld a,%11111100 ; black and white palette
  ld [rOBP0], a
  ld a,%11100100 ; 背景四色对比
  ld [rBGP], a

  call   CopyTilesToVRAM
  ld     hl, STARTOF(OAM)
  call   ResetOAM
  ld     hl, ShadowOAM
  call   ResetOAM
  call   InitializeObjects
  call   ResetBG              ; 清空 ShadowTilemap
  
  ; 游戏初始显示界面
  ld hl, ShadowTilemap        
  ld de, PressStr
  ld b, PressStr.end - PressStr
.copyWelcome:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .copyWelcome

  call CopyShadowTilemapToVRAM

  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitKey
  
; =========================================================
; 初始化关卡
; =========================================================
InitLevelState:               ; 初始化关卡里的数据
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  call   LoadLevel            ; 加载地图到 ShadowTilemap

  ; 绘制底部 UI 标签区
  ;Money
  ld hl, ShadowTilemap + 16 * 32 + 2
  ld de, MoneyLabelStr
  ld b, 5
.drawMoneyStr:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawMoneyStr
  
  ;HP
  ld hl, ShadowTilemap + 16 * 32 + 11 
  ld de, HPLabelStr
  ld b, 2
.drawHPStr:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawHPStr
  
  ;关卡钱，生命初始化
  call CountMoneyInLevel       ;数关卡里的钱
  call UpdatePrizeDigit        ;更新钱数 
  call UpdateHPDigit           ;更新生命数 

  call CopyShadowTilemapToVRAM
  
  xor a                        ;a=0
  ld [DirtyQueueCount], a      ;清空DirtyQueueCount
  
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

; =========================================================
; 关卡内主循环
; =========================================================
MainLoop:
  call UpdateInputs           ;识别玩家输入并移动玩家
  call RockCheck              ;石头重力检测
  call CheckPlayerDeath       ;玩家死亡检测
  call WaitVBlank
  call CopyShadowOAMtoOAM     ;更新玩家位置
  call ProcessDirtyQueue      ;更新DirtyQueue到地图
  jp MainLoop


SECTION "Functions", ROM0

; =========================================================
; 功能性函数
; =========================================================

; 响应任意按键的暂停挂起函数
; 实现：通过死循环
WaitKey:
.waitRelease:
  call WaitVBlank           
  call readKeys
  ld a, [previous]          
  or a
  jr nz, .waitRelease       

.waitPress:
  call WaitVBlank
  call readKeys
  ld a, [current]            
  or a
  jr z, .waitPress          

  xor a
  ld [previous], a          
  ret

; 仅响应 A/B/Select/Start 的暂停挂起函数
; 实现：通过死循环
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
  and $0F                   ; 屏蔽高4位(上下左右)，只检测低4位(功能键)
  jr z, .waitPressAct          

  xor a
  ld [previous], a          
  ret

; 把整个屏幕设置为空
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

; 初始化玩家
InitializeObjects:
  ld hl,   ShadowOAM   
.init:
  ld a,32
  ld [hl], a           
  inc      hl
  ld a,32
  ld [hl], a           
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

; 将一次更新的 Tile 加入脏区队列
; Input: a = 要更改成的TILEID
QueueTileUpdate:
  push hl
  push de
  push bc
  push af
  
; 一次只更新64个，防止vblank不够
  ld a, [DirtyQueueCount]
  cp 64                      
  jr nc, .skipQueueAdd
  
;计算出ShadowTilemap在VRAM的目标地址 (de = hl - ShadowTilemap + TILEMAP0)
;Logic:AddressInVRAM = FirstAddressInVRAM + address
;      AddressInShadow = FirstAddressInShadow + address
;   so AddressInVRAM = AddressInShadow - FirstAddressInShadow + FirstAddressInVRAM
;  de = VRAM地址   hl =  ShadowTilemap地址
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
  
; 约定:一条目3字节：VRAM高位, VRAM低位, TileID
;bc = a:记录队列总条目数  
  ld a, [DirtyQueueCount]
  ld c, a
  ld b, 0
  ld hl, DirtyQueueData  
;hl = DirtyQueueData + (条目数 × 3)
  add hl, bc                 
  add hl, bc
  add hl, bc
  
; 现在hl指向最新的空闲位置，开始把该数据写入队列
  ld [hl], d                 ;VRAM高位
  inc hl
  ld [hl], e                 ;VRAM低位
  inc hl
  pop af                     ;弹回TILEID
  push af                    
  ld [hl], a                 ;TIELEID
  ld a, [DirtyQueueCount]
  inc a                      ;计数条目数+1
  ld [DirtyQueueCount], a
.skipQueueAdd
  pop af
  pop bc
  pop de
  pop hl
  ret

ProcessDirtyQueue:
  ld a, [DirtyQueueCount]
  and a
  ret z                      ;队列空直接返回
  
;队列不为空，用b数剩下多少条目
  ld b, a                    
  ld hl, DirtyQueueData
.loop:
  ld d, [hl]                 
  inc hl
  ld e, [hl]                 
  inc hl
  ld a, [hl]                 
  inc hl
  
;de表示写入地址，a表示写入的tile
  ld [de], a                 
  dec b
  jr nz, .loop
  
;循环结束，把count归0
  xor a
  ld [DirtyQueueCount], a    
  ret

; =========================================================
; 功能性函数
; =========================================================
UpdateInputs:            ;识别玩家输入并移动玩家
  ld hl,ShadowOAM        ;人物素材坐标
  push hl
  
  call readKeys
  ld a,c                
  bit 5,a                
  jr nz, .moveLeft
  bit 6,a                
  jr nz, .moveUp
  bit 4,a                
  jp nz, .moveRight
  bit 7,a                
  jr nz, .moveDown
  jp .next

; a=1:Y   a=0:X
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
  jp nz,.next    ; 如果走通了，CheckMove 内部已经处理了保护状态，直接结束
  
  dec [hl]       ; 没走通，撤销坐标
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
  jp nz,.next
  
;碰撞检测
;检测是否石头
  ld d,h
  ld e,l
  call CountPlayerTileAddress
  ld a, [hl]
  cp TILE_ROCK
  jr nz,.LeftCantMove

;检测是否为空  
  dec hl
  ld a,[hl]
  cp TILE_EMPTY
  jr nz,.LeftCantMove

;为空，把这个格改成石头  
  ld a,TILE_ROCK
  ld [hl],a
  call QueueTileUpdate

;把上一格改为空  
  inc hl
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate
  
;成功移动，取消保护
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a
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
  
  ;右推石头判定
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
  
  ; [改动 10] 推石头属于有效操作，清空悬空锁！
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a
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

CheckMove:
  push hl              
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
  cp 160+4
  jp nc,.WithdrawMove
  cp 8
  jp c,.WithdrawMove
  
.Boundarydetectioncompleted
  ; 【核心优化】直接调用已有函数获取尝试移动后玩家在 ShadowTilemap 中的绝对地址
  call CountPlayerTileAddress  ; 返回的 hl 即为绝对内存地址
  ld a, [hl]                  ; 直接读取该格子的 Tile ID
  
  cp TILE_EMPTY
  jr z, .MoveAllowed
  cp TILE_START
  jr z, .MoveAllowed
  cp TILE_MONEY
  jr z, .MoveAllowedAndChangeBG
  cp TILE_DIRT
  jr z, .MoveAllowedAndChangeBG
  jr .WithdrawMove
  
.MoveAllowed   ;走到空地属于有效移动,取消保护
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a

  pop hl
  ld a, 0
  ret
  
.MoveAllowedAndChangeBG    
  ;挖泥土/吃金币属于有效移动,取消保护
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a

  ; 然后检查是否需要设立【新】的悬空锁（也就是头顶有没有石头）
  push hl                 ; 压栈保存当前格子的绝对地址
  ld de, -32
  add hl, de              ; 绝对地址可以直接 -32 指向正上方格子
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .noRockAbove
  
  ; 上方确实有石头，进行保护
  ld a, h
  ld [RockSuspendedH], a
  ld a, l
  ld [RockSuspendedL], a
.noRockAbove:
  pop hl                  ; 恢复 hl 为当前挖掘点的绝对地址
  
  ; 收集金币与挖掘泥土逻辑
  ld a, [hl]              ; 判断是否金币
  cp TILE_MONEY
  jr nz, .notMoneyCollected
  ld a, [prizeLeft]       
  and a
  jr z, .notMoneyCollected
  dec a                    
  ld [prizeLeft], a
  push hl
  call UpdatePrizeDigit   ; 更新金币数
  pop hl
.notMoneyCollected:
  ld a, TILE_EMPTY
  ld [hl], a              ; 将当前地址改为空地
  call QueueTileUpdate    ; 脏区队列同样接收绝对地址 hl
  
  pop hl                  ; 弹出最开始 push 的 ShadowOAM 坐标指针
  ld a, 0
  ret

.WithdrawMove
  pop hl
  ld a, 1
  ret

RockCheck:
.SearchForRock            ; 遍历整张地图，寻找石头
  ld hl, ShadowTilemap + 1024 - 1  
  ld bc, 1024
.SearchRockLoop
  ld a, [hl]                   
  cp TILE_ROCK       
  jp nz, .skip
.MoveRock

  ; 检测正在扫描的这块石头，是否处于被玩家挖掘保护的状态
  ld a, [RockSuspendedH]
  cp h
  jr nz, .NotSuspended
  ld a, [RockSuspendedL]
  cp l
  jr nz, .NotSuspended
  ; 如果地址完全一致，说明这正是悬空的石头
  jp .skip
  
.NotSuspended:
  ; 如果没被保护，执行正常重力扫描
  ld   d,h          
  ld   e,l
  ld   a,l
  add  LEVEL_W                    ;+32
  ld   l, a
  ld   a, h
  adc  0                          ;处理进位
  ld   h, a                       ;hl 现在是正下方的地址
  
  call CheckRockMove
  cp 1
  jr z,.CheckMoveRight
  
;将石头这格设为空（此时已经可以移动）
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jr .RockSkip
  
.CheckMoveRight
;下方是石头才进行左右检测
  ld a,[hl]
  cp TILE_ROCK
  jr nz,.RockSkip
  
.ContinueCheckMoveRight
;检测向左下移动是否可以（不清楚先左还是右,无需检测玩家死亡）
;往上再往左,检测左边
; -1-32
  dec hl
  
  ld   a,l           
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
  
;检测左下    
  ld   a,l               ;+32
  add  LEVEL_W 
  ld   l, a
  ld   a, h
  adc  0               
  ld   h, a   
  
  call CheckRockMove
  cp TILE_ROCK
  jr z,.ReturnHL
  
;将石头这格设为空（此时已经可以移动）
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jr .RockSkip
  
.ReturnHL                ;检测左下时+32了，用于恢复
  ld   a,l               ;-32
  sub  LEVEL_W 
  ld   l, a
  ld   a, h
  sbc  0               
  ld   h, a 
  
.CheckMoveLeft
  inc hl                 ;+2
  inc hl
  
  ld a,[hl]              ;检测右边
  cp TILE_ROCK
  jr z, .RockSkip
  cp TILE_DIRT
  jr z, .RockSkip
  cp TILE_MONEY
  jr z, .RockSkip
  cp TILE_WALL
  jr z, .RockSkip
  
  ld   a,l               ;检测右下角
  add  LEVEL_W 
  ld   l, a
  ld   a, h
  adc  0               
  ld   h, a   
  
  call CheckRockMove
  cp 1
  jr z,.RockSkip
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jr .RockSkip               
  
.RockSkip                ;用于复原hl
  ld h,d
  ld l,e
.skip
  dec hl                        
  dec bc                        
  ld a, b
  or c
  jp nz, .SearchRockLoop
  ret
  
CheckRockMove:            ;移动石头并推入脏队列
.CheckRockMoveStart
  push de              
  push hl
  
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
  
CountPlayerTileAddress:   ;计算玩家位置
  push bc
  push de
  
  ld de, ShadowOAM
  ld a, [de]
  sub OAM_Y_BIAS
  srl a
  srl a
  srl a
  ld b, a            ; b = 玩家 Y 坐标 (Tile)

  inc de
  ld a, [de]
  sub OAM_X_BIAS 
  srl a
  srl a
  srl a
  ld c, a            ; c = 玩家 X 坐标 (Tile)

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
  pop de
  pop bc
  ret
  
; =========================================================
; 彻底解耦的全屏重置逻辑
; =========================================================
CheckPlayerDeath:
  call CountPlayerTileAddress

  ld a, [hl]
  cp TILE_ROCK
  ret nz             ; 如果没有被石头砸，直接返回

  ; 玩家被砸中
  ; 1. 在 ShadowTilemap 里复原被砸毁的格子（旧位置变空，上方变石头）
  ld a, TILE_EMPTY
  ld [hl], a
  ld a, l
  sub LEVEL_W
  ld l, a
  ld a, h
  sbc 0
  ld h, a
  ld a, TILE_ROCK
  ld [hl], a

  ; 2. 扣减生命值并更新 UI
  ld a, [PlayerLives]
  dec a
  ld [PlayerLives], a
  call UpdateHPDigit

  ; 3. 判断是否彻底死亡
  ld a, [PlayerLives]
  and a
  jr z, .TriggerGameOver 
  
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call ProcessDirtyQueue

  ; --------- 情况 A: YOU ARE DEAD (全屏清空) ---------
  ; 安全关闭屏幕
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ; 将 VRAM 显显存完全清空为空地
  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAM1:
  ld a, TILE_EMPTY            ; 防止 a 寄存器在循环内被污染导致乱码
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAM1

  ; 在屏幕正中间写入 YOU ARE DEAD
  ld hl, TILEMAP0 + 8 * 32 + 4  ; X=(20-12)/2=4
  ld de, YouAreDeadStr
  ld b, 12
.drawDeadText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawDeadText

  ; 开启屏幕，隐藏精灵
  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  ; 冻结等待玩家功能键确认 (A/B/Select/Start)
  call WaitActionKey           

  ; 返回地图：再次安全关闭屏幕
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ; 将完好无损的 ShadowTilemap (含修复好的石头和血量) 完整倒回 VRAM
  call CopyShadowTilemapToVRAM
  
  ; 清除期间可能产生的残留脏区队列
  xor a
  ld [DirtyQueueCount], a

  ; 重新开启屏幕，并恢复精灵渲染，此时显示的是地图画面
  ld a, LCDC_ON | LCDC_OBJ_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a
  
  ; 玩家在地图上原地冻结，保留普通 WaitKey！
  call WaitKey
  
  ret

; --------- 情况 B: GAME OVER (完全重置) ---------
.TriggerGameOver:
  ; 安全关闭屏幕
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ; 清空 VRAM
  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAM2:
  ld a, TILE_EMPTY            ; 【核心修复】防止乱码
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAM2

  ; 写入 GAME OVER
  ld hl, TILEMAP0 + 8 * 32 + 5  ; X=(20-9)/2=5.5 向下取整为 5，完美居中
  ld de, GameOverStr
  ld b, 9
.drawGameOverText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawGameOverText

  ; 开启屏幕，关闭精灵渲染
  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

.halt:
  jr .halt


LoadLevel:
  ld hl, Level1Map            ;关卡地图的 ROM 地址
  ld de, ShadowTilemap        ;WRAM 中的影子地图起始地址
  xor a
  ld b, a                     ;b 行计数器

;新的一列
.row:
  xor a
  ld c, a                     ;c 列计数器
  
;新的一行
.col:
  ld a, [hl+]
  cp TILE_START
  jr nz, .writeTile
  
;遇到玩家出生点，记录出生坐标到 ShadowOAM
;X = col*8 + 8，Y = row*8 + 16
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

; 填充 ShadowTilemap 中剩余部分（即 LEVEL_SIZE 之后到 1024 字节）
  ld hl, ShadowTilemap + LEVEL_SIZE  
  ld bc, 1024 - LEVEL_SIZE
.fillRest:
  ld a, TILE_EMPTY
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .fillRest
  ret

CountMoneyInLevel:           ;遍历地图，数钱
  ld hl, Level1Map
  ld bc, LEVEL_SIZE
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

UpdatePrizeDigit:
  ld a, [prizeLeft]
  add a, 9                      ;变成数字
  ld hl, ShadowTilemap + 16 * 32 + 8 
  ld [hl], a
  call QueueTileUpdate       
  ret

UpdateHPDigit:
  ld a, [PlayerLives]
  add a, 9                    
  ld hl, ShadowTilemap + 16 * 32 + 14 
  ld [hl], a
  call QueueTileUpdate
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

MoneyLabelStr:
  DB "MONEY"
HPLabelStr:
  DB "HP"
YouAreDeadStr:
  DB "YOU ARE DEAD"
GameOverStr:
  DB "GAME OVER"

Level1Map:
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,1,5,5,5,5,5,5,5,5,1,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,1,1,1,5,5,5,5,5,5,5,5,5,5,5,5,1,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,0,0,0,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,3,3,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,3,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,0,1,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,0,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,1,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,5,6,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,1,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7

Tiles:
;0 = Dirt
 DB %10101011, %01010111, %10101011, %01010111, %10101011, %00000000, %00000000, %00000000
;1 = Rock
 DB %00111100, %01111110, %11011111, %11111111, %11111111, %01111110, %00111100, %00000000
;2 = NPC
 DB %01111110, %10000001, %10100101, %10000001, %10100101, %10011001, %10000001, %01111110
;3 = Money
 DB %00000000, %00001110, %00111110, %01111100, %01111000, %00011110, %00001110, %00000000
;4 = Wall
 DB %11111111, %10011001, %11111111, %10011001, %11111111, %10011001, %11111111, %00000000
;5 = Empty space
 DB %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000
;6 = Player start
 DB %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000
;7 = Blank
 DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
;8
 DB %00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000,%00000000
; font characters
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
PlayerLives: DS 1     
RockSuspendedH: DS 1  ; 悬空石头地址高位
RockSuspendedL: DS 1  ; 悬空石头地址低位
ShadowTilemap: DS 1024       
DirtyQueueCount: DS 1        
DirtyQueueData: DS 64 * 3    
prizeLeft: DS 1