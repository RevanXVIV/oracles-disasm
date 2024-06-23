; Macro to .incbin gfx data while allowing it to cross over banks.
; Must define DATA_ADDR and DATA_BANK prior to use (linker gets no say in its placement).
.macro m_GfxData
	.fopen {"{BUILD_DIR}/gfx/\1.cmp"} m_GfxDataFile
	.fsize m_GfxDataFile SIZE
	.fclose m_GfxDataFile

	.redefine SIZE SIZE-3 ; Skip .cmp file "header"

	.if DATA_ADDR + SIZE >= $8000
		.define DATA_READAMOUNT $8000-DATA_ADDR

		\1: .incbin {"{BUILD_DIR}/gfx/\1.cmp"} SKIP 3 READ DATA_READAMOUNT

		.redefine DATA_BANK DATA_BANK+1
		.BANK DATA_BANK SLOT 1
		.ORGA $4000

		.if DATA_READAMOUNT < SIZE
			.incbin {"{BUILD_DIR}/gfx/\1.cmp"} SKIP DATA_READAMOUNT+3
		.endif

		.redefine DATA_ADDR $4000 + SIZE-DATA_READAMOUNT
		.undefine DATA_READAMOUNT
	.else
		\1: .incbin {"{BUILD_DIR}/gfx/\1.cmp"} SKIP 3
		.redefine DATA_ADDR DATA_ADDR + SIZE
	.endif

	.undefine SIZE
.endm

; Same as last, but doesn't support inter-bank stuff, so DATA_ADDR and DATA_BANK
; don't need to be defined beforehand.
.macro m_GfxDataSimple
	.if NARGS == 2
		\1: .incbin {"{BUILD_DIR}/gfx/\1.cmp"} SKIP 3+(\2)
	.else
		\1: .incbin {"{BUILD_DIR}/gfx/\1.cmp"} SKIP 3
	.endif
.endm

; Start of a gfx header. Creates a label at the current position (ie. gfxHeader00:) and an exported
; definition.
; Arguments:
;   \1: Index of gfx header
;   \2: Name of gfx header, resolves to the index when used in code
.macro m_GfxHeaderStart
	.define \2 (\1) EXPORT
	gfxHeader{%.2x{\1}}:
.endm

; Use this at the end of a gfx header definition.
;
; Its actual effect is to ensure the "continue" bit of the previous gfx header entry remains unset,
; so it does not attempt to read any data after this.
;
; Optionally, a gfx header can end with a palette header (see constants/paletteHeaders.s). So this
; macro takes one optional parameter for that. (Unique GFX headers only?)
.macro m_GfxHeaderEnd
	.ifdef CURRENT_GFX_HEADER_INDEX
		.if NARGS >= 1 ; Set last entry's continue bit
			.define GFX_HEADER_{CURRENT_GFX_HEADER_INDEX}_CONT, $80
		.else ; Unset last entry's continue bit
			.define GFX_HEADER_{CURRENT_GFX_HEADER_INDEX}_CONT, $00
		.endif
		.undefine CURRENT_GFX_HEADER_INDEX
	.endif
	.if NARGS >= 1
		.db $00
		.db \1 ; Palette header index
	.endif
.endm

.enum 0
	GFX_HEADER_MODE_NORMAL:	 db
	GFX_HEADER_MODE_ANIM:	db
	GFX_HEADER_MODE_FORCE:	db
.ende

; Helper macro, defines the size/continue byte for gfx headers. The value for the "continue bit" is
; defined later, either when this is invoked again or when m_GfxHeaderEnd is invoked.
;
; As it's using a define with "\@" in its name, which is the number of times the current macro has
; been called, it's important to not copy/paste this into multiple macros.
.macro m_GfxHeaderContinueHelper
	; Mark "continue" bit on last defined gfx header entry
	.ifdef CURRENT_GFX_HEADER_INDEX
		.define GFX_HEADER_{CURRENT_GFX_HEADER_INDEX}_CONT $80
	.endif

	; Define size/continue byte for current gfx header entry
	.redefine CURRENT_GFX_HEADER_INDEX \@
	.db (\1) | GFX_HEADER_{CURRENT_GFX_HEADER_INDEX}_CONT
.endm

; Helper macro used for defining other macros with slightly varying parameters. See the other macros
; (ie. m_GfxHeader) for descriptions.
.macro m_GfxHeaderHelper
	.define m_GfxHeaderMode \1
	.shift

	; Read metadata from .cmp file
	.fopen {"{BUILD_DIR}/gfx/\1.cmp"} m_GfxHeaderFile
	.fread m_GfxHeaderFile cmp_mode ; First byte of .cmp file is compression mode
	.fread m_GfxHeaderFile decompressed_size_l ; Bytes 2-3 are the decompressed size
	.fread m_GfxHeaderFile decompressed_size_h
	.fclose m_GfxHeaderFile
	.define decompressed_size (decompressed_size_l | (decompressed_size_h<<8))

	; Byte 1: Source bank number & compression mode
	.if m_GfxHeaderMode == GFX_HEADER_MODE_FORCE
		.db (:\1) | ((\4)<<6)
	.else
		.db (:\1) | (cmp_mode<<6)
	.endif

	; Bytes 2-3: Source address
	.if m_GfxHeaderMode != GFX_HEADER_MODE_FORCE && NARGS >= 4
		dwbe (\1)+(\4)
	.else
		dwbe \1
	.endif

	; Bytes 4-5: Destination address & destination bank
	; If arg 2 (destination) isn't a label, we'll just assume that the bank number is already
	; baked into the parameter being passed.
	.if \?2 == ARG_LABEL || \?2 == ARG_PENDING_CALCULATION
		dwbe (\2)|(:\2)
	.else
		dwbe \2
	.endif

	; If size parameter is not passed, infer it from the file
	.if NARGS < 3
		.define size_byte (decompressed_size / 16) - 1
	.else
		.define size_byte \3
	.endif

	; Byte 6: Size / continue bit
	.if m_GfxHeaderMode == GFX_HEADER_MODE_NORMAL
		m_GfxHeaderContinueHelper size_byte
	.else
		.db size_byte
	.endif

	.undefine m_GfxHeaderMode
	.undefine cmp_mode
	.undefine decompressed_size_l
	.undefine decompressed_size_h
	.undefine decompressed_size
	.undefine size_byte
.endm

; Define a gfx header entry (a reference to graphics paired with a destination to load it to).
;
; Whenever this is used, you MUST also use m_GfxHeaderEnd at some point after it!
;
; Arg 1: gfx file (without extension)
; Arg 2: destination (usually vram)
; Arg 3 (optional): Size byte. If omitted, include the entire file.
; Arg 4 (optional): Skip first X bytes of graphics file.
;        Will only work with uncompressed graphics.
.macro m_GfxHeader
	.if NARGS == 4
		m_GfxHeaderHelper GFX_HEADER_MODE_NORMAL,\1,\2,\3,\4
	.elif NARGS == 3
		m_GfxHeaderHelper GFX_HEADER_MODE_NORMAL,\1,\2,\3
	.else
		m_GfxHeaderHelper GFX_HEADER_MODE_NORMAL,\1,\2
	.endif
.endm

; Identical to above except continue bit is never set. Bypasses the weird system for that which
; makes it simpler in general (and m_GfxHeaderEnd is not required when using it).
.macro m_GfxHeaderAnim
	.if NARGS == 4
		m_GfxHeaderHelper GFX_HEADER_MODE_ANIM,\1,\2,\3,\4
	.else
		m_GfxHeaderHelper GFX_HEADER_MODE_ANIM,\1,\2,\3
	.endif
.endm

; Same as m_GfxHeaderAnim but has a compression mode override as the 4th argument. This really isn't
; important, there's just an unusable gfx header in ages that needs the mode override to be able to
; define it. Obviously, it doesn't do anything useful.
.macro m_GfxHeaderForceMode
	m_GfxHeaderHelper GFX_HEADER_MODE_FORCE,\1,\2,\3,\4
.endm

; Define graphics header with the source being from RAM
; Arg 1: RAM bank
; Arg 2: Source (can combine args 1/2 as a label)
; Arg 3: Destination
; Arg 4: Size
.macro m_GfxHeaderRam
	.if NARGS == 4
		.db \1
		dwbe \2
		.shift
	.else
		.db :\1
		dwbe \1
	.endif

	dwbe \2
	m_GfxHeaderContinueHelper \3
.endm

; Define object gfx header entry.
;
; Arguments:
;   \1: filename
;   \2 (optional): Set to "1" if this is the end of a "chain" of ObjectGfxHeaders to be loaded.
;                  Defaults to 0.
;   \3 (optional): Skips into part of the graphics (only works if uncompressed)
.macro m_ObjectGfxHeader
	.fopen {"{BUILD_DIR}/gfx/\1.cmp"} m_GfxHeaderFile
	.fread m_GfxHeaderFile mode ; First byte of .cmp file is compression mode
	.fclose m_GfxHeaderFile

	.db (:\1) | (mode<<6)

	.if NARGS == 1
		.define m_ObjectGfxHeader_Cont 0
	.else
		.define m_ObjectGfxHeader_Cont (\2) & 1
	.endif

	.if NARGS >= 3
		dwbe ((\1)+(\3)) | ((m_ObjectGfxHeader_Cont)<<15)
	.else
		dwbe (\1) | ((m_ObjectGfxHeader_Cont)<<15)
	.endif

	.undefine mode
	.undefine m_ObjectGfxHeader_Cont
.endm
