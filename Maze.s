.include "Header.s"
.include "Macros.s"

;*****************************************************************
; Utility functions
;*****************************************************************
.segment "CODE"
.proc wait_frame
	INC nmi_ready
@loop:
	LDA nmi_ready
	BNE @loop
	RTS
.endproc

; ppu_update: waits until next NMI, turns rendering on (if not already), uploads OAM, palette, and nametable update to PPU
.proc ppu_update
    LDA ppu_ctl0
	ORA #VBLANK_NMI
	STA ppu_ctl0
	STA PPU_CONTROL
	LDA ppu_ctl1
	ORA #OBJ_ON|BG_ON
	STA ppu_ctl1
	JSR wait_frame
	RTS
.endproc

; ppu_off: waits until next NMI, turns rendering off (now safe to write PPU directly via PPU_VRAM_IO)
.proc ppu_off
    JSR wait_frame
	LDA ppu_ctl0
	AND #%01111111
	STA ppu_ctl0
	STA PPU_CONTROL
	LDA ppu_ctl1
	AND #%11100001
	STA ppu_ctl1
	STA PPU_MASK
	RTS
.endproc

.segment "CODE"
.proc reset
    SEI
    LDA #0
    STA PPU_CONTROL
    STA PPU_MASK
    ;sta APU_DM_CONTROL
    LDA #40
    STA JOYPAD2 

    CLD
    LDX #$FF
    TXS

wait_vblank:
    BIT PPU_STATUS
    BPL wait_vblank

    LDA #0
    LDX #0

clear_ram:
    STA $0000, x
    STA $0100, x
    STA $0200, x
    STA $0300, x
    STA $0400, x
    STA $0500, x
    STA $0600, x
    STA $0700, x
    INX
    BNE clear_ram

    LDA #255
    LDX #0

clear_oam:
    STA oam, x
    INX
    INX
    INX
    INX
    BNE clear_oam

wait_vblank2:
    BIT PPU_STATUS
    BPL wait_vblank2

    LDA #%10001000
    STA PPU_CONTROL

    JMP main
.endproc

.segment "CODE"
.proc clear_nametable
    LDA PPU_STATUS 
    LDA #$20
    STA PPU_VRAM_ADDRESS2
    LDA #$00
    STA PPU_VRAM_ADDRESS2

    LDA #0
    LDY #30
    rowloop:
        LDX #32
        columnloop:
            STA PPU_VRAM_IO
            DEX
            BNE columnloop
        DEY
        BNE rowloop

    LDX #64
    loop:
        STA PPU_VRAM_IO
        DEX
        BNE loop
    RTS
.endproc
;*****************************************************************

;*****************************************************************
; Interupts
;*****************************************************************
.segment "CODE"
irq:
	RTI

.proc nmi
    ;save registers
    PHA
    TXA
    PHA
    TYA
    PHA

    BIT PPU_STATUS
	; transfer sprite OAM data using DMA
	LDX #0
	STX PPU_SPRRAM_ADDRESS
	LDA #>oam
	STA SPRITE_DMA

	; transfer current palette to PPU
	LDA #%10001000 ; set horizontal nametable increment
	STA PPU_CONTROL 
	LDA PPU_STATUS
	LDA #$3F ; set PPU address to $3F00
	STA PPU_VRAM_ADDRESS2
	STX PPU_VRAM_ADDRESS2
	LDX #0 ; transfer the 32 bytes to VRAM
	LDX #0 ; transfer the 32 bytes to VRAM
@loop:
	LDA palette, x
	STA PPU_VRAM_IO
	INX
	CPX #32
	BCC @loop

	; write current scroll and control settings
	LDA #0
	STA PPU_VRAM_ADDRESS1
	STA PPU_VRAM_ADDRESS1
	LDA ppu_ctl0
	STA PPU_CONTROL
	LDA ppu_ctl1
	STA PPU_MASK

	; flag PPU update complete
	LDX #0
	STX nmi_ready

	; restore registers and return
	PLA
	TAY
	PLA
	TAX
	PLA
	RTI
.endproc
;*****************************************************************

;*****************************************************************
; Main Gameloop
;*****************************************************************
.segment "CODE"
.proc main

    JSR Init

mainloop:
    LDA has_generation_started
    BNE :+
        JSR start
    :

    JMP mainloop
.endproc
;*****************************************************************

;*****************************************************************
; Input
;*****************************************************************
.segment "CODE"
.proc gamepad_poll
	; strobe the gamepad to latch current button state
	LDA #1
	STA JOYPAD1
	LDA #0
	STA JOYPAD1
	; read 8 bytes from the interface at $4016
	LDX #8
loop:
    PHA
    LDA JOYPAD1
    ; combine low two bits and store in carry bit
	AND #%00000011
	CMP #%00000001
	PLA
	; rotate carry into gamepad variable
	ROR
	DEX
	BNE loop
	STA gamepad
	RTS
.endproc
;*****************************************************************

;*****************************************************************
; Init
;*****************************************************************
.segment "CODE"
.proc Init
    LDX #0
palette_loop:
    LDA default_palette, x  ;load palettes
    STA palette, x
    INX
    CPX #32
    BCC palette_loop

    JSR ppu_off
    JSR clear_nametable
    JSR ppu_update

    ;set an initial randomseed value
    LDA #$42
    STA RandomSeed
    
    ;choose a first frontier cell, does not matter which one (can be made random in future)
    add_to_Frontier #$0, #$0

    add_to_Frontier #1, #2
    add_to_Frontier #1, #3
    add_to_Frontier #1, #4
    add_to_Frontier #1, #5
    add_to_Frontier #1, #6
    add_to_Frontier #1, #7
    add_to_Frontier #1, #8
    add_to_Frontier #1, #9

    add_to_Frontier #1, #10
    add_to_Frontier #1, #11
    add_to_Frontier #1, #12
    add_to_Frontier #1, #13
    add_to_Frontier #1, #14
    add_to_Frontier #1, #15
    add_to_Frontier #1, #16
    add_to_Frontier #1, #17
    add_to_Frontier #1, #18
    add_to_Frontier #1, #19
    add_to_Frontier #1, #20

    add_to_Frontier #1, #21
    add_to_Frontier #1, #22
    add_to_Frontier #1, #23
    add_to_Frontier #1, #24
    add_to_Frontier #1, #25
    add_to_Frontier #1, #26
    add_to_Frontier #1, #27
    add_to_Frontier #1, #28
    add_to_Frontier #1, #29
    add_to_Frontier #1, #30

    add_to_Frontier #2, #2
    add_to_Frontier #2, #3
    add_to_Frontier #2, #4
    add_to_Frontier #2, #5
    add_to_Frontier #2, #6
    add_to_Frontier #2, #7
    add_to_Frontier #2, #8
    add_to_Frontier #2, #9
    add_to_Frontier #2, #10
    add_to_Frontier #2, #11
    add_to_Frontier #2, #12
    add_to_Frontier #2, #13
    add_to_Frontier #2, #14
    add_to_Frontier #2, #15
    add_to_Frontier #2, #16
    add_to_Frontier #2, #17
    add_to_Frontier #2, #18
    add_to_Frontier #2, #19
    add_to_Frontier #2, #20
    add_to_Frontier #2, #21
    add_to_Frontier #2, #22
    add_to_Frontier #2, #23
    add_to_Frontier #2, #24
    add_to_Frontier #2, #25
    add_to_Frontier #2, #26
    add_to_Frontier #2, #27
    add_to_Frontier #2, #28
    add_to_Frontier #2, #29
    add_to_Frontier #2, #30

    add_to_Frontier #3, #2
    add_to_Frontier #3, #3
    add_to_Frontier #3, #4
    add_to_Frontier #3, #5
    add_to_Frontier #3, #6
    add_to_Frontier #3, #7
    add_to_Frontier #3, #8
    add_to_Frontier #3, #9
    add_to_Frontier #3, #10
    add_to_Frontier #3, #11
    add_to_Frontier #3, #12
    add_to_Frontier #3, #13
    add_to_Frontier #3, #14
    add_to_Frontier #3, #15
    add_to_Frontier #3, #16
    add_to_Frontier #3, #17
    add_to_Frontier #3, #18
    add_to_Frontier #3, #19
    add_to_Frontier #3, #20
    add_to_Frontier #3, #21
    add_to_Frontier #3, #22
    add_to_Frontier #3, #23
    add_to_Frontier #3, #24
    add_to_Frontier #3, #25
    add_to_Frontier #3, #26
    add_to_Frontier #3, #27
    add_to_Frontier #3, #28
    add_to_Frontier #3, #29
    add_to_Frontier #3, #30

    add_to_Frontier #4, #2
    add_to_Frontier #4, #3
    add_to_Frontier #4, #4
    add_to_Frontier #4, #5
    add_to_Frontier #4, #6
    add_to_Frontier #4, #7
    add_to_Frontier #4, #8
    add_to_Frontier #4, #9
    add_to_Frontier #4, #10
    add_to_Frontier #4, #11
    add_to_Frontier #4, #12
    add_to_Frontier #4, #13
    add_to_Frontier #4, #14
    add_to_Frontier #4, #15
    add_to_Frontier #4, #16
    add_to_Frontier #4, #17
    add_to_Frontier #4, #18
    add_to_Frontier #4, #19
    add_to_Frontier #4, #20
    add_to_Frontier #4, #21
    add_to_Frontier #4, #22
    add_to_Frontier #4, #23
    add_to_Frontier #4, #24
    add_to_Frontier #4, #25
    add_to_Frontier #4, #26
    add_to_Frontier #4, #27
    add_to_Frontier #4, #28
    add_to_Frontier #4, #29
    add_to_Frontier #4, #30

    add_to_Frontier #5, #2
    add_to_Frontier #5, #3
    add_to_Frontier #5, #4
    add_to_Frontier #5, #5
    add_to_Frontier #5, #6
    add_to_Frontier #5, #7
    add_to_Frontier #5, #8
    add_to_Frontier #5, #9
    add_to_Frontier #5, #10
    add_to_Frontier #5, #11
    add_to_Frontier #5, #12
    add_to_Frontier #5, #13
    add_to_Frontier #5, #14
    add_to_Frontier #5, #15
    add_to_Frontier #5, #16
    add_to_Frontier #5, #17
    add_to_Frontier #5, #18
    add_to_Frontier #5, #19
    add_to_Frontier #5, #20
    add_to_Frontier #5, #21
    add_to_Frontier #5, #22
    add_to_Frontier #5, #23
    add_to_Frontier #5, #24
    add_to_Frontier #5, #25
    add_to_Frontier #5, #26
    add_to_Frontier #5, #27
    add_to_Frontier #5, #28
    add_to_Frontier #5, #29
    add_to_Frontier #5, #30

    add_to_Frontier #15, #$16
    
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile
    get_random_frontier_tile

    RTS
.endproc

;*****************************************************************
; Start
;       Gets called until the generation of the maze starts
;*****************************************************************
.proc start
    JSR gamepad_poll
    LDA gamepad
    AND #PAD_A
    BEQ A_NOT_PRESSED
        ;code for button press here  
        LDA a_pressed_last_frame
        BNE A_NOT_PRESSED           ;check for pressed this frame

        LDA #1
        STA has_generation_started         ;set map visible

        JSR display_map             ;copy map to ppu

        LDA #1
        STA a_pressed_last_frame
        JMP :+
    A_NOT_PRESSED:
        ;code for other buttons etc here
        LDA #0
        STA a_pressed_last_frame
    :

    INC RandomSeed 

    RTS
.endproc
;*****************************************************************

;*****************************************************************
; Graphics
;*****************************************************************
.segment "CODE"
.proc display_map
    JSR ppu_off
    JSR clear_nametable

    ;JSR run_prims_maze ;temporarily do this here every frame - this is just for resting and will be moved later.

    vram_set_address (NAME_TABLE_0_ADDRESS) 
    assign_16i paddr, MAP_BUFFER_ADDRESS    ;load map into ppu

    LDY #0          ;reset value of y
    loop:
        LDA (paddr),y   ;get byte to load
        TAX
        LDA #8          ;8 bits in a byte
        STA byte_loop_couter

        byteloop:
        TXA             ;copy x into a to preform actions on a copy
        set_Carry_to_highest_bit_A  ;rol sets bit 0 to the value of the carry flag, so we make sure the carry flag is set to the value of bit 7 to rotate correctly
        ROL             ;rotate to get the correct bit on pos 0
        TAX             ;copy current rotation back to x
        AND #%00000001  ;and with 1, to check if tile is filled
        STA PPU_VRAM_IO ;write to ppu

        DEC byte_loop_couter    ;decrease counter
        LDA byte_loop_couter    ;get value into A
        BNE byteloop            ;repeat byteloop if not done with byte yet

        INY
            CPY #MAP_BUFFER_SIZE              ;the screen is 120 bytes in total, so check if 120 bytes have been displayed to know if we're done
            BNE loop

        JSR ppu_update

        RTS
.endproc
;*****************************************************************

;*****************************************************************
; Simple Random number generation
;*****************************************************************
.segment "CODE"
.proc random_number_generator
    RNG:
        LDA RandomSeed  ; Load the current seed
        set_Carry_to_highest_bit_A ;to make sure the rotation happens properly (makes odd numbers possible)
        ROL             ; Shift left
        BCC NoXor       ; Branch if no carry
        EOR #$B4        ; XOR with a feedback value (tweak as needed)

    NoXor:
        STA RandomSeed  ; Store the new seed
        RTS             ; Return

.endproc
;*****************************************************************

;*****************************************************************
; The main algorithm loop (prims)
;*****************************************************************
.segment "CODE"
.proc run_prims_maze
    JSR random_number_generator
    STA MAP_BUFFER_ADDRESS

    RTS
.endproc
;*****************************************************************