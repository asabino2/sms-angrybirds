; ============================================================================
; ANGRY BIRDS CLASSIC — SEGA MASTER SYSTEM (SMS) EDITION
; File: sms/src/header.asm
; Official Sega Master System "TMR SEGA" ROM Header ($7FF0..$7FFF)
; Validated by all US, European & Brazilian (TecToy) Master System BIOSes
; ============================================================================

    .org $7FF0
SmsHeader:
    .db "TMR SEGA"          ; $7FF0..$7FF7: Official Sega Master System signature
    .db $00, $00            ; $7FF8..$7FF9: Reserved ($0000)
    .dw $0000               ; $7FFA..$7FFB: 16-bit Checksum (computed by asmz80.py)
    .db $26, $80, $00       ; $7FFC..$7FFE: Product Code 8026 (BCD), Version 0
    .db $4C                 ; $7FFF: Region 4 (SMS Export) | Size C (32KB Checksum)
