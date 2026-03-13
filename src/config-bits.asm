; UMR2
; copyright John Staskevich, 2017
; john@codeandcopper.com
;
; This work is licensed under a Creative Commons Attribution 4.0 International License.
; http://creativecommons.org/licenses/by/4.0/
;
; config-bits.asm
; [CHANGED] PIC16F18877用コンフィグビット - 16F1939から完全書き直し
;
; 16F18877 コンフィグワード: 0x8007-0x800B (5ワード)
;
		list p=16F18877				; [CHANGED]
		#include	<p16f18877.inc>		; [CHANGED]
		#include	<umr2.inc>

; ---------------------------------------------------------------
; CONFIG1 @ 0x8007
;	FEXTOSC_OFF	: 外部発振器なし (内部HFINTOSCを使用)
;	RSTOSC_HFINTOSC_1MHz : 起動時1MHz、boot.asmで32MHzに切替
;	CLKOUTEN_OFF : CLKOUTピン無効
;	CSWEN_ON	 : クロック切替許可
;	FCMEN_ON	 : フェイルセーフクロックモニタ有効
; ---------------------------------------------------------------
		__CONFIG _CONFIG1, _FEXTOSC_OFF & _RSTOSC_HFINTOSC_1MHz & _CLKOUTEN_OFF & _CSWEN_ON & _FCMEN_ON

; ---------------------------------------------------------------
; CONFIG2 @ 0x8008
;	MCLRE_ON	 : MCLRピンをリセット入力として使用
;	PWRTE_OFF	: パワーアップタイマ無効
;	LPBOREN_OFF	: 低消費電力BOR無効
;	BOREN_OFF	: ブラウンアウトリセット無効
;	BORV_LO		: BOR電圧設定(無効時は不問)
;	ZCD_OFF		: ゼロクロス検出無効
;	PPS1WAY_ON	: PPSは初回設定後ロック
;	STVREN_ON	: スタックオーバーフロー/アンダーフローでリセット
; ---------------------------------------------------------------
		__CONFIG _CONFIG2, _MCLRE_ON & _PWRTE_OFF & _LPBOREN_OFF & _BOREN_OFF & _BORV_LO & _ZCD_OFF & _PPS1WAY_ON & _STVREN_ON

; ---------------------------------------------------------------
; CONFIG3 @ 0x8009
;	WDTCPS_WDTCPS_31 : WDT周期設定(WDT無効時は不問65536:1)
;	WDTE_OFF		 : ウォッチドッグタイマ無効
; ---------------------------------------------------------------
		__CONFIG _CONFIG3, _WDTCPS_WDTCPS_31 & _WDTE_OFF

; ---------------------------------------------------------------
; CONFIG4 @ 0x800A
;	WDTCWS_WDTCWS_7 : WDTウィンドウ設定
;	WDTCCS_SC		: WDT入力クロック
;	WRT_OFF		 : フラッシュ書き込み保護なし
;	SCANE_available : スキャナモジュール使用可能
;	LVP_OFF		 : 低電圧プログラミング無効 (MCLR=リセット)
; ---------------------------------------------------------------
		__CONFIG _CONFIG4, _WDTCWS_WDTCWS_7 & _WDTCCS_SC & _WRT_OFF & _SCANE_available & _LVP_OFF

; ---------------------------------------------------------------
; CONFIG5 @ 0x800B
;	CP_OFF : コード保護なし
;	(保護が必要な場合は CP_ON に変更)
; ---------------------------------------------------------------
		__CONFIG _CONFIG5, _CP_OFF

	end