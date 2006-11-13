;---------------------------------------------------------------------------
;
; LTC decoder
;
; Firmware for ATMega16-16PI microcontroller
; Copyright by Maksym Veremeyenko, 2006
;
; Changelog:
;	2006-11-12:
;		*Finished LTC decoding proc, still using INT0 only with level 
;		change detection. Sometimes counter reports wrong value - do
;		not know why.... 
;	2006-11-10:
;		*Draft code start
;
;---------------------------------------------------------------------------
; Notes:
;
;	Fuse bits values (See page 220)
;		CKSEL0	=	1	(See page 26)
;		SUT0	=	1
;		SUT1	=	1
;
;		CKOPT	=	0	(See page 27)
;		CKSEL1	=	1
;		CKSEL2	=	1
;		CKSEL3	=	1
;
;		BOOTRST	=	1	(See page 45)
;		IVSEL	=	0



.nolist
.include "m16def.inc"		;chip definition
.list
.listmac

;	DEBUG SECTIONS
;.equ	__DEBUG_TIMER0_TICK_BIT__	= 1
;.equ	__DEBUG_INT0_CALL_BIT__		= 1
;.equ	__DEBUG_BIT_FOUND_BIT__		= 1
.equ	__DEBUG_TC_FOUND_BIT__		= 1
;.equ	__LTC_PEROID_COUNTER__		= 1
.equ	__LTC_ERR_PEROID_COUNTER__	= 1
;.equ	__DEBUG_ERR_PEROID__		= 1
;.equ	__DEBUG__				= 1
.equ	__SEND_CONST_TC__			= 1

;	ALGORITHM VARIANTS
.equ	__DIS_INT_TO_AVOID_NOICE__	= 4

;	timer configuration constants
;
;	1. Clock select | CS02 CS01 CS00 | = CLK/64 = 011
;	2. WaveFormGen  | GWM01 WGM00 | = CTC = 10
;	3. CompMatchOut | COM01 COM00 | = none = 00
;	4. FOC0 = 0
;	FOC0 WGM00 COM01 COM00 WGM01 CS02 CS01 CS00
;	0    0     0     0     1     0    1    0
;;;	we want int freq 10kHz
;;;.equ	TCCR0_VALUE				= 0x0A	; 00001010 - CLK/64
;;;.equ	OCR0_VALUE				= 99	; 10kHz = 16MHz/[ 2 * |8| * (X + 1)]

;	we want int freq 20kHz
.equ	TCCR0_VALUE				= 0x0A	; 00001010 - CLK/8
.equ	OCR0_VALUE				= 49	; 20kHz = 16MHz/[ 2 * |8| * (X + 1)]


;	Port direction
;		0 - in
;		1 - out
;		00001111 - |in|in|in|in|out|out|out|out|
;
;	Port A:						11111111
;		PA0	OUT	LPT_D0
;		PA1	OUT	LPT_D1
;		PA2	OUT	LPT_D2
;		PA3	OUT	LPT_D3
;		PA4	OUT	LPT_D4
;		PA5	OUT	LPT_D5
;		PA6	OUT	LPT_D6
;		PA7	OUT	LPT_D7
;
;	Port C:						XXXXX110
;		PC0	IN	LPT_LINE_FEED
;		PC1	OUT	DEBUG_TC_FOUND
;		PC2	OUT DEBUG_TIMER0_TICK
;		PC3	OUT DEBUG_INT0_CALL

;	Port D:						00000000
;
.equ	PORT_A_DIRECTION		= 0xFF
.equ	PORT_B_DIRECTION		= 0xFF
.equ	PORT_C_DIRECTION		= 0xFE
.equ	PORT_D_DIRECTION		= 0x00
.equ	DEBUG_TC_FOUND_BIT		= 1
.equ	DEBUG_TIMER0_TICK_BIT	= 2
.equ	DEBUG_INT0_CALL_BIT		= 3
.equ	DEBUG_BIT_FOUND_BIT		= 4
.equ	DEBUG_ERR_PEROID_BIT	= 5

; RAM pointers
.equ	SRAM_BEGIN				= 0x60
.equ	_LTC_BITS				= 0x00 + SRAM_BEGIN
.equ	_LTC_DETECTED			= 0x10 + SRAM_BEGIN
.equ	_LTC_TRANS_SNAPSHOT		= 0x20 + SRAM_BEGIN

; constants
.equ	LTC_FIRST_BIT_VALUE		= 0x01
.equ	LTC_LAST_BIT_VALUE		= 0x80
.equ	LTC_TAIL_SIGN_1			= 0xFC
.equ	LTC_TAIL_SIGN_2			= 0xBF
.equ	BITMASK_F_VALUE			= 0x0F
.equ	BITMASK_7_VALUE			= 0x07
.equ	BITMASK_3_VALUE			= 0x03

;;;; for 10kHz timer
;;;.equ	LTC_PEROID_LONG_VALUE	= 0x08
;;;.equ	LTC_PEROID_SHORT_VALUE	= 0x04

; for 20kHz timer
.equ	LTC_PEROID_LONG_VALUE	= 0x10
.equ	LTC_PEROID_SHORT_VALUE	= 0x08


; registers used
.def	temp0					= r16
.def	temp1					= r20
.def	temp2					= r21
.def	LTC_PEROID				= r14
.def	LTC_PEROID_COUNTER		= r15
.def	LTC_PEROID_LONG			= r13
.def	LTC_PEROID_SHORT		= r17
.def	LTC_ZEROS_COUNTER		= r18
.def	LTC_BIT_FOUND			= r19
.def	LTC_FIRST_BIT			= r12
.def	LTC_LAST_BIT			= r11
.def	BITMASK_F				= r22
.def	BITMASK_7				= r23
.def	BITMASK_3				= r24
.def	LTC_SNAPSHOT_POS		= r25

;---------------------------------------------------------------------------
;
; INTERRUPT VECTORS TABLE
;
;---------------------------------------------------------------------------
.cseg
.org	0					; #1
	rjmp	main			; RESET - main proc
.org 0x002					; #2
	rjmp	ltc_bit_dec		; INT0 - ext int #1 from comparator 
.org 0x004					; #3
	rjmp	send_to_lpt		; INT1
.org 0x006					; #4
	rjmp	int_ignore
.org 0x008					; #5
	rjmp	int_ignore
.org 0x00A					; #6
	rjmp	int_ignore
.org 0x00C					; #7
	rjmp	int_ignore
.org 0x00E					; #8
	rjmp	int_ignore
.org 0x010					; #9
	rjmp	int_ignore
.org 0x012					; #10
	rjmp	int_ignore
.org 0x014					; #11
	rjmp	int_ignore
.org 0x016					; #12
	rjmp	int_ignore
.org 0x018					; #13
	rjmp	int_ignore
.org 0x01A					; #14
	rjmp	int_ignore
.org 0x01C					; #15
	rjmp	int_ignore
.org 0x01E					; #16
	rjmp	int_ignore
.org 0x020					; #17
	rjmp	int_ignore
.org 0x022					; #18
	rjmp	int_ignore
.org 0x024					; #19
	rjmp	int_ignore
.org 0x026					; #20
	rjmp	period_counter	; TIMER0_COMP - counter of ticks
.org 0x028					; #21
	rjmp	int_ignore		

.org	0x100

;---------------------------------------------------------------------------
;
; ignore interrupts
;
;---------------------------------------------------------------------------
int_ignore:
	reti


;---------------------------------------------------------------------------
;
; main proc
;
;---------------------------------------------------------------------------
main:
	; init stack poiner
	ldi	r16,high(RAMEND) ;High byte only required if 
	out	SPH,r16	         ;RAM is bigger than 256 Bytes
	ldi	r16,low(RAMEND)	 
	out	SPL,r16

;	setup ports directions and start vals
	ldi temp0, PORT_A_DIRECTION
	out DDRA, temp0
	ldi temp0, PORT_B_DIRECTION
	out DDRC, temp0
	ldi temp0, PORT_C_DIRECTION
	out DDRC, temp0
	ldi temp0, PORT_D_DIRECTION
	out DDRD, temp0
	ldi temp0, 0xFF
	out PORTA, temp0
	out PORTB, temp0
	out PORTC, temp0
	out PORTD, temp0

;	setup TIMER0
	ldi temp0, TCCR0_VALUE		; setup timer counter control
	out TCCR0, temp0
	ldi temp0, OCR0_VALUE		; setup timer output compare reg
	out OCR0, temp0
	ldi temp0, 0x02				; OCIE0 output compare int enable
	out TIMSK, temp0

;	setup default values
	ldi temp0, LTC_PEROID_SHORT_VALUE
	mov LTC_PEROID_SHORT, temp0
	ldi temp0, LTC_PEROID_LONG_VALUE
	mov LTC_PEROID_LONG, temp0
	ldi temp0, LTC_FIRST_BIT_VALUE
	mov LTC_FIRST_BIT, temp0
	ldi temp0, LTC_LAST_BIT_VALUE
	mov LTC_LAST_BIT, temp0
	ldi temp0, BITMASK_F_VALUE
	mov BITMASK_F, temp0
	ldi temp0, BITMASK_7_VALUE
	mov BITMASK_7, temp0
	ldi temp0, BITMASK_3_VALUE
	mov BITMASK_3, temp0

;	setup INT0 and INT1
;	ldi temp0, 0x0E				; ISC1[2]=11 (rising edge) ISC0[2]=10 (falling edge)
	ldi temp0, 0x09				; ISC1[2]=10 (falling edge) ISC0[2]=01 (any logical change)
	out MCUCR, temp0
	ldi temp0, 0xC0
	out GICR, temp0

.ifdef __DEBUG__

	; test shifter
	ldi LTC_BIT_FOUND,1				; setup bit 1
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,1				; setup bit 1
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq

.endif



	sei							; enable interrupts
__endless_loop:
	nop
	nop
	nop
	rjmp __endless_loop


;---------------------------------------------------------------------------
;
; LPT port request byte
;
;---------------------------------------------------------------------------
send_to_lpt:
	
	; check if we need to send first byte
	in temp0, PINC
	ldi temp1, 1					; PC0 - LPT_LINE_FEED
	and temp0, temp1
	brne __skip_counter_reset
	; create snapshort 
	ldi r26, _LTC_DETECTED			; setup pointers
	clr r27
	ldi r28, _LTC_TRANS_SNAPSHOT
	clr r29
	ld temp0, X+					; copy byte #0
	st Y+, temp0
	ld temp0, X+					; copy byte #1
	st Y+, temp0
	ld temp0, X+					; copy byte #2
	st Y+, temp0
	ld temp0, X+					; copy byte #3
	st Y+, temp0
	; and reset counter
	ldi LTC_SNAPSHOT_POS, _LTC_TRANS_SNAPSHOT
__skip_counter_reset:
	mov r26, LTC_SNAPSHOT_POS		; setup pointers
	clr r27
	ld	temp0, X					; load byte
;	ldi temp0, 0xCC					; stupid byte 
	out PORTA, temp0				; output byte to port
	inc LTC_SNAPSHOT_POS

	reti


;---------------------------------------------------------------------------
;
; INT request from comparator
;
;---------------------------------------------------------------------------
ltc_bit_dec:

.ifdef __DIS_INT_TO_AVOID_NOICE__
	in temp0, GICR
	cbr temp0, 6					; disable INT0
	out GICR, temp0
.endif


.ifdef __LTC_PEROID_COUNTER__
	out PORTB, LTC_PEROID_COUNTER
.endif

.ifdef __DEBUG_INT0_CALL_BIT__
	; flip bit
	in temp0, PORTC
	ldi temp1, (1<<DEBUG_INT0_CALL_BIT)
	and temp1, temp0
	brne __ltc_bit_dec_clear_bit
	sbi PORTC, DEBUG_INT0_CALL_BIT
	rjmp __ltc_bit_dec_fin
__ltc_bit_dec_clear_bit:
	cbi PORTC, DEBUG_INT0_CALL_BIT
__ltc_bit_dec_fin:
.endif

.ifdef __LTC_ERR_PEROID_COUNTER__
	ldi temp0, 0					; reset err_period on port
	out PORTB, temp0
.endif

.ifdef __DEBUG_ERR_PEROID__
	cbi PORTC, DEBUG_ERR_PEROID_BIT	; clear err period detected bit
.endif

	mov temp0, LTC_PEROID_COUNTER	; test if period is long
	and temp0, LTC_PEROID_LONG
	brne __period_is_long
	mov temp0, LTC_PEROID_COUNTER	; test if period is short
	and temp0, LTC_PEROID_SHORT
	brne __period_is_short
									; incorrect length here
.ifdef __LTC_ERR_PEROID_COUNTER__
	out PORTB, LTC_PEROID_COUNTER
.endif

.ifdef __DEBUG_ERR_PEROID__
	sbi PORTC, DEBUG_ERR_PEROID_BIT
.endif
									; something wrong
__fin_dec:							; 
	clr LTC_PEROID_COUNTER			; reset counter
	reti

__period_is_long:
	clr LTC_ZEROS_COUNTER			; reset zero counter
	ldi LTC_BIT_FOUND,0				; setup bit 0
	call check_smpte_bits			; process seq
	rjmp __fin_dec					; goto exit

__period_is_short:
	tst LTC_ZEROS_COUNTER			; check zero counter
	brne __period_is_short2			; is not zero - need process
	inc LTC_ZEROS_COUNTER			; increment counter
	rjmp __fin_dec					; foto to finish

__period_is_short2:
	clr LTC_ZEROS_COUNTER			; reset zero counter
	ldi LTC_BIT_FOUND,1				; setup bit 1
	call check_smpte_bits			; process seq
	rjmp __fin_dec					; goto exit

;---------------------------------------------------------------------------
;
; TIMER0_COMP period counter, called in 10kHz freq
;
;---------------------------------------------------------------------------
period_counter:

.ifdef __DIS_INT_TO_AVOID_NOICE__
	ldi temp0, __DIS_INT_TO_AVOID_NOICE__
	cp temp0, LTC_PEROID_COUNTER
	brlt __skip_unlock
	in temp0, GICR
	sbr temp0, 6					; allow INT0
	out GICR, temp0
__skip_unlock:
.endif


	inc LTC_PEROID_COUNTER

.ifdef __DEBUG_TIMER0_TICK_BIT__
	; flip bit
	in temp0, PORTC
	ldi temp1, (1<<DEBUG_TIMER0_TICK_BIT)
	and temp1, temp0
	brne __period_counter_clear_bit
	sbi PORTC, DEBUG_TIMER0_TICK_BIT
	rjmp __period_counter_fin
__period_counter_clear_bit:
	cbi PORTC, DEBUG_TIMER0_TICK_BIT
__period_counter_fin:
.endif

	reti

;---------------------------------------------------------------------------
;
; Shift bits and check tail for correct value
;
;---------------------------------------------------------------------------
check_smpte_bits:

.ifdef __DEBUG_BIT_FOUND_BIT__
	; set output port to LTC_BIT_FOUND
	tst LTC_BIT_FOUND
	breq __check_smpte_bits_clear_bit
	sbi PORTC, DEBUG_BIT_FOUND_BIT
	rjmp __check_smpte_bits_modif_bit_fin
__check_smpte_bits_clear_bit:
	cbi PORTC, DEBUG_BIT_FOUND_BIT
__check_smpte_bits_modif_bit_fin:
.endif

	clr r27							; clear high bytes of addresses
	clr r29
	clr r31

	ldi r26, 10 + _LTC_BITS	; load indirect addr of after-tail byte
	st X, LTC_BIT_FOUND				; store byte

	; shift 10 bytes
	ldi r26,0 + _LTC_BITS			; i=0
	ldi r28,1 + _LTC_BITS			; j=1
	ldi temp0, 10					; 10 bytes
__shift_loop:
	ld temp1, X						; load byte[i]
	ld temp2, Y+					; load byte[i + 1]
	clc
	lsr temp1						; shift right
	and temp2, LTC_FIRST_BIT		; check if next byte has lower bit
	breq __store_byte				; no lower bit
	or temp1, LTC_LAST_BIT			; set bit from [i+1] byte
__store_byte:
	st X+, temp1					; store value
	dec temp0						; descrement counter
	brne __shift_loop				; loop until counter is not zero


	; check if tail is correct
	ldi r26, 8 + _LTC_BITS			; load indirect addr of tail signature 1
	ld temp1, X+					; load byte[8] signature #1
	ldi temp0, LTC_TAIL_SIGN_1		; load sinature value 
	cp temp1, temp0					; compare values
	brne __signature_not_found
	ld temp1, X+					; load byte[9] signature #2
	ldi temp0, LTC_TAIL_SIGN_2		; load sinature value
	cp temp1, temp0					; compare values
	brne __signature_not_found

	; extract tc values
	ldi r26,0 + _LTC_BITS			; i=
	ldi r28,1 + _LTC_BITS			; j=
	ldi r30,_LTC_DETECTED			; k=	

.ifdef __SEND_CONST_TC__
	ldi temp1, 0x12
	st Z+, temp1
	ldi temp1, 0x34
	st Z+, temp1
	ldi temp1, 0x56
	st Z+, temp1
	ldi temp1, 0x78
	st Z+, temp1
.else
	; frames
	ld temp1, X+
	ld temp2, Y+
	inc r26
	inc r28
	and temp1, BITMASK_F
	and temp2, BITMASK_3
	swap temp2
	or temp1, temp2
	st Z+, temp1
	; seconds
	ld temp1, X+
	ld temp2, Y+
	inc r26
	inc r28
	and temp1, BITMASK_F
	and temp2, BITMASK_7
	swap temp2
	or temp1, temp2
	st Z+, temp1
	; minutes
	ld temp1, X+
	ld temp2, Y+
	inc r26
	inc r28
	and temp1, BITMASK_F
	and temp2, BITMASK_7
	swap temp2
	or temp1, temp2
	st Z+, temp1
	; hours
	ld temp1, X+
	ld temp2, Y+
	inc r26
	inc r28
	and temp1, BITMASK_F
	and temp2, BITMASK_3
	swap temp2
	or temp1, temp2
	st Z+, temp1
.endif						; __SEND_CONST_TC__

.ifdef __DEBUG_TC_FOUND_BIT__
	; rise debug bit
	sbi PORTC, DEBUG_TC_FOUND_BIT
.endif
	rjmp __fin_check_bytes

__signature_not_found:
.ifdef __DEBUG_TC_FOUND_BIT__
	; clear debug bit
	cbi PORTC, DEBUG_TC_FOUND_BIT
.endif
__fin_check_bytes:
	ret