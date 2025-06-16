.global main

#include <avr/io.h>

; Register usage
; r0 - r15 reserved for Speck cipher packet encoding

; Start symbol - FU
#define START_SYMBOL 0x4655

#define SPM_WORD_LOW r0
#define SPM_WORD_HIGH r1
#define ZERO r2
#define RX_INTEGRATOR r18
#define RX_PLL_RAMP r19
#define RX_BITS_LOW r20
#define RX_BITS_HIGH r21
#define RX_LAST_PIN_STATE r15
#define RX_BITS_COUNT_REMAINS r16
#define RX_PAGES_REMAIN r22
#define RX_BUF_LEN r17
#define CRC r23
#define TMP1 r24
#define TMP2 r25
; Z-pointer is used for programming (SPM)
#define ZL r30
#define ZH r31

; r24 - function call parameter
; r25 - auxiliary - scratch

; Calculated using calctimer.c
#define TIMER_PRESCALER 2 ; 1 tick = 1 µs
#define TIMER_READ_NTICKS 62   ; sample bit every 62.5 µs (1000000 / 2000 / 8 = 62.5)
#define TIMER_WRITE_HALF_NTICKS 250 ; hold output bit for 500 µs (2 * 250), sampling every 62.5 µs

#define RH_ASK_RX_DDR DDRB
#define RH_ASK_RX_PIN PINB
#define RH_ASK_RX_BIT PB2

#define RH_MIN_BUFFER_LEN 2
#define RH_ASK_MAX_PAYLOAD_LEN 150

.macro RESET_TIMER
    out _SFR_IO_ADDR(TCNT0), ZERO
.endm

.macro DEBUG_LED_ON
    sbi _SFR_IO_ADDR(PORTB), PB1 ; Turn on debug LED
.endm

.macro DEBUG_LED_OFF
    cbi _SFR_IO_ADDR(PORTB), PB1 ; Turn off debug LED
.endm

.macro DISABLE_WATCHDOG
    wdr
    in TMP1, _SFR_IO_ADDR(WDTCSR)
    ori TMP1, (1<<WDCE)|(1<<WDE)
    out _SFR_IO_ADDR(WDTCSR), TMP1
    andi TMP1, ~((1<<WDCE)|(1<<WDE))
    out _SFR_IO_ADDR(WDTCSR), ZERO
    cli
.endm

main:
    ldi r16, hi8(RAMEND)
    out _SFR_IO_ADDR(SPH), r16
    ldi r16, lo8(RAMEND)
    out _SFR_IO_ADDR(SPL), r16

    rjmp start ; required due to owl bootloader

; --------------- MAIN ---------------

.org 0x1d00

start:
    clr ZERO

    DISABLE_WATCHDOG

    sbi _SFR_IO_ADDR(DDRB), 1           ; Debug LED pin as output
    DEBUG_LED_ON                        ; Turn on debug LED

; Timer initialization
    ldi r24, TIMER_PRESCALER
    out _SFR_IO_ADDR(TCCR0A), ZERO      ; Standard timer - normal mode - count 0–255
    out _SFR_IO_ADDR(TIMSK0), ZERO      ; No timer interrupts
    out _SFR_IO_ADDR(OCR0A),  ZERO      ; No output compare
    out _SFR_IO_ADDR(TCCR0B), r24       ; Set prescaler
    RESET_TIMER

    clr RX_PAGES_REMAIN                 ; Pages to be written - set by first page

main_loop:
    ; The caller may use watchdog to detect we're waiting for transmission start symbol
    ; If the symbol is detected and we start reading, watchdog is disabled
    ; We must not return from this point
    rcall receive_data                  ; Load next page data
    rjmp main_loop

; ----------------------------- READING without interrupts -----------------------------
; Read bit state every ~62.5 µs - we actively wait for timing instead of interrupts,
; because this runs in the bootloader and the user might want to use interrupts.
; The last pin state is stored in the T flag.
; r24 will contain the number of received bytes in [rx_buffer] at the end.

#define RH_ASK_RAMP_TRANSITION 80
#define RH_ASK_RX_RAMP_LEN 160
#define RH_ASK_RAMP_INC 20
#define RH_ASK_RAMP_INC_RETARD 11
#define RH_ASK_RAMP_INC_ADVANCE 9

; r30:r31 Z: used for nibble table
; r26:r27 X: used for rx_buffer

receive_data:
    clr RX_INTEGRATOR
    clt ; Use T bit as a flag indicating we're in active receive phase

wait_for_next_read_timer_tick:
    in r24, _SFR_IO_ADDR(TCNT0)
    cpi r24, TIMER_READ_NTICKS
    brcs wait_for_next_read_timer_tick

    RESET_TIMER

    in r24, _SFR_IO_ADDR(RH_ASK_RX_PIN) ; Read current pin state
    sbrc r24, RH_ASK_RX_BIT
    inc RX_INTEGRATOR

if_edge_change:
        eor RX_LAST_PIN_STATE, r24
        sbrs RX_LAST_PIN_STATE, RH_ASK_RX_BIT
        rjmp always_inc_pll
    edge_change_detected: ; (rxSample != _rxLastSample)
        cpi RX_PLL_RAMP, RH_ASK_RAMP_TRANSITION
        brlo pll_retard
    pll_advance:
        subi RX_PLL_RAMP, -RH_ASK_RAMP_INC_ADVANCE ; increase ramp (advance)
        rjmp always_inc_pll
    pll_retard:
        subi RX_PLL_RAMP, RH_ASK_RAMP_INC_RETARD ; decrease ramp (retard)

    always_inc_pll:
        subi RX_PLL_RAMP, -RH_ASK_RAMP_INC ; always add +20

    mov RX_LAST_PIN_STATE, r24 ; Save current sample state

if_ramp:
    cpi RX_PLL_RAMP, RH_ASK_RX_RAMP_LEN
if_ramp_not_finished:    
    brlo wait_for_next_read_timer_tick
if_ramp_finished:
    lsl RX_BITS_LOW
    rol RX_BITS_HIGH

    cpi RX_INTEGRATOR, 5 ; if RX_INTEGRATOR >= 5
    brlo not_adding_one
    ori RX_BITS_LOW, 0x01 ; Set MSB of the 12 bits (inverse to RH_ASK)
not_adding_one:
    subi RX_PLL_RAMP, RH_ASK_RX_RAMP_LEN ; Reset ramp
    clr RX_INTEGRATOR ; Reset for next bit

if_rx_active:
    brts rx_is_active
    rjmp rx_is_not_active
rx_is_active:
    dec RX_BITS_COUNT_REMAINS
    brne wait_for_next_read_timer_tick

all_12_bits_read:
    andi RX_BITS_HIGH, 0xF ; Clear junk, keep lower 4 bits

    mov r24, RX_BITS_LOW
    andi r24, 0x3F ; Mask to 6 bits
    rcall code_to_nibble
    mov r25, r24

    ; Shift top 2 bits of RX_BITS_LOW into RX_BITS_HIGH
    lsl RX_BITS_LOW
    rol RX_BITS_HIGH
    lsl RX_BITS_LOW
    rol RX_BITS_HIGH

    mov r24, RX_BITS_HIGH
    rcall code_to_nibble
    swap r24
    or r25, r24 ; r25 now contains full decoded byte

    mov r24, r25
    rcall calc_crc

    cpi RX_BUF_LEN, 0xFF ; First header byte?
    brne after_header_1
    mov ZH, r25
    rjmp continue_next_byte

after_header_1:
    cpi RX_BUF_LEN, 0xFE ; Second header byte?
    brne after_header_Z
    mov ZL, r25
    rjmp continue_next_byte

after_header_Z:
    cpi RX_BUF_LEN, 0xFD ; Third header byte - message index
    brne after_header_done

    cp RX_PAGES_REMAIN, r25 
    breq not_yet_finished_programming

    tst RX_PAGES_REMAIN ; Is this the first packet?
    breq first_packet_set_message_id

    ; FAILED - missed a message
    rjmp failed

first_packet_set_message_id:
    mov RX_PAGES_REMAIN, r25
    rjmp not_yet_finished_programming

not_yet_finished_programming:    
    ldi RX_BUF_LEN, 66 ; 64 bytes page + 1 CRC + 1 extra
    rjmp continue_next_byte

after_header_done:
    sbrc RX_BUF_LEN, 0
    rjmp not_word_aligned_have_first_byte
    mov r1, r25 ; Complete word ready
    ldi r25, 1 ; SPM write command
    out _SFR_IO_ADDR(SPMCSR), r25
    spm
    rjmp prepare_read_next_data_byte

not_word_aligned_have_first_byte:
    mov r0, r25

prepare_read_next_data_byte:
    adiw ZL, 1 ; Advance Z pointer

continue_next_byte:
    dec RX_BUF_LEN
    breq buffer_is_completely_read
    ldi RX_BITS_COUNT_REMAINS, 12
    rjmp wait_for_next_read_timer_tick

buffer_is_completely_read:
    tst CRC ; Check CRC = 0
    breq message_is_correct

failed:
    DEBUG_LED_ON
    wdr
    rjmp failed

message_is_correct:
    clt ; Clear T bit - rxActive = false
    sbiw ZL, 63
    sbiw ZL, 1

    ldi r24, 3 ; Erase page
    out _SFR_IO_ADDR(SPMCSR), r24
    spm

wait_for_flash_erase:
    in r24, _SFR_IO_ADDR(SPMCSR)
    sbrc r24, 0
    rjmp wait_for_flash_erase

    ldi r24, 5 ; Write page from buffer
    out _SFR_IO_ADDR(SPMCSR), r24
    spm

wait_for_flash_update:
    in r24, _SFR_IO_ADDR(SPMCSR)
    sbrc r24, 0
    rjmp wait_for_flash_update

    dec RX_PAGES_REMAIN
    breq bootloader_finished_properly
    ret

bootloader_finished_properly:
    ldi  r30, 0
    ldi  r31, 0
    ijmp ; Goodbye

rx_is_not_active:
    ; While we're here, we can still return to original code
    ; Do we have the start symbol?
    cpi RX_BITS_LOW, lo8(START_SYMBOL)
    brne endif_ramp
    cpi RX_BITS_HIGH, hi8(START_SYMBOL)
    brne endif_ramp

set_active_state:
    set ; Set T bit = rxActive = true
    clr CRC ; Initialize CRC
    ldi RX_BITS_COUNT_REMAINS, 12
    ldi RX_BUF_LEN, 0xFF ; Max length, reading header

endif_ramp:
    rjmp wait_for_next_read_timer_tick

code_to_nibble:
; r24 contains 6-bit symbol code, convert it to 4-bit nibble (in r24)
; Uses r23 and r25 temporarily, but they are saved to stack
; If lookup fails, r24 = 0x10
    push r23         ; Save temporary registers
    push r25
    push ZL
    push ZH
    ldi ZL, lo8(nibbles)
    ldi ZH, hi8(nibbles)
    clr r23          ; Index counter

code_to_nibble_search:
    lpm r25, Z+      ; Load byte from flash
    cp r25, r24
    breq nibble_found
    inc r23
    brlo code_to_nibble_search ; Continue if not found
    ldi r23, 0x10     ; Not found
nibble_found:
    mov r24, r23     ; Return result in r24
    pop ZH
    pop ZL
    pop r25
    pop r23
    ret

; Calculate CRC progressively from current byte in r24
; CRC is stored in r23
calc_crc: ; (CRC, r24: data) -> CRC
    push    r18
    push    r19
    push    r25
    eor     CRC, r24
    ldi     r25, 0x08 ; Loop counter
    ldi     r18, 0x8C ; Polynomial
calc_crc_loop:
    mov     r19, CRC
    andi    r19, 0x01       
    lsr     CRC
    sbrc    r19, 0 ; If LSB was 1
    eor     CRC, r18
    subi    r25, 0x01  
    brne    calc_crc_loop
    pop     r25
    pop     r19
    pop     r18
    ret

; Nibble to symbol encoding table (used in reverse decoding)
nibbles:
    .byte 0xd, 0xe, 0x13, 0x15, 0x16, 0x19, 0x1a, 0x1c
    .byte 0x23, 0x25, 0x26, 0x29, 0x2a, 0x2c, 0x32, 0x34, 0xFF ; 0xFF is terminator
