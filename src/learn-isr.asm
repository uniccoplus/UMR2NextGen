; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; learn-isr.asm
;
; Interrupt service routines for "learning" about host key matrix
;
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. 受信割込みフラグ: PIR1,RCIF → PIR3,RC1IF
;	3. 受信レジスタ: RCREG → RC1REG
;	4. 受信割込み許可/禁止: PIE1,RCIE → PIE3,RC1IE
;	5. Timer0割込みフラグ:
;		旧: INTCON,TMR0IF (INTCONのbit2)
;		新: PIR0,TMR0IF	(PIR0のbit5)

		list p=16F18877			 ; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include	<umr2.inc>

; ==================================================================
; ==================================================================
;
; Learn-Mode ISR
;
; ==================================================================
; ==================================================================

isr_learn_vector	code	0x1004
	GLOBAL	isr_learn_vector
isr_learn_vector
;	goto	isr_learn
;isr_learn	code
isr_learn

; New context
		clrf	BSR

; Check for serial receive
; [PIC16F18877] USART受信割込みチェック
; 旧: btfsc PIR1,RCIF
; 新: btfsc PIR3,RC1IF
		btfsc	PIR3,RC1IF			; [PIC16F18877] PIR1,RCIF → PIR3,RC1IF
		goto	handle_rx_learn

; Check for timer0 expiry
; [PIC16F18877] Timer0割込みチェック
; 旧: btfsc INTCON,TMR0IF
; 新: btfsc PIR0,TMR0IF
		btfsc	PIR0,TMR0IF		 ; [PIC16F18877] INTCON,TMR0IF → PIR0,TMR0IF
		goto	handle_timer_0_learn

		retfie

; =================================
;
; process incoming midi byte
;
; =================================

handle_rx_learn

; Grab the incoming byte
; [PIC16F18877] 受信データ取得
		banksel RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877] RCREG → RC1REG
		movwf	TEMP_ISR
		banksel	PORTA
; Check if first note has been received yet.
		btfss	STATE_FLAGS,3
		goto	handle_rx_learn_process

; shut down the RX
; [PIC16F18877] 受信割込み無効化
; 旧: banksel PIE1 / bcf PIE1,RCIE
; 新: banksel PIE3 / bcf PIE3,RC1IE
		banksel PIE3				; [PIC16F18877]
		bcf	 PIE3,RC1IE			; [PIC16F18877] PIE1,RCIE → PIE3,RC1IE
		retfie

handle_rx_learn_process
; If byte is a data byte, process it
		btfss	TEMP_ISR,7
		goto	process_data_byte_learn

process_status_byte_learn
; Don't let real time messages interrupt running status - check for them now
; real time message is status B'11111xxx'
		comf	TEMP_ISR,w
		andlw	B'11111000'
		btfsc	STATUS,Z
		retfie
; Check for note-on (0x9?)
		movlw	B'11110000'
		andwf	TEMP_ISR,w
		sublw	0x90
		bz	flag_note_on_learn
; All other status bytes and subsequent data are ignored.
ignore_message_learn
; Data will be ignored for other status bytes.
		clrf	MESSAGE_TYPE
		retfie

flag_note_on_learn
		movlw	NOTE_ON
		movwf	MESSAGE_TYPE
; store note-on status.	We'll use channel later.
		movfw	TEMP_ISR
		movwf	NOTE_ON_STATUS
; reset byte count
		bcf	STATE_FLAGS,1
		retfie

process_data_byte_learn
; always store the first data byte
		btfss	STATE_FLAGS,1
		goto	store_d0_learn

; second data byte.	reset byte count and check for relevant status
		bcf	STATE_FLAGS,1
; ignore data for message other than note on
		btfsc	MESSAGE_TYPE,1
		goto	process_note_on_learn
		retfie

store_d0_learn
		movfw	TEMP_ISR
		movwf	INBOUND_D0
		bsf	STATE_FLAGS,1
		retfie

; =================================
;
; handle Note On message
;
; =================================

process_note_on_learn
; Check for zero velocity (note off)
		movf	TEMP_ISR,f
		btfsc	STATUS,Z
		retfie

; store the note number.
		movfw	INBOUND_D0
		movwf	FIRST_NOTE

; advance to next step in learn procedure
		bsf	STATE_FLAGS,3
		retfie

; =================================
;
; handle Timer 0 expiry
;
; =================================

handle_timer_0_learn
; blinking STBY LED stuff
; [PIC16F18877] Timer0フラグクリア
; 旧: bcf INTCON,TMR0IF
; 新: bcf PIR0,TMR0IF
		bcf	 PIR0,TMR0IF		 ; [PIC16F18877] INTCON,TMR0IF → PIR0,TMR0IF
		decfsz	COUNTER_T0,f
		retfie

		movlw	COUNTER_T0_MAX
		movwf	COUNTER_T0
		movlw	B'00000100'
		xorwf	PORTC,f
		retfie

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

		end

