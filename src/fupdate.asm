; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; fupdate.asm
;
; bootloader / firmware update over MIDI
;
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. 受信割込みフラグ: PIR1,RCIF → PIR3,RC1IF
;	3. 受信レジスタ: RCREG → RC1REG
;	4. NVMレジスタ全面変更 (checksum.asmと同様)
;	5. ★重要★ プログラムFlash/EEPROM選択論理反転:
;		bcf NVMCON1,NVMREGS = プログラムFlash
;		bsf NVMCON1,NVMREGS = データEEPROM
;	6. 送受信バッファクリア時: PIR1,RCIF→PIR3,RC1IF, RCSTA→RC1STA
;
; ============================================================
; MIDIファームウェアアップデート SysExプロトコル仕様
; ============================================================
;
; 【起動方法】
;	電源OFF → PRGM0ボタン(PORTA,5)を押しながら電源ON
;	→ PRGMボタンを押したまま: ファームウェア更新モード待機
;	→ PRGMボタンを離す: ラーンモードへ移行
;
; 【SysExメッセージ全体構造】
;	F0	[ヘッダ4byte]	[フィラー/チャンク×N]	F7
;
; 【ヘッダ (F0の直後、4 bytes)】
;	00	マニュファクチャID byte1
;	01	マニュファクチャID byte2
;	5D	マニュファクチャID byte3
;	07	プロダクトID
;	※ヘッダ不一致 → エラー(LED点滅)
;
; 【フィラーバイト】
;	00	無視される。チャンク間の区切りに使用可。
;
; 【チャンク種別マーカー(ヘッダ確認後)】
;	7E	コードチャンク開始
;	7F	チェックサムチャンク開始
;
; ============================================================
; コードチャンク形式 (7E の直後)
; ============================================================
; 1チャンク = プログラムFlash 32word(64byte)ブロック
; アドレスは32word境界にアライメントすること
;
; ---- アドレス部 (4 bytes) ----
;	addr_lo	= address[6:0]			(7bit, MSB=0)
;	chk_lo	= (~addr_lo) & 0x7F	 チェックバイト
;	addr_hi	= address[13:7]		 (7bit, MSB=0)
;	chk_hi	= (~addr_hi) & 0x7F	 チェックバイト
;
;	実アドレス復元:
;	 real_addr[6:0]	= addr_lo
;	 real_addr[13:7] = addr_hi
;
;	チェック式: data_byte + 0x80 + check_byte + 1 = 0 (mod 256)
;
; ---- オペコード部 (32word × 4bytes = 128 bytes) ----
;	各14bitオペコードを4byteMIDIデータで送信:
;	 Byte A: munged_lo & 0x7F	 (難読化済みオペコード下位)
;	 Byte B: (~Byte_A) & 0x7F	チェックバイト
;	 Byte C: munged_hi & 0x7F	(難読化済みオペコード上位)
;	 Byte D: (~Byte_C) & 0x7F	チェックバイト
;
; ---- オペコード難読化(Munging)仕様 ----
; オペコードカウンタ(0-3のサイクル, TEMP_3 bits[1:0])で変化:
;
;	ビット操作命令判定: op_hi bits[5:4] == 01 の場合
;	(かつ op_hi != 0x00, op_hi != 0x01 の例外あり)
;	op_hi XOR値:
;	 カウンタ=0: XOR 0x09
;	 カウンタ=1: XOR 0x02
;	 カウンタ=2: XOR 0x0E
;	 カウンタ=3: XOR 0x05
;
;	op_lo XOR値 (全命令共通):
;	 カウンタ=0: XOR 0x1B
;	 カウンタ=1: XOR 0x21
;	 カウンタ=2: XOR 0x07
;	 カウンタ=3: XOR 0x32
;
;	例外1: op_hi == 0x00	→ op_hiへのXOR不要
;	例外2: op_hi == 0x01 かつ op_lo == 0x00 (CLRW命令) → op_hiへのXOR不要
;
; ============================================================
; チェックサムチャンク形式 (7F の直後)
; ============================================================
; 全コードチャンク送信後に1回だけ送信する
; 16bitチェックサム = 0x0000-0x1FFFの全opcodeバイトの和
;
; 16bitチェックサムの7bitMIDIエンコード (3バイト×2 = 6bytes):
;	sum_lo	= checksum[6:0]			bits 6-0
;	sum_mid = checksum[13:7]		 bits 13-7
;	sum_hi	= checksum[15:14]		bits 1-0のみ有効
;
;	Byte 1: sum_lo					(7bit)
;	Byte 2: (~sum_lo) & 0x7F		 チェック
;	Byte 3: sum_mid					(7bit)
;	Byte 4: (~sum_mid) & 0x7F		チェック
;	Byte 5: sum_hi					(7bit, bit1:0のみ有効)
;	Byte 6: (~sum_hi) & 0x7F		 チェック
;	Byte 7: version					(7bit, ファームウェアバージョン番号)
;	Byte 8: (~version) & 0x7F		チェック
;
; チェックサムチャンク受信完了後:
;	→ チェックサム + バージョンをデータEEPROMに書き込み
;	→ LED消灯して電源サイクル待ち(無限ループ)
;
; ============================================================
; 完全なメッセージ例
; ============================================================
;	F0 00 01 5D 07			SysExヘッダ
;	7E						コードチャンク開始
;	AL AC AH AHC			アドレス(低/チェック/高/チェック)
;	[OL OC OH OHC] × 32	オペコード×32 (各4byte)
;	00						フィラー(省略可)
;	7E						次のコードチャンク
;	...					 (全ブロック分繰り返し)
;	7F						チェックサムチャンク開始
;	SL SC SM SMC SH SHC V VC	チェックサム+バージョン(8byte)
;	F7						SysEx終了
;
; ============================================================
; エラー処理
; ============================================================
;	チェックバイト不一致 or ヘッダ不一致 → エラーモード(LED点滅)
;	電源サイクルで再試行可能
; ============================================================

		list p=16F18877			 ; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include <umr2.inc>
; =================================
;
; Firmware Update ISR
;
; =================================
isr_fupdate_code code 0x0100

; ==================================================================
;
; firmware update--all functionality in isr.
;
; ==================================================================

; STATE_FLAGS alternative bits
; 0 - Sysex has begun and we're listening
; 1 - Sysex Header is Valid
; 2 - 
; 3 - Firmware Update Mode (isr selector)
; 4 - Current chunk is checksum
; 5 - Current chunk is code
; 6 - 
; 7 - 

		GLOBAL	isr_fupdate
isr_fupdate
; new context
		clrf	STATUS
		clrf	BSR
;		clrf	PCLATH
; check for RX interrupt
; 旧: btfsc PIR1,RCIF
; 新: btfsc PIR3,RC1IF (EUSARTがPIR1からPIR3へ移動)
		btfsc	PIR3,RC1IF			; [PIC16F18877] PIR1,RCIF → PIR3,RC1IF
		goto	fupdate_handle_rx

; no other interrupts should be on!
		goto	fupdate_sysex_error


fupdate_handle_rx
; Grab the RX byte
; 旧: banksel RCREG / movfw RCREG
; 新: banksel RC1REG / movfw RC1REG
		banksel RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877] RCREG → RC1REG
		movwf	TEMP
		clrf	BSR

;		retfie

; is SysEx begin(0xF0)?
		movlw	0xF0
		subwf	TEMP,w
		bz		fupdate_sysex_begin

; is SysEx end (0xF7)?
		movlw	0xF7
		subwf	TEMP,w
		bz		fupdate_sysex_end

; real time status (0xF8-0xFF ignored)?
		movfw	TEMP
		andlw	B'11111000'
		sublw	B'11111000'
		bz		fupdate_isr_finish

; some other status?
		btfsc	TEMP,7
		goto	fupdate_sysex_error

; are we still checking?
		btfss	STATE_FLAGS,0
		goto	fupdate_isr_finish

; is the header complete?
		btfsc	STATE_FLAGS,1
		goto	fupdate_get_data

; check header for validity
fupdate_check
		incf	BYTE_COUNT,f
		movfw	BYTE_COUNT
		movwf	TEMP_2

fupdate_check_1
		decfsz	TEMP_2,f
		goto	fupdate_check_2
		movlw	0x00				; Byte1: マニュファクチャID 0x00
		subwf	TEMP,w
		bnz		fupdate_sysex_error
		goto	fupdate_isr_finish
		
fupdate_check_2
		decfsz	TEMP_2,f
		goto	fupdate_check_3
		movlw	0x01				; Byte2: マニュファクチャID 0x01
		subwf	TEMP,w
		bnz		fupdate_sysex_error
		goto	fupdate_isr_finish
		
fupdate_check_3
		decfsz	TEMP_2,f
		goto	fupdate_check_4
		movlw	0x5D				; Byte3: マニュファクチャID 0x5D
		subwf	TEMP,w
		bnz		fupdate_sysex_error
		goto	fupdate_isr_finish
		
fupdate_check_4
		decfsz	TEMP_2,f
		goto	fupdate_sysex_error
		movlw	0x07				; Byte4: プロダクトID 0x07
		subwf	TEMP,w
		bnz		fupdate_sysex_error
; header now relevant
		bsf		STATE_FLAGS,1		; ヘッダ確認済みセット
; reset bytecount
		clrf	BYTE_COUNT
		goto	fupdate_isr_finish

fupdate_sysex_begin
; new message
		clrf	BYTE_COUNT
; incomplete
		bsf		STATE_FLAGS,0		; 受信中フラグセット
; not yet relevant
		bcf		STATE_FLAGS,1		; ヘッダ未確認
		goto	fupdate_isr_finish

fupdate_get_data
; check for chunk start
		incf	BYTE_COUNT,f
		movfw	BYTE_COUNT
		movwf	TEMP_2

fupdate_get_1
		decfsz	TEMP_2,f
		goto	fupdate_get_chunk_body
		movlw	0x7E
		subwf	TEMP,w
		bz		fupdate_get_code_begin
		movlw	0x7F
		subwf	TEMP,w
		bz		fupdate_get_checksum_begin

		movfw	TEMP
		bnz		fupdate_sysex_error
; for zero byte, treat as filler and wait for a chunk start byte
		decf	BYTE_COUNT,f
		goto	fupdate_isr_finish

fupdate_get_chunk_body
		btfsc	STATE_FLAGS,5
		goto	fupdate_get_code_chunk
		btfsc	STATE_FLAGS,4
		goto	fupdate_get_checksum_chunk
		goto	fupdate_sysex_error

fupdate_get_code_begin
; set the code chunk flag
		bsf		STATE_FLAGS,5
; clear the code counter
		clrf	TEMP_3
		goto	fupdate_isr_finish

fupdate_get_checksum_begin
; set the checksum chunk flag
		bsf		STATE_FLAGS,4
		goto	fupdate_isr_finish

fupdate_get_checksum_chunk
fg_sum_1
		decfsz	TEMP_2,f
		goto	fg_sum_2
; checksum low data
		movfw	TEMP
		movwf	TEMP_4
		goto	fupdate_isr_finish
fg_sum_2
		decfsz	TEMP_2,f
		goto	fg_sum_3
; checksum low check
		movfw	TEMP_4
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
		goto	fupdate_isr_finish
fg_sum_3
		decfsz	TEMP_2,f
		goto	fg_sum_4
; checksum mid data
		movfw	TEMP
		movwf	TEMP_6
		goto	fupdate_isr_finish
fg_sum_4
		decfsz	TEMP_2,f
		goto	fg_sum_5
; checksum mid check
		movfw	TEMP_6
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
		goto	fupdate_isr_finish
fg_sum_5
		decfsz	TEMP_2,f
		goto	fg_sum_6
; checksum high data
		movfw	TEMP
		movwf	TEMP_7
		goto	fupdate_isr_finish
fg_sum_6
		decfsz	TEMP_2,f
		goto	fg_sum_7
; checksum high check
		movfw	TEMP_7
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
; move all 16 bits to TEMP_6,TEMP_4
		btfsc	TEMP_6,0
		bsf		TEMP_4,7
		btfsc	TEMP_7,0
		bsf		TEMP_6,7
		bcf		STATUS,C
		rrf		TEMP_6,f
		btfsc	TEMP_7,1
		bsf		TEMP_6,7
		goto	fupdate_isr_finish
fg_sum_7
		decfsz	TEMP_2,f
		goto	fg_sum_8
; version data
		movfw	TEMP
		movwf	TEMP_7
		goto	fupdate_isr_finish
fg_sum_8
		decfsz	TEMP_2,f
		goto	fupdate_sysex_error
; version check
		movfw	TEMP_7
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
; store the checksum & version to data EEPROM
; store to EEPROM
; turn off all interrupts
		bcf		INTCON,GIE
		btfsc	INTCON,GIE
		goto	$-2
; make sure any writes are complete
; [PIC16F18877] NVM書き込み完了待ち
		banksel NVMCON1			 ; [PIC16F18877]
		btfsc	NVMCON1,WR			; [PIC16F18877] EECON1,WR → NVMCON1,WR
		goto	$-1
; write version
		clrf	NVMADRH				; clear[PIC16F18877]
		movfw	TEMP_7
		movwf	NVMDATL			 ; [PIC16F18877] EEDATL → NVMDATL
		movlw	PROM_VERSION
		movwf	NVMADRL			 ; [PIC16F18877] EEADRL → NVMADRL
; [PIC16F18877] データEEPROM選択: bsf NVMCON1,NVMREGS (1=EEPROM)
; 旧: bcf EECON1,EEPGD ← ★論理反転
		bsf	 NVMCON1,NVMREGS	 ; [PIC16F18877] ★論理反転
		bsf	 NVMCON1,WREN		; [PIC16F18877] EECON1,WREN → NVMCON1,WREN
		movlw	0x55
		movwf	NVMCON2			 ; [PIC16F18877] EECON2 → NVMCON2
		movlw	0xAA
		movwf	NVMCON2			 ; [PIC16F18877]
		bsf	 NVMCON1,WR			; [PIC16F18877]
; make sure any writes are complete
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; write high byte
		movfw	TEMP_6
		movwf	NVMDATL			 ; [PIC16F18877]
		incf	NVMADRL,f			; [PIC16F18877]
		bsf	 NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2			 ; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2			 ; [PIC16F18877]
		bsf	 NVMCON1,WR			; [PIC16F18877]
; make sure any writes are complete
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; write low byte
		movfw	TEMP_4
		movwf	NVMDATL			 ; [PIC16F18877]
		incf	NVMADRL,f			; [PIC16F18877]
		bsf	 NVMCON1,NVMREGS	 ; [PIC16F18877]
		bsf	 NVMCON1,WREN		; [PIC16F18877]
		movlw	0x55
		movwf	NVMCON2			 ; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2			 ; [PIC16F18877]
		bsf	 NVMCON1,WR			; [PIC16F18877]
; make sure any writes are complete
		btfsc	NVMCON1,WR			; [PIC16F18877]
		goto	$-1
; shut off activity LED and wait for user to power cycle
		clrf	BSR
		movlw	B'11001100'
		movwf	PORTC
fupdate_wait_for_reset
		goto	fupdate_wait_for_reset

fupdate_get_code_chunk
fg_code_1
		decfsz	TEMP_2,f
		goto	fg_code_2
; address low data
		movfw	TEMP
		movwf	TEMP_6
		goto	fupdate_isr_finish

fg_code_2
		decfsz	TEMP_2,f
		goto	fg_code_3
; address low check
		movfw	TEMP_6
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
		goto	fupdate_isr_finish

fg_code_3
		decfsz	TEMP_2,f
		goto	fg_code_4
; address high data
		movfw	TEMP
		movwf	TEMP_7
		goto	fupdate_isr_finish

fg_code_4
		decfsz	TEMP_2,f
		goto	fg_code_5
; address high check
		movfw	TEMP_7
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
; change address from 7:7bit to 6:8bit
		btfsc	TEMP_7,0
		bsf		TEMP_6,7
		bcf		STATUS,C
		rrf		TEMP_7,f
		goto	fupdate_isr_finish

fg_code_5
		decfsz	TEMP_2,f
		goto	fg_code_6
; opcode low data
		movfw	TEMP
;		movwf	TEMP_4
		movwf	TEMP_5
		goto	fupdate_isr_finish

fg_code_6
		decfsz	TEMP_2,f
		goto	fg_code_7
; opcode low check
;		movfw	TEMP_4
		movfw	TEMP_5
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
		goto	fupdate_isr_finish

fg_code_7
		decfsz	TEMP_2,f
		goto	fg_code_8
; opcode high data
		movfw	TEMP
		movwf	TEMP_4
		goto	fupdate_isr_finish

fg_code_8
		decfsz	TEMP_2,f
		goto	fupdate_sysex_error
; opcdode high check
		movfw	TEMP_4
		addlw	B'10000000'
		addwf	TEMP,f
		incfsz	TEMP,f
		goto	fupdate_sysex_error
; ok--munged opcode is now TEMP_4(7) : TEMP_5 (7)
; change from 7:7bit to 6:8bit
		btfsc	TEMP_4,0
		bsf		TEMP_5,7
		bcf		STATUS,C
		rrf		TEMP_4,f
; ok--munged opcode is now in TEMP_4:TEMP_5
; de-munge the opcode
		movfw	TEMP_4
		bnz		demunge_check_clrw
; high byte is zero--
; no operations necessary.
		goto	fg_code_store		; op_hi == 0: 難読化なし

; clrw	(1 0000 0000)
demunge_check_clrw
		movfw	TEMP_4
		sublw	0x01
		bnz		demunge_bit_oriented
		movfw	TEMP_5
		bz		fg_code_store		; CLRW命令: 難読化なし

; de-munge the bit-oriented opcodes
; use the opcode counter to cycle modifications
demunge_bit_oriented
; bit oriented instructions are 01 iibb bfff ffff
; check for the 01
; ビット操作命令 (op_hi bits[5:4] == 01) の上位バイトXOR
		movfw	TEMP_4
		andlw	B'00110000'
		sublw	B'00010000'
		bnz		demunge_reg_lit

		btfsc	TEMP_3,1
		goto	demunge_bit_oriented_1x
demunge_bit_oriented_0x
		btfsc	TEMP_3,0
		goto	demunge_bit_oriented_01
demunge_bit_oriented_00
		movlw	B'00001001'
		xorwf	TEMP_4,f
		goto	demunge_reg_lit
demunge_bit_oriented_01
		movlw	B'00000010'
		xorwf	TEMP_4,f
		goto	demunge_reg_lit
demunge_bit_oriented_1x
		btfsc	TEMP_3,0
		goto	demunge_bit_oriented_11
demunge_bit_oriented_10
		movlw	B'00001110'
		xorwf	TEMP_4,f
		goto	demunge_reg_lit
demunge_bit_oriented_11
		movlw	B'00000101'
		xorwf	TEMP_4,f

; de-munge the registers & literals
; use the opcode counter to cycle modifications
demunge_reg_lit
		btfsc	TEMP_3,1
		goto	demunge_reg_lit_1x
demunge_reg_lit_0x
		btfsc	TEMP_3,0
		goto	demunge_reg_lit_01
demunge_reg_lit_00
		movlw	B'00011011'
		xorwf	TEMP_5,f
		goto	fg_code_store
demunge_reg_lit_01
		movlw	B'00100001'
		xorwf	TEMP_5,f
		goto	fg_code_store
demunge_reg_lit_1x
		btfsc	TEMP_3,0
		goto	demunge_reg_lit_11
demunge_reg_lit_10
		movlw	B'00000111'
		xorwf	TEMP_5,f
		goto	fg_code_store
demunge_reg_lit_11
		movlw	B'00110010'
		xorwf	TEMP_5,f


fg_code_store
; store opcode low byte in RAM buffer(FIRMWARE_BUFFER)
		clrf	FSR0H
		movlw	FIRMWARE_BUFFER
		movwf	FSR0L
		movfw	TEMP_3
		addwf	FSR0L,f
		addwf	FSR0L,f
		movfw	TEMP_5
		movwf	INDF0
; store opcode high byte in RAM buffer(FIRMWARE_BUFFER)
		incf	FSR0L,f
		movfw	TEMP_4
		movwf	INDF0
; increment the opcode counter
		incf	TEMP_3,f
; check for chunk completion
		movlw	D'32'
		subwf	TEMP_3,w
		bz	fg_code_chunk_complete
; prepare bytecount for next 4-byte opcode
		movlw	0x04
		subwf	BYTE_COUNT,f
		goto	fupdate_isr_finish

fg_code_chunk_complete
; write the code chunk to program EEPROM
; disable interrupts
		bcf		INTCON,GIE
		btfsc	INTCON,GIE
		goto	$-2

;		goto	fupdate_flush

;;;;
; erase EEPROM block before write
;;;;
		banksel NVMADRH			 ; [PIC16F18877]
		movfw	TEMP_7
		movwf	NVMADRH			 ; [PIC16F18877] EEADRH → NVMADRH
		movfw	TEMP_6
		movwf	NVMADRL			 ; [PIC16F18877] EEADRL → NVMADRL
; [PIC16F18877] プログラムFlash選択: bcf NVMCON1,NVMREGS (0=Flash)
; 旧: bsf EECON1,EEPGD ← ★論理反転
		bcf	 NVMCON1,NVMREGS	 ; [PIC16F18877] ★論理反転
		bsf	 NVMCON1,WREN		; [PIC16F18877]
		bsf	 NVMCON1,FREE		; [PIC16F18877] Flash行消去モード
		movlw	0x55
		movwf	NVMCON2			 ; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2			 ; [PIC16F18877]
		bsf	 NVMCON1,WR			; [PIC16F18877]
		nop
		nop
		bcf	 NVMCON1,FREE		; [PIC16F18877]
		bcf	 NVMCON1,WREN		; [PIC16F18877]
;;;;
; write code to EEPROM
;;;;
; FSR0L points to code buffer
		clrf	FSR0H
		movlw	FIRMWARE_BUFFER
		movwf	FSR0L
		movfw	TEMP_7
		movwf	NVMADRH			 ; [PIC16F18877]
		movfw	TEMP_6
		movwf	NVMADRL			 ; [PIC16F18877]
		bsf	 NVMCON1,WREN		; [PIC16F18877]
		movlw	D'32'
		movwf	TEMP
fg_code_write_loop
		moviw	INDF0++
		movwf	NVMDATL			 ; [PIC16F18877] EEDATL → NVMDATL
		moviw	INDF0++
		movwf	NVMDATH			 ; [PIC16F18877] EEDATH → NVMDATH
; clear LWLO only for last of groups of 8 words

; LWLO bit位置: EECON1 bit5 → NVMCON1 bit6 (named bitで自動解決)
		bsf	 NVMCON1,LWLO		; [PIC16F18877] ラッチ保持モード
		movf	NVMADRL,w			; [PIC16F18877]
		xorlw	0x07
		andlw	0x07
		btfsc	STATUS,Z
		bcf	 NVMCON1,LWLO		; [PIC16F18877] 8word目でFlash書き込みトリガ
		movlw	0x55
		movwf	NVMCON2			 ; [PIC16F18877]
		movlw	0xAA
		movwf	NVMCON2			 ; [PIC16F18877]
		bsf	 NVMCON1,WR			; [PIC16F18877]
		nop
		nop
		incf	NVMADRL,f			; [PIC16F18877] EEADR → NVMADRL
		decfsz	TEMP,f
		goto	fg_code_write_loop
		bcf	 NVMCON1,WREN		; [PIC16F18877]

fupdate_flush
; flush RX
; 旧: banksel RCREG / movfw RCREG / movfw RCREG
; 新: banksel RC1REG / movfw RC1REG / movfw RC1REG
		banksel RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877]
		movfw	RC1REG				; [PIC16F18877]
; [PIC16F18877] 受信割込みフラグクリア: PIR1,RCIF → PIR3,RC1IF (bit5→bit5)
		banksel PIR3				; [PIC16F18877]
		bcf	 PIR3,RC1IF			; [PIC16F18877] PIR1,RCIF → PIR3,RC1IF
; [PIC16F18877] 受信器リセット: RCSTA → RC1STA
		banksel RC1STA				; [PIC16F18877]
		bcf	 RC1STA,CREN		 ; [PIC16F18877] RCSTA → RC1STA
		bsf	 RC1STA,CREN		 ; [PIC16F18877]
		clrf	BSR
; re-enable interrupts
		bsf		INTCON,GIE
; clear the code chunk flag
		bcf		STATE_FLAGS,5
; reset the bytecount
		clrf	BYTE_COUNT
; wait for more chunks
		goto	fupdate_isr_finish


fupdate_sysex_end
; execution here is an error condition
; ignore other data
		bcf		STATE_FLAGS,1
		bcf		STATE_FLAGS,0
; clear LED
		clrf	BSR
; porta read-mod-write ok here
;		bsf		PORTA,0
		goto	$-1				 ; 無限ループ (エラー扱い)


fupdate_sysex_error
; ignore rest of message.
		bcf		STATE_FLAGS,1
		bcf		STATE_FLAGS,0
; blink the activity LED and do nothing.
		clrf	BSR
; blink off
fupdate_error_blink
		movlw	B'11001100'
		movwf	PORTC
		clrf	COUNTER_L
		clrf	COUNTER_H
		nop
		nop
		nop
		nop
		decfsz	COUNTER_L,f
		goto	$-5
		decfsz	COUNTER_H,f
		goto	$-7

; blink on
		movlw	B'11000100'
		movwf	PORTC
		clrf	COUNTER_L
		clrf	COUNTER_H
		nop
		nop
		nop
		nop
		decfsz	COUNTER_L,f
		goto	$-5
		decfsz	COUNTER_H,f
		goto	$-7
		goto	fupdate_error_blink

fupdate_isr_finish
		retfie

		end

