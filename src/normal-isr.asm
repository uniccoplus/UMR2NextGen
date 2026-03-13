; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; normal-isr.asm
;
; Interrupt service routines.
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. 受信割込みフラグ: PIR1,RCIF → PIR3,RC1IF
;	3. 受信レジスタ: RCREG → RC1REG
;	4. 送信レジスタ: TXREG → TX1REG
;	5. Timer0割込みフラグ:
;		旧: INTCON,TMR0IF (INTCONのbit2)
;		新: PIR0,TMR0IF	(PIR0のbit5)
;	6. Timer0割込み制御:
;		旧: BCF/BSF INTCON,TMR0IE (INTCONのbit5)
;		新: BCF/BSF PIE0,TMR0IE	(PIE0のbit5)

		list p=16F18877			 ; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include <umr2.inc>

; ==================================================================
; ==================================================================
;
; ISR
;
; ==================================================================
; ==================================================================

isr_normal_vector	code	0x0804
	GLOBAL	isr_normal_vector
isr_normal_vector
;	goto	isr_normal
;isr_normal	code
isr_normal
; New context
		clrf	BSR

; Check for serial receive
; [PIC16F18877] USART受信割込みチェック
; 旧: btfsc PIR1,RCIF
; 新: btfsc PIR3,RC1IF
		btfsc	PIR3,RC1IF			; [PIC16F18877] PIR1,RCIF → PIR3,RC1IF
		goto	handle_rx

; Check for timer0 expiry
; [PIC16F18877] Timer0割込みチェック
; 旧: btfsc INTCON,TMR0IF
; 新: btfsc PIR0,TMR0IF (Timer0フラグがPIR0へ移動)
		btfsc	PIR0,TMR0IF		 ; [PIC16F18877] INTCON,TMR0IF → PIR0,TMR0IF
		goto	handle_timer_0

		retfie

; =================================
;
; Handle Timer 0 expiry
;
; =================================

handle_timer_0
; [PIC16F18877] Timer0割込みをクリアし無効化
; 旧: bcf INTCON,TMR0IE / bcf INTCON,TMR0IF
; 新: bcf PIE0,TMR0IE / bcf PIR0,TMR0IF
		banksel PIE0
		bcf	 PIE0,TMR0IE		 ; [PIC16F18877] INTCON,TMR0IE → PIE0,TMR0IE
		banksel PIR0
		bcf	 PIR0,TMR0IF		 ; [PIC16F18877] INTCON,TMR0IF → PIR0,TMR0IF
		clrf	BSR
; Turn off blinked LED
		movlw	B'00001000'
		movwf	PORTC
		retfie

; =================================
;
; process incoming midi byte
;
; =================================

handle_rx
; Grab the incoming byte
; [PIC16F18877] 受信データ取得
; 旧: banksel RCREG / movfw RCREG / movwf TXREG
; 新: banksel RC1REG / movfw RC1REG / movwf TX1REG
		banksel RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877] RCREG → RC1REG
		movwf	TX1REG				; [PIC16F18877] TXREG → TX1REG (MIDIスルー)
		movwf	TEMP_ISR
		clrf	BSR

; If byte is a data byte, process it(MSB=0なら2バイト目以降)
		btfss	TEMP_ISR,7
		goto	process_data_byte

process_status_byte
; Don't let real time messages interrupt running status - check for them now
; real time message is status B'11111xxx'(0xF8-0xFF)
		comf	TEMP_ISR,w
		andlw	B'11111000'
		btfsc	STATUS,Z
		retfie
; check for note-off (0x8?)
		movfw	NOTE_OFF_STATUS
		subwf	TEMP_ISR,f
		bz	flag_note_off
; Check for note-on (0x9?)
		movlw	0x10
		subwf	TEMP_ISR,f
		bz	flag_note_on
; All other status bytes and subsequent data are ignored.
ignore_message
; Data will be ignored for other status bytes.
		clrf	MESSAGE_TYPE
		retfie

flag_note_on
		movlw	NOTE_ON
		movwf	MESSAGE_TYPE
; reset byte count
		bcf	STATE_FLAGS,1
		retfie
flag_note_off
		movlw	NOTE_OFF
		movwf	MESSAGE_TYPE
; reset byte count
		bcf	STATE_FLAGS,1
		retfie


process_data_byte
; always store the first data byte
		btfss	STATE_FLAGS,1
		goto	store_d0

; second data byte. reset byte count and check for relevant status
		bcf	STATE_FLAGS,1
; ignore data for message other than note off/on
		btfsc	MESSAGE_TYPE,0
		goto	process_note_off
		btfsc	MESSAGE_TYPE,1
		goto	process_note_on
		retfie

store_d0
; subtract first note from D0 to get internal note number.
; wrap at 128.
		movfw	FIRST_NOTE
		subwf	TEMP_ISR,w
		andlw	B'01111111'
		movwf	INBOUND_D0
		bsf	STATE_FLAGS,1
; blink activity LED
		clrf	PORTC
		clrf	TMR0
; [PIC16F18877] Timer0フラグクリア&割込み有効
; 旧: bcf INTCON,TMR0IF / bsf INTCON,TMR0IE
; 新: bcf PIR0,TMR0IF / bsf PIE0,TMR0IE
		banksel PIR0
		bcf	 PIR0,TMR0IF		 ; [PIC16F18877] INTCON,TMR0IF → PIR0,TMR0IF
		banksel PIE0
		bsf	 PIE0,TMR0IE		 ; [PIC16F18877] INTCON,TMR0IE → PIE0,TMR0IE
		retfie

; =================================
;
; handle Note Off message
;
; =================================

process_note_off
; clear the key bit for this note number.
		movfw	INBOUND_D0
		movwf	FSR0L
		movlw	0xBD
		movwf	FSR0H
; 3-byte record for each note number:
; - lo indirect address for keybits byte
		movfw	INDF0
		movwf	FSR1L
; - hi indirect address for keybits byte
		incf	FSR0H,f
		movfw	INDF0
		movwf	FSR1H
; - bitmask to apply to keybits byte
		incf	FSR0H,f
		comf	INDF0,w
		andwf	INDF1,f			 ; キービットクリア
; blink the activity LED
;		clrf	PORTC
;		clrf	TMR0
;		bcf	INTCON,TMR0IF
;		bsf	INTCON,TMR0IE
		retfie

; =================================
;
; handle Note On message
;
; =================================

process_note_on
; Check for zero velocity (note off)
		movf	TEMP_ISR,f
		bz	process_note_off

; set the key bit for this note number.
		movfw	INBOUND_D0
		movwf	FSR0L
		movlw	0xBD
		movwf	FSR0H
; 3-byte record for each note number:
; - lo indirect address for keybits byte
		movfw	INDF0
		movwf	FSR1L
; - hi indirect address for keybits byte
		incf	FSR0H,f
		movfw	INDF0
		movwf	FSR1H
; - bitmask to apply to keybits byte
		incf	FSR0H,f
		movfw	INDF0
		iorwf	INDF1,f			 ; キービットセット
; blink the activity LED
;		clrf	PORTC
;		clrf	TMR0
;		bcf	INTCON,TMR0IF
;		bsf	INTCON,TMR0IE
		retfie

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

		end

