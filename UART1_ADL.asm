;	<< UART1_ADL.asm >>
;	R.L. Shoemaker  22-Apr-24

	.assume	ADL = 1				;set the program to run in ADL mode	

	DEFINE  CODE1,SPACE=RAM
	SEGMENT CODE1

;==============================================================================
UART1_START	EQU (4F000h + 0C00h)
;==============================================================================

	.global INIT_GPIO,OPEN_UART1
	.global	CONOUT,PRINT,PRINTI
	.global CONIN,CONSTS,TI,GET_STRING
	.global CRLF,PSPACE,HLPRNT,APRNT

;==============================================================================
; eZ80 GPIO port addresses
PC_DR		EQU 9Eh		;Port C Data register
PC_DDR 		EQU 9Fh		;Port C Data Direction register
PC_ALT1 	EQU A0h		;Port C Alternate Register 1
PC_ALT2 	EQU A1h		;Port C Alternate Register 2

;==============================================================================
; eZ80 UART1 port addresses
UART1_BRG_L EQU 0D0h	;UART1 Baud Rate Generator Register Low Byte
UART1_BRG_H	EQU 0D1h	;UART1 Baud Rate Generator Register High Byte
UART1_LCTL 	EQU 0D3h	;UART1 Line Control Register
UART1_LSR 	EQU 0D5h	;UART1 Line Status Register
UART1_THR	EQU 0D0h	;UART1 Transmit Holding Register
UART1_RBR 	EQU 0D0h	;UART1 Receive Buffer Register
UART1_IER	EQU 0D1h	;UART1 Interrupt Enable Register
UART1_IIR	EQU 0D2h	;UART1 Interrupt Identification Register
UART1_FCTL	EQU 0D2h	;UART1 FIFO Control Register
UART1_MCTL	EQU 0D2h	;UART1 Modem Control Register
UART1_MSR   EQU 0D6h    ;UART1 Modem Status Register
UART1_SPR	EQU 0D7h	;UART1 Scratch Pad Register

;==============================================================================
; Baud rate = 18432000/16*BRGdivisor = 1152000*(1/BRGdivisor)
; BRGdivisor = 10 gives a baud rate of 115200
; BRGdivisor = 20 gives a baud rate of 57600
; BRGdivisor = 30 gives a baud rate of 38400
; BRGdivisor = 60 gives a baud rate of 19200
; BRGdivisor = 120 gives a baud rate of 9600
BAUD_DIV_115  EQU 10
BAUD_DIV_57   EQU 20
BAUD_DIV_38   EQU 30
BAUD_DIV_19	  EQU 60
BAUD_DIV_9600 EQU 120

;=============================================================================
; Constants
CR		EQU	0DH		;ASCII code for carriage return
LF		EQU	0AH	    ;ASCII code for line feed
TAB		EQU	09H		;ASCII code for TAB
BS		EQU 08H		;ASCII code for backspace
NULL	EQU 00H		;ASCII code for NUL
ESC		EQU 1BH		;ASCII code for escape key

;==============================================================================
;============================= UART1 I/O ROUTINES =============================

	ORG  UART1_START
;------------------------------------------------------------------------------
; CONOUT - Output a byte to the UART1 serial port
;	Entry: C = byte to send
;   Exit:  All registers unchanged
;------------------------------------------------------------------------------	
CONOUT:
	PUSH BC
	PUSH AF
CO1:
	IN0 A,(UART1_LSR)	;read the UART1 Line Status Register
	AND	 20h			;is the Transmit Holding Register empty?
	JR	 Z,CO1			;it's not empty, so keep checking
	LD	 A,C
	OUT0 (UART1_THR),A	;empty, so send byte to the Transmit Holding Register
	POP	 AF
	POP	 BC
	RET

;------------------------------------------------------------------------------
; CONIN - Input a byte from UART1 by polling the Data Ready bit in the
;	Line Status Register.
;	Entry: none
;   Exit:  A = byte received. All other registers unchanged
;------------------------------------------------------------------------------	
CONIN:
	IN0	 A,(UART1_LSR)	;read the UART1 Line Status Register
	AND	 01				;is the Data Ready bit set?
	JR	 Z,CONIN		;no, keep checking
	IN0	 A,(UART1_RBR)	;yes, get the byte from the Receive Buffer Register
	RET

;------------------------------------------------------------------------------
; CONSTS - Check the console status.
;	Entry: none
;   Exit:  A = 00 if no byte from keyboard waiting
;		   All other registers unchanged
;		Else:
;			A = FF if a byte waiting in the UART
;			All other registers unchanged
;------------------------------------------------------------------------------
CONSTS:
	IN0	 A,(UART1_LSR)	;read the UART1 Line Status Register
	AND	 01				;is the Data Ready bit set?
	LD	 A,00			;return zero if no byte
	JR	 Z,NOBYTE
	CPL					;return 0FF otherwise
NOBYTE:
	RET

;------------------------------------------------------------------------------
; INIT_GPIO - Set all 4 GPIO mode control registers of Port C to their default
;	values. This sets all 8 pins of Port C to be configured as standard digital
;	input pins (i.e. Mode 2).
;------------------------------------------------------------------------------
INIT_GPIO:
	LD	 A,0FFh
	OUT0 (PC_DR),A
	OUT0 (PC_DDR),A
	LD	 A,00
	OUT0 (PC_ALT1),A
	OUT0 (PC_ALT2),A
	RET

;------------------------------------------------------------------------------
; OPEN_UART1 - Initialize UART1 of the eZ80 to provide serial input and serial
;	output in polling mode, with 8-bit data, 1 stop bit, and no parity.
;------------------------------------------------------------------------------
OPEN_UART1:
	LD	 A,80h				;set the DLAB bit in the Line Control Register to
	OUT0 (UART1_LCTL),A		;  allow access to the Baud Rate Generator registers
	LD	 A,BAUD_DIV_38		;set BRG Register Low Byte to give 38400 baud	
	OUT0 (UART1_BRG_L),A
	LD	 A,00				;set BRG Register High Byte to 00
	OUT0 (UART1_BRG_H),A
	LD	 A,00				;clear DLAB in the Line Control Register to allow
	OUT0 (UART1_LCTL),A		;  access to the transmit and receive registers

; The next set of instructions sets pins 0 and 1 of Port C into GPIO Mode 7.
; Mode 7 configures the two pins to be controlled by the alternate functions
; assigned to those pins (UART1 TxD and RxD for pins 0 and 1 of Port C).	
	IN0	 A,(PC_DDR)			;set pins 0,1 in the PC_DDR register to be inputs
	OR	 A,03
	OUT0 (PC_DDR),A
	IN0	 A,(PC_ALT1)		;clear pins 0,1 in the PC_ALT1 register
	AND	 A,0FCh
	OUT0 (PC_ALT1),A
	IN0	 A,(PC_ALT2)		;set pins 0 and 1 in the PC_ALT2 register
	OR	 A,03
	OUT0 (PC_ALT2),A	

; Initialize the remaining UART1 registers
	XOR	 A				;disable modem control signals in the
	OUT0 (UART1_MCTL),A	;  Modem Control Register
	LD	 A,07			;set the receive FIFO trigger level to 1, clear and
	OUT0 (UART1_FCTL),A	;  enable the transmit and receive FIFOs in the
						;  FIFO Control Register
	LD	 A,03			;set 8 bit data, one stop bit, no parity in the
	OUT0 (UART1_LCTL),A	;  Line Control Register
	RET

;------------------------------------------------------------------------------
; CLOSE_UART1 - Close UART1 of the eZ80 
;------------------------------------------------------------------------------
CLOSE_UART1:
	XOR	 A
	OUT0 (UART1_IER),A		;disable UART1 interrupts
	OUT0 (UART1_LCTL),A		;bring Line Control Register to it's reset value
	OUT0 (UART1_MCTL),A		;bring Modem Control Register to it's reset value
	OUT0 (UART1_FCTL),A		;bring FIFO Control Register to it's reset value
	RET

;------------------------------------------------------------------------------
; TI - This is a keyboard input handling routine. It converts lower case
;	characters to upper case and then echoes them, except for carriage
;	return and escape, which are not echoed.
;	Entry: none
;   Exit:  A = ASCII code for the key pressed (converted to upper case)
;		   All other registers unchanged
TI:
	CALL CONIN	;get a character
	CP	 CR		;don't echo if CR
	RET	 Z
	CP	 ESC	;don't echo if ESC
	RET	 Z	
	CP	 'A'-1	;ASCII code is less than 'A', just echo it
	JR	 C,ECHO
	CP	 'z'+1	;ASCII code is greater than 'z', just echo it
	JR	 NC,ECHO
	AND	 5FH	;ASCII code in range 'A'-'z", convert to upper case 
ECHO:
	PUSH BC		;echo the character
	LD	 C,A
	CALL CONOUT
	LD	 A,C
	POP	 BC
	RET

;------------------------------------------------------------------------------
; GET_STRING - get a zero-terminated string from the keyboard and save it in
;	memory. Enter a CR to terminate the string entry.
;	Entry: HL = pointer to memory where the string will be stored
;   Exit:  A and HL modified. All other registers unchanged
GET_STRING:
	PUSH BC
NXT_CHAR:
	CALL CONIN		;get a character
	CP	 A,CR
	JR	 Z,END_NXT	;done if it's a carriage return
	LD	 (HL),A		;else store it in memory
	INC	 HL
	LD	 C,A		;echo the character to the screen
	CALL CONOUT
	JR	 NXT_CHAR	;and go get the next one
END_NXT:
	LD	 A,00		;terminate the string with 00
	LD	 (HL),A
	CALL CRLF
	POP	 BC
	RET

;------------------------------------------------------------------------------
; PRINT - Prints a zero-terminated string on the console. A pointer to the
;	message must be	in HL on entry.
;	Entry: HL = address of string to print
;   Exit:  Register HL is modified
PRINT:
	PUSH AF
	PUSH BC
PRNT1:
	LD	 A,(HL)		;pick up character from message pointer in HL
	INC	 HL
	CP	 00			;is it a zero?
	JR  Z,PRNT2		;done if yes
	LD	 C,A		;else print it
	CALL CONOUT
	JR	 PRNT1		;and go back for more
PRNT2:
	POP	 BC
	POP	 AF
	RET

;------------------------------------------------------------------------------
; PRINTI - Prints the NULL-terminated string given in the next line of code
;	on the console.
;	Entry: HL = address of string to print
;   Exit:  Register HL is modified
PRINTI:
	EX	 (SP),HL	;put address of next instruction in HL
	CALL PRINT
	EX	 (SP),HL	;move updated return address back to stack
	RET


;------------------------------------------------------------------------------
; CRLF - Prints a carriage return-line feed on the console.
;	Entry: none
;   Exit:  All registers unchanged
CRLF:
	PUSH BC
	LD	 C,LF
	CALL CONOUT
	LD	 C,CR
	CALL CONOUT
	POP	 BC
	RET

;------------------------------------------------------------------------------
; PSPACE - Prints a space on the console
;	Entry: none
;   Exit:  register C is modified
PSPACE:
	LD   C,' '	;print a space on the console
	JP   CONOUT

;------------------------------------------------------------------------------
; HLPRNT - Prints the contents of the 24-bit HL register on the console.
;	Entry: HL = 24-bit address to display
;   Exit:  All registers unchanged
HLPRNT:
	PUSH AF
	PUSH HL		;save the 3-byte value of HL on the stack
	LD	 HL,2	;set HL = SP + 2 so it now points to the most significant
	ADD	 HL,SP	;  byte of the original 3-byte value in HL
	LD	 A,(HL)	;load that byte into A
	POP	 HL		;restore SP
	CALL APRNT	;and print the most significant byte of HL
	LD   A,H	;now print the 8-bit H register on the console
	CALL APRNT
	LD	 A,L	;and then the 8-bit L register
	CALL APRNT
	POP	 AF
	RET

;------------------------------------------------------------------------------
; APRNT - Prints the contents of the A register on the console.
;	Entry: A = byte to display
;   Exit:  All registers unchanged
APRNT:
	PUSH BC
	PUSH AF
	RRCA		;move high nibble of [A] into low nibble	
	RRCA	
	RRCA	
	RRCA	
	CALL CONV	;convert nibble into ASCII character
	CALL CONOUT	;and display it on the console
	POP	 AF
	PUSH AF		;do the same for the low nibble  of [A] 
	CALL CONV
	CALL CONOUT
	POP	 AF
	POP BC
	RET

;------------------------------------------------------------------------------
; CONV - Converts the low nibble in A to an ASCII character and returns it in C
CONV:
	AND	 0FH
	ADD	 A,90H
	DAA	
	ADC	 A,40H
	DAA	
	LD	 C,A
	RET

	END

