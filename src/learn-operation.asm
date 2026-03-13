; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; learn-operation.asm
;
; Main program loop for "learning" host keyboard configuration
;
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. Timer0割込み有効化:
;		旧: movlw B'11100000' / movwf INTCON (GIE+PEIE+TMR0IE)
;		新: movlw B'11000000' / movwf INTCON (GIE+PEIE)
;			+ banksel PIE0 / bsf PIE0,TMR0IE (Timer0IEをPIE0で設定)
;	3. 受信割込み: PIE1,RCIE → PIE3,RC1IE
;	4. NVMレジスタ全面変更 (checksum.asmと同様)
;	5. ★重要★ EEPROM選択論理反転:
;		bsf NVMCON1,NVMREGS = データEEPROM
;		bcf NVMCON1,NVMREGS = プログラムFlash
;	6. RCSTA → RC1STA, RCREG → RC1REG
;	7. 送信: PIR1,TXIF → PIR3,TX1IF, TXREG → TX1REG

		list p=16F18877				; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include	<umr2.inc>

; =================================
;
; Learn Mode Operation
;
; =================================

start_learn_vector code			0x1000
	GLOBAL	start_learn_vector
start_learn_vector
	goto	start_learn
start_learn	code			0x1400
start_learn

; =================================
;
; Configuration Report
; Send config data via sysex.	Useful for debugging & customer support.
;
; =================================

		call	send_sysex_config
; store setup count for later increment
		movfw	TEMP_4
		movwf	SETUP_COUNT

; =================================
;
; Variable Init
;
; =================================

; =================================
;
; LED Init
;
; =================================

; turn off both LEDs.
		movlw	B'00001100'
		movwf	PORTC
; enable Timer 0 so that STBY LED blinks.
; Enable Interrupts so the first note can be recorded.
; [PIC16F18877] Timer0割込み有効化 + GIE/PEIE設定
; 旧: movlw B'11100000' / movwf INTCON	(GIE+PEIE+TMR0IE一括)
; 新: INTCONにGIE+PEIEのみ設定し、TMR0IEはPIE0で個別に設定
		movlw	COUNTER_T0_MAX
		movwf	COUNTER_T0
		movlw	B'11000000'			; [PIC16F18877] GIE+PEIE (TMR0IEはPIE0へ)
		movwf	INTCON
		banksel PIE0
		bsf		PIE0,TMR0IE			; [PIC16F18877] Timer0割込み有効(INTCON→PIE0)
		clrf	BSR

; flush out any rx errors
		call	flush_rx_learn

; =================================
;
; Wait for first note
;
; =================================

wait_for_first_note
		btfss	STATE_FLAGS,3
		goto	wait_for_first_note
; disable MIDI receive
; [PIC16F18877] 受信割込み無効化: PIE1,RCIE → PIE3,RC1IE
		banksel PIE3				; [PIC16F18877]
		bcf		PIE3,RC1IE			; [PIC16F18877] PIE1,RCIE → PIE3,RC1IE
		clrf	BSR
; disable interrupts
		bcf	INTCON,GIE
; set the activity LED, clear the STBY LED
		movlw	B'00000100'
		movwf	PORTC
; store the MIDI channel number in data EEPROM
		movlw	0x0F
		andwf	NOTE_ON_STATUS,w
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877] EECON1,WR → NVMCON1,WR
		goto	$-1
; write channel
		movwf	NVMDATL				; [PIC16F18877] EEDATL → NVMDATL
		movlw	PROM_CHANNEL
		movwf	NVMADRL				; [PIC16F18877] EEADRL → NVMADRL
; [PIC16F18877] データEEPROM選択: bsf NVMCON1,NVMREGS ← ★論理反転
		bsf		NVMCON1,NVMREGS		; [PIC16F18877] ★論理反転: bcf EEPGD → bsf NVMREGS
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877] EECON2 → NVMCON2
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]

; store the first note number in data EEPROM
		clrf	BSR
		movfw	FIRST_NOTE
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; write first note
		movwf	NVMDATL				; [PIC16F18877]
		movlw	PROM_FIRST_NOTE
		movwf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN			; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; make sure write is complete
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
		clrf	BSR

; =================================
;
; Record the default data states for each select line
;
; =================================
; init default key bits and select flags
		clrf	SELECT_FLAGS	
		clrf	SELECT_FLAGS+D'1'
		clrf	SELECT_FLAGS+D'2'
		clrf	SELECT_FLAGS+D'3'
		clrf	SELECT_FLAGS+D'4'
		clrf	SELECT_FLAGS+D'5'
		clrf	SELECT_FLAGS+D'6'
		clrf	SELECT_FLAGS+D'7'
		clrf	SELECT_FLAGS+D'8'
		clrf	KEY_BITS
		clrf	KEY_BITS+D'1'
		clrf	KEY_BITS+D'2'
		clrf	KEY_BITS+D'3'
		clrf	KEY_BITS+D'4'
		clrf	KEY_BITS+D'5'
		clrf	KEY_BITS+D'6'
		clrf	KEY_BITS+D'7'
		clrf	KEY_BITS+D'8'
; init the rx map
		clrf	FSR0L
rx_map_init_loop
		movlw	0x21
		movwf	FSR0H
		clrf	INDF0
		incf	FSR0H,f
		movlw	0x22
		movwf	INDF0
		incf	FSR0H,f
		clrf	INDF0
		incfsz	FSR0L,f
		goto	rx_map_init_loop
; init the tx map
		movlw	0x20
		movwf	FSR0H
		movlw	0x80
		movwf	FSR0L
tx_map_init_loop
		movlw	0xFF
		movwf	INDF0
		incfsz	FSR0L,f
		goto	tx_map_init_loop

; poll a fixed number of times
		clrf	COUNTER_L
		clrf	COUNTER_M
		movlw	0x08
		movwf	COUNTER_H

poll_default_keys
		decfsz	COUNTER_L,f
		goto	poll_default_keys_go
		decfsz	COUNTER_M,f
		goto	poll_default_keys_go
		decfsz	COUNTER_H,f
		goto	poll_default_keys_go
		goto	poll_default_keys_complete

poll_default_keys_go
; take a snapshot of select and data lines
		call	take_snapshot_learn
; is number of active select lines exactly 1?
		decfsz	TEMP_4,f	
		goto	poll_default_keys
; point to the data state register for this select line
		call	point_to_key_data_learn
; flag storage of this select state
		bsf	INDF0,0
; store the state.
		movlw	0x10
		addwf	FSR0L,f
		movfw	TEMP_3
		movwf	INDF0
		goto	poll_default_keys

poll_default_keys_complete
; clear activity LED
		movlw	B'00001100'
		movwf	PORTC
; start STBY LED blinking again
		movlw	COUNTER_T0_MAX
		movwf	COUNTER_T0
		bsf	INTCON,GIE

; =================================
;
; Monitor keystrokes.	For each, record select/data/note number
;
; =================================

; FSR1L is MIDI note number 0-127 for the next keystroke
;		movfw	FIRST_NOTE
;		movwf	FSR1L
; start notes at location 0.	First note will be used as an offset
; in runtime.
		clrf	FSR1L

poll_setup_keystrokes
; check for user signal that setup is complete
		btfss	PORTA,5
		goto	setup_write
; take a snapshot of select and data lines
		call	take_snapshot_learn
; is number of active select lines exactly 1?
		decfsz	TEMP_4,f	
		goto	poll_setup_keystrokes
; point to the data state register for this select line
		call	point_to_key_data_learn
; does this select have a default recorded?
		btfss	INDF0,0
		goto	poll_setup_keystrokes
; check the data state.
		movlw	0x10
		addwf	FSR0L,f
		movfw	TEMP_3
		xorwf	INDF0,w
; no change?	do nothing.
		bz	poll_setup_keystrokes
; data state has changed.	store select and data states for current note.
; put changed bit into TEMP_4
		movwf	TEMP_4
; rx map info.	3 bytes indexed by note number.
; select low
		movlw	0x21
		movwf	FSR1H
		movfw	TEMP
		movwf	INDF1
; select high.	add in base address for normal operation
		incf	FSR1H,f
		movfw	TEMP_2
		andlw	B'00000001'
		addlw	0x22
		movwf	INDF1
; data
		incf	FSR1H,f
		movfw	TEMP_4
		movwf	INDF1
; tx map info.	one byte indexed by select 1-12 x data 1-8
		movlw	0x20
		movwf	FSR0H
		movlw	0x80
		movwf	FSR0L
; point to correct block of 8.
point_to_tx_map_select
		btfsc	TEMP,0
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,1
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,2
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,3
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,4
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,5
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,6
		goto	point_to_tx_map_data
		movlw	D'8'
		addwf	FSR0L,f
		btfsc	TEMP,7
		goto	point_to_tx_map_data
; at this point, TEMP_2,0 is assumed to be set
		movlw	D'8'
		addwf	FSR0L,f
; point to correct byte.
point_to_tx_map_data
		btfsc	TEMP_4,0
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,1
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,2
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,3
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,4
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,5
		goto	store_tx_map_note
		incf	FSR0L,f
		btfsc	TEMP_4,6
		goto	store_tx_map_note
; at this point, TEMP_4,7 is assumed to be set.
		incf	FSR0L,f
store_tx_map_note
; move the current note number in FSR1L (not INDF1!) into tx map
		movfw	FSR1L
		movwf	INDF0
; advance to next note.	wrap at 128.
		incf	FSR1L,f
		movlw	B'01111111'
		andwf	FSR1L,f

; blink activity LED
		bcf	INTCON,GIE
		nop
		nop
		movlw	B'00000100'
		movwf	PORTC
		call	blink_delay_learn
		movlw	B'00001000'
		movwf	PORTC
		movlw	COUNTER_T0_MAX
		movwf	COUNTER_T0
		bsf	INTCON,GIE
		goto	poll_setup_keystrokes

setup_write
; don't need interrupts anymore.
		bcf	INTCON,GIE
; set the activity LED
		movlw	B'00000100'
		movwf	PORTC
; write tx map and rx map to program ROM
		movlw	0x20
		movwf	TEMP_5
		clrf	TEMP_4
		movlw	0x3C
		movwf	TEMP_7
		clrf	TEMP_6
setup_write_loop
; write 32 bytes at a time.
		call	write_32_learn
; next RAM block
		movlw	0x20
		addwf	TEMP_4,f
		btfsc	STATUS,C
		incf	TEMP_5,f
; next ROM block
		addwf	TEMP_6,f
		btfsc	STATUS,C
		incf	TEMP_7,f
; check for completion at PROM 0x4000
		btfss	TEMP_7,6
		goto	setup_write_loop

; write the note count
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; write the note count.	Limit to 7 bits.
		clrf	NVMADRH				; clear[PIC16F18877]
		movfw	FSR1L
		andlw	B'01111111'
		movwf	NVMDATL				; [PIC16F18877]
		movlw	PROM_NOTE_COUNT
		movwf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; write the setup completion flag
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; write setup count
; increment the previous value by one.	Limit to 7 bits.
		clrf	BSR
		incf	SETUP_COUNT,w
		andlw	B'01111111'
		banksel	NVMDATL				; [PIC16F18877]
		movwf	NVMDATL				; [PIC16F18877]
		movlw	PROM_SETUP_COUNT
		movwf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; make sure write is complete
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
		clrf	BSR

; Send config data via sysex.	Useful for debugging & customer support.
		call	send_sysex_config
; all done.	shut down.
; wait for a sec
		call	blink_delay_learn
		call	blink_delay_learn
; clear LEDs
		movlw	B'00001100'
		movwf	PORTC
		nop
		goto	$-1


; =================================
;
; delay to for slow LED blink
;
; =================================

blink_delay_learn
		movlw	0x04
		movwf	COUNTER_H
blink_loop_a_learn
		movlw	0xff
		movwf	COUNTER_M
blink_loop_b_learn
		movlw	0xff
		movwf	COUNTER_L
blink_loop_c_learn
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop
		nop

		decfsz	COUNTER_L,f
		goto	blink_loop_c_learn
		decfsz	COUNTER_M,f
		goto	blink_loop_b_learn
		decfsz	COUNTER_H,f
		goto	blink_loop_a_learn

		return

; =================================
;
; take a snapshot of select and data lines
; select in TEMP_2:TEMP
;	data in		TEMP_3
;
; =================================
take_snapshot_learn
; TEMP: Select 8-1
		movfw	PORTB
		movwf	TEMP
; TEMP_2: Select 9
		movfw	PORTA
		movwf	TEMP_2
; TEMP_3: Data 1-8
		movfw	PORTD
		movwf	TEMP_3
; resample a to make sure snapshot is stable
		movfw	PORTB
		subwf	TEMP,w
		btfss	STATUS,Z
		return
		movfw	PORTA
		subwf	TEMP_2,w
		btfss	STATUS,Z
		return
		movfw	PORTD
		subwf	TEMP_3,w
		btfss	STATUS,Z
		return
; check matrix polarity
		btfss	PORTC,5
		goto	count_active_select_learn
; negative polarity. complement everything.
		comf	TEMP,f
		comf	TEMP_2,f
		comf	TEMP_3,f
count_active_select_learn
; sample is only valid if the number of active select lines is 1
; store number of active select lines in TEMP_4
		clrf	TEMP_4
		btfsc	TEMP,0
		incf	TEMP_4,f
		btfsc	TEMP,1
		incf	TEMP_4,f
		btfsc	TEMP,2
		incf	TEMP_4,f
		btfsc	TEMP,3
		incf	TEMP_4,f
		btfsc	TEMP,4
		incf	TEMP_4,f
		btfsc	TEMP,5
		incf	TEMP_4,f
		btfsc	TEMP,6
		incf	TEMP_4,f
		btfsc	TEMP,7
		incf	TEMP_4,f
		btfsc	TEMP_2,0
		incf	TEMP_4,f

		return

; =================================
;
; Set up FSR0 to point to key state data
; FSR0L is select line number from 0-8.
;
; =================================
point_to_key_data_learn
		clrf	FSR0H
		movlw	SELECT_FLAGS
		movwf	FSR0L

		btfsc	TEMP,0
		return
		incf	FSR0L,f
		btfsc	TEMP,1
		return
		incf	FSR0L,f
		btfsc	TEMP,2
		return
		incf	FSR0L,f
		btfsc	TEMP,3
		return
		incf	FSR0L,f
		btfsc	TEMP,4
		return
		incf	FSR0L,f
		btfsc	TEMP,5
		return
		incf	FSR0L,f
		btfsc	TEMP,6
		return
		incf	FSR0L,f
		btfsc	TEMP,7
		return
; at this point, TEMP_2,0 is assumed to be set
		incf	FSR0L,f
		return

; =================================
;
; clear out the receive FIFO
;
; =================================
flush_rx_learn
; Flush the FIFO
; [PIC16F18877] RCREG → RC1REG, RCSTA → RC1STA
		banksel RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877]
; Flush out any bytes & errors sitting around
		banksel	RC1STA				; [PIC16F18877]
		bcf		RC1STA,CREN			; [PIC16F18877] RCSTA → RC1STA
		bsf		RC1STA,CREN			; [PIC16F18877]
		clrf	BSR

		return

; =================================
;
; write 32 bytes to program PROM
; from RAM: TEMP_5:TEMP_4
; to program ROM: TEMP_7:TEMP_6
;
; =================================
write_32_learn
		movfw	TEMP_5
		movwf	FSR0H
		movfw	TEMP_4
		movwf	FSR0L
; erase EEPROM block before write
; [PIC16F18877] Flashブロック消去
		banksel NVMADRH				; [PIC16F18877]
		movfw	TEMP_7
		movwf	NVMADRH				; [PIC16F18877]
		movfw	TEMP_6
		movwf	NVMADRL				; [PIC16F18877]
; [PIC16F18877] プログラムFlash選択: bcf NVMCON1,NVMREGS ← ★論理反転
		bcf		NVMCON1,NVMREGS		; [PIC16F18877] ★論理反転
		bsf		NVMCON1,WREN		; [PIC16F18877]
		bsf		NVMCON1,FREE		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
		nop
		nop
		bcf		NVMCON1,FREE		; [PIC16F18877]
		bcf		NVMCON1,WREN		; [PIC16F18877]
; write EEPROM block
; EEADRH:EEADRL points to program EEPROM
		movfw	TEMP_7
		movwf	NVMADRH				; [PIC16F18877]
		movfw	TEMP_6
		movwf	NVMADRL				; [PIC16F18877]
; EECON1 stuff
		bsf		NVMCON1,WREN		; [PIC16F18877]
; 32 words to write
		movlw	D'32'
		movwf	TEMP
write_buffer_learn_loop
; we're only using the low byte for storage.	clear the high byte.
		moviw	INDF0++
		movwf	NVMDATL				; [PIC16F18877]
		clrf	NVMDATH				; [PIC16F18877] 上位バイトは0
; clear LWLO only for last of groups of 8 words
; ---> EEADRL[2:0] = B'111'
		bsf		NVMCON1,LWLO		; [PIC16F18877]
		movf	NVMADRL,w			; [PIC16F18877]
		xorlw	0x07
		andlw	0x07
		btfsc	STATUS,Z
		bcf		NVMCON1,LWLO		; [PIC16F18877]
; trigger the write
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
		nop
		nop
; next word
		incf	NVMADRL,f			; [PIC16F18877]
		decfsz	TEMP,f
		goto	write_buffer_learn_loop
		bcf		NVMCON1,WREN		; [PIC16F18877]

		clrf	BSR

		return

; =================================
;
; fill 32 bytes to program PROM
; to program ROM: TEMP_6:TEMP_5
; fill data from TEMP_2
;
; =================================
fill_32_learn
; erase EEPROM block before write
		banksel	NVMADRH				; [PIC16F18877]
		movfw	TEMP_6
		movwf	NVMADRH				; [PIC16F18877]
		movfw	TEMP_5
		movwf	NVMADRL				; [PIC16F18877]
; [PIC16F18877] Flash選択 & 消去
		bcf		NVMCON1,NVMREGS		; [PIC16F18877] ★論理反転
		bsf		NVMCON1,WREN		; [PIC16F18877]
		bsf		NVMCON1,FREE		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
		nop
		nop
		bcf		NVMCON1,FREE		; [PIC16F18877]
		bcf		NVMCON1,WREN		; [PIC16F18877]
; write EEPROM block
; EEADRH:EEADRL points to program EEPROM
		movfw	TEMP_6
		movwf	NVMADRH				; [PIC16F18877]
		movfw	TEMP_5
		movwf	NVMADRL				; [PIC16F18877]
; EECON1 stuff
		bsf		NVMCON1,WREN		; [PIC16F18877]
; 16 words to write
		movlw	D'32'
		movwf	TEMP
fill_buffer_learn_loop
; we're only using the low byte for storage.	clear the high byte.
		movfw	TEMP_2
;		movfw	EEADRL
		movwf	NVMDATL				; [PIC16F18877]
		clrf	NVMDATH				; [PIC16F18877]
; clear LWLO only for last of groups of 8 words
; ---> EEADRL[2:0] = B'111'
		bsf		NVMCON1,LWLO		; [PIC16F18877]
		movf	NVMADRL,w			; [PIC16F18877]
		xorlw	0x07
		andlw	0x07
		btfsc	STATUS,Z
		bcf		NVMCON1,LWLO		; [PIC16F18877]
; trigger the write
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
		nop
		nop
; next word
		incf	NVMADRL,f			; [PIC16F18877]
		decfsz	TEMP,f
		goto	fill_buffer_learn_loop
		bcf		NVMCON1,WREN		; [PIC16F18877]

		clrf	BSR

		return

; =================================
;
; Send config info via sysex.
;
; =================================
send_sysex_config
; grab bytes from data prom
		banksel	NVMADRL				; [PIC16F18877]
		clrf	NVMADRH				; clear[PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877] データEEPROM選択
; version
		clrf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,RD			; [PIC16F18877]
		nop
		movfw	NVMDATL				; [PIC16F18877]
		movwf	TEMP
; channel
		movlw	PROM_CHANNEL
		movwf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,RD			; [PIC16F18877]
		nop
		movfw	NVMDATL				; [PIC16F18877]
		movwf	TEMP_2
; first note
		incf	NVMADRL,f			; [PIC16F18877]
		bsf		NVMCON1,RD			; [PIC16F18877]
		nop
		movfw	NVMDATL				; [PIC16F18877]
		movwf	TEMP_3
; note count
		incf	NVMADRL,f			; [PIC16F18877]
		bsf		NVMCON1,RD			; [PIC16F18877]
		nop
		movfw	NVMDATL				; [PIC16F18877]
		movwf	TEMP_5
; setup complete flag
		incf	NVMADRL,f			; [PIC16F18877]
		bsf		NVMCON1,RD			; [PIC16F18877]
		nop
		movfw	NVMDATL				; [PIC16F18877]
		movwf	TEMP_4
		clrf	BSR
; send sysex header
		movlw	0xF0
		call	transmit_byte_learn
		movlw	0x00
		call	transmit_byte_learn
		movlw	0x01
		call	transmit_byte_learn
		movlw	0x5D
		call	transmit_byte_learn
		movlw	0x07
		call	transmit_byte_learn
		movlw	0x00
		call	transmit_byte_learn
; firmware version
		movfw	TEMP
		call	transmit_byte_learn
; polarity jumper
		movlw	0x01
		btfss	PORTC,5
		clrw
		call	transmit_byte_learn
; setup count
		movfw	TEMP_4
		call	transmit_byte_learn
; channel
		movfw	TEMP_2
		call	transmit_byte_learn
; first note
		movfw	TEMP_3
		call	transmit_byte_learn
; note count
		movfw	TEMP_5
		call	transmit_byte_learn
; footer
		movlw	0xF7
		call	transmit_byte_learn

		return

; =================================
;
; Send a MIDI byte from W register.
; Wait to make sure USART is ready.
;
; =================================
transmit_byte_learn
		nop
		nop
; [PIC16F18877] 送信バッファ空き待ち: PIR1,TXIF → PIR3,TX1IF
		btfss	PIR3,TX1IF			; [PIC16F18877] PIR1,TXIF → PIR3,TX1IF
		goto	$-1
		banksel	TX1REG				; [PIC16F18877]
		movwf	TX1REG				; [PIC16F18877] TXREG → TX1REG
		clrf	BSR
		return

; =================================
;
; Reset to "factory" state
;
; =================================
wipe_config
; clear the program rom
; first, the tx map
		movlw	0xFF
		movwf	TEMP_2
		movlw	0x3C				; [PIC16F18877]
		movwf	TEMP_6
		clrf	TEMP_5
wipe_config_loop_a
		call	fill_32_learn
		movlw	0x20
		addwf	TEMP_5,f
		btfsc	STATUS,C
		incf	TEMP_6,f
; check for completion at PROM 0x3D00
		btfss	TEMP_6,0			; 0x3D(bit0=1)になったら終了[PIC16F18877]
		goto	wipe_config_loop_a
; second, the rx map
		clrf	TEMP_2				; bug 2026.3.13 uniccoplus
		movlw	0x3D
		movwf	TEMP_6
		clrf	TEMP_5
wipe_config_loop_b
		call	fill_32_learn
		movlw	0x20
		addwf	TEMP_5,f
		btfsc	STATUS,C
		incf	TEMP_6,f
; check for completion at PROM 0x4000
		btfss	TEMP_6,6
		goto	wipe_config_loop_b
; clear the data rom
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; wipe channel
		clrf	NVMADRH				; clear[PIC16F18877]
		clrf	NVMDATL				; [PIC16F18877]
		movlw	PROM_CHANNEL
		movwf	NVMADRL				; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; wipe first note
		incf	NVMADRL,f			; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; make sure EEPROM is ready to go
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; wipe setup complete flag
		incf	NVMADRL,f			; [PIC16F18877]
		bsf		NVMCON1,NVMREGS		; [PIC16F18877]
		bsf		NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2				; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2				; [PIC16F18877]
		bsf		NVMCON1,WR			; [PIC16F18877]
; make sure write is complete
		banksel	NVMCON1				; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
		clrf	BSR

		return


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

		end

