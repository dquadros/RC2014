;
;  RC2014 Machine Language Monitor
;  Daniel Quadros 2017  - http://dqsoft.blogspot.com
;
;  Initialization and 6850 ACIA rotines addapted from Grant Searle code
;  http://searle.hostei.com/grant/index.html
;  home.micros01@btinternet.com
;

; ASCII Characters
DEFC    BS      =   08H             ; Backspace
DEFC    CR      =   0DH
DEFC    LF      =   0AH
DEFC    SOH     =   01H
DEFC    EOT     =   04H
DEFC    ACK     =   06H
DEFC    CAN     =   18H
DEFC    NAK     =   15H

DEFC    PROMPT  =   '>'

; ACIA
DEFC    ACIA_STATUS     =   80H
DEFC    ACIA_CONTROL    =   80H
DEFC    ACIA_RX         =   81H
DEFC    ACIA_TX         =   81H
DEFC    RTS_HIGH        =   0D6H
DEFC    RTS_LOW         =   096H
DEFC    RTS_LOW_DI      =   016H

ifdef ROM
                .ORG    8000H

; Serial receive buffer
DEFC    SER_BUFSIZE     =   3FH         ; Size of the buffer
DEFC    SER_FULLSIZE    =   30H         ; Limit for flow control
DEFC    SER_EMPTYSIZE   =   5           ; Limit for flow control

serBuf:         DEFS    SER_BUFSIZE
serInPtr:       DEFS    2
serRdPtr:       DEFS    2
serBufUsed:     DEFS    1

else
                ORG     8080H
                
                JP      INIT_HELLO
endif

; Buffer for command
DEFC    CMD_MAXSIZE     =   32
cmdBuf:         DEFS   CMD_MAXSIZE+1
cmdSize:        DEFS   1

; Buffer used for Display output and Xmodem
auxbuf:         DEFS    132

; Comand parameters
orig:           DEFS   2
dest:           DEFS   2
len:            DEFS   2

; Xmodem
DEFC    MAX_RETRIES  =  10
blockno:         DEFS   1

ifdef ROM

                ORG $0000
;------------------------------------------------------------------------------
; Reset

RST00:          DI                      ;Disable interrupts
                JP      INIT            ;Initialize Hardware and go

;------------------------------------------------------------------------------
; Transmit a character

                ORG    0008H
RST08:          JP     TXA

;------------------------------------------------------------------------------
; Receive a character (waits for reception)

                ORG    0010H
RST10:          JP     RXA

;------------------------------------------------------------------------------
; Check serial status

                ORG    0018H
RST18:          JP     CKINCHAR

;------------------------------------------------------------------------------
; RST 38 - INTERRUPT VECTOR [ for IM 1 ]

                ORG     0038H
RST38:          JR      serialInt       

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

endif

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
                CP      20H
                JR      C,READ_CMD_1
                CP      60H
                JR      C,READ_CMD_3
                AND     A,0DFH          ; convert to uppercase
READ_CMD_3:
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
                LD      A,C
                LD      (cmdSize),A     ; save size
                LD      A,CR
                RST     08H             
                LD      A,LF
                RST     08H             ; new line
                RET

;------------------------------------------------------------------------------
; Reads an 8 bit value
; Input:   B - default value
; Return:  B - value
;          Z = 1 if ENTER was pressed
; Affects: Flags, A, B
GET8:
                RST     10H         ; read char
                CP      CR
                RET     Z           ; Enter ends
                CP      ' '
                JR      NZ,GET8_1
                OR      A,0FFH      ; set Z=0
                RET                 ; normal exit
GET8_1:
                CP      'a'
                JR      C,GET8_2
                SUB     20H         ; change to uppercase
GET8_2:
                LD      C,A
                SUB     '0'
                JR      C,GET8      ; ignore if ilegal
                CP      10
                JR      C,GET8_3
                SUB     7
                JR      C,GET8      ; ignore if ilegal
                CP      16
                JR      NC,GET8     ; ignore if ilegal
GET8_3:
                PUSH    AF
                LD      A,C
                RST     08H         ; echo
                LD      A,B
                ADD     A,A
                ADD     A,A
                ADD     A,A
                ADD     A,A
                LD      B,A
                POP     AF
                ADD     A,B
                LD      B,A
                JR      GET8

;------------------------------------------------------------------------------
; Skip blanks and get 16 bit hex value from command buffer
; Input:   HL - pointer to next char
;          DE - default value
; Returns: HL - updated pointer to next char
;          DE - value
;          CY = 1 if error
;          CY = 0 and Z = 1 if no value
;          CY = 0 and Z = 0 if success
;          
; Affects: Flags, A, BC, DE, HL
GET16:
                LD  A,(HL)
                OR  A
                RET Z           ; return at end
                CP  20H
                JR  NZ,GET16_1
                INC HL          ; skip leading blanks
                JR  GET16
GET16_1:
                LD  DE,0        ; found something
GET16_2:
                SUB '0'
                RET C           ; return if less then '0'
                CP  10
                JR  C,GET16_3   ; ok if '0' to '9'
                SUB 7
                RET C           ; return if > '9' and < 'A'
GET16_3:
                CP  16
                CCF
                RET C
                EX  DE,HL
                ADD HL,HL
                ADD HL,HL
                ADD HL,HL
                ADD HL,HL
                LD  B,0
                LD  C,A
                ADD HL,BC
                EX  DE,HL       ; DE = (DE << 4) + digit
                INC HL
                LD  A,(HL)
                OR  A
                JR  Z,GET16_4   ; stop if at end of line
                CP  20H
                JR  NZ,GET16_2  ; repeat if found a non blank
GET16_4:
                OR  A,0FFH      ; set Z=0 and CY=0
                RET             ; normal exit

; Put hex representation of a byte in a buffer
; Input:    B  value
;           IX pointer to buffer
; Returns:  IX next pos in buffer
; Affects:  Flags, A, IX
PUT8:
                LD      A,B
                SRL     A
                SRL     A
                SRL     A
                SRL     A
                CALL    PUT4
                LD      (IX+0),A
                INC     IX
                LD      A,B
                CALL    PUT4
                LD      (IX+0),A
                INC     IX
                RET
PUT4:
                AND     A,0Fh
                ADD     A,30H
                CP      03Ah
                RET     C
                ADD     A,7
                RET

;------------------------------------------------------------------------------
; Initialization
ifdef ROM
INIT:
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
endif
INIT_HELLO:
                ; init stack
                LD        HL,0               ; Stack at end of Ram
                LD        SP,HL              ; Set up the stack
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
                LD      IX,CMD_TABLE
                LD      A,(cmdBuf)
                OR      A
                LD      B,A
                RET     Z
EXEC_CMD_1:
                LD      A,(IX)
                OR      A
                JR      Z,EXEC_CMD_3
                CP      B
                JR      Z,EXEC_CMD_2
                INC     IX
                INC     IX
                INC     IX
                JR      EXEC_CMD_1
EXEC_CMD_2:
                INC     IX
                LD      L,(IX)
                INC     IX
                LD      H,(IX)
                JP      (HL)
EXEC_CMD_3:
                LD        HL,ERR_CMD
                CALL      PRINT
                RET

;------------------------------------------------------------------------------
; Command decode table
CMD_TABLE:
                DEFB   'A'
                DEFW   CMD_NOT_IMP
                DEFB   'C'
                DEFW   CMD_COMPARE
                DEFB   'D'
                DEFW   CMD_DISPLAY
                DEFB   'E'
                DEFW   CMD_ENTER
                DEFB   'F'
                DEFW   CMD_FILL
                DEFB   'G'
                DEFW   CMD_GOTO
                DEFB   'I'
                DEFW   CMD_INPUT
                DEFB   'L'
                DEFW   CMD_LOAD
                DEFB   'M'
                DEFW   CMD_MOVE
                DEFB   'O'
                DEFW   CMD_OUTPUT
                DEFB   'S'
                DEFW   CMD_NOT_IMP
                DEFB   'U'
                DEFW   CMD_NOT_IMP
                DEFB   'W'
                DEFW   CMD_WRITE
                DEFB   0

;------------------------------------------------------------------------------
; Compare command
; C addr1 len addr2
CMD_COMPARE:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (orig),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (len),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                ; compare
                LD      HL,(orig)
                LD      BC,(len)
CMD_COMPARE_1:
                LD      A,(DE)
                CP      (HL)
                JR      Z,CMD_COMPARE_2
                
                ; show difference
                PUSH    BC
                LD      IX,auxbuf
                LD      B,H
                CALL    PUT8
                LD      B,L
                CALL    PUT8
                LD      (IX+0),':'
                INC     IX
                LD      B,(HL)
                CALL    PUT8
                LD      (IX+0),' '
                INC     IX
                
                EX      DE,HL
                LD      B,H
                CALL    PUT8
                LD      B,L
                CALL    PUT8
                LD      (IX+0),':'
                INC     IX
                LD      B,(HL)
                CALL    PUT8
                LD      (IX+0),CR
                INC     IX
                LD      (IX+0),LF
                INC     IX
                LD      (IX+0),0
                INC     IX
                EX      DE,HL
                POP     BC
                
                PUSH    HL
                LD      HL,auxbuf
                CALL    PRINT
                POP     HL
CMD_COMPARE_2:
                INC     HL
                INC     DE
                DEC     BC
                LD      A,B
                OR      C
                JR      NZ,CMD_COMPARE_1
                RET

;------------------------------------------------------------------------------
; Display command
; D [addr [len]]
; if addr and len are ommited, displays the next 128 bytes
; if len is ommited, 128 is assumed
CMD_DISPLAY:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,(orig)
                CALL    GET16
                JP      C,PARAM_ERR
                LD      (orig),DE
                LD      DE,128
                CALL    GET16
                JP      C,PARAM_ERR
                LD      (len),DE
CMD_DISP_1:
                ; prepare output line
                ; xxxx: xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx xx xxxxxxxxxxxxxxxx
                LD      HL,auxbuf+4
                LD      (HL),':'
                INC     HL
                LD      C,65
                LD      A,20H
CMD_DISP_2:
                LD      (HL),A
                INC     HL
                DEC     C
                JR      NZ,CMD_DISP_2
                
                LD      (HL),CR
                INC     HL
                LD      (HL),LF
                INC     HL
                LD      (HL),0

                LD      HL,(orig)
                LD      IX,auxbuf
                LD      B,H
                CALL    PUT8
                LD      A,L
                AND     A,0F0H
                LD      B,A
                CALL    PUT8
                INC     IX
                INC     IX
                LD      IY,auxbuf+54
                
                ; Position at first byte
                LD      A,L
                AND     A,0Fh
                LD      C,A
                LD      B,0
                ADD     IY,BC
                ADD     IX,BC
                ADD     IX,BC
                ADD     IX,BC
                LD      A,16
                SUB     A,C
                LD      C,A
CMD_DISP_3:
                LD      B,(HL)
                CALL    PUT8
                INC     IX
                LD      B,'.'
                LD      A,(HL)
                INC     HL
                CP      20H
                JR      C,CMD_DISP_4
                CP      7EH
                JR      NC,CMD_DISP_4
                LD      B,A
CMD_DISP_4:
                LD      (IY+0),B
                INC     IY
                LD      DE,(len)
                DEC     DE
                LD      (len),DE
                LD      A,D
                OR      A,E
                JR      Z,CMD_DISP_5
                DEC     C
                JR      NZ,CMD_DISP_3
                LD      (orig),HL
                LD      HL,auxbuf
                CALL    PRINT
                JR      CMD_DISP_1
CMD_DISP_5:
                LD      (orig),HL
                LD      HL,auxbuf
                CALL    PRINT

                RET

;------------------------------------------------------------------------------
; Enter command
; E [addr]
; if addr is ommited, start at next addr
CMD_ENTER:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,(orig)
                CALL    GET16
                JP      C,PARAM_ERR
                LD      (orig),DE
CMD_ENTER_1:
                LD      A,8
                LD      (len),A
                LD      IX,auxbuf
                LD      HL,(orig)
                LD      B,H
                CALL    PUT8
                LD      B,L
                CALL    PUT8
                LD      (IX+0),':'
                LD      (IX+1),0
                LD      HL,auxbuf
                CALL    PRINT
CMD_ENTER_2:
                LD      HL,(orig)
                LD      IX,auxbuf
                LD      (IX+0),' '
                INC     IX
                LD      B,(HL)
                CALL    PUT8
                LD      (IX+0),'-'
                LD      (IX+1),0
                LD      HL,auxbuf
                CALL    PRINT
                LD      B,(HL)
                CALL    GET8
                LD      HL,(orig)
                LD      (HL),B
                INC     HL              ; note: does not affect Z
                LD      (orig),HL
                JR      Z,CMD_ENTER_3
                LD      A,(len)
                DEC     A
                LD      (len),A
                JR      NZ,CMD_ENTER_2
                LD      HL,NEWLINE
                CALL    PRINT
                JR      CMD_ENTER_1
CMD_ENTER_3:
                LD      HL,NEWLINE
                CALL    PRINT
                RET
                
;------------------------------------------------------------------------------
; Fill command
; F addr1 len val
CMD_FILL:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (orig),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (len),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                ; fill
                LD      HL,(orig)
                LD      BC,(len)
CMD_FILL_1:
                LD      (HL),E
                INC     HL
                DEC     BC
                LD      A,B
                OR      C
                JR      NZ,CMD_FILL_1
                RET

;------------------------------------------------------------------------------
; Goto command
; G addr
CMD_GOTO:
                ; get parameter
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                ; go there
                EX      DE,HL
                JP      (HL)

;------------------------------------------------------------------------------
; Input command
; I port
CMD_INPUT:
                ; get parameter
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      C,E
                IN      B,(C)
                LD      IX,auxbuf
                CALL    PUT8
                LD      (IX+0),CR
                LD      (IX+1),LF
                LD      (IX+2),0
                LD      HL,auxbuf
                CALL    PRINT
                RET
                
;------------------------------------------------------------------------------
; Load command
; L addr
CMD_LOAD:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (orig),DE
                
                ; Will use our own receive routine, no interrupts
                LD      A,RTS_LOW_DI
                OUT     (ACIA_CONTROL),A
                
                ; Xmodem reception
                LD      A,1         ; send NAK
                LD      (blockno),A
                LD      C,100       ; wait more time at start
CMD_LOAD_1:
                CALL    XM_RX_BLOCK
                CP      1
                JR      NC,CMD_LOAD_3
                ; ok, save block on memory
                LD      HL,(orig)
                LD      DE,auxbuf+2
                LD      C,128
CMD_LOAD_2:
                LD      A,(DE)
                LD      (HL),A
                INC     DE
                INC     HL
                DEC     C
                JR      NZ,CMD_LOAD_2
                LD      (orig),HL
                LD      A,(blockno)
                INC     A
                LD      (blockno),A
                LD      C,MAX_RETRIES
                XOR     A           ; send ACK
                JR      CMD_LOAD_1
CMD_LOAD_3:
                JR      NZ,CMD_LOAD_4
                ; received EOT
                LD      HL,XM_LOAD_OK
                JR      CMD_LOAD_END
CMD_LOAD_4:
                ; error
                LD      HL,XM_LOAD_ERR
CMD_LOAD_END:
                CALL    PRINT
                ; Turn on ACIA Rx interrupt
                LD        A,RTS_LOW
                OUT       (ACIA_CONTROL),A
                RET

; Receive a block (with retries)
; Input  A = 0 send ACK (for last packet received)
;            1 send NAK (start of protocol)
;        C = retries
; Return A = 0 if block received OK
;            1 if received EOT
;            2 if error
; Affects Flags, A, B, C, H, L
XM_RX_BLOCK:
                OR      A
                LD      B,ACK
                JR      Z,XM_RX_BLOCK_1
                LD      B,NAK
XM_RX_BLOCK_1:
                IN      A,(ACIA_STATUS)
                AND     2
                JR      Z,XM_RX_BLOCK_1     ; wait transmitter free
                LD      A,B
                OUT     (ACIA_TX),A
XM_RX_BLOCK_2:
                CALL    XM_RX_PKT
                CP      1
                RET     C                   ; good block, ack will be sent latter
                CP      2
                JR      NC,XM_RX_BLOCK_4
                ; EOT
XM_RX_BLOCK_3:
                IN      A,(ACIA_STATUS)
                AND     2
                JR      Z,XM_RX_BLOCK_3
                LD      A,ACK
                OUT     (ACIA_TX),A         ; send ACK
                LD      A,1
                RET
XM_RX_BLOCK_4:
                JR      NZ,XM_RX_BLOCK_5
                ; Duplicate
                LD      B,ACK
                DEC     C
                JR      NZ,XM_RX_BLOCK_1    ; send ACK and try again
                JR      XM_RX_BLOCK_6
XM_RX_BLOCK_5:
                CP      4
                JR      Z,XM_RX_BLOCK_6     ; CAN, abort now
                ; Error
                CALL    XM_CLEAR_RX
                LD      B,NAK
                DEC     C
                JR      NZ,XM_RX_BLOCK_1    ; send NAK and try again
XM_RX_BLOCK_6:
                ; Too many retries
                LD      A,2
                RET

; Receive a block (without retries)
; Return A = 0 if block received OK
;            1 if received EOT
;            2 if duplicate
;            3 if error
;            4 if CAN
; Affects Flags, A, D, E, H, L
XM_RX_PKT:
                PUSH    BC
                CALL    XM_GETCH
                JR      Z,XM_RX_PKT_ERR     ; Timeout
                CP      SOH
                JR      Z,XM_RX_PKT_0
                LD      B,1
                CP      EOT
                JR      Z,XM_RX_PKT_END     ; EOT
                LD      B,4
                CP      CAN
                JR      Z,XM_RX_PKT_END     ; Host abort
                JR      XM_RX_PKT_ERR       ; Unexpected char
XM_RX_PKT_0:
                LD      D,1                 ; D = checksum
                LD      E,130               ; blockno, ~blockno, data
                LD      HL,auxbuf
XM_RX_PKT_1:
                CALL    XM_GETCH
                JR      Z,XM_RX_PKT_ERR     ; Timeout
                LD      (HL),A              ; put in buffer
                ADD     D
                LD      D,A                 ; update checksum
                INC     HL
                DEC     E
                JR      NZ,XM_RX_PKT_1      ; repeat for whole packet
                
                CALL    XM_GETCH            ; read checksum
                JR      Z,XM_RX_PKT_ERR     ; Timeout
                SUB     D
                LD      D,A                 ; D = 0 if checksum ok
                
                LD      A,(auxbuf)
                LD      E,A
                LD      A,(auxbuf+1)
                CPL
                CP      E
                JR      NZ,XM_RX_PKT_ERR    ; Bad block number
                
                LD      A,D
                OR      A
                JR      NZ,XM_RX_PKT_ERR    ; Checksum error
                
                LD      A,(blockno)
                CP      E
                LD      B,0
                JR      Z,XM_RX_PKT_END     ; All right
                DEC     A
                CP      E
                LD      B,2
                JR      Z,XM_RX_PKT_END     ; Duplicate
                ; unexpected packet
XM_RX_PKT_ERR:
                LD      B,3                 ; Error
XM_RX_PKT_END:
                LD      A,B
                POP     BC
                RET

;------------------------------------------------------------------------------
; Move command
; M orig len dest
CMD_MOVE:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (orig),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (len),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                
                ; decide direction
                LD      BC,(len)
                LD      HL,(orig)
                LD      A,H
                CP      D
                JR      C,CMD_MOVE_1
                JR      NZ,CMD_MOVE_3
                LD      A,L
                CP      E
                RET     Z
                JR      NC,CMD_MOVE_3
CMD_MOVE_1:
                ADD     HL,BC
                EX      DE,HL
                ADD     HL,BC
                EX      DE,HL
CMD_MOVE_2:                
                DEC     HL
                DEC     DE
                LD      A,(HL)
                LD      (DE),A
                DEC     BC
                LD      A,B
                OR      C
                JR      NZ,CMD_MOVE_2
                RET
CMD_MOVE_3:
                LD      A,(HL)
                LD      (DE),A
                INC     HL
                INC     DE
                DEC     BC
                LD      A,B
                OR      C
                JR      NZ,CMD_MOVE_3
                RET

;------------------------------------------------------------------------------
; Output command
; O port value
CMD_OUTPUT:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      (orig),DE
                LD      DE,0
                CALL    GET16
                JP      C,PARAM_ERR
                JP      Z,PARAM_ERR
                LD      A,(orig)
                LD      C,A
                OUT     (C),E
                RET
                
;------------------------------------------------------------------------------
; Write command
; W addr len
; len will be rounded up to the next multiple of 128
CMD_WRITE:
                ; get parameters
                LD      HL,cmdBuf+1
                LD      DE,0
                CALL    GET16
                JP      Z,PARAM_ERR
                JP      C,PARAM_ERR
                LD      (orig),DE
                LD      DE,0
                CALL    GET16
                JP      Z,PARAM_ERR
                JP      C,PARAM_ERR
                LD      HL,7FH
                ADD     HL,DE
                LD      A,L
                AND     80H
                LD      L,A
                OR      H
                JP      Z,PARAM_ERR
                LD      (len),HL
                
                ; Will use our own receive routine, no interrupts
                LD        A,RTS_LOW_DI
                OUT       (ACIA_CONTROL),A
                
                ; Xmodem transmission
                XOR      A
                LD      (blockno),A
                CALL    XM_START_TX
                JR      Z,CMD_WRITE_ERR
CMD_WRITE_1:
                LD      A,(blockno)
                INC     A
                LD      (blockno),A
                CALL    XM_SEND_BLK
                JR      Z,CMD_WRITE_ERR
                LD      HL,(orig)
                LD      DE,128
                ADD     HL,DE
                LD      (orig),HL
                LD      HL,(len)
                LD      DE,0FF80H   ; -128
                ADD     HL,DE
                LD      (len),HL
                LD      A,H
                OR      L
                JR      NZ,CMD_WRITE_1
                
                CALL    XM_END_TX
                JR      Z,CMD_WRITE_ERR
                LD      HL,XM_SEND_OK
                CALL    PRINT
                JR      CMD_WRITE_END
CMD_WRITE_ERR:
                LD      HL,XM_SEND_ERR
                CALL    PRINT
CMD_WRITE_END:
                ; Turn on ACIA Rx interrupt
                LD        A,RTS_LOW
                OUT       (ACIA_CONTROL),A
                RET

; Wait for the starting NAK
; Returns Z = 1 if timeout
; Affects:  Flags, A, BC, HL
XM_START_TX:
                LD      L,90    ; total timeout aprox 30 seg
XM_START_TX_1:
                CALL    XM_GETCH
                JR      Z,XM_START_TX_2
                CP      NAK
                JR      Z,XM_START_TX_3
XM_START_TX_2:
                DEC     L
                JR      NZ,XM_START_TX_1
                RET
XM_START_TX_3:     
                OR      1       ; clear Z
                RET
                
; Send the current block
; Returns Z = 1 if timeout or max retreis
; Affects:  Flags, A, BC, DE, HL
XM_SEND_BLK:
                ; mount packet
                LD      HL,auxbuf
                LD      (HL),SOH
                INC     HL
                LD      A,(blockno)
                LD      (HL),A
                INC     HL
                CPL
                LD      (HL),A
                INC     HL
                LD      DE,(orig)
                LD      BC,128
XM_SEND_BLK_1:
                LD      A,(DE)
                INC     DE
                LD      (HL),A
                INC     HL
                ADD     A,B
                LD      B,A
                DEC     C
                JR      NZ,XM_SEND_BLK_1
                LD      (HL),B
                ; Send
                LD      E,MAX_RETRIES
XM_SEND_BLK_2:
                LD      HL,auxbuf
                LD      C,132
XM_SEND_BLK_3:
                IN      A,(ACIA_STATUS)
                AND     2
                JR      Z,XM_SEND_BLK_3   ; wait transmitter free
                LD      A,(HL)
                OUT     (ACIA_TX),A
                INC     HL
                DEC     C
                JR      NZ,XM_SEND_BLK_3
                ; Wait for ACK
XM_SEND_BLK_4:
                CALL    XM_GETCH
                JR      Z,XM_SEND_BLK_5
                CP      ACK
                JR      Z,XM_SEND_BLK_6
XM_SEND_BLK_5:
                DEC     E
                JR      NZ,XM_SEND_BLK_2
                RET
XM_SEND_BLK_6:
                OR      1       ; clear Z
                RET

; Send end of transmission
; Returns Z = 1 if timeout or max retreis
; Affects:  Flags, A, BC, HL
XM_END_TX:
                LD      L,MAX_RETRIES
XM_END_TX_1:
                IN      A,(ACIA_STATUS)
                AND     2
                JR      Z,XM_END_TX_1   ; wait transmitter free
                LD      A,EOT
                OUT     (ACIA_TX),A
                
                CALL    XM_GETCH
                JR      Z,XM_END_TX_2
                CP      ACK
                JR      Z,XM_END_TX_3
XM_END_TX_2:
                DEC     L
                JR      NZ,XM_END_TX_1
                RET
XM_END_TX_3:
                OR      1       ; clear Z
                RET

; Receive until timeout
; Affects:  Flags, A
XM_CLEAR_RX:
                PUSH    BC
XM_CLEAR_RX_1:
                CALL    XM_GETCH
                JR      NZ,XM_CLEAR_RX_1
                POP     BC
                RET

; Receive a char
; timout = 65536 x (10+7+7+6+4+4+12) / 7372.8 = aprox 0,355 sec
; Returns:  A received char (if any)
;           Z = 1 and C = 0 if timeout
; Affects:  Flags, A, BC
XM_GETCH:
            LD      BC,0
XM_GETCH_1:
            IN      A,(ACIA_STATUS)
            AND     $01
            JR      NZ,XM_GETCH_2
            DEC     BC
            LD      A,B
            OR      C
            JR      NZ,XM_GETCH_1
            RET
XM_GETCH_2:
            IN       A,(ACIA_RX)    ; Get char from ACIA
            RET

;------------------------------------------------------------------------------
; Command not implemmented
CMD_NOT_IMP:
                LD        HL,NOT_IMP
                CALL      PRINT
                RET

;------------------------------------------------------------------------------
; Invalid parameter
PARAM_ERR:
                LD        HL,PARAM_INV
                CALL      PRINT
                RET

;------------------------------------------------------------------------------
; Messages
HELLO:      
            DEFB    CR,LF
            DEFB    "Z80 Monitor v0.7 by Daniel Quadros",CR,LF
            DEFB    "Serial routines by Grant Searle"
NEWLINE:
            DEFB    CR,LF
            DEFB    0
            
ERR_CMD:
            DEFB    "Unknown command",CR,LF
            DEFB    0

NOT_IMP:
            DEFB    "Not implemented",CR,LF
            DEFB    0

PARAM_INV:
            DEFB    "Invalid parameter",CR,LF
            DEFB    0

XM_SEND_OK:
            DEFB    "Transmission successful",CR,LF
            DEFB    0

XM_SEND_ERR:
            DEFB    "Error in transmission",CR,LF
            DEFB    0

XM_LOAD_OK:
            DEFB    "Reception successful",CR,LF
            DEFB    0

XM_LOAD_ERR:
            DEFB    "Error in reception",CR,LF
            DEFB    0
