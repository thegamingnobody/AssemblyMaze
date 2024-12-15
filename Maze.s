.include "Header.s"
.include "Macros.s"

; hardware
.include "Graphics.s"
.include "Util.s"
.include "TestCode.s"

; gameplay
.include "HardMode.s"
.include "Score.s"
.include "Player.s"

; algorithms
.include "Prims.s"
.include "LeftHandRule.s"
.include "BFS.s"

;*****************************************************************
; Interupts | Vblank
;*****************************************************************
.segment "CODE"
irq:
	RTI

;only caused by vblank right now
.proc nmi
    ;save registers
    PHA
    TXA
    PHA
    TYA
    PHA
    
    BIT PPU_STATUS

    ;increase our frame counter (one vblank occurs per frame)
    INC frame_counter
    LDA #0
    STA checked_this_frame

    JSR draw_background
    JSR draw_player_sprite
    JSR display_score

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
; init
;*****************************************************************
.segment "CODE"
.proc init
    LDX #0
    palette_loop:
        LDA default_palette, x  ;load palettes
        STA palette, x
        INX
        CPX #32
        BCC palette_loop

    ;clear stuff
    JSR ppu_off
    JSR clear_nametable
    JSR ppu_update

    JSR clear_changed_tiles_buffer

    ;set an initial randomseed value - must be non zero
    LDA #$10
    STA random_seed

    LDA #$FF
    STA player_row
    STA player_collumn

    ;start generation immediately
    LDA #0
    STA current_game_mode
    STA has_started

    JSR reset_generation
            
    ;run test code
    ;JSR test_frontier ;test code
    ;JSR test_queue

    ; 000G HSSS
    LDA #%00000001
    ORA #HARD_MODE_MASK
   ; ORA #GAME_MODE_MASK

    STA input_game_mode

    RTS
.endproc
;*****************************************************************

;*****************************************************************
; Main Gameloop
;*****************************************************************
.segment "CODE"
.proc main
    JSR init

    mainloop:
        INC random_seed  ; Chnage the random seed as many times as possible per frame
        
        LDA current_game_mode
        ;------------;
        ; GENERATING ;
        ;------------;
        @GENERATING: 
            CMP #0
            BNE @PLAYING

            ; ONCE PER FRAME
            LDA checked_this_frame
            CMP #1
            BEQ mainloop
                LDA #1
                STA checked_this_frame ; set flag so that we only do this once per frame

                JSR poll_clear_buffer ; clear buffer if necessary

                ; Have we started the algorithm yet? if not, execute the start function once
                LDA has_started
                CMP #0
                BNE :+

                    JSR start_prims_maze
                    LDA #1
                    STA has_started
                :

                ;slow down generation if necessary
                modulo frame_counter, #MAZE_GENERATION_SPEED
                CMP #0
                BNE mainloop
                JSR run_prims_maze ; whether or not the algorithm is finished is stored in the A register (0 when not finished)

                ; Has the maze finished generating?
                CMP #0
                BEQ :++
                    JSR calculate_prims_start_end

                    ; reset some flags for the next game mode so that they could be reused
                    LDA #0
                    STA has_started

                    ; Select correct gamemode after generating  
                    LDA input_game_mode
                    AND #GAME_MODE_MASK
                    CMP #GAME_MODE_MASK
                    BEQ :+
                        LDA #1 
                        STA current_game_mode
                        JMP @END
                    :
                    LDA #2
                    STA current_game_mode
                :

                JMP @END

        ;---------;
        ; PLAYING ;
        ;---------;
        @PLAYING: 
            CMP #1
            BNE @SOLVING
            
            JSR input_logic ; poll input as often as possible

            ; ONCE PER FRAME
            LDA checked_this_frame
            CMP #1
            BEQ mainloop
                LDA #1
                STA checked_this_frame ; set flag so that we only do this once per frame
                
                JSR poll_clear_buffer ; clear buffer if necessary

                ; Have we started the game yet? if not, execute the start function once
                LDA has_started
                CMP #0
                BNE :+ 
                    JSR start_game
                    LDA #1
                    STA has_started ;set started to 1 so that we start drawing the sprite
                :

                JSR update_player_sprite
                
                ; are we in hard mode?
                LDA input_game_mode
                AND #HARD_MODE_MASK
                CMP #0
                BEQ :+
                    JSR update_visibility
                :

                ; Has the player reached the end?
                LDA player_row
                CMP end_row
                BNE @END
                LDA player_collumn
                CMP end_col
                BNE @END

                ; ONLY EXECUTED WHEN END IS REACHED
                ; reset some flags for the next game mode so that they could be reused
                LDA #0
                STA has_started

                LDA #0 ;set the gamemode to generating
                STA current_game_mode
                JSR reset_generation

                JMP @END

        ;---------;
        ; SOLVING ;
        ;---------;
        @SOLVING: 
            CMP #2
            BNE @END

            ; ONCE PER FRAME
            LDA checked_this_frame
            CMP #1
            BEQ @END
                LDA #1
                STA checked_this_frame ; set flag so that we only do this once per frame

                JSR poll_clear_buffer ; clear buffer if necessary

                ; Have we started the solving algorithm yet? if not, execute the start function once
                LDA has_started
                CMP #0
                BNE :+++ 
                    ;which solve mode do we have to start?
                    LDA input_game_mode
                    AND #SOLVE_MODE_MASK
                    CMP #0 ;BFS
                    BNE :+ 
                        JSR start_BFS
                        JMP :++
                    :
                    CMP #1 ;left hand
                    BNE :+
                        ;start left hand
                    :

                    LDA #1
                    STA has_started 
                :

                ; execute one step of the algorithm
                LDA input_game_mode
                AND #SOLVE_MODE_MASK
                @BFS_SOLVE: 
                    CMP #0 ;BFS
                    BNE @LFR_SOLVE
                    JSR step_BFS

                    LDA is_backtracking
                    CMP #$FF                 
                    BEQ @SOLVE_END_REACHED

                    JMP @END_SOLVE_MODES
                @LFR_SOLVE: 
                    CMP #1 ;LFR
                    BNE @END_SOLVE_MODES
                    JSR left_hand_rule

                    ; check if player reached end
                    LDA player_row
                    CMP end_row
                        BNE @END_SOLVE_MODES
                    LDA player_collumn 
                    CMP end_col
                        BNE @END_SOLVE_MODES

                    JMP @SOLVE_END_REACHED
                @END_SOLVE_MODES: 
                    JMP @END
                
                @SOLVE_END_REACHED: 
                    ; back to generating
                    LDA #0 ;set the gamemode to generating
                    STA current_game_mode
                    STA has_started

                    JSR reset_generation

                    JMP @END

        @END: 
            JMP mainloop
.endproc
;*****************************************************************

;*****************************************************************
; Start
;       Gets called multiple times per frame
;*****************************************************************
.proc input_logic
    JSR gamepad_poll
    LDA gamepad
    AND #PAD_A
    BEQ A_NOT_PRESSED


        JMP :+
    A_NOT_PRESSED:

    :
    RTS
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
; Gameplay
;*****************************************************************
; resets everything necessary so that the maze generation can start again
.proc reset_generation
    JSR hide_player_sprite
    JSR clear_changed_tiles_buffer
    JSR clear_maze
    JSR display_map
    
    RTS
.endproc

.proc start_game
    
    LDA input_game_mode
    AND #HARD_MODE_MASK
    CMP #0
    BEQ :+
        JSR display_clear_map
        JSR start_hard_mode
    :
    RTS
.endproc 
;*****************************************************************
