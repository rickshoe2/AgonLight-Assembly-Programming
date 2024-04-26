;	<< eZapple.asm >>
;	R.L. Shoemaker  22-Apr-24

; Memory usage by this monitor is as follows:
;	040000 - 040100  initialization code
;	040100 - 046F80	 memory available for user programs (28288 bytes)
;	046F80 - 046FD0  monitor stack area (80 bytes)
;	046FD0 - 047000  saved register area (48 bytes)
;	047000 - 047C00  monitor program code (3072 bytes)
;	047C00 - 047E00  UART1 I/O code (512 bytes)

 
	.assume	ADL = 1				;set the program to run in ADL mode

	DEFINE  CODE1,SPACE=RAM
	SEGMENT CODE1

	.global MONITOR_START
	.extern INIT_GPIO,OPEN_UART1
	.extern	CONOUT,PRINT,PRINTI
	.extern CONIN,CONSTS,TI,GET_STRING
	.extern CRLF,PSPACE,HLPRNT,APRNT

;==============================================================================
MONITOR_START	EQU 4F000h
;==============================================================================

;==============================================================================
; Constants for XModem
SOH		EQU	1		;a byte of 01 indicates start of header
EOT		EQU	4		;a byte of 04 indicates end of transmission
ACK		EQU	6		;Acknowledge
NAK		EQU	15H		;Not Acknowledge
CAN		EQU	24		;Cancel Xmodem transfer

;=============================================================================
; Offsets from STACK_TOP (046FD0h) for saved registers
RSSP	EQU	00		;offset of SP in register save area
RSAF	EQU	03		;offset of AF in register save area
RSBC	EQU	06 		;offset of BC in register save area
RSDE	EQU	09		;offset of DE in register save area
RSHL	EQU	0Ch		;offset of HL in register save area
RPC		EQU	0Fh		;offset of PC in register save area
RSIX	EQU	12h		;offset of IX in register save area
RSIY	EQU	15h		;offset of IY in register save area
RSIR	EQU	18h		;offset of IR in register save area
RSAF2	EQU	1Bh		;offset of AF' in register save area
RSBC2	EQU	1Eh		;offset of BC' in register save area
RSDE2	EQU	21h		;offset of DE' in register save area
RSHL2	EQU	24h		;offset of HL' in register save area

;==============================================================================
; Error codes for HexLoad
ERR1	 	EQU 01	;Initial colon not found
ERR2	 	EQU 02	;Illegal hex digit in record
ERR3		EQU 03	;Checksum error
ERR4		EQU 04	;Corrupt end-of-file record
ERR5		EQU 05	;Unknown record type error

;==============================================================================
; MOS API FUNCTIONS - functions made available thru the MOS API (Application
;	Programming Interface). The complete list of functions is in mos_api.inc 
mos_getkey	EQU	00h
mos_load	EQU	01h
mos_save	EQU	02h
mos_del		EQU	05h

;=============================================================================
; Constants
CR		EQU	0DH		;ASCII code for carriage return
LF		EQU	0AH	    ;ASCII code for line feed
BS		EQU 08H		;ASCII code for backspace
TAB		EQU	09H		;ASCII code for TAB
COMMA   EQU 2CH     ;ASCII code for comma
ESC		EQU 1BH		;ASCII code for escape key
RST6	EQU 0030H   ;software interrupt RST6 jumps to this address

MAX_SIZE  	EQU 06000h  ;maximum file size for HEXLOAD

USER_START EQU 040100h	;starting address for user programs called by the 'U'
						;  command
SRCH_START EQU 040000h ;starting address for the WHERE command
SRCH_LEN   EQU 00FFFFh  ;search length for WHERE command (64K)

;==============================================================================
; STACK_TOP defines the top of the monitor's system stack. The monitor itself
;	begins at 047000h, and the 30h bytes between 046FD0h and 047000h are
;	reserved for the register storage area used by the
;	GOTO command.
STACK_TOP EQU (MONITOR_START - 30h)

	; ORG 040000h
	; JP	 MAIN		;jump to _start

	; BLKB 3Ch,00		;fill locations 4-63 with zeros
	; ALIGN 64		;the 5-byte MOS header must be located at byte 64		
	; DB	"MOS"		;flag for MOS - to confirm this is a valid MOS command
	; DB	00			;MOS header version 0
	; DB	01			;flag for run mode (0: Z80, 1: ADL)
	; BLKB 0BBh,00	;fill locations 69-255 with zeros

;=============================================================================
; START OF MAIN PROGRAM CODE
;=============================================================================
	ORG MONITOR_START

MAIN:
	LD	 IX,STACK_TOP		;put the stack top address in IX
	LD	 SP,IX			;and initialize SPL (the stack pointer for ADL mode)
	LD	 (StackTop),IX	;also save a copy of the initial SP in the restart area
	CALL INIT_GPIO		;initialize the GPIO ports
	CALL OPEN_UART1		;and UART1
	CALL PRINTI
	DB	'eZ80 Zapple',CR,LF,00
	CALL PRINTI
	DB	'SPL=',00
	LD	HL,(StackTop)
	CALL HLPRNT			;print current stack location
	CALL CRLF			;then CRLF

;==============================================================================	
;========================== START OF MAIN MONITOR LOOP- =======================
MAIN_LOOP:
	LD	 HL,(StackTop)	;reset the stack pointer
	LD	 SP,HL
	CALL CRLF			
	LD	 C,'>'		;display the Zapple command prompt
	CALL CONOUT
FLUSH:
	CALL CONSTS			;check if garbage at keyboard
	JR	 Z,NO_GARBAGE	;check if garbage at keyboard
	CALL CONIN			;if so flush it
	JR	 FLUSH
NO_GARBAGE:	
	CALL TI	 		;get a console character
	CP	 ESC		;exit program if ESC key pressed
	JR	 Z, GO_MOS
	CP	 'C'		;change and/or examine memory
	JP	 Z,CHANGE
	CP	 'D'		;display a block of memory
	JP	 Z,DISP
	CP	 'E'		;error
	JP	 Z,ERROR
	CP	 'F'		;fill a block of memory with a constant
	JP	 Z,FILL
	CP	 'G'		;execute a program that has been loaded into memory
	JP	 Z,GOTO
	CP	 'H'		;load a Hex file into memory from the PC
	JP	 Z,HEXLOAD
	CP	 'L'		;load a binary file from the SD card into memory
	JP	 Z,LOAD
	CP	 'M'		;move a block of memory from one location to another
	JP	 Z,MOVE
	CP	 'Q'		;read or write any of the eZ80's I/O ports
	JP	 Z,QUERY
	CP	 'R'		;display the contents of the eZ80's registers
	JP	 Z,REGDISP
	CP	 'S'		;save a file from memory to the SD card
	JP	 Z,SAVE			
	CP	 'T'		;display a block of memory as ASCII text
	JP	 Z,TYPE
	CP	 'U'		;jump to location 040100 to execute a user program
	JP	 Z,USER
	CP	 'V'		;verify that two blocks of memory are identical
	JP	 Z,VERIFY
	CP	 'W'		;search memory for a specified sequence of bytes
	JP	 Z,WHERE
	CP	 'X'		;search memory for a specified sequence of bytes
	JP	 Z,XMODEM
	JP	 MAIN_LOOP

GO_MOS:
	JP	 000000

;==============================================================================
;============================== MONITOR COMMANDS ==============================	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CHANGE COMMAND - allows examination and modification of memory on a byte
;	by byte basis. It takes one address parameter,followed by a space. The data
;   at that location will be displayed. To change it, a new value is entered,
;   and a following space displays the next byte. A CR terminates the command.
;   A Backspace backs up the pointer and displays the previous location.
;   USAGE: C<addr><SP>
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CHANGE:
	CALL HEXSP1		;get the starting address
	POP	 HL
SUB0:
	LD	 A,(HL)		;get a byte from memory
	CALL APRNT	    ;display it
	CALL COPCK	    ;modify it?
	JP	 C,MAIN_LOOP   	; no, all done
	JR	 Z,SUB1	    ;don't modify, skip ahead
	CP	 BS	     	;backup one byte?
	JR	 Z,SUB2		;yes
	PUSH HL	     	;else save pointer
	CALL EXF	    ;get new value
	POP	 DE	     	;value is in E
	POP	 HL			;restore HL
	LD	(HL),E	    ;modify memory
	LD	 A,B	    ;test for delimiter
	CP	 CR
	JP	 Z,MAIN_LOOP ;done if CR
SUB1:
	INC	 HL			;next byte
SUB3:
	LD	 A,L	    ;8 bytes on this line yet?
	AND	 07H
	CALL Z,LFADR	;yes, start new line
	JR	 SUB0
SUB2:
	DEC	 HL	     	;decrement pointer
	JR	 SUB3	    ;and print data there
COPCK:
 	LD	C,'-'	     ;print the prompt for the CHANGE command
	CALL CONOUT	
PCHK:
  	CALL TI			;get a character in A
	CALL QCHK		;return 0 if A = space or comma, carry set if CR
	RET

LFADR:
	CALL	CRLF	;CRLF before HLSP
	CALL HLPRNT
	LD   C,' '		;print a space on the console
	JP   CONOUT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DISPLAY COMMAND - displays the contents of memory from <addr1> to <addr2>
;	in hex with the starting location displayed at the beginning of each line.
;   USAGE: D<addr1> <addr2>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
DISP: CALL GET2HEX		;get parameters in HL and DE
	LD	 A,L		;round off addresses to XX00H
	AND	 0F0H
	LD	 L,A
	LD	 A,E		;final address lower half
	AND	 0F0H
	ADD	 A,10H		;finish to end 0f line
DS0: CALL CRLF		;CRLF and print address
	CALL HLPRNT
DS1: CALL PSPACE    ;space over
	LD	 A,(HL)
	CALL APRNT
	CALL HILOX		;test for end of range, return to MAIN_LOOP if range exceeded
	LD	 A,L
	AND	 0FH
	JR	 NZ,DS1
	LD	 C,TAB		;insert tab between hex and ASCII
	CALL CONOUT
	LD	 B,4H		;also 4 spaces
TA11: LD C,20h		;20h = ASCII code for a space
	CALL CONOUT
	DJNZ TA11	
	LD	 B,16		;now print 16 ASCII characters
	PUSH DE			;temporarily save DE
	LD	 DE,0010H
	SBC	 HL,DE
	POP	 DE
T11: LD	 A,(HL)
	AND	 7FH
	CP	 ' ' 		;filter out control characters
	JR	 NC,T33
T22: LD	 A,'.'
T33: CP	 07CH
	JR	 NC,T22
	LD	 C,A		;set up to display ASCII
	CALL CONOUT
	INC	 HL
	DJNZ T11		;repeat for entire line
	JR	DS0

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ERROR COMMAND - Restores the stack pointer to its startup value, prints a
;	'*' to announce an error, and jumps back to the start of eZapple's
;	main work loop.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ERROR:
	LD HL,(StackTop)		;restore SP to it's startup value
	LD   SP,HL
	LD	 C,'*'	   		;announce error
	CALL CONOUT
	JP	 MAIN_LOOP	   	;go back to work

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FILL COMMAND - fills a memory block from <addr1> to <addr2> with a byte value.
;   USAGE: F<addr1> <addr2> <byte>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
FILL:
	CALL GET3HEX	;get 3 parameters
FIL0:
	LD	 (HL),C		;store the byte
	CALL HILO		;increment pointer and see if done
	JR	 NC,FIL0
	JP	 MAIN_LOOP	   	;go back to work

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; GOTO COMMAND - executes a program with or without a breakpoint. When this
;   command is executed, SP points to the address of START, so a RET at the end
;   of the program being executed will return to there.
;   USAGE:
;		G<start addr>[CR]			   Execute program with no breakpoints
;		G<start addr> <brkpt addr>[CR] Execute program from start to breakpoint
;		G[CR]				Restart program execution from current PC
;		G,<brkpt addr>[CR]	Restart program execution from current PC to
;							next breakpoint			
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
GOTO:
	CALL TI			;get a character in A
	CALL QCHK			;return 0 if char is space or comma, carry set if CR
    LD   (InChar),A		;save the char
	JP	 C,RESTART    	;restart program if only CR entered
	JR	 Z,BRKPT    	;comma entered, get breakpoint
	CALL EXF	    	;get start address on the stack 
	POP	 HL				;and put it in HL
	LD	 (GoAddr),HL	;store the start address in GoAddr
	LD	 A,B			;last char typed after address is in B
	CP	 CR	     		;if last character was a CR,all done
	JR	 NZ,BRKPT       ;else get breakpoint address
	LD	 DE,MAIN_LOOP	;put main loop start address on stack so a return
	PUSH DE				;  by the user program goes back to the main loop
	JP (HL) 			;execute the program, no breakpoint
	
BRKPT:
	CALL HEXSP1			;get breakpoint address on stack
	POP	 HL	     		;put breakpoint address in HL
	LD	 (BrakPt),HL	;store the breakpoint address in BrakPt
	XOR	 A	     		;make sure breakpoint address is not 0
	LD	 DE,040000h
	SBC	 HL,DE
	JP	 Z,ERROR		;quit if it is

	
	PUSH IX				;save the index registers
	PUSH IY
	LD	 IY,JPbytes		;initialize JPbytes to contain a jump to SAVREG
	LD	 A,0C3h
	LD	 (IY),A
	LD	 BC,SAVREG
	LD	 (IY+1),BC
	LD	 HL,(BrakPt)	;replace the 4 bytes at the breakpoint address with
	LD	 IX,Ibytes		;  a jump to the SAVREG routine
	LD	 IY,JPbytes
	LD	 B,04
SET_JUMP:
	LD	 A,(HL)			;pick up an instruction byte
	LD	 (IX),A			;store it in Ibytes
	LD	 A,(IY)			;get replacement byte
	LD	 (HL),A			;and store it at the breakpoint address
	INC	 HL
	INC	 IX
	INC	 IY
	DJNZ SET_JUMP
	POP	 IY
	POP	 IX

    LD   A,(InChar)		;was comma entered as first character?
    CP   COMMA
    JP   Z,RESTART      ;yes, start from stored PC
	LD	HL,(GoAddr)	    ;else get start address from GOADDR

	JP	(HL)			;execute the program with breakpoint set

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; HEXLOAD - Converts an Intel Hex file to a binary file and loads it into
;	memory at the load address specified in the file. The first record of the
;	Hex file is assumed to be an Extended Linear Address record.
;   USAGE: 	H[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
HEXLOAD:
	CALL CONIN			;wait for a CR to be entered
	CALL PRINTI
    DB	 CR,LF,'HexLoad',CR,LF,00
	CALL PRINTI
    DB	 CR,LF,'Send Hex File from PC',CR,LF,00
	CALL PRINTI
    DB	 'Records loaded: ',00
	LD	 A,00			;zero the record count
	LD	 (RecordNumber),A
	LD	 HL,040000h			;set the default extended address to be 040000
	LD	 (ExtAddress),HL
NEXT_RECORD:
	LD	 B,04
COLON_CHK:
	CALL CONIN			;look for a colon (marks the start of a new line)
	CP	 ':'
	JR	 Z,GOT_COLON
	DJNZ COLON_CHK
	LD	 A,ERR1			;error, colon not found
	JP	 ERR_IN_REC
GOT_COLON:
	LD	 A,(RecordNumber)
	INC	 A
	LD	 (RecordNumber),A
	LD	 E,00			;initialize the checksum byte
	CALL GET_BYTE		;save the record length in DataBytes
	LD	 (DataBytes),A
	LD	 HL,000000		;clear HL
	CALL GET_BYTE		;get the 16-bit load address in HL
	LD	 H,A
	CALL GET_BYTE
	LD	 L,A
	LD	 (LoadAddr),HL ;and save it in LoadAddr
	CALL GET_BYTE		;get the record type
	CP	 A,04
	JP	 Z, ELA_REC		;if the record type is 04 this is an
						;  Extended Linear Address record
	CP	 A,01
	JP	 Z,EOF_REC		;if the record type is 01 this is an END-OF-FILE record
NOT_EXTENDED_ADDR:
	LD	 A,(DataBytes)	;save the record length in D
	LD	 D,A
	LD	 HL,(LoadAddr)		;get the load address
	LD	 BC,(ExtAddress)	;add the extended address to it to get a complete
	XOR	 A					;clear the CY flag
	ADC	 HL,BC				;  24-bit load address
	LD	 (LoadAddr),HL
	LD	 A,(RecordNumber)	;get the record number
	CALL APRNT				;and print it
	CALL PSPACE
	CP	 A,01			;is this the first record?
	JR	 NZ,NOT_FIRST
	LD	 (StartAddr),HL	;if yes, save address as the StartAddr
NOT_FIRST:
	JP	 DATA_REC	;handle a DATA record

EXIT:
	CALL CRLF
	CALL PRINTI
    DB   'HexLoad complete',CR,LF,00
	CALL PRINTI
    DB   'Start Address: ',00
	LD	 HL,(StartAddr)
	CALL HLPRNT
	CALL CRLF
	CALL PRINTI
    DB   'End Address:   ',00
	LD	 HL,(EndAddr)
	CALL HLPRNT
	JP	 MAIN_LOOP		;done, return to main monitor loop

;------------------------------------------------------------------------------
; ELA_REC - handle the EXTENDED LINEAR ADDRESS record. Returns with the 24-bit
;	extended address stored in ExtAddress
ELA_REC:
	LD	 A,(RecordNumber)	;don't count this as a data record
	DEC	 A
	LD	 (RecordNumber),A
	CALL GET_BYTE	;get bits [31:24] of the extended address and ignore them
	CALL GET_BYTE	;get bits [23:16] of the extended address
	LD	 (ExtAddress+2),A	;store HLU in the MSB of the extended address variable
	XOR	 A,A
	LD	 (ExtAddress+1),A	;clear address bits [15:0] - these will be loaded
	LD	 (ExtAddress),A		;  from record type 0
	CALL GET_BYTE		;get the updated checksum (stored in [E])
	LD	 A,E
	OR	 A				;the sum of all data including checksum must be zero
	LD	 A,ERR3
	JP	 NZ,ERR_IN_REC	;if not, there is a checksum error
	JP	 NEXT_RECORD

;------------------------------------------------------------------------------
; DATA_REC - Store the data given in a Data Record and go back for next record.
DATA_REC:
	CALL GET_BYTE		;get a data byte
	LD	 (HL),A			;and store it at the current load address
	INC	 HL				;increment load address
	LD	 (EndAddr),HL
	DEC	 D
	JR	 NZ,DATA_REC	;repeat until the number of data bytes given by the
						;  Record Length have been stored
	CALL GET_BYTE		;get the updated checksum (stored in [E])
	LD	 A,E
	OR	 A				;the sum of all data including checksum must be zero
	LD	 A,ERR3
	JR	 NZ,ERR_IN_REC	;if not, there is a checksum error
	JP	 NEXT_RECORD

;------------------------------------------------------------------------------
; EOF_REC - Handle the End-of-File record and exit the HexLoad routine
EOF_REC:
	CALL GET_BYTE
	CP	 0FFh			;if last byte of hex file is FFh, file load is complete
	JP	 Z,EXIT
	LD	 A,ERR4			;else have corrupt end-of-file record
	JR	 ERR_IN_REC

;------------------------------------------------------------------------------
; ERR_IN_REC - Print an error message on the console and abort the HexLoad
;	program.
ERR_IN_REC:
	PUSH AF			;save the error code
	CALL CRLF
	CALL PRINTI
	DB	 'Error ',00
	POP	 AF
	CALL APRNT
	CALL PRINTI
	DB	 ' in record ',00
	LD	 A, (RecordNumber)
	CALL APRNT
	JP	 MAIN_LOOP		;exit command and return to main monitor loop

;------------------------------------------------------------------------------
; GET_BYTE - Reads in two hex characters from the serial port, converts them
;	to a single binary byte, and updates the checksum
;	Entry: [E] = checksum
;   Exit:  [A] = the data byte
;		   [E] = updated checksum. All other registers unchanged
GET_BYTE:
	PUSH BC
	CALL CONIN
	CALL ASC2HEX		;convert it to a binary number
	LD	 C,A			;save it in C
	LD	 A,ERR2
	JP	 C,ERR_IN_REC
	LD	 A,C			;no error, get binary number back in [A]
	RLCA				;shift nibble into high 4 bits
	RLCA
	RLCA
	RLCA
	LD	 B,A			;save high nibble in [B]
	CALL CONIN
	CALL ASC2HEX		;convert it to a binary number
	LD	 C,A			;save it in C
	LD	 A,ERR2
	JP	 C,ERR_IN_REC
	LD	 A,C			;no error, get binary number back in [A]
	OR	 A,B			; combine the two nibbles into one byte
	LD	 B,A			; save the byte in [B]
	ADD	 A,E			; update the checksum
	LD	 E,A
	LD	 A,B			;and return the byte in [A]
	POP	 BC
	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; LOAD COMMAND - loads a binary file from the SD card into memory at
;	<start addr> or at the default address of 040000 if only a carriage return
;	is entered.  The file name  entered must include the path if the file
;	isn't in the root directory.
;   USAGE:  L<start addr>[CR]
;			L[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
LOAD:
	CALL HEXSP1
	POP	 HL
	LD	 (LoadAddr),HL
	CALL CRLF
	CALL PRINTI
	DB	 'Enter name of file to load: ',00	
	LD	 HL,FileName		;set pointer to storage for the file name
	CALL GET_STRING			;read in the file name from the keyboard
MOS_LOAD:
	LD	 HL,FileName	;put the address of the FileName string in HL
	LD	 DE,(LoadAddr)	;put the start address at which to load the file in DE
	LD	 BC,MAX_SIZE	; maximum allowed size
	LD	 A,mos_load		;execute the MOS command to load a file
	RST.LIL	08h
	CP	 A,00
	JR	 NZ,FILE_LD_ERR
	CALL PRINTI
	DB	 'File loaded OK',00	
	JP	 MAIN_LOOP		;done, return to main monitor loop

FILE_LD_ERR:
	CALL PRINTI
	DB	 'File load error',00
	JP	 MAIN_LOOP		;done, return to main monitor loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; MOVE COMMAND - moves a block of memory from <addr1> thru <addr2> to the
;	the address starting at <addr3>.  
;   USAGE: M<start addr> <end addr> <destination start addr>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
MOVE:
	CALL GET3HEX	;get 3 parameters, start address in HL
MO1:
	LD   A,(HL)		;move one byte to destination address given by BC
	LD   (BC),A
	INC  BC	    	;increment destination pointer
	CALL HILOX		;inc source addr (HL) and see if end addr (DE) exceeded
	JR   MO1		;if so, return to main monitor loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; QUERY I/O PORT COMMAND - reads a byte from an input port and displays it
;   as a binary number, or sends a byte to an output port.
;	USAGE: QO<port>,<byte>[CR]   or   QI<port>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
QUERY:
	CALL TI				;get next character
	CP	 'O'
	JR	 Z,QOUT			;do port output operation if 'O'
	CP	 'I'			;do port input operation if 'I'
	JP	 NZ,ERROR		;else it's an error
	CALL HEXSP1			;get input port number in [C]
	POP	 BC
	CALL IN_OUT_MODIFY ;change byte 3 of the next instruction to the value in [C]
	DB	 0EDh,18h,00   ;machine language for the IN0 E,(nn) instruction
	CALL BITS
	JP	 MAIN_LOOP		;done, return to main monitor loop

QOUT:
	CALL HEXSP2			;get output port number and byte to output
	POP	 DE				;the byte to output is in E
	POP	 BC				;and the port number is in C
	CALL IN_OUT_MODIFY  ;change byte 3 of the next instruction to the value in [C]
	DB	 0EDh,19h,00	;machine language for the OUT0 (nn),E instruction
	JP	 MAIN_LOOP		;done, return to main monitor loop

;------------------------------------------------------------------------------
; IN_OUT_MODIFY - Replaces the 3rd byte of the instruction immediately
;	following  a call to this routine with the value in the [C] register. 
IN_OUT_MODIFY:
	EX	 (SP),IX	;SP points at the instruction that follows this call, so put
	LD	 (IX+2),C	;  SP into IX and load the value in [C] into location IX+2
	EX	 (SP),IX
	RET

;------------------------------------------------------------------------------
; BITS - displays the byte in [E] on the console as a binary number
BITS:
	LD	 B,8
	CALL PSPACE		;space over
QUE2:
	SLA	 E			;shift a bit into CY
	LD	 A,18H		;load ASCII '0' divided by 2
	ADC	 A,A	    ;make into '0' or '1'
	LD	 C,A		;print it
	CALL CONOUT
	DJNZ QUE2
	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; REGDISP COMMAND - Displays the contents of all Z80 registers on the console.
;	USAGE: R[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
REGDISP:
	LD  IX,(StackTop)
	LD   B,13		;display contents of all 13 registers
REG_LP:
	LD	 HL,REG_ORDR
	LD	 A,B
	DEC	 A			;register # is in A
	CALL ADD_HL_A 	;pick up an offset from REGORDER
	LD	 A,(HL)
	OR	 A			;set flags. preserve offset in A in subsequent code
	CALL M,CRLF
	AND	 0FH
	CALL GET_NAME 	;get address of reg name in HL
	PUSH AF			;print reg name, preserve A
	CALL PRINT
	POP	 AF
	CALL PRINT_REG	;print contents of register
	CALL PRINTI
	DB	 '  ',00
	DJNZ REG_LP
	JP	 MAIN_LOOP	;done, return to main monitor loop
	
; Get address of the register name in HL
GET_NAME:
	PUSH AF
	RLCA
	RLCA
	LD	 HL,NAMES
	CALL ADD_HL_A
	POP	 AF
	RET
; Print register contents
PRINT_REG:
	CALL PRINTI
	DB	 '= ',00
	LD	 HL,(StackTop)	;get start of saved register area in HL
	LD	 C,A			;multiply value in A by 3
	RLCA
	ADD	 A,C
	CALL ADD_HL_A	;HL = where to find Register
	LD	 HL,(HL)	;HL = (HL)
	LD	 E,00		;E serves as the "print AF" flag
	CP	 A,03		;are we printing contents of AF?
	CALL Z,SET_AF_FLAG
	CP	 A,1Bh		;or AF'?
	CALL Z,SET_AF_FLAG
	LD	 A,E
	CP	 A,0FFh		;printing AF or AF'?
	CALL Z,AFPRNT	;yes, print register contents as "AA  FF"
	CALL NZ,HLPRNT  ;else print as contents of a 24-bit register
    LD   C,' '	    ;followed by a space
	CALL CONOUT
	RET
	
; Add the value in A to HL
ADD_HL_A:
	PUSH AF
	ADD	 A,L
	LD   L,A
	JR  NC,NO_CY
	INC  H
NO_CY:
	POP	 AF
	RET

SET_AF_FLAG:
	LD	 E,0FFh
	RET
	
AFPRNT:
	PUSH AF
	LD	 A,H
	CALL APRNT	;print the value of the [A] register
	CALL PSPACE	;print a space
	LD	 A,L
	CALL APRNT	;print the value of the [F] register
	CALL PSPACE	;print a space	
	POP	 AF
	RET

;------------------------------------------------------------------------------
; HL24PRNT - Prints the contents of the 24-bit HL register on the console.
;	Entry: HL = 24-bit address to display
;   Exit:  All registers unchanged
HL24PRNT:
	PUSH	HL		;save the 3-byte value of HL on the stack
	LD		HL, 2	;set HL = SP + 2 so it now points to the most significant
	ADD		HL, SP	;  byte of the original 3-byte value in HL
	LD		A, (HL)	;load that byte into A
	POP		HL		;restore SP
	CALL APRNT		;and print the most significant byte of HL
	LD  A,H			;now print the 8-bit H register on the console
	CALL APRNT
	LD	 A,L		;and then the 8-bit L register
	CALL APRNT
	RET

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SAVE COMMAND - Save a file to the SD card. The file name entered should
;	include the path if you don't want it stored in the root directory.
;   USAGE: S<StartAddr> <EndAddr>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SAVE:
	CALL GET2HEX		;get parameters in HL and DE
	LD	 (StartAddr),HL	;save start address
	LD	 (EndAddr),DE	;and end address
	CALL PRINTI			;get the file name
	DB	 'Enter file name: ',00
	LD	 HL,FileName
	CALL GET_STRING

	LD	 HL,FileName
	LD	 A,mos_del
	RST.LIL	08h
	; CP	 A,00
	; JR	 NZ,FILE_DEL_ERR
	LD	 HL,(EndAddr)	;put end address of the file in HL
	LD	 DE,(StartAddr)	;put start address of the file in DE
	SBC	 HL,DE			;calculate (EndAddr - StartAddr)
	LD	 BC,000000
	LD	 B,H			;put the number of bytes to save in BC
	LD	 C,L
	LD	 HL,FileName	;put the address of the FileName string in HL
	LD	 A,mos_save		;execute the MOS command to save a file
	RST.LIL	08h
	CP	 A,00
	JR	 NZ,FILE_SAV_ERR
	CALL PRINTI
	DB	 'File saved OK',00	
	JP	 MAIN_LOOP		;done, return to main monitor loop

FILE_SAV_ERR:
	CALL PRINTI
	DB	 'File save error',00
	JP	 MAIN_LOOP		;done, return to main monitor loop

; FILE_DEL_ERR:
	; CALL PRINTI
	; DB	 'Existing file delete error',00
	; JP	 MAIN_LOOP		;done, return to main monitor loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; TYPE COMMAND - Displays the contents of a block of memory as ASCII text
;	USAGE: T<addr1> <addr2>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
TYPE:
	LD	 C,02		;get 2 parameters
	CALL HEXSP
	POP	 DE			;put <addr2> in DE
	POP	 HL			;and <addr1> in HL
TYP1:
	CALL CRLF
	CALL HLPRNT		;print HL and a space
	LD	 C,20h		;20h = ASCII code for a space
	CALL CONOUT
	LD	 B,60
TYP2:
	LD	 A,(HL)		;get a character
	AND	 7Fh		;mask off high bit
	CP	 ' '		;is it a control code?
	JR	 NC,TYP4
TYP3:
	LD	 A,'.'		;change char to a period if a Control code
TYP4:
	CP	 7Eh		;or if the DEL character
	JR	 NC,TYP3
	LD	 C,A
	CALL CONOUT
	CALL HILOX		;quit if end of range reached 
	DJNZ TYP2		;start new line when B = 0
	JR	 TYP1

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; USER COMMAND - This jumps to any user program that has been stored in memory
;	starting at location USER_START (040100h)
;	USAGE:	U[CR}
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
USER:
	LD	 HL,USER_START		;just put a return at location 040100h for now
	LD	 A,0C9h
	LD	 (HL),A

	CALL USER_START		;call a user program (must end with a return)
	JP	 MAIN_LOOP		;return to main monitor loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; VERIFY COMMAND - Verifies that the contents of one memory block are identical
;   to another block of memory. 
;   USAGE: V<start addr> <end addr> <start addr of 2nd memory block>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
VERIFY:	CALL GET3HEX ;get 3 parameters, start address in HL
VERI0:	LD	 A,(BC)	;get a byte of 2nd memory block (BC)
	CP	 (HL)		;compare with byte in 1st block
	JR	 Z,VERI1	;continue if OK
	PUSH BC			;else display address of error
	CALL CERR	
	POP	 BC
VERI1: INC	BC		;increment 2nd block address
	CALL HILOX		;inc 1st block addr (HL),see if end addr (DE) exceeded
	JR	 VERI0

; Display the current location pointed to by (HL), the value at that
; location, and the contents of the accumulator.
CERR: LD	B,A	     ;save A
	CALL HLPRNT	     ;display HL
	CALL PSPACE
	LD	 A,(HL)
	CALL APRNT	     ;print contents of location pointed to by HL
	CALL PSPACE	     ;space over
	LD	 A,B
	CALL APRNT	     ;print the accumulator
	JP	 CRLF	     ;CRLF and return
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; WHERE COMMAND - searches memory for a specified sequence of bytes.
;	As many bytes as desired may be entered, separated by commas. The entire
;	memory is searched starting from 0000, and all starting addresses of each
;	occurance of the search string are printed on the console.
;   USAGE: W<byte1>,<byte2>,<byte3>,...[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
WHERE:
	PUSH IX			;save IX
	LD	 DE,000000	;search string byte count will be in E
	LD	 IX,SrchBytes
WHER0:
	CALL HEXSP1		;get one byte, put it on the stack, and save it in B
	POP	 HL	     	;pick it up
	LD	 (IX),L
	INC	 IX
	INC	 E	     	;increment byte count
	LD	 A,B	    ;was last char entered a CR?
	SUB	 CR
	JR	 NZ,WHER0		;more to go
	LD	 A,E
	LD	 (ByteCount),A	;save the search string byte count
	LD	 HL,SRCH_START	;HL = starting search address
	LD	 BC,SRCH_LEN
FINDC:
	LD	 IX,SrchBytes
	CALL CRLF
FIND:
	LD	 A,(ByteCount)	;reset the search string byte count
	LD	 E,A
	LD	 A,(IX)   		;get the first search byte
	CPIR		    	;compare A with (HL), inc HL, dec BC, and repeat
						;  until A = (HL) or BC-1 = 0
	JP	 PO,WDONE		;PO flag is set if BC-1 = 0
 
	LD	 (SrchAddr),HL	;save current search address
FOUND:
	DEC	 E				;decrement count of search bytes
	JR	 Z,TELL	    	;found the string
	LD	 A,(IX+1)  		;check next search byte
	CP	 A,(HL)	    	;is it a match?
	JR	 NZ,FIND		;no match, keep looking
	INC	 HL	     		;bump pointers
	INC	 IX
	JR	 FOUND	   		;test next match
TELL:
	LD	 A,(ByteCount)	;put ByteCount in DE
	LD	 E,A
	XOR	 A				;clear CY
	SBC	 HL,DE			;set HL = HL - ByteCount
	CALL HLPRNT	   		;show address of found string on console
	LD	 HL,(SrchAddr)
	JR	 FINDC
WDONE:
	POP	 IX			;restore original IX value
	JP	 MAIN_LOOP	;return to main monitor loop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; XMODEM COMMAND - Reads a file sent via a serial port from a PC terminal
;	program like TeraTerm  and places it in RAM at a specified location.
;	The file must be sent via the XModem protocol.
;   USAGE: X<StartAddr>[CR]
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
XMODEM:
	LD	 C,01			;get a beginning load address
	CALL HEXSP
	POP	 HL
	CALL CRLF
	LD	 (NextByte),HL	;save the load address
	LD	 HL,SIGNON		;print the signon message
	CALL PRINT
	CALL CRLF
	LD	 A,01			;initialize the block number
	LD	 (BlockNum),A
	LD	 HL,WAITMSG		;waiting for XModem program to start
	CALL PRINT
	LD	 A,15			;make sure line is clear for 15 seconds		
	CALL TIMEOUT_BYTE	;while XModem program on PC is being started
	JP	 NC,CANCEL		;abort if garbage character received
	LD	 HL,STARTMSG
	CALL PRINT
	CALL PRINTI
	DB	 'Start Address: ',00
	LD	 HL,(NextByte)
	CALL HLPRNT
	CALL CRLF
	CALL XM_INIT
XM_LP:
	CALL XM_RECV		;receive the next packet
	JR	 XM_LP			;loop until EOT Received		
		
;-------------------------------------------------------------------------
;XM_INIT -Tell PC to start an XModem transfer and receive first packet		
XM_INIT:
	LD	 A,01			;initialize the block number
	LD	 (BlockNum),A
	LD	 A,NAK			;send a NAK to terminal to start the transfer
	CALL PUT_CHAR
RECV_LP:
	CALL GET_HDR		;get the packet header
	JR 	 GET_DATA		;header good, get rest of packet
	
;--------------------- XMODEM RECEIVE --------------------------
;Entry:	XM_INIT jumps to GET_DATA in the middle of the routine
;		NXT_BYTE = next memory location to write the file to
;		BLKNUM = current block number
;------------------------------------
XM_RECV:
	LD A,ACK			;send ACK to start receiving next packet
	CALL PUT_CHAR
	CALL GET_HDR	
GET_DATA:
	LD C,A			;put block # in C
	LD	 A,(BlockNum)	;compare with expected block number #
	CP	 C
	JR	 Z,BLKNUM_OK	;get rest of packet if block # is correct
	JP	 CANCEL			;cancel if block # isn't correct
BLKNUM_OK:
	LD B,128		;128 bytes per block
	LD	 C,0			;clear the checksum
	LD	 HL,(NextByte)	;save HL, has the address where block is to go
BLK_LP:
	CALL CONIN			;get a data byte
	LD	 (HL),A			;store it in memory
	LD	 A,(HL)			;update the checksum
	ADD	 A,C
	LD	 C,A
	INC	 HL				;advance to next memory location
	DEC	 B				;decrement # of bytes left in packet
	JR   NZ,BLK_LP		;some bytes left, go back for more
	LD	 (NextByte),HL	;update RAM storage address
	CALL CONIN			;end of packet reached, get checksum
	CP	 C
	JR	 NZ,CANCEL		;abort if checksum not valid	
	LD	 A,(BlockNum)	;advance to next packet
	INC	 A
	LD	 (BlockNum),A
	RET				
						
;---------------------------------------------------------------
;GET_HDR - Get a valid packet header
;	Exit: CY clear and A = B = block # if valid header found
;		  Jump to GOT_EOT if end of text character received
;		  Abort if neither SOH or EOT received
GET_HDR:
	CALL CONIN		;test first byte in header
	CP	 SOH
	JR	 Z,GET_BLK	;if SOH received, get block # next
	CP	 EOT
	SCF
	JR	 Z,GOT_EOT	;if EOT received, transfer complete
	JP	 CANCEL		;else abort
		
GET_BLK:
	CALL CONIN		;get the block #
	LD	 B,A		;save it in B
	CALL CONIN		;get the complement of the block #
	CPL
	CP	 B			;is the block # valid?
	JP	 NZ,CANCEL	;no, abort
	RET											

;---------------------------------------------------------------
; PUT_CHAR - Output a character to the console
;	Entry: A = character to send
;   Exit:  All registers unchanged
PUT_CHAR:
	PUSH AF
	PUSH BC		;Save registers
	LD	C,A
	CALL CONOUT
	POP BC
	POP AF
	RET	
						
;---------------------------------------------------------------
;CANCEL - Cancel transfer and abort on all errors
CANCEL:
	LD A,CAN
	CALL PUT_CHAR
	CALL PUT_CHAR
	CALL PURGE
	LD	 HL,CANCELMSG
	CALL PRINT
	JP	ERROR						

GOT_EOT:
	LD A,NAK		;NAK the EOT
	CALL PUT_CHAR
	CALL CONIN		;wait for 2nd EOT
	CP	 EOT
	JR	 Z,FINISH
	CALL CANCEL
	
FINISH: 
	LD A,ACK		;ACK the 2nd EOT
	CALL PUT_CHAR
	CALL PRINTI
	DB	 'End Addresss: ',00
	LD	 HL,(NextByte)
	CALL HLPRNT
	CALL CRLF
	LD	 HL,FINISHMSG
	CALL PRINT
	CALL CRLF
	JP	 MAIN_LOOP			;return to main monitor loop					

;============================== END OF COMMANDS ===============================
;==============================================================================

;==============================================================================	
;============================== SUPPORT ROUTINES ==============================

HEXSP1:	LD	C,01	;get 1 parameter from console and put it on the stack
		JP HEXSP
		
HEXSP2:	LD	C,02	;get 2 parameters from console and put them on the stack
		JP HEXSP

;------------------------------------------------------------------------------
; HEXSP - This is the main "parameter-getting" routine. It takes hex values
;	entered at the console, separated by a space or comma, and places them
;	on the stack as 24-bit binary values.
;	On entry the C register must contain the number of hex values expected.
;	If a carriage return is entered instead of an expected hex value, it places
;	a 0000 on the stack. Entering a non-hex character causes HEXSP to abort.
HEXSP: LD   HL,0	 ;initialize HL to zero
EX0:  CALL TI	     ;get something from console
EX1:  LD   B,A	     ;save it in B
	CALL ASC2HEX	     ;convert ascii to hex
	JR	 C,EX2	     ;illegal character dectected if carry set
	ADD	 HL,HL	     ;multiply by 16
	ADD	 HL,HL
	ADD	 HL,HL
	ADD	 HL,HL
	OR	 L	     	 ;or in a nibble
	LD	 L,A
	JR	 EX0	     ;get more nibbles
EX2: EX	(SP),HL	     ;save on the stack
	PUSH HL	     	 ;replace the return
	LD	 A,B	     ;test the delimiter
	CALL QCHK
	JR	 NC,EX3	     ;jump if CR entered
	DEC	 C	     	;should go to zero
	RET	 Z	     	;return if it does
EX3: JP	 NZ,ERROR   ;something wrong
	DEC	 C	     	;do this again?
	JR	NZ,HEXSP	    ;yes
	RET		     	;else return
EXF: LD	 C,1
	LD	 HL,0
	JR	 EX1

;------------------------------------------------------------------------------
; ASC2HEX - Qualify the ASCII character in A as representing a valid hex digit,
;   and convert it to hexadecimal number. Returns with CY set if not
;   a hex digit (0 thru F)
ASC2HEX: SUB	'0'	;qualify the character
	RET	 C	     	;no good if <0
	CP	 'G'-'0'	;is it >F?
	CCF		     	;also no good
	RET	 C
	CP	 10	     	;is it a number?
	CCF
	RET	 NC	     	;return clean if so
	SUB	 'A'-'9'-1	;adjust and filter out ":" thru "@"
	CP	 0AH
	RET

;------------------------------------------------------------------------------		
; GET2HEX - get two parameters from the console, place them in DE & HL,
;	and then CRLF
GET2HEX: LD	C,02
	CALL HEXSP
	POP	DE		;put 2nd param in DE
	POP	HL		;and 1st param in HL
	JP	CRLF
	
;------------------------------------------------------------------------------	
; GET3HEX - Gets 3 parameters from the console, places the 1st parameter in HL,
;   the 2nd in DE, and the 3rd in BC
GET3HEX:	LD C,03
	CALL	HEXSP
	CALL	CRLF
	POP	BC
	POP	DE
	POP	HL
	RET

;------------------------------------------------------------------------------	
; HILOX - Tests for end address of a range. The Carry flag is set if the range
;   has been exceeded. Used by the DISPLAY, MOVE, TYPE, and VERIFY commands.
HILOX:
	CALL	HILO
	RET	 NC	    	;address is within range, just return
	JP	 MAIN_LOOP	;else end command and go back to monitor main loop
HILO:
	INC	HL		;increment HL
	LD	A,H	    ;test for crossing 64K border
	OR	L
	SCF
	RET	Z	    ;return with Carry set if HL = 0
	LD	A,E	    ;now test HL vs. DE
	SUB	L
	LD	A,D
	SBC	A,H
	RET		    ;return with Carry set if HL > DE

;------------------------------------------------------------------------------
; QCHK - Returns zero if A holds a space or a comma, and returns with carry set
;   if it's a CR
QCHK:  	CP 	 ' '	;return zero if delimiter
		RET	 Z
		CP	 ','
		RET	 Z
		CP	 CR		;return with carry set if CR
		SCF	
		RET	 Z
		CCF		 	;else return non-zero, no carry
		RET

;------------------------------------------------------------------------------
; SP_RET - This routine restores IX and SP to their startup values and jumps to
;   the main monitor work loop.
SP_RET:
	LD	 IX,(StackTop)
	LD	 SP,IX
	JP	 MAIN_LOOP	    ;go back to work


;---------------------------------------------------------------
;PURGE - Clears all incoming bytes until the serial input line
;  is clear for 2 seconds
PURGE: LD	A,2		;2 seconds for time out
	CALL TIMEOUT_BYTE
	JR	 NC,PURGE
	RET

;---------------------------------------------------------------
; CHK_BYTE - Check if a data byte is available, input the byte
;	if one is available
;		Exit: CY=0, A = data byte
;			  CY=1, no data byte available
;		All other registers unchanged
CHK_BYTE: CALL CONSTS
		JR	 Z,NO_CHAR
		CALL CONIN
		CCF
		RET
NO_CHAR: SCF
		RET


;---------------------------------------------------------------
; TIMEOUT_BYTE - Gets a byte within a time limit
;  Entry: A = number of seconds before timeout
;  Exit:  CY=1, No Char (Time Out)
;		  CY=0, A = Char
TIMEOUT_BYTE:
	PUSH HL
	PUSH DE
	PUSH BC
	LD	 DE,0001
GET3:
	PUSH AF
	LD	 HL,3282	;inner loop count down until timeout
GET1:
	LD	 B,0FFh
GET2:
	CALL CHK_BYTE	;see if a data byte is available
	JP	 NC,GOT_BYTE
	DJNZ GET2
	SBC	 HL,DE
	JR	 NZ,GET1
	POP	 AF
	DEC	 A
	JR	 NZ,GET3
	SCF				;carry set to indicate timeout
GOT_BYTE:
	POP	 BC
	POP	 DE
	POP	 HL 
	RET

;==============================================================================
; SAVREG - This routine saves all the eZ80 registers in the register storage
;   area, restores the code bytes at the breakpoint, and then jumps to the
;	register display routine. 
SAVREG:
	LD	 (IX_Sav),IX	;temporarily save the IX value at the breakpoint
	LD	 IX,(StackTop)	;get stack top into IX			
	LD	 (IX+RSHL),HL	;save HL in the register storage area
	LD	 (IX+RSBC),BC	;save BC in the register storage area
	LD	 (IX+RSDE),DE	;save DE in the register storage area
	LD	 (IX+RSIY),IY	;save IY in the register storage area
	LD	 HL,(BrakPt)	;save PC in the register storage area
	LD	 (IX+RPC),HL
	LD	 (SP_Sav),SP	;save SP in the register storage area
	LD	 HL,(SP_Sav)
	LD	 (IX+RSSP),HL
	PUSH AF				;save AF in the register storage area
	POP	 HL
	LD	 (IX+RSAF),HL
	LD	 HL,000000		;save I and R in the register storage area
	LD	 A,I
	LD	 H,A
	LD	 A,R
	LD	 L,A
	
	EXX					;save alternate register set	
	EX	 AF,AF'
	LD	 (IX+RSHL2),HL	;save HL' in the register storage area
	LD	 (IX+RSBC2),BC	;save BC' in the register storage area
	LD	 (IX+RSDE2),DE	;save DE' in the register storage area
	PUSH AF				;save AF' in the register storage area
	POP	 HL
	LD	 (IX+RSAF2),HL
	EXX
	EX	 AF,AF'

	LD	 IY,(IX_Sav)	;finally save the value of IX at the breakpoint
	LD	 (IX+RSIX),IY	;all registers are now saved

	PUSH IX
	LD	 HL,(BrakPt)	;restore saved instruction bytes back into program
	LD	 IX,Ibytes
	LD	 B,04
RESTOR:
	LD	 A,(IX)
	LD	 (HL),A
	INC	 HL
	INC	 IX
	DJNZ RESTOR
	POP	 IX
    CALL PRINTI
    DB 	 CR,LF,'Break @',00
    LD   HL,(BrakPt)
    CALL HLPRNT        ;print breakpoint address
    JP	 REGDISP       ;and display registers

;==============================================================================
; RESTART - This routine is executed when a program halted by a breakpoint is
; restarted using the G,<breakpt>[CR] or the G[CR} command. IR and the
; alternate register set are not restored in this version
RESTART:
	LD  A,0C3H
	LD   (JmpLoc),A
    LD	 HL,(StackTop)
    LD   BC,000003
    ADD  HL,BC
	LD	 SP,HL      ;set SP to point at RSAF in register storage area
	POP	 AF			;restore the registers
	POP	 BC
    POP  DE
    POP  HL
    POP  IX         ;IX now contains the saved value of the PC
    LD   (JmpLoc+1),IX
    POP  IX
    POP  IY
	LD	 SP,(SP_Sav) ;restore SP
    JP   JmpLoc      ;and start code execution at the stored PC location

;------------------------------------------------------------------------------
; Table of offsets used by the register display routine
REG_ORDR:
		DB	0		;registers to dump (Numbers shifted left)
		DB	5		;MSB will indicate a NEW LINE
		DB	8
		DB	7
		DB	6 + 80H
		DB	12
		DB	11
		DB	10
		DB	9 + 80H
		DB	4
		DB	3
		DB	2
		DB	1 + 80H	;first Register to Dump

;------------------------------------------------------------------------------
; Table of register names -	used by the register display routine	
NAMES:
		DB	'SP ',00	 ;0
		DB	'AF ',00	 ;1
		DB	'BC ',00	 ;2
		DB	'DE ',00	 ;3
		DB	'HL ',00	 ;4
		DB	'PC ',00	 ;5
		DB	'IX ',00	 ;6
		DB	'IY ',00	 ;7
		DB	'IR ',00	 ;8
		DB	'AF',27h,00  ;9	  27h is the ASCII code for a single quote mark
		DB	'BC',27h,00  ;10
		DB	'DE',27h,00  ;11
		DB	'HL',27h,00  ;12

;==============================================================================
;================================= MESSAGES ===================================		
SIGNON:		DB	CR,LF,'XModem File Transfer',00
ADDRESSMSG:	DB	CR,LF,'Enter file start address: ',00
WAITMSG:	DB	'20 second delay for Xmodem start',CR,LF,00
STARTMSG:	DB	'Starting transfer',CR,LF,00
CANCELMSG:	DB	'Transfer Canceled',CR,LF,00
FINISHMSG:	DB 	CR,LF,'Transfer Complete',00

MAIN_END:	DB 77h

;==============================================================================
;============================= LOCAL VARIABLES ================================
	ALIGN 10h
; Variables for WHERE command
SrchBytes 	DS 8
SrchAddr	DS 3
ByteCount	DS 1

; Variables for restart from a breakpoint
StackTop DS 3	;address of the monitor's stack top
IX_Sav  DS 3	;saved value of IX
SP_Sav  DS 3	;saved value of SP
InChar  DS 1
GoAddr  DS 3	;program start address used by GOTO command
BrakPt  DS 3	;breakpoint address
Ibytes  DS 4	;storage for the instruction at the next breakpoint
JPbytes DS 4	;storage for a jump instruction inserted into the code
				;  at a breakpoint
JmpLoc	DS 4	;storage for the jump instruction used for a restart
				;  after a breakpoint

; Variables for file I/O
RecordNumber DS 1	;number of Hex file records read
DataBytes   DS 1	;number of data bytes in record
ExtAddress	DS 3	;24-bit extended address for HEXLOAD
LoadAddr	DS 3	;load address for the binary output file
StartAddr	DS 3	;start address for the binary output file
EndAddr		DS 3	;end address for the binary output file
FileName	DS 32

; Variables for XMODEM command
NextByte 	DS 3	;address of next byte to store
BlockNum 	DS 3	;storage for the block number	
	END
