;*****************************************************************
; Graphics utility functions
;*****************************************************************
.proc poll_clear_buffer
    LDA should_clear_buffer
    BEQ :+
        JSR clear_changed_tiles_buffer
        LDA #0
        STA should_clear_buffer
    :
    RTS
.endproc


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
    sta APU_DM_CONTROL
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
; Graphics 
;*****************************************************************
 ;Displays the map in one go
.segment "CODE"
.proc display_map
    JSR ppu_off
    JSR clear_nametable
    
    vram_set_address (NAME_TABLE_0_ADDRESS) 
    assign_16i paddr, maze_buffer    ;load map into ppu

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

;displays a clear map
.proc display_clear_map
    JSR ppu_off
    JSR clear_nametable

    ; Set PPU address to $2000 (nametable start)
    LDA #$20         ; High byte of address
    STA $2006
    LDA #$00         ; Low byte of address
    STA $2006

    LDA #07
    LDY #30
    rowloop:
        LDX #32
        columnloop:
            STA $2007        ; Write tile 0 to PPU data
            DEX
            BNE columnloop
        DEY
        BNE rowloop

    JSR ppu_update

    RTS
.endproc

;handles the background tiles during vblank using the buffers set in zero page
.proc draw_background
    ;update the map tiles
    LDY #0
    maploop: 
        LDX #0 ; flag wall or not
        LDA #0
        STA high_byte

        ;row
        LDA changed_tiles_buffer, y
        ;LDA #0
        CMP #$FF ;end of buffer
        BEQ done 
        STA low_byte

        ;1110 0000 -> 0000 0111
        ;extract the tileID  
        LSR
        LSR
        LSR
        LSR
        LSR

        TAX ;Store the 3-bit TileID in X (0-7)        

        LDA low_byte
        AND #%00011111 ; Clear the tileID from the row
        STA low_byte
        
        CLC
        ASL low_byte ;x2
        ROL high_byte
        ASL low_byte ;x2
        ROL high_byte
        ASL low_byte ;x2
        ROL high_byte
        ASL low_byte ;x2
        ROL high_byte
        ASL low_byte ;x2 == 32
        ROL high_byte

        LDA #$20 ;add high byte
        CLC
        ADC high_byte
        STA $2006
        
        ;col
        INY
        LDA changed_tiles_buffer, y
        ;LDA #0
        
        ADC low_byte
        STA $2006

        STX PPU_VRAM_IO

        INY
        CPY #CHANGED_TILES_BUFFER_SIZE
        BNE maploop    
    done: 
        LDA #1
        STA should_clear_buffer
.endproc

; populate oam buffer with player sprite
.segment "CODE"
.proc draw_player_sprite
    LDA has_game_started
    BEQ :+

    ldx #0 

    ;SPRITE 0
    lda player_y ;Y coordinate
    sta oam, x
    inx

    CLC
    LDA #$D0   ;tile pattern index
    ADC player_dir

    sta oam, x
    inx 

    lda #%00000000 ;flip bits to set certain sprite attributes
    sta oam, x
    inx

    lda player_x   ;X coordinate
    sta oam, x
    ;INX to go to the next sprite location 
    
    :
    rts

.endproc

;simply hides the sprite off screen
.proc clear_player_sprite
    LDX #0          ; Start at the first byte of the OAM (sprite 0 Y-coordinate)
    LDA #$F0        ; Y-coordinate off-screen
    STA oam, x      ; Write to OAM
    RTS
.endproc

;display the score
.proc display_score
    LDX #4

    LDA #SCORE_DIGIT_OFFSET
    ROL     ; x2
    ROL     ; x2 = x4
    STA temp
    
    LDA score_low

    CLC
    CMP #$0A
    BCC skip_modulo

    modulo score_low, #$0A  ;skip modulo if smaller than 10

    STA a_val               ;store remainder for later

    skip_modulo:

    JSR draw_digit
    CLC
    LDA temp
    SBC #SCORE_DIGIT_OFFSET
    STA temp    

    LDA score_low
    SEC
    SBC a_val

    divide10 score_low

    JSR draw_digit
    CLC
    LDA temp
    SBC #SCORE_DIGIT_OFFSET
    STA temp

    
    
    
    LDA score_high

    CLC
    CMP #$0A
    BCC skip_modulo2

    modulo score_high, #$0A  ;skip modulo if smaller than 10

    STA a_val               ;store remainder for later

    skip_modulo2:

    JSR draw_digit
    CLC
    LDA temp
    SBC #SCORE_DIGIT_OFFSET
    STA temp    

    LDA score_high
    SEC
    SBC a_val

    divide10 score_high

    JSR draw_digit
    CLC
    LDA temp
    SBC #SCORE_DIGIT_OFFSET
    STA temp

    ; JSR draw_digit
    ; CLC
    ; LDA temp
    ; ADC #SCORE_DIGIT_OFFSET     ;add 10 for x offset
    ; STA temp   
    
    
    ; divide10 score_high
    ; CLC
    ; CMP #$0A
    ; BCC skip_modulo

    ; modulo score_high, #$0A

    ; skip_modulo:

    ; JSR draw_digit
    ; CLC
    ; LDA temp
    ; ADC #SCORE_DIGIT_OFFSET
    ; STA temp    

    ; divide10 score_low

    ; JSR draw_digit
    ; CLC
    ; LDA temp
    ; ADC #SCORE_DIGIT_OFFSET     ;add 10 for x offset
    ; STA temp   
    
    
    ; divide10 score_low
    ; CLC
    ; CMP #$0A
    ; BCC skip_modulo2

    ; modulo score_low, #$0A

    ; skip_modulo2:

    ; JSR draw_digit
    ; CLC
    ; LDA temp
    ; ADC #SCORE_DIGIT_OFFSET
    ; STA temp    
    
    RTS
.endproc

;draws the digit stored in a reg
.proc draw_digit
    ;convert digit 0-9 to correct tile index
    CLC
    ADC #$10        ; get correct tile ID  
    TAY

    LDA #SCORE_DIGIT_OFFSET ;Y coordinate
    STA oam, x
    INX

    TYA
    STA oam, x
    INX 

    LDA #%00000001 ;flip bits to set certain sprite attributes
    STA oam, x
    INX

    LDA temp   ;X coordinate
    STA oam, x
    INX 

    RTS
.endproc

;*****************************************************************