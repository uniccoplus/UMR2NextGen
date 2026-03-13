; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; boot.asm
;
; Board initialization
;
; [PIC16F18877] 変更点一覧:
;	1. list/include: 16F1939 → 16F18877
;	2. 発振器設定:
;		旧: banksel OSCCON / movlw B'11110000' / movwf OSCCON
;		新: OSCCON1でHFINTOSC選択 + OSCFRQで32MHz指定 + OSCCON3安定待ち
;	3. Timer0設定:
;		旧: OPTION_REGの下位3bitで分周比設定
;		新: T0CON1(クロック源+分周比) + T0CON0(有効化+ポストスケーラ)で設定
;		OPTION_REGはプルアップ無効のみに使用
;	4. USART:
;		旧: SPBRGL / TXSTA / RCSTA
;		新: SP1BRGL / TX1STA / RC1STA
;	5. 受信割込み許可:
;		旧: banksel PIE1 / bsf PIE1,RCIE
;		新: banksel PIE3 / bsf PIE3,RC1IE

		list p=16F18877			 ; [PIC16F18877]
		#include <p16f18877.inc>	; [PIC16F18877]
		#include <umr2.inc>

	EXTERN	start_normal_vector
	EXTERN	start_learn_vector
	EXTERN	isr_normal_vector
	EXTERN	isr_learn_vector
	EXTERN	isr_fupdate
	EXTERN	compute_checksum

; =================================
;
; vectors
;
; =================================

reset_code code	 0x0000
		goto	go_boot

isr_code code		0x0004
		clrf	PCLATH
		btfsc	STATE_FLAGS,0
		goto	isr_select
		pagesel isr_normal_vector
		goto	isr_normal_vector
isr_select
		btfss	STATE_FLAGS,2
		goto	isr_fupdate
		pagesel isr_learn_vector
		goto	isr_learn_vector

boot_code	code	0x0700

go_boot

; =================================
;
; boot
;
; =================================

; [PIC16F18877] OPTION_REG: プルアップ無効のみ設定
; 旧: movlw B'10000111' でTimer0分周比も設定していたが
; PIC16F18877ではTimer0設定はT0CON0/T0CON1で行う
		banksel OPTION_REG
		movlw	B'10000000'		 ; [PIC16F18877] bit7=WPUEN(1=プルアップ無効)のみ
		movwf	OPTION_REG

; [PIC16F18877] Timer0設定 (OPTION_REGから分離)
; T0CON1: T0CS=010(FOSC/4=8MHz), T0ASYNC=0, T0CKPS=0111(1:128)
; T0CON0: T0EN=1(有効), T016BIT=0(8bitモード), T0OUTPS=0001(1:2ポストスケーラ)
; 実効分周: 128 × 2 = 256
; タイマ周期: 256 × 256 / 8MHz ≒ 8.19ms
; COUNTER_T0_MAX=0x1Fで約254msのLED点滅周期
		banksel T0CON1
		movlw	B'01000111'		 ; [PIC16F18877] T0CS=010, T0ASYNC=0, T0CKPS=0111
		movwf	T0CON1
		movlw	B'10000001'		 ; [PIC16F18877] T0EN=1, 8bitモード, T0OUTPS=0001
		movwf	T0CON0

; 出力ポート初期化
		clrf	BSR
		clrf	PORTA
		clrf	PORTB
		movlw	B'11001100'		 ; LEDオフ(PORTC bit2=ACT, bit3=STBY)
		movwf	PORTC
		clrf	PORTD
		clrf	PORTE

; アナログ入力無効化 (全ポートデジタルI/O)
		banksel ANSELA
		clrf	ANSELA
		clrf	ANSELB
		clrf	ANSELD
		clrf	ANSELE

; [PIC16F18877] 内部発振器 32MHz 設定
; 旧: banksel OSCCON / movlw B'11110000' / movwf OSCCON
; 新: OSCCON1でクロック源選択 + OSCFRQで周波数設定
		banksel OSCCON1
		movlw	B'01100000'		 ; [PIC16F18877] NOSC=110(HFINTOSC), NDIV=0000(分周なし)
		movwf	OSCCON1
		banksel OSCFRQ
		movlw	B'00000110'		 ; [PIC16F18877] HFFRQ=0110 → 32MHz
		movwf	OSCFRQ

; [PIC16F18877] 発振器安定待ち
; OSCCON3のORDYビットが1=クロック準備完了
		banksel OSCCON3
osc_wait
		btfss	OSCCON3,ORDY		; [PIC16F18877] 発振器レディ待ち (元にはなかった処理)
		goto	osc_wait

; ポート方向設定 (元と同一)
		banksel TRISA
		movlw	B'01111111'
		movwf	TRISA
		movlw	B'11111111'
		movwf	TRISB
		movlw	B'11100000'
		movwf	TRISC
		movlw	B'11111111'
		movwf	TRISD
		movlw	B'11111000'
		movwf	TRISE

; =================================
; USART設定 (31250 baud = MIDI)
; ボーレート: 32MHz / (16 × (63+1)) = 31250 baud (元と同一計算)
; =================================

; [PIC16F18877] レジスタ名変更
; SPBRGL → SP1BRGL, TXSTA → TX1STA, RCSTA → RC1STA
		banksel SP1BRGL			 ; [PIC16F18877]
		movlw	D'63'				; BRG値=63 (31250baud @ 32MHz, BRGH=1)
		movwf	SP1BRGL			 ; [PIC16F18877] SPBRGL → SP1BRGL
		movlw	B'00100110'		 ; TXEN=1, BRGH=1, SYNC=0(非同期)
		movwf	TX1STA				; [PIC16F18877] TXSTA → TX1STA
		movlw	B'10010000'		 ; SPEN=1, CREN=1
		movwf	RC1STA				; [PIC16F18877] RCSTA → RC1STA

; [PIC16F18877] 受信割込み許可
; 旧: banksel PIE1 / bsf PIE1,RCIE
; 新: banksel PIE3 / bsf PIE3,RC1IE (EUSARTがPIE3に移動)
		banksel PIE3				; [PIC16F18877]
		bsf	 PIE3,RC1IE			; [PIC16F18877] PIE1,RCIE → PIE3,RC1IE

; 状態フラグ初期化
		clrf	BSR
		clrf	STATE_FLAGS

; PRGMボタン確認 (PORTA,5 = PRGM0入力)
		btfss	PORTA,5
		goto	fupdate_wait

; ファームウェアチェックサム検証後、通常動作へ
		call	compute_checksum
		pagesel start_normal_vector
		goto	start_normal_vector

fupdate_wait
; ファームウェア更新待機: LED表示
		movlw	B'11000100'
		movwf	PORTC
; ファームウェア更新モードフラグセット
		bsf	 STATE_FLAGS,0
; MIDI受信割込み有効化 (GIE + PEIE)
		movlw	B'11000000'
		movwf	INTCON
; PRGMボタンが離されるまでループ待機
		btfss	PORTA,5
		goto	$-1
; ボタン離し → ラーンモードへ
		bcf	 INTCON,GIE
		nop
		nop
		bsf	 STATE_FLAGS,2
		call	compute_checksum
		pagesel start_learn_vector
		goto	start_learn_vector

		end

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

		end

