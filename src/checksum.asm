; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; checksum.asm
;
; Checksum the application firmware image.
;
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. NVMレジスタ全面変更:
;		EECON1	→ NVMCON1
;		EECON2	→ NVMCON2	(本ファイルでは未使用)
;		EEADRL	→ NVMADRL
;		EEADRH	→ NVMADRH
;		EEDATL	→ NVMDATL
;		EEDATH	→ NVMDATH
;	3. ★重要★ プログラムFlash/EEPROMの選択論理が反転:
;		旧: bsf EECON1,EEPGD	→ プログラムFlash選択
;		新: bcf NVMCON1,NVMREGS → プログラムFlash選択	← 論理反転
;		旧: bcf EECON1,EEPGD	→ データEEPROM選択
;		新: bsf NVMCON1,NVMREGS → データEEPROM選択	← 論理反転
;	4. NVMビット名は同名(WREN/WR/RD等)だがNVMCON1内の
;	 ビット位置が変わる。named bitを使用するため自動解決。


		list p=16F18877			 ; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include <umr2.inc>

checksum_code	code	0x740

; =================================
;
; Flush the RX buffer
;
; ================================

	GLOBAL	compute_checksum
compute_checksum

; プログラムFlash (0x0000-0x1FFF) のチェックサムを計算する
		clrf	TEMP
		clrf	TEMP_2
		banksel NVMADRL			 ; [PIC16F18877] EEADRL → NVMADRL
		clrf	NVMADRL			 ; [PIC16F18877] アドレス下位 = 0x0000
		clrf	NVMADRH			 ; [PIC16F18877] EEADRH → NVMADRH

; [PIC16F18877] プログラムFlash選択
; 旧: bsf EECON1,EEPGD	(1=プログラムFlash)
; 新: bcf NVMCON1,NVMREGS (0=プログラムFlash) ← ★論理反転
		bcf	 NVMCON1,NVMREGS	 ; [PIC16F18877] ★論理反転: bsf EEPGD → bcf NVMREGS

; add all opcodes from 0x0000 to 0x1FFF
checksum_loop
; [PIC16F18877] Flash読み出しトリガ
; 旧: bsf EECON1,RD
; 新: bsf NVMCON1,RD (ビット位置変更: bit0→bit1、named bitで自動解決)
		bsf	 NVMCON1,RD			; [PIC16F18877] EECON1,RD → NVMCON1,RD
		nop
		nop
		movfw	NVMDATL			 ; [PIC16F18877] EEDATL → NVMDATL (下位バイト加算)
		addwf	TEMP,f
		movfw	NVMDATH			 ; [PIC16F18877] EEDATH → NVMDATH (上位バイト加算)
		addwfc	TEMP_2,f
; increment program address
		incfsz	NVMADRL,f			; [PIC16F18877] EEADRL → NVMADRL
		goto	checksum_loop
		incf	NVMADRH,f			; [PIC16F18877] EEADRH → NVMADRH
		btfss	NVMADRH,5			; [PIC16F18877] bit5=1 → アドレス >= 0x2000 で終了
		goto	checksum_loop


; sum value is now in TEMP_2,TEMP
; EEPROMに保存されている補数値を読み出して合算する。

; [PIC16F18877] データEEPROM選択
; 旧: bcf EECON1,EEPGD	(0=データEEPROM)
; 新: bsf NVMCON1,NVMREGS (1=データEEPROM) ← ★論理反転
		movlw	PROM_CHECKSUM
		movwf	NVMADRL			 ; [PIC16F18877]
		bsf	 NVMCON1,NVMREGS	; [PIC16F18877] ★論理反転: bcf EEPGD → bsf NVMREGS
		bsf	 NVMCON1,RD		 ; [PIC16F18877] EEPROM読み出し
		nop						 ; [PIC16F18877] EEPROM読み出し待ち1サイクル
		movfw	NVMDATL			 ; [PIC16F18877]
		movwf	TEMP_4
		incf	NVMADRL,f			; [PIC16F18877]
		bsf	 NVMCON1,RD		 ; [PIC16F18877]
		nop
		movfw	NVMDATL			 ; [PIC16F18877]
		movwf	TEMP_3

; complement value is now in TEMP_4,TEMP_3チェックサム + 補数 + 1 = 0 を確認 (キャリービットで+1)
		bsf		STATUS,C
		movfw	TEMP_3
		addwfc	TEMP,f
		movfw	TEMP_4
		addwfc	TEMP_2,f

; check for zero(両バイトが0なら正常)
		movfw	TEMP_2
		bnz		checksum_error
		movfw	TEMP
		bnz		checksum_error

checksum_ok
; continue with init
		clrf	BSR
		return

checksum_error
; blink the activity LED and do nothing.
		clrf	BSR
; blink off
		movlw	B'00001100'
		movwf	PORTC
		clrf	COUNTER_L
		clrf	COUNTER_M
		movlw	0x08
		movwf	COUNTER_H
error_loop_a
		nop
		decfsz	COUNTER_L,f
		goto	error_loop_a
		decfsz	COUNTER_M,f
		goto	error_loop_a
		decfsz	COUNTER_H,f
		goto	error_loop_a

; blink on
		movlw	B'00000100'
		movwf	PORTC
		clrf	COUNTER_L
		clrf	COUNTER_M
		movlw	0x08
		movwf	COUNTER_H
error_loop_b
		nop
		decfsz	COUNTER_L,f
		goto	error_loop_b
		decfsz	COUNTER_M,f
		goto	error_loop_b
		decfsz	COUNTER_H,f
		goto	error_loop_b
		goto	checksum_error_blink

; should never execute here.
		return
		end
