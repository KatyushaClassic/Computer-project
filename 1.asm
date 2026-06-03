INCLUDE "hardware.inc"

DEF OBJCOUNT EQU 1
DEF PLAYER_TILE_ID EQU 2
DEF LEVEL_AMMOUNT EQU 2

; 底部 2 行 UI 预留（见 PLAY_Y_MAX）
DEF SCR_H         EQU 144
DEF UI_ROWS       EQU 2
DEF TILE_PX       EQU 8
DEF SPRITE_PX     EQU 8
DEF OAM_Y_BIAS    EQU 16
DEF OAM_X_BIAS    EQU 8
DEF PLAY_Y_MAX    EQU SCR_H - (UI_ROWS * TILE_PX) - SPRITE_PX + OAM_Y_BIAS
DEF PLAY_Y_MIN    EQU OAM_Y_BIAS

DEF MAP_W         EQU 20
DEF MAP_H         EQU 18
DEF MAP_SIZE      EQU MAP_W * MAP_H
DEF SCR_STRIDE    EQU 32  ; Tilemap 换行步长固定为 32

DEF TILE_DIRT     EQU 0
DEF TILE_ROCK     EQU 1
DEF TILE_MONEY    EQU 3
DEF TILE_WALL     EQU 4
DEF TILE_EMPTY    EQU 5
DEF TILE_START    EQU 6
DEF TILE_UI       EQU 7
DEF TILE_BARRIER  EQU 8 
DEF PLAY_ROWS     EQU MAP_H - UI_ROWS

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
  
  ; 游戏彻底开始时，初始化当前关卡为关卡 1 (索引为 0)
  xor a
  ld [CurrentLevel], a

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

  call WaitActionKey
  
; 初始化关卡
InitLevelState:               ; 初始化关卡里的数据
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  call   LoadLevel            ; 加载地图到 ShadowTilemap

  ;Money
  ld hl, ShadowTilemap + 17 * 32 + 2
  ld de, MoneyLabelStr
  ld b, 5
.drawMoneyStr:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawMoneyStr
  
  ;HP
  ld hl, ShadowTilemap + 17 * 32 + 11 
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

MainLoop:
  call UpdateInputs           ;识别玩家输入并移动玩家
  
  ; 每帧检测金币是否全部吃完，若归零则进入胜利切关流程
  ld a, [prizeLeft]
  and a
  jp z, TriggerYouWin

  call RockCheck              ;石头重力检测
  call CheckPlayerDeath       ;玩家死亡检测
  call WaitVBlank
  call CopyShadowOAMtoOAM     ;更新玩家位置
  call ProcessDirtyQueue      ;更新DirtyQueue到地图
  jp MainLoop


SECTION "Functions", ROM0

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
; bc = a:记录队列总条目数  
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
  jp nz,.next             ; 如果走通了，CheckMove 内部已经处理了保护状态，直接结束
  
  dec [hl]                ; 没走通，撤销坐标
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
  cp 160+4                         ;PLAY_X_MAX
  jp nc,.WithdrawMove
  cp 8                             ;PLAY_X_MIN
  jp c,.WithdrawMove
  
.Boundarydetectioncompleted
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
  
.MoveAllowed   
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a

  pop hl
  ld a, 0
  ret
  
.MoveAllowedAndChangeBG    
  xor a
  ld [RockSuspendedH], a
  ld [RockSuspendedL], a


; 然后检查是否需要设立【新】的悬空锁（也就是头顶有没有石头）
  push hl                 
  ld de, -32
  add hl, de                   ; hl 现在是正上方格子的索引
  ld a, [hl]
  cp TILE_ROCK
  jr nz, .noRockAbove
  
; 上方确实有石头！记录这块石头的内存地址赋予保护！
  ld a, h
  ld [RockSuspendedH], a
  ld a, l
  ld [RockSuspendedL], a
.noRockAbove:
  pop hl                  
  
  ; 收集金币与挖掘泥土逻辑
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

; 检测正在扫描的这块石头，是否处于被玩家挖掘保护的状态
.MoveRock
  ld a, [RockSuspendedH]
  cp h
  jr nz, .NotSuspended
  ld a, [RockSuspendedL]
  cp l
  jr nz, .NotSuspended
  jp .skip
  
.NotSuspended:
; 如果没被保护，执行正常重力扫描。设x = 当前位置
  ld   d,h          
  ld   e,l
  ld   a,l
  add  SCR_STRIDE                 ;x+32
  ld   l, a
  ld   a, h
  adc  0                          
  ld   h, a                       ; hl 现在是正下方的地址
  
  call CheckRockMove
  cp 1
  jr z,.CheckMoveRight
  
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jp .RockSkip
  
.CheckMoveRight                   ;x+32
;必须下面是石头才能滑动
  ld a,[hl]
  cp TILE_ROCK
  jp nz,.RockSkip
  
;检测左边  
.ContinueCheckMoveRight
  ;如果在第 0 列，强行关闭左滑功能
  ;如何实现：取地址除以32的余数
  ld a, e                         ; 不需要理会高8位，因为除以32得到的余数只有后5位
  sub LOW(ShadowTilemap)          ; 因为当前de地址 = ShadowTilemap + Tile地址
  and 31                          ;and 00011111 = 保留后5位，得到余数
  jr z, .SkipLeftSlide            ; 此时x+32，余数为0处于最左边界，直接去处理右侧滑落准备

  dec hl                          ;x+31
  
  ld   a,l           
  sub  SCR_STRIDE                 
  ld   l, a
  ld   a, h
  sbc  0               
  ld   h, a                       ;x-1
 
  ld a,[hl]
  cp TILE_ROCK
  jr z, .CheckMoveLeft
  cp TILE_DIRT
  jr z, .CheckMoveLeft
  cp TILE_MONEY
  jr z, .CheckMoveLeft
  cp TILE_WALL
  jr z, .CheckMoveLeft
  
;左边为空，检测左下边
  ld   a,l                                
  add  SCR_STRIDE 
  ld   l, a
  ld   a, h
  adc  0               
  ld   h, a                       ;x-33
  
  call CheckRockMove
  cp 1
  jr z,.ReturnHL
  
  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jr .RockSkip

.ReturnHL                         ;到了x-33，要+32变成x-1
  ld   a,l               
  sub  SCR_STRIDE 
  ld   l, a
  ld   a, h
  sbc  0               
  ld   h, a 

;检测右边                         ;x-1
.CheckMoveLeft
  inc hl                 
  inc hl                          ;x+1
  
;如果在第 19 列，强行关闭右滑功能
  ld a, e
  sub LOW(ShadowTilemap)
  and 31
  cp 19                           ; 余数为19
  jr z, .RockSkip                 ; 处于最右边界，直接放弃右滑

  ld a,[hl]              ; 检测右边
  cp TILE_ROCK
  jr z, .RockSkip
  cp TILE_DIRT
  jr z, .RockSkip
  cp TILE_MONEY
  jr z, .RockSkip
  cp TILE_WALL
  jr z, .RockSkip                 ;x+1
  
;检测右下边
  ld   a,l               
  add  SCR_STRIDE 
  ld   l, a
  ld   a, h
  adc  0               
  ld   h, a                       ;x-31
  
  call CheckRockMove
  cp 1
  jr z,.RockSkip

  ld h,d
  ld l,e
  ld a,TILE_EMPTY
  ld [hl],a
  call QueueTileUpdate       
  jr .RockSkip               

.SkipLeftSlide                    ;x-32
  ld a, l
  sub 33
  ld l, a
  ld a, h
  sbc 0
  ld h, a                         ;x-1
  jr .CheckMoveLeft

.RockSkip                         ;用于返回hl值
  ld h,d
  ld l,e
.skip                             ;因为de值可能乱掉，所以分开
  dec hl                        
  dec bc                        
  ld a, b
  or c
  jp nz, .SearchRockLoop
  ret
  
CheckRockMove:            
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
  
CountPlayerTileAddress:   
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
  add hl, de         
  pop de
  pop bc
  ret
  
CheckPlayerDeath:
  call CountPlayerTileAddress

  ld a, [hl]
  cp TILE_ROCK
  ret nz                 ; 如果没有被石头砸，直接返回

; 玩家被砸中
; 在 ShadowTilemap 里复原被砸毁的格子（旧位置变空，上方变石头）
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

; 扣减生命值并更新 UI
  ld a, [PlayerLives]
  dec a
  ld [PlayerLives], a
  call UpdateHPDigit
  
;判断是否彻底死亡
  ld a, [PlayerLives]
  and a
  jr z, .TriggerGameOver 
  
  call WaitVBlank
  call CopyShadowOAMtoOAM
  call ProcessDirtyQueue

; 情况 A: YOU ARE DEAD (全屏清空)
; 安全关闭屏幕
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a
  
; 将 VRAM 显存完全清空为空地
  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAM1:
  ld a, TILE_EMPTY            
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAM1

; 在屏幕正中间写入 YOU ARE DEAD
  ld hl, TILEMAP0 + 8 * 32 + 4  
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
  
  call WaitKey
  
  ret

;GAME OVER
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

.halt:
  jr .halt

LoadLevel:
  call GetLevelMapAddress     
  ld de, ShadowTilemap        
  xor a
  ld b, a                    

.row:
  xor a
  ld c, a                 ;c = 列计数器 <= 19   
  
.col:
  ld a, [hl+]
  cp TILE_START
  jr nz, .writeTile
 
; 设置出生点
  push bc
  
; 计算并设置玩家的 X 坐标
  ld a, c
  add a
  add a
  add a
  add 8
  ld [ShadowOAM + 1], a   ;x = row*8 + 8
  
; 计算并设置玩家的 Y 坐标
  ld a, b
  add a
  add a
  add a
  add OAM_Y_BIAS
  ld [ShadowOAM], a       ;y = col*8 + 16
  
  pop bc
  ld a, TILE_EMPTY
  
;写入
.writeTile:
  ld [de], a
  inc de
  inc c                   ;递增列
  ld a, c
  cp MAP_W                    
  jr nz, .col

  push bc
  ld b, SCR_STRIDE - MAP_W;b = 32 -20 =12
;行尾填充UI
.padLoop:
  ld a, TILE_UI
  ld [de], a
  inc de
  dec b
  jr nz, .padLoop
  pop bc
  
  inc b                   ;递增行
  ld a, b
  cp MAP_H                    
  jr nz, .row

  ld hl, ShadowTilemap + (MAP_H * SCR_STRIDE)    ; hl = ShadowTilemap + (18 * 32) = 第 18 行的起始地址
  ld bc, 1024 - (MAP_H * SCR_STRIDE)             ; bc = 1024 - 576 = 448 字节，即剩下的 14 行 × 32 列
  
.fillRest:
  ld a, TILE_EMPTY
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .fillRest
  ret

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

;hl = 下一个地图地址
GetLevelMapAddress:
  ld a, [CurrentLevel]     ;a = CurrentLevel
  add a                    ;a = CurrentLevel*2   
  ld e, a
  ld d, 0                  ;de = a
  ld hl, LevelPointers     
  add hl, de               ;hl = LevelPointersAddress + CurrentLevel*2  
  
  ld a, [hl+]              ;读入低字节
  ld h, [hl]               ;读入高字节
  ld l, a                    
  ret

TriggerYouWin:
  call WaitVBlank
  ld a, 0
  ld [rLCDC], a

  ld hl, TILEMAP0
  ld bc, 1024
.clearVRAMWin:
  ld a, TILE_EMPTY           
  ld [hl+], a
  dec bc
  ld a, b
  or c
  jr nz, .clearVRAMWin

  ld hl, TILEMAP0 + 8 * 32 + 6  
  ld de, YouWinStr
  ld b, 7                       
.drawWinText:
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .drawWinText

  ld a, LCDC_ON | LCDC_BG_ON | LCDC_BLOCK01
  ld [rLCDC], a

  call WaitActionKey           

  ld a, [CurrentLevel]      ;进入下一关
  inc a
  cp LEVEL_AMMOUNT          ;看看有没有打到最后        
  jr nz, .saveNext
  
;最后一关已完成
.DeadLoop
  jr .DeadLoop
  
;进入下一关  
.saveNext:
  ld [CurrentLevel], a

  jp InitLevelState

;Show Money
UpdatePrizeDigit:
  ld a, [prizeLeft]
  add a, 9                      
  ld hl, ShadowTilemap + 17 * 32 + 8 
  ld [hl], a
  call QueueTileUpdate       
  ret

;Show HP
UpdateHPDigit:
  ld a, [PlayerLives]
  add a, 9                    
  ld hl, ShadowTilemap + 17 * 32 + 14 
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
YouWinStr:
  DB "YOU WIN"

LevelPointers:      ;存放地图地址
  DW Level1Map
  DW Level2Map

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
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7

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
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7
  DB 7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7

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
;8 = Invisible Barrier 
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
RockSuspendedH: DS 1  
RockSuspendedL: DS 1  
CurrentLevel:   DS 1  
ShadowTilemap: DS 1024       
DirtyQueueCount: DS 1        
DirtyQueueData: DS 64 * 3    
prizeLeft: DS 1