;
;  RC2014 Machine Language Monitor
;  Daniel Quadros 2017  - http://dqsoft.blogspot.com
;
;  Initialization and 6850 ACIA rotines addapted from Grant Searle code
;  http://searle.hostei.com/grant/index.html
;  home.micros01@btinternet.com
;

; ASCII Characters
BS              .EQU    08H             ; Backspace
CR              .EQU    0DH
LF              .EQU    0AH
FF              .EQU    0CH             ; Clear screen

PROMPT          .EQU    '>'

; ACIA
ACIA_STATUS     .EQU    80H
ACIA_CONTROL    .EQU    80H
ACIA_RX         .EQU    81H
ACIA_TX         .EQU    81H
RTS_HIGH        .EQU    0D6H
RTS_LOW         .EQU    096H

                .ORG    8000H

; Serial receive buffer
SER_BUFSIZE     .EQU    3FH         ; Size of the buffer
SER_FULLSIZE    .EQU    30H         ; Limit for flow control
SER_EMPTYSIZE   .EQU    5           ; Limit for flow control

serBuf          .DEFS   SER_BUFSIZE
serInPtr        .DEFS   2
serRdPtr        .DEFS   2
serBufUsed      .DEFS   1

; Buffer for command
CMD_MAXSIZE     .EQU    32
cmdBuf          .DEFS   CMD_MAXSIZE+1
cmdSize         .DEFS   1

                .ORG $0000
;------------------------------------------------------------------------------
; Reset

RST00           DI                      ;Disable interrupts
                JP      INIT            ;Initialize Hardware and go

;------------------------------------------------------------------------------
; Transmit a character

                .ORG    0008H
RST08            JP     TXA

;------------------------------------------------------------------------------
; Receive a character (waits for reception)

                .ORG    0010H
RST10            JP     RXA

;------------------------------------------------------------------------------
; Check serial status

                .ORG    0018H
RST18            JP     CKINCHAR

;------------------------------------------------------------------------------
; RST 38 - INTERRUPT VECTOR [ for IM 1 ]

                .ORG     0038H
RST38            JR      serialInt       

;------------------------------------------------------------------------------
; Serial interrupt - put received char in the buffer
serialInt:      PUSH     AF
                PUSH     HL

                IN       A,(ACIA_STATUS)
                AND      $01            ; Check if interupt due to read buffer full
                JR       Z,rts0         ; if not, ignore

                IN       A,(ACIA_RX)    ; Get char from ACIA
                PUSH     AF
                LD       A,(serBufUsed)
                CP       SER_BUFSIZE     ; If buffer full then ignore
                JR       NZ,notFull
                POP      AF
                JR       rts0

notFull:        LD       HL,(serInPtr)
                INC      HL
                LD       A,L             ; Only need to check low byte becasuse buffer<256 bytes
                CP       (serBuf+SER_BUFSIZE) & $FF
                JR       NZ, notWrap
                LD       HL,serBuf
notWrap:        LD       (serInPtr),HL
                POP      AF
                LD       (HL),A         ; store char in buffer
                LD       A,(serBufUsed)
                INC      A              ; one more char in the buffer
                LD       (serBufUsed),A
                CP       SER_FULLSIZE
                JR       C,rts0
                LD       A,RTS_HIGH     ; too much in buffer, stop
                OUT      (ACIA_CONTROL),A
rts0:           POP      HL
                POP      AF
                EI
                RETI

;------------------------------------------------------------------------------
; Receive a character (waits for reception)
; Returns   <A> received char
; Affects   Flags, A
RXA:
waitForChar:    LD       A,(serBufUsed)
                OR       A
                JR       Z, waitForChar ; Wait for char in buffer
                PUSH     HL
                LD       HL,(serRdPtr)
                INC      HL
                LD       A,L            ; Only need to check low byte becasuse buffer<256 bytes
                CP       (serBuf+SER_BUFSIZE) & $FF
                JR       NZ, notRdWrap
                LD       HL,serBuf
notRdWrap:      DI
                LD       (serRdPtr),HL
                LD       A,(serBufUsed)
                DEC      A              ; One less char in buffer
                LD       (serBufUsed),A
                CP       SER_EMPTYSIZE
                JR       NC,rts1
                LD       A,RTS_LOW
                OUT      (ACIA_CONTROL),A
rts1:
                LD       A,(HL)         ; Get char from buffer
                EI
                POP      HL
                RET

;------------------------------------------------------------------------------
; Send char in <A>
; Affects: nothing
TXA:            PUSH     AF             ; Store character
conout1:        IN       A,(ACIA_STATUS)
                BIT      1,A            ; Set Zero flag if still transmitting character       
                JR       Z,conout1      ; Loop until flag signals ready
                POP      AF             ; Retrieve character
                OUT      (ACIA_TX),A        ; Output the character
                RET

;------------------------------------------------------------------------------
; Tests if there is a char in the buffer
; Returns: Z=1 if buffer empty
; Affects   Flags, A
CKINCHAR        LD       A,(serBufUsed)
                CP       $0
                RET

;------------------------------------------------------------------------------
; Print a zero-ended message
; Input <HL> address of the message
; Returns: Z=1 if buffer empty
; Affects   Flags, A, HL
PRINT:          LD       A,(HL)          ; Get character
                OR       A               ; Is it $00 ?
                RET      Z               ; Then RETurn on terminator
                RST      08H             ; Print it
                INC      HL              ; Next Character
                JR       PRINT           ; Continue until $00
                RET

;------------------------------------------------------------------------------
; Read a command
; Returns: comand in cmdBuf (zero ended)
;          size of comand in cmdSize
; Affects: Flags, A, C, HL
READ_CMD:
                LD      HL,cmdBuf
                LD      C,0             ; empty buffer
READ_CMD_1:
                RST     10H             ; read char
                CP      CR
                JR      Z,READ_CMD_END  ; Enter ends
                CP      BS
                JR      NZ,READ_CMD_2
                LD      A,C             ; backspace
                OR      A
                JR      Z,READ_CMD_1    ; ignore if buffer empty
                LD      A,BS
                RST     08H             ; back cursor
                LD      A,' '
                RST     08H             ; erase char
                LD      A,BS
                RST     08H             ; back cursor
                DEC     HL
                DEC     C
                JR      READ_CMD_1
READ_CMD_2:
                AND     A,0BFH          ; convert to uppercase
                LD      (HL),A          ; save char
                LD      A,C
                CP      CMD_MAXSIZE                JR      Z,READ_CMD_1    ; ignore if buffer full
                LD      A,(HL)          ; get char back
                RST     08H             ; echo
                INC     HL
                INC     C
                JR      READ_CMD_1
READ_CMD_END:
                LD      (HL),0          ; end string
                LD      A, C
                LD      (cmdSize),C     ; save size
                LD      A,CR
                RST     08H             
                LD      A,LF
                RST     08H             ; new line
                RET

;------------------------------------------------------------------------------
; Initialization
INIT:
                ; init stack
                LD        HL,0               ; Stack at end of Ram
                LD        SP,HL              ; Set up the stack
                ; init serial buffer
                LD        HL,serBuf
                LD        (serInPtr),HL
                LD        (serRdPtr),HL
                XOR       A                  ;0 to accumulator
                LD        (serBufUsed),A
                ; init ACIA
                LD        A,RTS_LOW
                OUT       (ACIA_CONTROL),A   ; Initialise ACIA
                IM        1                  ; Interrupt Mode 1
                EI
                ; say hello to the world
                LD        HL,HELLO        ; Sign-on message
                CALL      PRINT           ; Output string
;------------------------------------------------------------------------------
; Main Loop
MAIN:
                LD      A,PROMPT
                RST     08H
                CALL    READ_CMD
                CALL    EXEC_CMD
                JR      MAIN

;------------------------------------------------------------------------------
; Execute the comand
EXEC_CMD:
                LD      IX,0
                LD      A,(cmdBuf)
                OR      A
                LD      B,A
                RET     Z
EXEC_CMD_1:
                LD      A,(CMD_TABLE+IX)
                OR      A
                JR      Z,EXEC_CMD_3
                CMP     B
                JR      Z,EXEC_CMD_2
                INC     IX
                INC     IX
                JR      EXEC_CMD_1
EXEC_CMD_2:
                INC     IX
                LD      L,(CMD_TABLE+IX)
                INC     IX
                LD      H,(CMD_TABLE+IX)
                JP      (HL)
EXEC_CMD_3:
                LD        HL,ERR_CMD
                CALL      PRINT
                RET

;------------------------------------------------------------------------------
; Command decode table
CMD_TABLE:
                .BYTE   'A'
                .WORD   CMD_NOT_IMP
                .BYTE   'C'
                .WORD   CMD_NOT_IMP
                .BYTE   'D'
                .WORD   CMD_DISPLAY
                .BYTE   'E'
                .WORD   CMD_NOT_IMP
                .BYTE   'F'
                .WORD   CMD_NOT_IMP
                .BYTE   'G'
                .WORD   CMD_NOT_IMP
                .BYTE   'I'
                .WORD   CMD_NOT_IMP
                .BYTE   'L'
                .WORD   CMD_NOT_IMP
                .BYTE   'M'
                .WORD   CMD_NOT_IMP
                .BYTE   'O'
                .WORD   CMD_NOT_IMP
                .BYTE   'S'
                .WORD   CMD_NOT_IMP
                .BYTE   'U'
                .WORD   CMD_NOT_IMP
                .BYTE   'W'
                .WORD   CMD_NOT_IMP
                .BYTE   0

;------------------------------------------------------------------------------
; Display command
CMD_DISPLAY:
                RET

;------------------------------------------------------------------------------
; Command not implemmented
CMD_NOT_IMP:
                LD        HL,NOT_IMP
                CALL      PRINT
                RET

;------------------------------------------------------------------------------
; Messages
HELLO:      .BYTE     FF
            .BYTE     "Z80 Monitor by Daniel Quadros",CR,LF
            .BYTE     "Serial routines by Grant Searle",CR,LF
            .BYTE     0
            
NOT_IMP:
            .BYTE     "Not implemented",CR,LF
            .BYTE     0

ERR_CMD:
            .BYTE     "Unknown command",CR,LF
            .BYTE     0
