; This is a replacement for giveTreasure that accounts for item progression. Call through
; giveTreasureCustom or giveTreasureCustomSilent, since this function doesn't xor the a that it
; returns. Importantly, this replacement treats c as a subID, not a param, so this should *not* be
; called by non-randomized whatevers.
giveTreasureCustom_body:
	ld b,a
	push hl
	callab treasureData.getTreasureDataBCE
	pop hl
	ld a,b
	jp giveRandomizedTreasure


giveTreasureCustomSilent:
	call giveTreasureCustom_body
	xor a
	ret


giveTreasureCustom:
	call giveTreasureCustom_body
	jr z,@noSound
	push hl
	call playSound
	pop hl

@noSound:
	ld a,e
	cp a,$ff
	ret z
	ld b,>TX_0000
	ld c,e
	call showText
	xor a
	ret


; Like calling giveTreasure. See "handleGetItem_body".
;
; @param	a	Treasure
; @param	c	Parameter
giveRandomizedTreasure:
	push bc
	push de
	push hl
	ld b,a
	callab treasureInteraction.giveRandomizedTreasure_body
	ld a,b
	pop hl
	pop de
	pop bc
	ret