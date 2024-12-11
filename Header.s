;*****************************************************************
; Defines
;*****************************************************************
; PPU Registers
PPU_CONTROL = $2000 ; PPU Control Register 1 (Write)
PPU_MASK = $2001 ; PPU Control Register 2 (Write)
PPU_STATUS = $2002; PPU Status Register (Read)
PPU_SPRRAM_ADDRESS = $2003 ; PPU SPR-RAM Address Register (Write)
PPU_SPRRAM_IO = $2004 ; PPU SPR-RAM I/O Register (Write)
PPU_VRAM_ADDRESS1 = $2005 ; PPU VRAM Address Register 1 (Write)
PPU_VRAM_ADDRESS2 = $2006 ; PPU VRAM Address Register 2 (Write)
PPU_VRAM_IO = $2007 ; VRAM I/O Register (Read/Write)
SPRITE_DMA = $4014 ; Sprite DMA Register

; PPU control register masks
NT_2000 = $00 ; nametable location
NT_2400 = $01
NT_2800 = $02
NT_2C00 = $03

; Useful PPU memory addresses
NAME_TABLE_0_ADDRESS		= $2000
ATTRIBUTE_TABLE_0_ADDRESS	= $23C0
NAME_TABLE_1_ADDRESS		= $2400
ATTRIBUTE_TABLE_1_ADDRESS	= $27C0

VRAM_DOWN = $04 ; increment VRAM pointer by row

OBJ_0000 = $00 
OBJ_1000 = $08
OBJ_8X16 = $20

BG_0000 = $00 ; 
BG_1000 = $10

VBLANK_NMI = $80 ; enable NMI

BG_OFF = $00 ; turn background off
BG_CLIP = $08 ; clip background
BG_ON = $0A ; turn background on

OBJ_OFF = $00 ; turn objects off
OBJ_CLIP = $10 ; clip objects
OBJ_ON = $14 ; turn objects on

; APU Registers
APU_DM_CONTROL = $4010 ; APU Delta Modulation Control Register (Write)
APU_CLOCK = $4015 ; APU Sound/Vertical Clock Signal Register (Read/Write)

; INPUT
; Joystick/Controller values
JOYPAD1 = $4016 ; Joypad 1 (Read/Write)
JOYPAD2 = $4017 ; Joypad 2 (Read/Write)

; Gamepad bit values
PAD_A      = $01
PAD_B      = $02
PAD_SELECT = $04
PAD_START  = $08
PAD_U      = $10
PAD_D      = $20
PAD_L      = $40
PAD_R      = $80

; MAP BUFFER
MAP_BUFFER_SIZE = 120
MAP_COLUMNS = 32 ;32 bits
MAP_ROWS = 30

; Frontier list
FRONTIER_LISTQ1 = $0320
FRONTIER_LISTQ2 = $041E
FRONTIER_LISTQ3 = $051C
FRONTIER_LISTQ4 = $061A

; Neighbor util - directions
TOP_N = 0
RIGHT_N = 1 
BOTTOM_N = 2
LEFT_N = 3

; directions for solving algo 
TOP_D = 0
RIGHT_D = 1
BOTTOM_D = 2
LEFT_D = 3




;changed tiles util
CHANGED_TILES_BUFFER_SIZE = 40

;sets the delay for player movement (==  movement speed)
PLAYER_MOVEMENT_DELAY = 5

MAZE_GENERATION_SPEED = 1 ;how much is maze generation slowed down
;*****************************************************************

.segment "HEADER"
INES_MAPPER = 0                                                     ; 0 = NROM
INES_MIRROR = 0                                                     ; 0 = horizontal mirror/1 = vertical
INES_SRAM = 0                                                       ; 1 = battery save at $6000-7FFF

.byte 'N', 'E', 'S', $1A ; ID
.byte $02                                                           ; 16 KB program bank count
.byte $01                                                           ; 8 KB program bank count
.byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $f) << 4)
.byte (INES_MAPPER & %11110000)
.byte $0, $0, $0, $0, $0, $0, $0, $0                                ; padding

.segment "TILES"
.incbin "Tiles.chr"

.segment "VECTORS"
.word nmi
.word reset
.word irq

;*****************************************************************
; 6502 Zero Page Memory (256 bytes)
;*****************************************************************
.segment "ZEROPAGE"
;internal (hardware) use flags and values
nmi_ready:		    	.res 1 ; set to 1 to push a PPU frame update, 2 to turn rendering off next NMI

ppu_ctl0:		    	.res 1 ; PPU Control Register 2 Value
ppu_ctl1:		    	.res 1 ; PPU Control Register 2 Value

;input
gamepad:		    	.res 1 ; stores the current gamepad values

frame_counter: 			.res 1
last_frame_ct: 			.res 1 ;for things we want to execute once per frame

;random
RandomSeed:				.res 1 ; Initial seed value | Used internally for random function, do not overwrite

;gameplay flags
has_generation_started: .res 1 
has_game_started:		.res 1
display_steps:			.res 1 ;flag to toggle displaying maze generation step by step
odd_frontiers: 			.res 1 ;was the maze generated with odd or even frontier rows
is_hard_mode:           .res 1 ;is the game running in hard mode or not
checked_this_frame:     .res 1 

;maze
maze_buffer:        	.res 120

end_row: 				.res 1
end_col:				.res 1

;graphics buffers
should_clear_buffer: 	.res 1
changed_tiles_buffer: 	.res 40 ;changed tiles this frame - used for graphics during vblank 
                                ; layout: row, col, row, col; FF by default 
                                ; first 3 bits of row are the tileID

low_byte: 				.res 1
high_byte: 				.res 1

;frontier list specific
frontier_listQ1_size:	.res 1 ; | Internal use for frontier list, do not overwrite
frontier_listQ2_size:	.res 1 ; | Internal use for frontier list, do not overwrite
frontier_listQ3_size:	.res 1 ; | Internal use for frontier list, do not overwrite
frontier_listQ4_size:	.res 1 ; | Internal use for frontier list, do not overwrite
frontier_pages_used:	.res 1 ; | Internal use for frontier list, do not overwrite

;temporary values used in macros, ... - have to check when you use these in other routines if they arent used anywhere internally
x_val:					.res 1 ;x and y value stored in zero page for fast accesss when it's necessary to store these
y_val:					.res 1

a_val: 					.res 1
b_val: 					.res 1

byte_loop_couter:   	.res 1 ; counter for the bits in map transfer

paddr:              	.res 2 ; 16-bit address pointer
tempPadrToLast: 		.res 2 ;last item in address for a given quarter, used for the remove from list macro

temp_address:			.res 1

;temp vals used for prims algorithm loop - only used during the generation loop so possible to overwrite outside of the loop
frontier_page: 			.res 1
frontier_offset:		.res 1

frontier_row:			.res 1
frontier_col:			.res 1

used_direction:			.res 1

execs: 					.res 1

temp_row:				.res 1
temp_col:				.res 1
temp: 					.res 1

;PLAYER SPRITE VARIABLES
player_x: 				.res 1
player_y: 				.res 1
player_row: 			.res 1
player_collumn: 		.res 1

score_low:              .res 1
score_high:             .res 1

testvar:                .res 1

;SOLVING ALGORITHM VARIABLES
solving_row:            .res 1
solving_collumn:        .res 1
temp_solving_collumn:    .res 1
temp_solving_row:        .res 1
solving_local_direction:.res 1


;*****************************************************************

.segment "OAM"
oam: .res 256	; sprite OAM data

.segment "BSS"
palette: .res 32 ; current palette buffer

;*****************************************************************
; Our default palette table 16 entries for tiles and 16 entries for sprites
;*****************************************************************
.segment "RODATA"
default_palette:
.byte $0F,$10,$26,$37 ; bg0 purple/pink
.byte $0F,$09,$19,$29 ; bg1 green
.byte $0F,$01,$11,$21 ; bg2 blue
.byte $0F,$00,$10,$30 ; bg3 greyscale
.byte $0F,$11,$21,$2C ; sp0 blue (changed)
.byte $0F,$14,$24,$34 ; sp1 purple
.byte $0F,$1B,$2B,$3B ; sp2 teal
.byte $0F,$12,$22,$32 ; sp3 marine
;*****************************************************************
