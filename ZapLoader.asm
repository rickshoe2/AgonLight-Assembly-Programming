;	<< ZapLoader.asm >>
;	R.L. Shoemaker  22-Apr-24
 
	.assume	ADL = 1				;set the program to run in ADL mode	

	DEFINE  CODE1,SPACE=RAM
	SEGMENT CODE1

mos_load	EQU	01h

	ORG 040000h
	JP	 MAIN		;jump to code start

	BLKB 3Ch,00		;fill locations 4-63 with zeros
	ALIGN 64		;the 5-byte MOS header must be located at byte 64		
	DB	"MOS"		;flag for MOS - to confirm this is a valid MOS command
	DB	00			;MOS header version 0
	DB	01			;flag for run mode (0: Z80, 1: ADL)
	BLKB 0BBh,00	;fill locations 69-255 with zeros

;=============================================================================
; START OF MAIN PROGRAM CODE
;=============================================================================
	ORG 040100h

MAIN:
	LD	 HL,FileName	;put the address of the FileName string in HL
	LD	 DE,04F000h
	LD	 BC,1000h		; maximum allowed file size
	LD	 A,mos_load		;execute the MOS command to load a file
	RST.LIL	08h
	JP	 04F000h		;done, start the monitor

FileName	DB 'eZapple.bin',00
