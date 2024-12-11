.include "Header.s"
.include "Macros.s"

.include "TestCode.s"
.include "Graphics.s"
.include "Util.s"

.include "HardMode.s"
.include "Score.s"

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
; Main Gameloop
;*****************************************************************
.segment "CODE"
.proc main
    JSR Init

    mainloop:
        INC RandomSeed 

        ;only when not generating 
        LDA has_generation_started
        BNE :++
            ;poll input and similar
            JSR start

            ;auto generation once maze is completed (useful for debugging)
            ; LDA #1
            ; STA has_generation_started


            ;once per frame
            LDA checked_this_frame
            CMP #1
            BEQ mainloop

                LDA is_hard_mode
                CMP #0
                BEQ :+
                    JSR update_visibility
                :   

                JSR poll_clear_buffer

                ;JSR update_player_sprite
                jsr left_hand_rule


                LDA frame_counter ;sets last frame ct to the same as frame counter
                LDA #1
                STA checked_this_frame

                ;check if we reached the end
                LDA player_row
                CMP end_row
                BNE mainloop
                LDA player_collumn 
                CMP end_col
                BNE mainloop
                    LDA #1
                    STA has_generation_started

                JMP mainloop
        :

        ;only when generating
        LDA has_generation_started
        BEQ mainloop
            LDA #0
            STA has_game_started
            ;clear everything and display empty map at start of generation

            JSR clear_player_sprite

            JSR clear_maze
            JSR clear_changed_tiles_buffer
            JSR wait_frame
            JSR display_map

            JSR start_prims_maze

        LDA display_steps
        BEQ display_once

            step_by_step_generation_loop:
                JSR wait_frame ;wait until a vblank has happened

                modulo frame_counter, #MAZE_GENERATION_SPEED
                CMP #0
                BNE step_by_step_generation_loop

                JSR poll_clear_buffer
                JSR run_prims_maze
                
                LDA has_generation_started
                BEQ stop
                JMP step_by_step_generation_loop

            display_once: 
                JSR run_prims_maze
                LDA has_generation_started
                BNE display_once
                JSR display_map
                JMP stop

        stop:
            JSR calculate_prims_start_end
            JSR wait_frame

            JSR clear_changed_tiles_buffer
            LDA #0
            STA should_clear_buffer

            LDA is_hard_mode
            CMP #0
            BEQ :+
                JSR display_clear_map
                JSR start_hard_mode

            :

            LDA #1
            STA has_game_started

    JMP mainloop
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

    ;clear stuff
    JSR ppu_off
    JSR clear_nametable
    JSR ppu_update

    JSR clear_changed_tiles_buffer
    JSR clear_maze

    ;set an initial randomseed value - must be non zero
    LDA #$10
    STA RandomSeed
    
    ;run test code
    ;JSR test_frontier ;test code

    ;start generation immediately
    LDA #1
    STA has_generation_started

    ;display maze generation step-by-step
    LDA #1
    STA display_steps

    ;set gamemode
    LDA #0
    STA is_hard_mode
    
 ;   add_score #$FF
    add_score #10

    ;init solving direction
    lda #BOTTOM_D
    sta solving_local_direction ; start facing down



    RTS
.endproc
;*****************************************************************

;*****************************************************************
; Start
;       Gets called multiple times per frame as long as the maze is not being generated 
;*****************************************************************
.proc start
    JSR gamepad_poll
    LDA gamepad
    AND #PAD_A
    BEQ A_NOT_PRESSED

        LDA #1
        STA has_generation_started

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
; The main algorithm loop (prims)
;*****************************************************************
.segment "CODE"
.proc start_prims_maze
    ; step 0 of the maze generation, set a random cell as passage and calculate its frontier cells
    JSR random_number_generator
    modulo RandomSeed, #29
    ;LDA #29
    STA a_val
    STA frontier_row
    ;STA temp
    JSR random_number_generator
    modulo RandomSeed, #31
    ;LDA #31
    STA b_val
    STA frontier_col
    ;STA temp


    ;set the even / uneven row and col flag
    LDA #0
    STA odd_frontiers
    
    LDA frontier_row
    CMP #0
    BEQ end_row ;when zero were even
    
    modulo frontier_row, #2
    CMP #0
    BEQ end_row
        LDA #%11110000
        STA odd_frontiers 
    end_row:

    LDA frontier_col
    CMP #0
    BEQ end_col ;when zero were even  

    modulo frontier_col, #2
    CMP #0
    BEQ end_col
        LDA odd_frontiers 
        ORA #%00001111
        STA odd_frontiers
    end_col:

    set_map_tile a_val, b_val
    add_to_changed_tiles_buffer frontier_row, frontier_col, #1

        access_map_neighbor #LEFT_N, frontier_row, frontier_col
        CMP #0 
        BNE TopN

        JSR add_cell

    TopN: ;top neighbor
        access_map_neighbor #TOP_N, frontier_row, frontier_col
        CMP #0 
        BNE RightN

        JSR add_cell

    RightN: ;right neighbor
        access_map_neighbor #RIGHT_N, frontier_row, frontier_col
        CMP #0 
        BNE BottomN

        JSR add_cell

    BottomN: ;bottom neighbor
        access_map_neighbor #BOTTOM_N, frontier_row, frontier_col
        CMP #0
        BNE End

        JSR add_cell
 
    End: ;end

   RTS
.endproc

.segment "CODE"
.proc run_prims_maze
    loop:
    
    LDA execs
    CMP #3
    BNE :+
       RTS ;early return if debugging amt of execs is completed
    :
    ;calculate pages used to see if all are empty - if so the maze is finished
    calculate_pages_used
    LDA frontier_pages_used
    BNE :+

        LDA #0
        STA has_generation_started

        RTS ;early return if finished
    :

    ;useful for debugging but not necessary for algorithm    
    LDA #%11111111
    STA used_direction

    ;step one of the agorithm: pick a random frontier cell of the list
    get_random_frontier_tile ;returns col and row in x and y reg respectively | page and offset are maintained in a and b val
    
    ;store row and col in zero page to use in the access function.
    STX frontier_col
    STY frontier_row

    ;store a and b val in a new value since a and b will be overwritten in the access map neighbor function
    LDA a_val
    STA frontier_page
    LDA b_val
    STA frontier_offset


    ;pick a random neighbor of the frontier cell that's in state passage
    ;start a counter for the amt of dirs we can use on temp val (since its not used in any of the macros we call during this section)
    LDA #0
    STA temp

    access_map_neighbor #TOP_N, frontier_row, frontier_col
    CMP #1 ;we want something in state passage
    BNE :+
        ;valid cell, Jump to next step
        LDA #TOP_N 
        PHA ;push direction on stack
        INC temp
    : ;right
    access_map_neighbor #RIGHT_N, frontier_row, frontier_col
    CMP #1 ;we want something in state passage
    BNE :+
        ;valid cell, Jump to next step
        LDA #RIGHT_N 
        PHA ;push direction on stack
        INC temp

    : ;bottom
    access_map_neighbor #BOTTOM_N, frontier_row, frontier_col
    CMP #1 ;we want something in state passage
    BNE :+
        ;valid cell, Jump to next step
        LDA #BOTTOM_N 
        PHA ;push direction on stack
        INC temp        
    : ;left
    access_map_neighbor #LEFT_N, frontier_row, frontier_col
    CMP #1 ;we want something in state passage
    BNE :+
        ;valid cell, Jump to next step
        LDA #LEFT_N 
        PHA ;push direction on stack
        INC temp
    
    ;pick a random direction based on the temp counter
    :
    JSR random_number_generator
    modulo RandomSeed, temp ;stores val in A reg
    
    ;the total amt of pulls from stack is stored in X    
    LDX temp
    ;the direction idx we want to use is stored in A
    STA temp
    dirloop: 
        PLA
        
        DEX 

        CPX temp
        BNE :+
            STA used_direction
        :

        CPX #0
        BNE dirloop

    ;calculate the cell between picked frontier and passage cell and set this to a passage 
    nextstep: 
    LDA used_direction
    CMP #TOP_N
    BNE :+
        LDA frontier_row
        STA temp_row
        DEC temp_row

        LDA frontier_col
        STA temp_col
        JMP nextnextstep

    :; right
    CMP #RIGHT_N
    BNE :+
        LDA frontier_row
        STA temp_row

        LDA frontier_col
        STA temp_col
        INC temp_col
        JMP nextnextstep

    :; bottom
    CMP #BOTTOM_N
    BNE :+
        LDA frontier_row
        STA temp_row
        INC temp_row

        LDA frontier_col
        STA temp_col
        JMP nextnextstep

    : ;left
    CMP #LEFT_N
    BNE :+
        LDA frontier_row
        STA temp_row

        LDA frontier_col
        STA temp_col
        DEC temp_col
        JMP nextnextstep
    :
    ;wont reach this label in algorithm but useful for debugging 

    nextnextstep: 
        set_map_tile temp_row, temp_col
        add_to_changed_tiles_buffer temp_row, temp_col, #1

    ;calculate the new frontier cells for the chosen frontier cell and add them
        access_map_neighbor #LEFT_N, frontier_row, frontier_col
        CMP #0 
        BEQ :+
            JMP TopN
        :

        ;if exists check
        STY temp_row        
        STX temp_col
        exists_in_Frontier temp_row, temp_col
        CPX #1
        BEQ TopN 

        LDY temp_row
        LDX temp_col

        JSR add_cell

    TopN: ;top neighbor
        access_map_neighbor #TOP_N, frontier_row, frontier_col
        CMP #0 
        BEQ :+
            JMP RightN
        :

        ;if exists check
        STY temp_row        
        STX temp_col
        exists_in_Frontier temp_row, temp_col
        CPX #1
        BEQ RightN 

        LDY temp_row
        LDX temp_col

        JSR add_cell

    RightN: ;right neighbor
        access_map_neighbor #RIGHT_N, frontier_row, frontier_col
        CMP #0 
        BEQ :+
            JMP BottomN
        :

        ;if exists check
        STY temp_row        
        STX temp_col
        exists_in_Frontier temp_row, temp_col
        CPX #1
        BEQ BottomN

        LDY temp_row
        LDX temp_col

        JSR add_cell

    BottomN: ;bottom neighbor
        access_map_neighbor #BOTTOM_N, frontier_row, frontier_col
        CMP #0 
        BEQ :+
            JMP end
        :

        ;if exists check
        STY temp_row        
        STX temp_col
        exists_in_Frontier temp_row, temp_col
        CPX #1
        BEQ end

        LDY temp_row
        LDX temp_col

        JSR add_cell
    end: 
    ; ;remove the chosen frontier cell from the list
    set_map_tile frontier_row, frontier_col
    add_to_changed_tiles_buffer frontier_row, frontier_col, #1
    remove_from_Frontier frontier_page, frontier_offset

    ;INC execs
    ;JMP loop

    RTS
.endproc

.proc calculate_prims_start_end
    LDA odd_frontiers
    ;are rows even
    AND %11110000

    LDA odd_frontiers      
    AND #%11110000
    CMP #%11110000 
    BEQ :+
        JMP even_rows
    :
    ;uneven row means black border at top
    rowloop_ue:
    JSR random_number_generator
    modulo RandomSeed, #31
    STA temp

    get_map_tile_state #1, temp
    BEQ rowloop_ue

    set_map_tile #0, temp
    add_to_changed_tiles_buffer #0, temp, #1
    LDA #0
    STA player_row
    sta solving_row ; make sure solver starts at the beginning of the maze
    LDA temp
    STA player_collumn ;

    LDA #0
    STA player_y
    LDA player_collumn
    sta solving_collumn ; make sure solver starts at the beginning of the maze
    CLC
    ASL
    ASL
    ASL
    STA player_x

    JMP col_check

    ;even rows means black border at bottom, find a tile in row 30 with a white tile above to set as start pos
    even_rows:
        rowloop_e:
        JSR random_number_generator
        modulo RandomSeed, #31
        STA temp

        get_map_tile_state #28, temp
        BEQ rowloop_e

        set_map_tile #0, temp
        add_to_changed_tiles_buffer #29, temp, #1

        LDA #29
        STA player_row
        sta solving_row ; make sure the solving algorithm also starts at the players row
        LDA temp
        STA player_collumn

        LDA player_row
        CLC
        ASL
        ASL
        ASL
        STA player_y
        LDA player_collumn
        sta solving_collumn ; make sure the solving algorithm also starts at the players collumn
        CLC
        ASL
        ASL
        ASL
        STA player_x


    col_check: 
        LDA odd_frontiers
        ;are cols even
        AND 00001111

        LDA odd_frontiers      
        AND #%00001111
        CMP #%00001111 
        BEQ :+
            JMP even_cols
        :

        colloop_ue:
        JSR random_number_generator
        modulo RandomSeed, #29
        STA temp

        get_map_tile_state temp, #1
        BEQ colloop_ue

        set_map_tile temp, #0
        add_to_changed_tiles_buffer temp, #0, #1
        
        LDA temp
        STA end_row
        LDA #0
        STA end_col

        JMP end

    even_cols:
        colloop_e:
        JSR random_number_generator
        modulo RandomSeed, #29
        STA temp

        get_map_tile_state temp, #30
        BEQ colloop_e

        set_map_tile temp, #31
        add_to_changed_tiles_buffer temp, #31, #1

        LDA temp
        STA end_row
        LDA #31
        STA end_col

    end: 

    RTS
.endproc


;*****************************************************************

;*****************************************************************
; Player
;*****************************************************************
;update player position with player input
.proc update_player_sprite
    ;check is delay is reached
    modulo frame_counter, #PLAYER_MOVEMENT_DELAY
    CMP #0
    BEQ :+
        RTS
    :   

    lda gamepad
    and #PAD_D
    beq NOT_GAMEPAD_DOWN 
        ;gamepad down is pressed

        ;bounds check first
        LDA player_row
        CMP #MAP_ROWS - 1
        BNE :+
            JMP NOT_GAMEPAD_DOWN
        :   

        ;--------------------------------------------------------------
        ;COLLISION DETECTION
        ;--------------------------------------------------------------
        INC player_row
        get_map_tile_state player_row, player_collumn ;figure out which row and colom is needed
        ; a register now holds if the sprite is in a non passable area (0) or passable area (non zero)

        BEQ HitDown
            LDA player_y
            CLC 
            ADC #8 ; set position
            STA player_y
            JMP NOT_GAMEPAD_DOWN

        HitDown: 
            ;sprite collided with wall
            DEC player_row
            JMP NOT_GAMEPAD_DOWN
        

    NOT_GAMEPAD_DOWN: 
    lda gamepad
    and #PAD_U
    beq NOT_GAMEPAD_UP

        ;bounds check first
        LDA player_row
        BNE :+
            JMP NOT_GAMEPAD_UP
        :   

        ;--------------------------------------------------------------
        ;COLLISION DETECTION
        ;--------------------------------------------------------------
        DEC player_row
        get_map_tile_state player_row, player_collumn ;figure out which row and colom is needed
        ; a register now holds if the sprite is in a non passable area (0) or passable area (non zero)
        
        BEQ HitUp
        LDA player_y
        SEC 
        SBC #8 ; set position
        sta player_y
        JMP NOT_GAMEPAD_UP

        HitUp: 
            ;sprite collided with wall
            INC player_row
            JMP NOT_GAMEPAD_UP

    NOT_GAMEPAD_UP: 
    lda gamepad
    and #PAD_L
    beq NOT_GAMEPAD_LEFT
        ;gamepad left is pressed

        ;bounds check first
        LDA player_collumn
        BNE :+
            JMP NOT_GAMEPAD_LEFT
        :

        ;--------------------------------------------------------------
        ;COLLISION DETECTION
        ;--------------------------------------------------------------
        DEC player_collumn

        get_map_tile_state player_row, player_collumn ;figure out which row and colom is needed
        ; a register now holds if the sprite is in a non passable area (0) or passable area (non zero)

        BEQ HitLeft
            LDA player_x
            SEC 
            SBC #8 ; set position
            STA player_x
            JMP NOT_GAMEPAD_LEFT


        HitLeft: 
            ;sprite collided with wall
            INC player_collumn
            JMP NOT_GAMEPAD_LEFT


    NOT_GAMEPAD_LEFT: 
    lda gamepad
    and #PAD_R
    beq NOT_GAMEPAD_RIGHT
        ;bounds check first
        LDA player_collumn
        CMP #MAP_COLUMNS - 1
        BNE :+
            JMP NOT_GAMEPAD_RIGHT
        :

        ;--------------------------------------------------------------
        ;COLLISION DETECTION
        ;--------------------------------------------------------------
        INC player_collumn
        
        get_map_tile_state player_row, player_collumn ;figure out which row and colom is needed
        ; a register now holds if the sprite is in a non passable area (0) or passable area (non zero)

        BEQ HitRight
            LDA player_x
            CLC 
            ADC #8 ; set position
            STA player_x
            JMP NOT_GAMEPAD_RIGHT

        HitRight: 
            ;sprite collided with wall
            DEC player_collumn
            JMP NOT_GAMEPAD_RIGHT


    NOT_GAMEPAD_RIGHT: 
        ;neither up, down, left, or right is pressed
    RTS
.endproc

;****************************************************************
;MAZE SOLVER
;****************************************************************
.proc left_hand_rule

    ;-----------------------------------------------------------
    ;CAP THE ROW AND COLLUMN
    ;-----------------------------------------------------------
    ; lda solving_row      
    ; cmp #29              
    ; bcc :+               ; Branch if value is less than or equal to 29 (Carry Clear)
    ; lda #29              ; If value > 29, load 29 into the accumulator
    ; dec solving_local_direction
    ; sta solving_row 
 
    ; :   
    ; sta solving_row
    ; cmp #0                ; Compare solving_row with 0
    ; bcs :+                ; Branch if value is >= 0 (Carry Set)
    ; lda #0          
    ; dec solving_local_direction      ; If value < 0, load 0 into the accumulator
    ; sta solving_row    

    ; :
    ; lda solving_collumn 
    ; cmp #31              
    ; bcc :+       
    ; lda #31        
    ; dec solving_local_direction      
    ; sta solving_collumn 
    ; :    
    ; sta solving_collumn
    ; cmp #0                ; Compare solving_row with 0
    ; bcs value_ok               ; Branch if value is >= 0 (Carry Set)
    ; lda #0          
    ; dec solving_local_direction      ; If value < 0, load 0 into the accumulator
    ; sta solving_collumn    



    value_ok:


    ;---------------------------------------------------------------------------------------------------------------------------
    ;WHEN SOLVING, UPDATE PLAYER MOVEMENT OUTSIDE OF INPUT FROM PLAYER (WE SHOULD DISABLE THE PLAYER_UPDATE IN THIS MODE)
    ;---------------------------------------------------------------------------------------------------------------------------
    lda solving_row
    sta player_row
    asl            ; Multiply by 2 
    asl            ; Multiply by 4 
    asl            ; Multiply by 8 
    sta player_y  ;set y position

    lda solving_collumn
    sta player_collumn
    asl
    asl
    asl 
    sta player_x ;set x position


    ;----------------------------------------------------------
    ;DRAW CELL
    ;----------------------------------------------------------
    add_to_changed_tiles_buffer solving_row, solving_collumn, #2 

    ;----------------------------------------------------------
    ;MAKE SURE LOCAL DIRECTION IS WITHIN RANGE 0-3
    ;----------------------------------------------------------
    lda solving_local_direction
    cmp #$FF        ; Check if A went below 0 (will become $FF due to underflow)
    bne SkipWrap    ; If not $FF, skip wrapping
    lda #$03        ; Wrap around to 3 if A is $FF
    sta solving_local_direction

    SkipWrap:
    ;solver_local_direction now contains a value between 0-3

    ;---------------------------------------------------------
    ;LOAD LOCAL DIRECTION OF TILE
    ;---------------------------------------------------------
    sta solving_local_direction ; direction is TOP
    cmp #TOP_D
    beq DIRECTION_IS_TOP
    cmp #BOTTOM_D
    beq dir_is_bottom_intermediate
    cmp #RIGHT_D
    beq dir_is_right_intermediate
    cmp #LEFT_D
    beq dir_is_left_intermediate

    dir_is_right_intermediate :
        jmp DIRECTION_IS_RIGHT ;intermediate jump cause of range error
    dir_is_left_intermediate :
        jmp DIRECTION_IS_LEFT ;intermediate jump cause of range error
    dir_is_bottom_intermediate : 
        jmp DIRECTION_IS_BOTTOM ; intermediate jump cause of range error

        
    ;**********************
    ;MAIN ALGORITHM START
    ;**********************
    DIRECTION_IS_TOP: 
    ;---------------------------------------
    ;CHECK LEFT TILE
    ;---------------------------------------
        lda solving_collumn
        sec 
        sbc #1 ;tile to the left is current collumn - 1
        sta temp_solving_collumn

        get_map_tile_state solving_row, temp_solving_collumn ; a register now holds passable (!0) or non passable (0)

        bne :+                           ; Branch to the intermediate jump if Z flag is not set
        jmp AFTER_BRANCH4            ; If Z flag is set, skip the jump and continue here
        :
        jmp LEFT_TILE_IS_PASSABLE_REL_TOP
        AFTER_BRANCH4:
        ;-------------------------------------------------------
        ;LEFT TILE NOT PASSABLE, CHECK IF WE CAN MOVE FORWARDS
        ;------------------------------------------------------
            lda solving_row
            sec 
            sbc #1 ;tile to the top is row - 1
            sta temp_solving_row; rotate local direction to the left
            get_map_tile_state temp_solving_row, solving_collumn ; a register now holds passable (!0) or non passable (0)

            bne FORWARDS_TOP_PASSABLE
            ;---------------------------------------------------------------
            ;MOVING FORWARDS NOT POSSIBLE, SO WE CHECK IF RIGHT IS POSSIBLE
            ;---------------------------------------------------------------
            moving_forward_not_possible_row: 
                lda solving_collumn
                clc
                adc #1 ;tile to the right is collumn + 1
                sta temp_solving_collumn; 
                get_map_tile_state solving_row, temp_solving_collumn ; a register now holds passable (!0) or non passable (0)

                bne RIGHT_TOP_PASSABLE
                    moving_right_not_possible: 
                    ;---------------------------------
                    ;RIGHT NOT POSSIBLE, SO WE ROTATE
                    ;---------------------------------
                    dec solving_local_direction
                    rts

                RIGHT_TOP_PASSABLE:
                    ;--------------------------------
                    ;RIGHT POSSIBLE, SO MOVE RIGHT
                    ;--------------------------------
                    LDA solving_collumn        ; Load the value of solving_collumn
                    CMP #31                   ; Compare solving_collumn with 31
                    BEQ SkipMoveRight         ; If it's 31, skip the increment

                    INC solving_collumn        ; Increment solving_collumn (move right)
                    LDA #RIGHT_D              ; Update the local direction to RIGHT
                    STA solving_local_direction
                    RTS                        ; Return from subroutine

                SkipMoveRight:
                ; MOVING RIGHT IS NOT POSSIBLE
                    jmp moving_right_not_possible
                     

            FORWARDS_TOP_PASSABLE: 
            ;----------------------------------------------
            ;MOVING FORWARDS IS POSSIBLE, SO WE DO
            ;----------------------------------------------

                
                LDA solving_row            ; Load the value of solving_row
                BEQ SkipMoveForwardRow        ; If solving_row is 0, skip the decrement

                DEC solving_row            ; Decrement solving_row (move forward)
                LDA #TOP_D                 ; Update the local direction to TOP
                STA solving_local_direction
                RTS                        ; Return from subroutine

                SkipMoveForwardRow:
                ; MOVING FORWARD NOT POSSIBLE
                jmp moving_forward_not_possible_row

        LEFT_TILE_IS_PASSABLE_REL_TOP: 
        ;----------------------------------------------
        ;LEFT TILE IS PASSABLE, SO WE MOVE LEFT
        ;----------------------------------------------

            LDA solving_collumn        ; Load the value of solving_collumn
            BEQ SkipMoveLeft           ; If solving_collumn is 0, skip the decrement

            DEC solving_collumn        ; Decrement solving_collumn (move left)
            LDA #LEFT_D                ; Update the local direction to LEFT
            STA solving_local_direction
            RTS                        ; Return from subroutine

        SkipMoveLeft:
            ;LEFT TILE IS NOT PASSABLE
            jmp AFTER_BRANCH4
    DIRECTION_IS_BOTTOM: 
    ;----------------------------------------
    ;CHECK LEFT TILE
    ;----------------------------------------

    ;relative to rasterspace it is the right tile
        lda solving_collumn
        clc 
        adc #1 ;tile to the left is current collum + 1
        sta temp_solving_collumn
        get_map_tile_state solving_row, temp_solving_collumn ;passable (non zero) non passable (0)


       
        bne :+                           ; Branch to the intermediate jump if Z flag is not set
        jmp AFTER_BRANCH3             ; If Z flag is set, skip the jump and continue here
        :
        jmp LEFT_TILE_PASSABLE_REL_BOTTOM
        AFTER_BRANCH3:
        ;-------------------------------------------------------
        ;LEFT TILE NOT PASSABLE, CHECK IF WE CAN MOVE FORWARDS
        ;------------------------------------------------------
            lda solving_row
            clc 
            adc #1 ;tile to the bottom is row + 1
            sta temp_solving_row; rotate local direction to the left
            get_map_tile_state temp_solving_row, solving_collumn ; a register now holds passable (!0) or non passable (0)

            bne FORWARDS_BOTTOM_PASSABLE
           ;---------------------------------------------------------------
            ;MOVING FORWARDS NOT POSSIBLE, SO WE CHECK IF RIGHT IS POSSIBLE
            ;---------------------------------------------------------------
            moving_forward_not_possible_row2: 
                lda solving_collumn
                sec
                sbc #1 
                sta temp_solving_collumn; 
                get_map_tile_state solving_row, temp_solving_collumn ; a register now holds passable (!0) or non passable (0)

                bne RIGHT_BOTTOM_PASSABLE
                    ;---------------------------------
                    ;RIGHT NOT POSSIBLE, SO WE ROTATE
                    ;---------------------------------
                    right_not_possible: 
                    dec solving_local_direction
                    rts

                RIGHT_BOTTOM_PASSABLE:
                    ;--------------------------------
                    ;RIGHT POSSIBLE, SO MOVE RIGHT
                    ;--------------------------------

                    LDA solving_collumn        ; Load the value of solving_collumn
                    BEQ SkipMoveLeft1           ; If solving_collumn is 0, skip the decrement

                    DEC solving_collumn        ; Decrement solving_collumn (move left)
                    LDA #LEFT_D                ; Update the local direction to LEFT
                    STA solving_local_direction
                    RTS                        ; Return from subroutine

                SkipMoveLeft1:
                    ;RIGHT NOT POSSIBLE
                    jmp right_not_possible

            FORWARDS_BOTTOM_PASSABLE: 
            ;----------------------------------------------
            ;MOVING FORWARDS IS POSSIBLE, SO WE DO
            ;----------------------------------------------

            LDA solving_row            ; Load the value of solving_row
            CMP #29                   ; Compare solving_row with 29
            BEQ SkipMoveDown        ; If solving_row is 29, skip the increment

            INC solving_row            ; Increment solving_row (move down)
            LDA #BOTTOM_D             ; Update the local direction to BOTTOM
            STA solving_local_direction
            RTS                        ; Return from subroutine

            SkipMoveDown:
            ;MOVING FORWARDS NOT POSSIBLE
            jmp moving_forward_not_possible_row2


    LEFT_TILE_PASSABLE_REL_BOTTOM: 
    ;-----------------------------------------------
    ;LEFT TILE IS PASSABLE, SO WE MOVE THERE
    ;-----------------------------------------------
            LDA solving_collumn        ; Load the value of solving_collumn
            CMP #31                   ; Compare solving_collumn with 31
            BEQ SkipMoveRight1         ; If it's 31, skip the increment

            INC solving_collumn        ; Increment solving_collumn (move right)
            LDA #RIGHT_D              ; Update the local direction to RIGHT
            STA solving_local_direction
            RTS                        ; Return from subroutine

            SkipMoveRight1:
                ;LEFT TILE NOT PASSABLE
                jmp AFTER_BRANCH3

    DIRECTION_IS_RIGHT: 
    ;if direction is right then check top tile
        lda solving_row
        sec
        sbc #1
        sta temp_solving_row

        get_map_tile_state temp_solving_row, solving_collumn ;passable (0) non passable (!0)

        bne :+                          
        jmp AFTER_BRANCH2             
        :
        jmp LEFT_TILE_PASSABLE_REL_RIGHT
        AFTER_BRANCH2:
        ;-------------------------------------------------------
        ;LEFT TILE NOT PASSABLE, CHECK IF WE CAN MOVE FORWARDS
        ;------------------------------------------------------
            lda solving_collumn
            clc 
            adc #1 ;tile to the top is row - 1
            sta temp_solving_collumn; rotate local direction to the left
            get_map_tile_state solving_row, temp_solving_collumn ; a register now holds passable (!0) or non passable (0)

            bne FORWARDS_RIGHT_PASSABLE
            moving_forward_not_possible1: 
            ;---------------------------------------------------------------
            ;MOVING FORWARDS NOT POSSIBLE, SO WE CHECK IF RIGHT IS POSSIBLE
            ;---------------------------------------------------------------
                lda solving_row
                clc
                adc #1 ;tile to the right is collumn + 1
                sta temp_solving_row; 
                get_map_tile_state temp_solving_row, solving_collumn ; a register now holds passable (!0) or non passable (0)

                bne RIGHT_RIGHT_PASSABLE
                    ;---------------------------------
                    ;RIGHT NOT POSSIBLE, SO WE ROTATE
                    ;---------------------------------
                    right_not_possible3:
                    dec solving_local_direction
                    rts

                RIGHT_RIGHT_PASSABLE:
                    ;--------------------------------
                    ;RIGHT POSSIBLE, SO MOVE RIGHT
                    ;--------------------------------
                    LDA solving_row          
                    CMP #29                   
                    BEQ SkipMoveDown2          

                    INC solving_row            
                    LDA #BOTTOM_D             
                    STA solving_local_direction
                    RTS                        

                SkipMoveDown2:
                    ; RIGHT NOT POSSIBLE 
                    jmp right_not_possible3

            FORWARDS_RIGHT_PASSABLE: 
            ;----------------------------------------------
            ;MOVING FORWARDS IS POSSIBLE, SO WE DO
            ;----------------------------------------------

                LDA solving_collumn        ; Load the value of solving_collumn
                CMP #31                   ; Compare solving_collumn with 31
                BEQ SkipMoveRight2         ; If it's 31, skip the increment

                INC solving_collumn        ; Increment solving_collumn (move right)
                LDA #RIGHT_D              ; Update the local direction to RIGHT
                STA solving_local_direction
                RTS                        ; Return from subroutine

            SkipMoveRight2:
             ; MOVING FORWARD IS NOT POSSIBLE 
             jmp moving_forward_not_possible1

        LEFT_TILE_PASSABLE_REL_RIGHT: 
            ;---------------------------------
            ;LEFT TILE PASSABLE
            ;---------------------------------
            ;move left relative to direction (up in rasterspace)

            LDA solving_row            ; Load the value of solving_row
            BEQ SkipMoveForwardRow2        ; If solving_row is 0, skip the decrement

            DEC solving_row            ; Decrement solving_row (move forward)
            LDA #TOP_D                 ; Update the local direction to TOP
            STA solving_local_direction
            RTS                        ; Return from subroutine

        SkipMoveForwardRow2:
        ; LEFT TILE NOT PASSABLE
            jmp AFTER_BRANCH2

    DIRECTION_IS_LEFT: 
    ;if direction is left then check bottom tile
        lda solving_row
        clc
        adc #1
        sta temp_solving_row

        get_map_tile_state temp_solving_row, solving_collumn ; passable(0) non passable(!0)

        bne :+                          
        jmp AFTER_BRANCH             
        :
        jmp LEFT_TILE_PASSABLE_REL_LEFT 
        AFTER_BRANCH:
        ;-------------------------------------------------------
        ;LEFT TILE NOT PASSABLE, CHECK IF WE CAN MOVE FORWARDS
        ;------------------------------------------------------
            lda solving_collumn
            sec 
            sbc #1 ;tile to the top is col - 1
            sta temp_solving_collumn; rotate local direction to the left
            get_map_tile_state solving_row, temp_solving_collumn ; a register now holds passable (!0) or non passable (0)

            bne FORWARDS_LEFT_PASSABLE
            moving_forward_not_possible:
            ;---------------------------------------------------------------
            ;MOVING FORWARDS NOT POSSIBLE, SO WE CHECK IF RIGHT IS POSSIBLE
            ;---------------------------------------------------------------
                lda solving_row
                sec
                sbc #1 
                sta temp_solving_row; 
                get_map_tile_state temp_solving_row, solving_collumn ; a register now holds passable (!0) or non passable (0)

                bne RIGHT_LEFT_PASSABLE
                    ;---------------------------------
                    ;RIGHT NOT POSSIBLE, SO WE ROTATE
                    ;---------------------------------
                    right_not_possible2:
                    dec solving_local_direction
                    rts

                RIGHT_LEFT_PASSABLE:
                    ;--------------------------------
                    ;RIGHT POSSIBLE, SO MOVE RIGHT
                    ;--------------------------------
                    
                    LDA solving_row            ; Load the value of solving_row
                    BEQ SkipMoveForwardRow3        ; If solving_row is 0, skip the decrement

                    DEC solving_row            ; Decrement solving_row (move forward)
                    LDA #TOP_D                 ; Update the local direction to TOP
                    STA solving_local_direction
                    RTS                        ; Return from subroutine

                    SkipMoveForwardRow3:
                    ;RIGHT NOT POSSIBLE
                    jmp right_not_possible2
            FORWARDS_LEFT_PASSABLE: 
            ;----------------------------------------------
            ;MOVING FORWARDS IS POSSIBLE, SO WE DO
            ;----------------------------------------------

                LDA solving_collumn        ; Load the value of solving_collumn
                BEQ SkipMoveLeft2           ; If solving_collumn is 0, skip the decrement

                DEC solving_collumn        ; Decrement solving_collumn (move left)
                LDA #LEFT_D                ; Update the local direction to LEFT
                STA solving_local_direction
                RTS                        ; Return from subroutine

        SkipMoveLeft2:
                ;MOVING FORWARDS NOT POSSIBLE
                jmp moving_forward_not_possible

        LEFT_TILE_PASSABLE_REL_LEFT:
            ;--------------------------- 
            ;LEFT TILE PASSABLE
            ;----------------------------
            ;move left relative to direction (bottom in rasterspace)
            LDA solving_row            ; Load the value of solving_row
            CMP #29                   ; Compare solving_row with 29
            BEQ SkipMoveDown3          ; If solving_row is 29, skip the increment

            INC solving_row            
            LDA #BOTTOM_D             
            STA solving_local_direction
            RTS                        ;

            SkipMoveDown3:
            ; LEFT TILE NOT PASSABLE
            jmp AFTER_BRANCH




.endproc


;*****************************************************************