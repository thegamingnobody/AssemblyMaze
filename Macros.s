.macro vram_set_address newaddress
    lda PPU_STATUS
    lda #>newaddress
    sta PPU_VRAM_ADDRESS2
    lda #<newaddress
    sta PPU_VRAM_ADDRESS2
.endmacro

.macro assign_16i dest, value
    lda #<value
    sta dest+0
    lda #>value
    sta dest+1
.endmacro

.macro vram_clear_address
    lda #0
    sta PPU_VRAM_ADDRESS2
    sta PPU_VRAM_ADDRESS2
.endmacro

.macro set_Carry_to_highest_bit_A
    cmp #%10000000
    bmi :+
    sec
    jmp :++
    :
    clc
    :
.endmacro
;*****************************************************************
; Vblank buffers
;*****************************************************************
; most significant bits are set to 000 - 111 (tileID 0-7 of the row)
.macro add_to_changed_tiles_buffer Row, Col, TileID
    LDY #0
    .local loop
    loop:

        LDA changed_tiles_buffer, y
        CMP #$FF
        BEQ add_vals
        
        INY
        INY

        CPY #CHANGED_TILES_BUFFER_SIZE - 2
        BNE loop

    .local add_vals
    add_vals:
        ;convert tileID (0000 0111) to te correct bits (1110 0000)
        LDA TileID

        ASL			
        ASL			
        ASL			
        ASL			
        ASL			

        ORA Row

        STA changed_tiles_buffer, y
        INY
        LDA Col
        STA changed_tiles_buffer, y
.endmacro
;*****************************************************************

;*****************************************************************
; Map buffer macros
;*****************************************************************
;Example: 
;Column: 0123 4567  89...
; Row 0: 0000 0000  0000 0000   0000 0000   0000 0000   0000 0000
; Row 1: 0000 0000  0000 0000   0000 0000   0000 0000   0000 0000
;...


;util macro to calculate the mask and address for a given tile
;mask: the bitmask for the requested row and column
;e.g row 0, column 1 == 0100 0000
;address: the address in the buffer for the requested row and column
;e.g row 2, column 1 == $00 + $4 == $04
.macro calculate_tile_address_and_mask Row, Column
    ;Calculate the base address of the row (Row * 4)
    LDA Row
    ASL             ;== times 2
    ASL             ;== times 2
    CLC
    ADC #maze_buffer ; Add base address of the map buffer
    STA x_val

    ;Calculate the byte offset within the row (Column / 8)
    LDA Column
    LSR
    LSR
    LSR
    STA y_val

    ;Add the byte offset to the base row address
    LDA x_val
    CLC 
    ADC y_val
    STA temp_address
    
    ; bitmask: 
    ;Clamp the 0-31 Column to 0-7 
    LDA Column
    : ;Loop
    CMP #$08       ; Compare the number with 8 (i.e., check if it's greater than 7)
    BCC :+         ; If the number is less than or equal to 7, branch to Done
    SEC            ; Set the Carry flag before subtraction (since we're subtracting)
    SBC #$08       ; Subtract 8 from the number
    JMP :-

    : ;end clamp loop
    STA x_val

    LDA #%00000001
    STA y_val

    ;Calculate how many times we should shift
    LDA #7
    SEC
    SBC x_val    
    BEQ :++
    TAX
    
    LDA y_val
    :    
    ASL
    DEX
    BNE :-

    STA y_val
    :
.endmacro

;loads the state for a given tile in the A register - 0 when not passable, or any bit is set when it is passable
;Row: Row index in the map buffer (0 to MAP_ROWS - 1)
;Column:  Column index (0 to 31, across 4 bytes per row);
.macro get_map_tile_state Row, Column
    calculate_tile_address_and_mask Row, Column

    LDY #0
    LDA (temp_address), Y   
    AND y_val
.endmacro

;sets the state for a given cell of the map to passage (1)
;Row: Row index in the map buffer (0 to MAP_ROWS - 1)
;Column:  Column index (0 to 31, across 4 bytes per row);
.macro set_map_tile Row, Column
    calculate_tile_address_and_mask Row, Column
    
    LDY #0
    LDA (temp_address), Y   
    ORA y_val
    STA (temp_address), Y
.endmacro

.macro bounds_check_neighbor Direction, Row, Col
    ;Jump to the correct direction check
    LDA Direction
    CMP #TOP_N
    BEQ :+

    CMP #RIGHT_N
    BEQ :++

    CMP #BOTTOM_N
    BEQ :+++

    CMP #LEFT_N
    BEQ :++++

    JMP :+++++ ;no valid direction, invalid neighbor

    : ;top check
    ; If Row is 0 or 1, it's out of bounds
    LDA Row
    CMP #2 
    BCC :++++ ; row < 2
    JMP :+++++ 

    : ;right check
    ; If col is 31 or 30, it's out of bounds
    LDA Col
    CMP #30
    BCS :+++ ; col >= 30
    JMP :++++ 

    : ;bottom check
    ; If Row is 28 or 29, it's out of bounds
    LDA Row
    CMP #28
    BCS :++ ; row >= 28
    JMP :+++ 

    : ;left check
    ; If col is 0 or 1, it's out of bounds
    LDA Col
    CMP #2 
    BCC :+ ; col < 2
    JMP :++ 

    : ;out of bounds
    LDA #$0 ;0 indicates invalid neighbor
    JMP :++

    : ;in bounds
    LDA #$1 ;1 indicates valid neighbor 

    : ;end
.endmacro

; stores the new row and col in Y and X reg
.macro calculate_neighbor_position Direction, Row, Col
    ;Jump to the correct direction check
    LDA Direction
    CMP #TOP_N
    BEQ :+

    CMP #RIGHT_N
    BEQ :++

    CMP #BOTTOM_N
    BEQ :+++

    CMP #LEFT_N
    BEQ :++++
    
    JMP :+++++ ;no valid direction, invalid neighbor

    ;top
    : 
    LDA Row
    SEC
    SBC #2
    TAY
    LDX Col
    JMP :++++

    ;right
    :
    LDA Col
    CLC
    ADC #2
    TAX
    LDY Row
    JMP :+++

    ;bottom
    :
    LDA Row
    CLC
    ADC #2
    TAY
    LDX Col
    JMP :++

    ;left
    :
    LDA Col
    SEC
    SBC #2
    TAX
    LDY Row

    ;end
    :
.endmacro

;When there is no valid neighbor, the A register will be set to 255, when there is a valid neighbor it will be set to 0 or 1; 0 when its a wall, 1 when its a passable tiles.
;Row (Y) and Column (X) of the neighbor in Y and X register (useful to add to frontier afterwards) note: these are not set when there is not a valid neighbor; check this first! 
;Direction: The direction of the neighbor we are polling (0-3, defines are stored in the header for this)
;Row: Row index in the map buffer (0 to MAP_ROWS - 1)
;Column: Column index (0 to 31, across 4 bytes per row)
.macro access_map_neighbor Direction, Row, Column
    bounds_check_neighbor Direction, Row, Column
    ;Check if A is valid (1)
    CMP #0
    BNE :+ ;else return   
    JMP set_invalid
    :
    ;calculate the neighbors row and col
    calculate_neighbor_position Direction, Row, Column ;returns row in y and col in x register

    ;store before getting state of neighbor
    STX a_val ;col 
    STY b_val ;row

    ;store the new row and col on the stack
    TXA
    PHA
    TYA
    PHA 
        
    get_map_tile_state b_val, a_val
    CMP #0
    BNE passable ;if the neighbor is not a wall (wall == 0) it is passable 
    
        ;wall neighbor
        ;restore the neighbors row and col
        PLA
        TAY
        PLA
        TAX

        LDA #0 ;the neighbor is a wall
        JMP return

    .local set_invalid
    set_invalid:
        LDA #%11111111 ;invalid -> max val
        JMP return

    ;in the case of no wall we still have to restore the stack
    .local passable
    passable:
        ;restore the neighbors row and col
        PLA
        TAY
        PLA
        TAX

        LDA #1

    .local return
    return:

.endmacro

    ;*****************************************************************
    ; Map buffer - visited list 
    ; same macros as maze buffer but not in zero page. read maze buffer documentation for info
    ;*****************************************************************
    .macro calculate_offset_and_mask_visited Row, Column
        ;Calculate the base address of the row (Row * 4)
        LDA Row
        ASL             ;== times 2
        ASL             ;== times 2
        CLC
        STA x_val

        ;Calculate the byte offset within the row (Column / 8)
        LDA Column
        LSR
        LSR
        LSR
        STA y_val

        ;Add the byte offset to the base row address
        LDA x_val
        CLC 
        ADC y_val
        STA temp_address ; == byte offset
        
        ; bitmask: 
        ;Clamp the 0-31 Column to 0-7 
        LDA Column
        : ;Loop
        CMP #$08       ; Compare the number with 8 (i.e., check if it's greater than 7)
        BCC :+         ; If the number is less than or equal to 7, branch to Done
        SEC            ; Set the Carry flag before subtraction (since we're subtracting)
        SBC #$08       ; Subtract 8 from the number
        JMP :-

        : ;end clamp loop
        STA x_val

        LDA #%00000001
        STA y_val

        ;Calculate how many times we should shift
        LDA #7
        SEC
        SBC x_val    
        BEQ :++
        TAX
        
        LDA y_val
        :    
        ASL
        DEX
        BNE :-

        STA y_val
        :
    .endmacro

    .macro set_visited Row, Col
        calculate_offset_and_mask_visited Row, Col
        
        LDY temp_address
        LDA VISISTED_ADDRESS, Y   
        ORA y_val
        STA VISISTED_ADDRESS, Y

    .endmacro

    .macro is_visited Row, Col
        calculate_offset_and_mask_visited Row, Col
        
        LDY temp_address
        LDA VISISTED_ADDRESS, Y   
        AND y_val

    .endmacro

    ;*****************************************************************


;*****************************************************************

;*****************************************************************
; Frontier list macros
;*****************************************************************
;page 0 - 1 | offset 0-127
;loads the row in the X register, col in the Y register
.macro access_Frontier page, offset
    LDA page
    CMP #0
    BNE :+

    ; Calculate the address of the item in the list
    LDA offset
    ASL

    TAX

    ;row
    LDA FRONTIER_LISTQ1, X
    TAY
    INX

    ;col
    LDA FRONTIER_LISTQ1, X
    TAX

    JMP end

    :
    CMP #1
    BNE :+

    ; Calculate the address of the item in the list
    LDA offset
    ASL

    TAX

    ;row
    LDA FRONTIER_LISTQ2, X
    TAY
    INX

    ;col
    LDA FRONTIER_LISTQ2, X
    TAX        

    .local end
    end: 

.endmacro

;returns whether or not the row and col pair exist in the frontier list in the X register (1 found, 0 not found)
.macro exists_in_Frontier Row, Col
    LDX #0
    STX temp

    .local loop_p0
    loop_p0:        
        LDX temp
        CPX frontier_listQ1_size
        BNE :+
            LDX #0
            STX temp
            JMP loop_p1
        :
        
        access_Frontier #0, temp
        INC temp
        
        CPY Row
        BEQ :+
            JMP loop_p0
        :
        CPX Col
        BEQ :+
            JMP loop_p0
        :

        JMP return_found

    .local loop_p1
    loop_p1:        
        LDX temp
        CPX frontier_listQ2_size
        BNE :+
            LDX #0
            STX temp
            JMP return_not_found
        :
        
        access_Frontier #1, temp
        INC temp
        
        CPY Row
        BEQ :+
            JMP loop_p1
        :
        CPX Col
        BEQ :+
            JMP loop_p1
        :

        JMP return_found

    .local return_not_found
    return_not_found:
        LDX #0
        JMP n

    .local return_found
    return_found:
        LDX #1
        JMP n

    .local n
    n: 
.endmacro

; page 0 - 1 | offset 0-127
; basically uses the "swap and pop" technique of a vector in C++
.macro remove_from_Frontier page, offset
    LDA page
    CMP #0
    BNE :+      ;remove from page 0? (Q1)

        ; Calculate the address of the last item in the list
        LDA frontier_listQ1_size

        TAX
        DEX ;decrease size by 1 before multiplying (otherwise we will go out of bounds since size 1 == index 0 )
        TXA

        ASL
        TAX ;calculated address offset for last item in X

        LDA FRONTIER_LISTQ1, X ; store last items in temp values
        STA a_val
    
        INX
        LDA FRONTIER_LISTQ1, X ; store last items in temp values
        STA b_val

        ; Calculate the address to be removed
        LDA offset
        ASL
        TAX

        LDA a_val
        STA FRONTIER_LISTQ1, X
        INX 
        LDA b_val
        STA FRONTIER_LISTQ1, X


        ; ; in case you want to replace the garbage at end with FF for debugging (clear values)
        ; LDA frontier_listQ1_size

        ; TAX
        ; DEX ;decrease size by 1 before multiplying (otherwise we will go out of bounds since size 1 == index 0 )
        ; TXA

        ; ASL
        ; TAX ;calculated address offset for last item in X

        ; LDA #$FF
        ; STA FRONTIER_LISTQ1, X 
        ; INX
        ; LDA #$FF
        ; STA FRONTIER_LISTQ1, X


        DEC frontier_listQ1_size
        JMP end    ;jump to end
    :
    CMP #1
    BNE :+      ;remove from page 1? (Q2)
        ; Calculate the address of the last item in the list
        LDA frontier_listQ2_size

        TAX
        DEX ;decrease size by 1 before multiplying (otherwise we will go out of bounds since size 1 == index 0 )
        TXA

        ASL
        TAX ;calculated address offset for last item in X

        LDA FRONTIER_LISTQ2, X ; store last items in temp values
        STA a_val
    
        INX
        LDA FRONTIER_LISTQ2, X ; store last items in temp values
        STA b_val

        ; Calculate the address to be removed
        LDA offset
        ASL
        TAX

        LDA a_val
        STA FRONTIER_LISTQ2, X
        INX 
        LDA b_val
        STA FRONTIER_LISTQ2, X


        ; ; in case you want to replace the garbage at end with FF for debugging (clear values)
        ; LDA frontier_listQ2_size

        ; TAX
        ; DEX ;decrease size by 1 before multiplying (otherwise we will go out of bounds since size 1 == index 0 )
        ; TXA

        ; ASL
        ; TAX ;calculated address offset for last item in X

        ; LDA #$FF
        ; STA FRONTIER_LISTQ2, X 
        ; INX
        ; LDA #$FF
        ; STA FRONTIER_LISTQ2, X


        DEC frontier_listQ2_size
        JMP end    ;jump to end
    .local end
    end: 
.endmacro

;Defintion of row and col can be found in the map buffer section.
.macro add_to_Frontier Row, Col
    ;multiply current size of Q1 by 2, 2 bytes required per element in list
    LDA frontier_listQ1_size
    ASL

    CMP #%11111110      ;check if it should be added to Q1 or not
    BEQ :+
        
        TAX
        LDA Row
        STA FRONTIER_LISTQ1, X
        INX
        LDA Col
        STA FRONTIER_LISTQ1, X

        INC frontier_listQ1_size   
        JMP end                   ;jump to end
    :
    ;multiply current size of Q2 by 2, 2 bytes required per element in list
    LDA frontier_listQ2_size
    ASL

    CMP #%11111110      ;check if it should be added to Q2 or not
    BEQ :+

        TAX
        LDA Row
        STA FRONTIER_LISTQ2, X
        INX
        LDA Col
        STA FRONTIER_LISTQ2, X

        INC frontier_listQ2_size   

        .local end
        end: 
.endmacro
;*****************************************************************


; result = value % modulus
; => result is stored in the A register
.macro modulo value, modulus
    LDA value
    SEC

    :
    SBC modulus
    CMP modulus
    BCS :-

.endmacro

;calculates how many frontier list pages are used and stores it in the variable in zero page.
.macro calculate_pages_used
    ;calculate how many pages are currently in use
    LDX #0

    LDA frontier_listQ1_size
    CMP #0
    BEQ :+
    INX
    
    :
    LDA frontier_listQ2_size
    CMP #0
    BEQ :+
    INX
    
    :
    ;store the pages that are used 
    STX frontier_pages_used
.endmacro

;stores a random frontier page in a_val and a random offset from that page into b_val, then calls access_frontier on that tile
.macro get_random_frontier_tile
    calculate_pages_used ;macro calculating how many pages are used, in the final project it is possible to just call this once per frame after any adding / removing to 'optimize' slightly

    ;random number for page
    JSR random_number_generator

    ;clamp page
    modulo RandomSeed, frontier_pages_used
    STA a_val

    ;random number for offset
    JSR random_number_generator

    ;pages checked stored in y
    LDY #0

    ;pick the page with a size larger > 0 corresponding to a_val
    ;page 0: 
    LDA frontier_listQ1_size
    CMP #0
    BEQ page1
        ;page has items in it, check if we should use this page
        TYA
        CMP a_val
        BNE incP1
            ;clamp the offset
            modulo RandomSeed, frontier_listQ1_size
            STA b_val
            LDA #0
            STA a_val
            JMP endSwitch
    .local incP1
    incP1:
    ;increase checked pages
    INY

    .local page1
    page1: 
    LDA frontier_listQ2_size
    CMP #0
    BEQ endSwitch
        ;page has items in it, check if we should use this page
        TYA
        CMP a_val
        BNE incP2
            ;clamp the offset
            modulo RandomSeed, frontier_listQ2_size
            STA b_val
            LDA #1
            STA a_val
            JMP endSwitch
    .local incP2
    incP2:
    ;increase checked pages
    INY

    .local endSwitch
    endSwitch:
        access_Frontier a_val, b_val

.endmacro


.macro multiply10 value
    LDA value
    ROL ;x2
    TAX
    ROL ;x2
    ROL ;x2 = x8
    STA a_val
    TXA
    ADC a_val
.endmacro

.macro divide10 value
        ;with help from chatGPT
        
        LDA value
        LDY #0          ; Initialize Y (Quotient) to 0
        SEC             ; Set carry for subtraction

    .local DivideLoop
    DivideLoop:
        SBC #10         ; Subtract 10 from A
        BCC Done        ; If result is negative, exit loop
        INY             ; Increment Y (Quotient)
        JMP DivideLoop  ; Repeat the loop

    .local Done
    Done:
        STA Remainder   ; Store the remainder (A)
        TYA     ; Store the quotient (Y)

.endmacro
