; MiSTang Monitor for the Apple I core. Original program.
; Commands (one line, hex numbers, upper or lower case):
;   ADDR            show the byte at ADDR
;   ADDR.ADDR       dump a range, 8 bytes per row
;   ADDR: B B B     store bytes starting at ADDR
;   ADDR R          run the program at ADDR (JSR; RTS returns to the monitor)
KBD    = $D010
KBDCR  = $D011
DSP    = $D012
CURL   = $24
CURH   = $25
ENDL   = $26
ENDH   = $27
VALL   = $28
VALH   = $29
MODE   = $2A
FLAG   = $2B
CNT    = $2C
YSAV   = $2D
BUF    = $0200

.org $F000
RESET:  CLD
        LDX #$FF
        TXS
        LDA #$0D
        JSR PUTC
        LDX #0
BANNER: LDA msg,X
        BEQ MAIN
        JSR PUTC
        INX
        BNE BANNER
MAIN:   LDA #'\'
        JSR PUTC
        JSR READLINE
        JSR PARSE
        JMP MAIN

PUTC:   BIT DSP
        BMI PUTC
        STA DSP
        RTS

GETC:   LDA KBDCR
        BPL GETC
        LDA KBD
        AND #$7F
        RTS

READLINE: LDY #0
RL1:    JSR GETC
        CMP #$0D
        BEQ RLEND
        CMP #$08
        BEQ RLBS
        CMP #$7F
        BEQ RLBS
        CMP #$20
        BCC RL1
        CMP #$61
        BCC RL2
        AND #$DF
RL2:    STA BUF,Y
        JSR PUTC
        INY
        CPY #$7E
        BCC RL1
RLEND:  LDA #$0D
        STA BUF,Y
        JSR PUTC
        RTS
RLBS:   CPY #0
        BEQ RL1
        DEY
        LDA #$08
        JSR PUTC
        JMP RL1

PARSE:  LDY #0
        STY MODE
        STY FLAG
PNEXT:  LDA BUF,Y
        INY
        CMP #$0D
        BNE PN_A
        JMP PEOL
PN_A:   CMP #'.'
        BNE PN_B
        JMP PDOT
PN_B:   CMP #':'
        BNE PN_C
        JMP PCOL
PN_C:   CMP #'R'
        BNE PN_D
        JMP PRUN
PN_D:   JSR HEXDIG
        BCS PNEXT
        STA VALL
        LDA #0
        STA VALH
PNUM:   LDA BUF,Y
        JSR HEXDIG
        BCS PEND
        INY
        ASL VALL
        ROL VALH
        ASL VALL
        ROL VALH
        ASL VALL
        ROL VALH
        ASL VALL
        ROL VALH
        ORA VALL
        STA VALL
        JMP PNUM
PEND:   LDA MODE
        BEQ PADDR
        CMP #1
        BEQ PSTORE
        LDA VALL
        STA ENDL
        LDA VALH
        STA ENDH
        JSR DUMP
        LDA #0
        STA MODE
        STA FLAG
        JMP PNEXT
PADDR:  LDA VALL
        STA CURL
        LDA VALH
        STA CURH
        LDA #1
        STA FLAG
        JMP PNEXT
PSTORE: LDA VALL
        LDX #0
        STA (CURL,X)
        INC CURL
        BNE PS1
        INC CURH
PS1:    JMP PNEXT
PDOT:   LDA #2
        STA MODE
        JMP PNEXT
PCOL:   LDA #1
        STA MODE
        LDA #0
        STA FLAG
        JMP PNEXT
PRUN:   LDA #0
        STA FLAG
        JSR RUNIT
        JMP PNEXT
RUNIT:  JMP (CURL)
PEOL:   LDA FLAG
        BEQ PDONE
        JSR PRLABEL
        LDA #' '
        JSR PUTC
        LDY #0
        LDA (CURL),Y
        JSR PRBYTE
        LDA #$0D
        JSR PUTC
PDONE:  RTS

HEXDIG: SEC
        SBC #$30
        BCC HDNO
        CMP #$0A
        BCC HDOK
        SBC #$07
        CMP #$0A
        BCC HDNO
        CMP #$10
        BCS HDNO
HDOK:   CLC
        RTS
HDNO:   SEC
        RTS

DUMP:   STY YSAV
        LDA #0
        STA CNT
        JSR PRLABEL
DLOOP:  LDA #' '
        JSR PUTC
        LDY #0
        LDA (CURL),Y
        JSR PRBYTE
        INC CURL
        BNE D1
        INC CURH
D1:     LDA ENDL
        CMP CURL
        LDA ENDH
        SBC CURH
        BCC DEND
        INC CNT
        LDA CNT
        AND #7
        BNE DLOOP
        LDA #$0D
        JSR PUTC
        JSR PRLABEL
        JMP DLOOP
DEND:   LDA #$0D
        JSR PUTC
        LDY YSAV
        RTS

PRLABEL: LDA CURH
        JSR PRBYTE
        LDA CURL
        JSR PRBYTE
        LDA #':'
        JMP PUTC
PRBYTE: PHA
        LSR A
        LSR A
        LSR A
        LSR A
        JSR PRNIB
        PLA
        AND #$0F
PRNIB:  ORA #$30
        CMP #$3A
        BCC PN1
        ADC #$06
PN1:    JMP PUTC

msg:    .byte "MISTANG APPLE I", $0D, 0

.org $FFFA
        .word RESET
        .word RESET
        .word RESET
