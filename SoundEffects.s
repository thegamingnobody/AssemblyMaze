; This file is for the FamiStudio Sound Engine and was generated by FamiStudio


.if FAMISTUDIO_CFG_C_BINDINGS
.export _sounds=sounds
.endif

sounds:
	.word @pal
	.word @pal
@pal:
	.word @sfx_pal_mazegeneration
	.word @sfx_pal_scoreincrease
	.word @sfx_pal_select

@sfx_pal_mazegeneration:
	.byte $84,$3a,$85,$01,$83,$3f,$87,$75,$88,$02,$86,$8f,$89,$f0,$06,$83
	.byte $30,$86,$80,$14,$81,$3a,$82,$01,$80,$3f,$06,$81,$d1,$82,$00,$07
	.byte $81,$9d,$84,$d7,$83,$3f,$87,$b0,$88,$03,$86,$8f,$06,$81,$75,$83
	.byte $30,$86,$80,$07,$81,$57,$84,$75,$85,$02,$83,$3f,$87,$ec,$88,$04
	.byte $86,$8f,$06,$81,$75,$83,$30,$86,$80,$07,$81,$5d,$84,$76,$85,$01
	.byte $83,$3f,$87,$ed,$88,$02,$86,$8f,$06,$81,$7c,$83,$30,$86,$80,$07
	.byte $81,$a6,$84,$f3,$83,$3f,$87,$e8,$88,$03,$86,$8f,$06,$81,$7c,$83
	.byte $30,$86,$80,$07,$81,$8b,$84,$ed,$85,$02,$83,$3f,$87,$db,$88,$05
	.byte $86,$8f,$06,$81,$ba,$83,$30,$86,$80,$07,$81,$f9,$84,$f3,$85,$01
	.byte $83,$3f,$87,$e8,$88,$03,$86,$8f,$06,$81,$ba,$83,$30,$86,$80,$07
	.byte $81,$b0,$84,$61,$83,$3f,$87,$c3,$88,$02,$86,$8f,$06,$81,$84,$83
	.byte $30,$86,$80,$07,$81,$62,$84,$f3,$83,$3f,$87,$e8,$88,$03,$86,$8f
	.byte $06,$81,$49,$83,$30,$86,$80,$07,$81,$37,$84,$de,$85,$00,$83,$3f
	.byte $87,$bd,$88,$01,$86,$8f,$06,$81,$49,$83,$30,$86,$80,$07,$81,$62
	.byte $84,$d7,$85,$01,$83,$3f,$87,$b0,$88,$03,$86,$8f,$06,$81,$3a,$83
	.byte $30,$86,$80,$07,$81,$4e,$84,$61,$83,$3f,$87,$c3,$88,$02,$86,$8f
	.byte $06,$81,$68,$83,$30,$86,$80,$07,$81,$3e,$84,$f9,$85,$00,$83,$3f
	.byte $87,$f3,$88,$01,$86,$8f,$06,$80,$30,$83,$30,$86,$80,$14,$81,$9d
	.byte $80,$3f,$84,$8c,$85,$01,$83,$3f,$87,$19,$88,$03,$86,$8f,$06,$83
	.byte $30,$86,$80,$0d,$00
@sfx_pal_scoreincrease:
	.byte $81,$68,$82,$00,$80,$3f,$84,$9d,$85,$00,$83,$3f,$89,$f0,$05,$81
	.byte $4e,$84,$75,$06,$80,$30,$00
@sfx_pal_select:
	.byte $84,$45,$85,$00,$83,$3f,$87,$8b,$88,$00,$86,$8f,$8a,$09,$89,$3f
	.byte $05,$83,$30,$87,$5d,$89,$f0,$05,$00

.export sounds
