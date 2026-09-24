; =====================================================================
; File:   bios.S
; Author: <your names here>
;
; ECE 3301L Practical Midterm - "Write Your Own BIOS": Reset, Vectors, and POST
; ECE 3301L - Introduction to Microcontrollers Laboratory
;
; Pure-assembly boot firmware for the PIC18F46K22. You are the BIOS
; author: reset vector -> POST -> vector setup -> boot handoff.
;
; Pin Assignments:
;   RD0-RD7 - POST / status LEDs (RD7 doubles as ISR-toggle LED)
;   RA4     - heartbeat / SOS LED
;   RB0     - INT0 external button (active-low, 10k pull-up)
;   RE0     - RAM-test fault jumper (10k pull-up to 3.3V): ground it
;             to force POST failure. Without the pull-up the pin
;             floats and the boot decision is a coin flip.
;
; Build (pic-as driver - this is what CI runs; NO linker options
; are needed: the vector psects are absolute, ORG'd in the source):
;   pic-as -mcpu=18F46K22 -o firmware.hex bios.S
;
; PROVIDED: config bits, delay routines, SOS trap, app_blink.
; YOU WRITE: boot init, RAM test, LED sweep, ISR body, vector setup.
; =====================================================================

#include <xc.inc>

; ---------------- Configuration bits (PROVIDED - do not change) -----
CONFIG FOSC=INTIO67, PLLCFG=OFF, PRICLKEN=ON, FCMEN=OFF, IESO=OFF
CONFIG PWRTEN=ON, BOREN=SBORDIS, BORV=250
CONFIG WDTEN=OFF, WDTPS=32768
CONFIG CCP2MX=PORTC1, PBADEN=OFF, CCP3MX=PORTB5, HFOFST=ON
CONFIG T3CMX=PORTC0, P2BMX=PORTD2, MCLRE=EXTMCLR
CONFIG STVREN=ON, LVP=ON, XINST=OFF
CONFIG CP0=OFF, CP1=OFF, CP2=OFF, CP3=OFF, CPB=OFF, CPD=OFF
CONFIG WRT0=OFF, WRT1=OFF, WRT2=OFF, WRT3=OFF, WRTC=OFF, WRTB=OFF, WRTD=OFF
CONFIG EBTR0=OFF, EBTR1=OFF, EBTR2=OFF, EBTR3=OFF, EBTRB=OFF

; ---------------- BIOS variables (access bank) ----------------
PSECT udata_acs
del_a:      DS 1        ; delay loop counters (used by PROVIDED delays)
del_b:      DS 1
del_c:      DS 1
sos_i:      DS 1        ; SOS pattern index

; =====================================================================
; RESET VECTOR - the very first instruction the CPU executes.
; An ABSOLUTE psect: the ORG below pins it to address 0x0000 in
; the source itself - no linker options, no IDE settings.
; =====================================================================
PSECT resetVec,abs,ovrld,class=CODE,reloc=2
    ORG     0x0000
resetVec:
    goto    boot

; =====================================================================
; HIGH-PRIORITY INTERRUPT VECTOR - absolute psect ORG'd to 0x0008.
; "Installing an interrupt vector" = putting code at this address.
; =====================================================================
PSECT intVec,abs,ovrld,class=CODE,reloc=2
    ORG     0x0008
intVec:
    ; TODO: 1. If INT0IF (INTCON bit 1) is NOT set, return (retfie 1)
    ;       2. Blink RD7 rapidly for ~2 seconds (about 10 flashes:
    ;          20 toggles of LATD bit 7, ~100 ms apart) so the press
    ;          is unmistakable.
    ;          !! TRAP: do NOT call delay_100ms from here - the
    ;          interrupt may have fired INSIDE delay_100ms, and
    ;          calling it again clobbers del_a/del_b mid-count in
    ;          the interrupted code. Write your own delay loop with
    ;          NEW variables (declare them in udata_acs).
    ;       3. Clear INT0IF AFTER the blink - bounce edges that
    ;          arrived during the blink get swallowed
    ;       4. retfie 1  (fast return restores W/STATUS/BSR shadows)
    retfie  1

; =====================================================================
; BOOT
; =====================================================================
PSECT code
boot:
    ; TODO: Clock - the chip wakes up at 1 MHz. Set OSCCON for
    ;       16 MHz HFINTOSC: IRCF=111, SCS=10 (one movlw/movwf pair;
    ;       work out the byte value from the OSCCON register map).

    ; TODO: I/O so POST can report:
    ;       - all ANSELx digital (ANSELA/B/D/E = 0)
    ;         !! TRAP: the ANSELx registers live at 0xF38-0xF3C, which
    ;         is BELOW the access-bank SFR window (0xF60+). Clearing
    ;         them with ",a" assembles without warning but silently
    ;         writes ordinary RAM - the pins stay analog and analog
    ;         pins always READ AS 0. Use banked access instead:
    ;             banksel ANSELA
    ;             clrf    BANKMASK(ANSELA),b
    ;             ...
    ;             movlb   0
    ;       - PORTD all outputs, LEDs off (TRIS/LAT are at 0xF80+,
    ;         inside the access bank - ",a" is fine for those)
    ;       - RA4 output, off
    ;       - RB0 input (INT0 button), RE0 input (fault jumper)

; ---------------------------------------------------------------------
; POST STAGE 1 - RAM test.
; Walk 0x55 then 0xAA through GPR bank 1 (0x100-0x1FF) using FSR0.
; If the RE0 jumper reads LOW, simulate a fault -> goto sos_trap.
; ---------------------------------------------------------------------
post_ram:
    ; TODO: if RE0 is low, goto sos_trap (simulated RAM fault)

    ; TODO: pattern test with W=0x55 then W=0xAA - either inline or
    ;       via a subroutine:
    ;         fill:   lfsr 0,0x100; write pattern via POSTINC0 until
    ;                 FSR0H reaches 0x02
    ;         verify: lfsr 0,0x100; cpfseq POSTINC0 against the
    ;                 pattern; any mismatch -> goto sos_trap
    bra     post_leds

; ---------------------------------------------------------------------
; POST STAGE 2 - LED sweep + button sanity check.
; ---------------------------------------------------------------------
post_leds:
    ; TODO: sweep a single lit LED across RD0->RD7, two passes,
    ;       ~100 ms per step (use the provided delay_100ms).
    ;       Hints: start LATD=0x01; rlcf LATD shifts the bit left;
    ;       the carry flag tells you when it walked off RD7.
    ;       !! TRAP: the provided delay routines use del_a and del_b
    ;       as scratch and leave them clobbered. Your pass counter
    ;       must be a NEW variable (declare it in udata_acs) - a
    ;       counter in del_a/del_b gets wiped by every delay call
    ;       and the sweep loops forever.

    ; TODO: verify the RB0 button reads RELEASED (high).
    ;       Held/stuck at boot -> goto sos_trap.

; ---------------------------------------------------------------------
; VECTOR SETUP - make the installed INT0 handler live.
; ---------------------------------------------------------------------
install_vectors:
    ; TODO: clear INT0IF, set INT0IE, INTEDG0 = falling edge,
    ;       then set GIE. (All in INTCON / INTCON2.)

; ---------------------------------------------------------------------
; BOOT HANDOFF - the BIOS's last act.
; ---------------------------------------------------------------------
    goto    app_blink

; =====================================================================
; SOS TRAP (PROVIDED) - POST failure. Blinks ...---... forever.
; =====================================================================
sos_trap:
    clrf    LATD,a
sos_loop:
    movlw   3
    movwf   sos_i,a
sos_dots1:
    call    blink_short
    decfsz  sos_i,f,a
    bra     sos_dots1
    movlw   3
    movwf   sos_i,a
sos_dashes:
    call    blink_long
    decfsz  sos_i,f,a
    bra     sos_dashes
    movlw   3
    movwf   sos_i,a
sos_dots2:
    call    blink_short
    decfsz  sos_i,f,a
    bra     sos_dots2
    movlw   20                  ; 2 s dark between SOS letters
    movwf   del_c,a
sos_gap:
    call    delay_100ms
    decfsz  del_c,f,a
    bra     sos_gap
    bra     sos_loop

blink_short:                    ; DOT: quick 50 ms flick, 150 ms off
    bsf     LATA,4,a
    call    delay_50ms
    bcf     LATA,4,a
    call    delay_100ms
    call    delay_50ms
    return

blink_long:                     ; DASH: a full 1 s on, 300 ms off -
    bsf     LATA,4,a            ; deliberately nothing like the 1 Hz
    movlw   10                  ; heartbeat
    movwf   del_c,a
bl_on:
    call    delay_100ms
    decfsz  del_c,f,a
    bra     bl_on
    bcf     LATA,4,a
    call    delay_100ms
    call    delay_100ms
    call    delay_100ms
    return

; =====================================================================
; "USER APPLICATION" (PROVIDED) - what your BIOS boots into.
; =====================================================================
app_blink:
    btg     LATA,4,a
    movlw   5
    movwf   del_c,a
app_wait:
    call    delay_100ms
    decfsz  del_c,f,a
    bra     app_wait
    bra     app_blink

; =====================================================================
; Delays (PROVIDED) - software loops at 16 MHz.
; =====================================================================
delay_100ms:
    movlw   2
    movwf   del_a,a
d100_outer:
    clrf    del_b,a
d100_mid:
    clrf    WREG,a
d100_inner:
    decfsz  WREG,w,a
    bra     d100_inner
    decfsz  del_b,f,a
    bra     d100_mid
    decfsz  del_a,f,a
    bra     d100_outer
    return

delay_50ms:
    movlw   1
    movwf   del_a,a
    bra     d100_outer

    END
