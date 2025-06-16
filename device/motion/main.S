#define FW_VERSION 0x10

.global main

#include <avr/io.h>

#define MAX_WDT_COUNT 2

; FLAG bity
#define FLAG_WDT (1 << 0)
#define FLAG_PIR (1 << 1)
#define FLAG_RCWL (1 << 2)

#define PIR_PIN PINA
#define PIR_BIT PA0

#define RCWL_PIN PINA
#define RCWL_BIT PA2

#define IRR_PIN PINB
#define IRR_BIT PB2
#define IRR_PCINT PCINT10

#define SCRATCH r0
#define ZERO r1

; Tohle se nesmi nikde pouzivat - pouziva se k nacteni START symbolu
#define UART_BYTE_A r8
#define UART_BYTE_B r9
#define UART_BYTE_C r10
#define UART_BYTE_D r11

#define CNT r15

; POZOR r16 a r17 se nesmi pouzivat na nic jineho nikde jinde, protoze se upravuji v preruseni!!!
#define TICKS r16
#define FLAGS r17

#define TMP r24
#define TMP2 r25

.macro GPIO_SETUP
    ldi TMP, 7                          ; PA0-PA2
    out _SFR_IO_ADDR(PCMSK0), TMP
    ldi TMP, (1 << IRR_PCINT)           ; PB2 - IRR
    out _SFR_IO_ADDR(PCMSK1), TMP
    ldi TMP, (1 << PCIE0) | (1 << PCIE1)
    out _SFR_IO_ADDR(GIMSK), TMP
.endm

.macro DEBUG_LED_ON
    sbi _SFR_IO_ADDR(DDRB), PB1
    sbi _SFR_IO_ADDR(PORTB), PB1 ; DEBUG LED
.endm

.macro DEBUG_LED_OFF
    sbi _SFR_IO_ADDR(DDRB), PB1
    cbi _SFR_IO_ADDR(PORTB), PB1 ; DEBUG LED
.endm

.macro SAVE_SREG_TMP
    push TMP
    in TMP, _SFR_IO_ADDR(SREG)
    push TMP
.endm

.macro LOAD_SREG_TMP
    pop TMP
    out _SFR_IO_ADDR(SREG), TMP
    pop TMP
.endm

.org 0x0000                  ; reset vektor
    rjmp main                ; Skok na hlavní program
    reti                     ; INT0_vect - External Interrupt Request 0
    rjmp PCINT0_vect         ; Pin Change Interrupt Request 0
    rjmp PCINT1_vect         ; PCINT1_vect - Pin Change Interrupt Request 1
    rjmp WDT_vect            ; Watchdog Time-out Interrupt
    reti                     ; TIMER1_Capt
    reti                     ; TIMER1_COMPA_vect - Timer/Counter1 Compare Match A
    reti                     ; TIMER1_COMPB_vect - Timer/Counter1 Compare Match B
    reti                     ; TIMER1_OVF_vect - Timer/Counter1 Overflow
    rjmp TIMER0_COMPA_vect   ; TIMER0_COMPA - Timer/Counter0 Compare Match A
    reti                     ; TIMER0_COMPB - Timer/Counter0 Compare Match B
    reti                     ; TIMER0_OVF_vect - Timer/Counter0 Overflow
    reti                     ; ANA_COMP_vect - Analog Comparator
    reti                     ; ADC_vect - ADC Conversion Complete
    reti                     ; EEPROM_READY_vect - EEPROM Ready
    reti                     ; USI_START_vect - USI Start Condition
    reti                     ; USI_OVF_vect - USI Overflow

WDT_vect:
    SAVE_SREG_TMP
    push xh
    push xl

    ldi TMP, (1 << WDIE) | (1 << WDP3) | (1 << WDP0) ; kazdych 8s se probudime
    out _SFR_IO_ADDR(WDTCSR), TMP
    
    ; inkrementujeme WDT counter
    ldi xl, lo8(var_wdt_cnt)
    ldi xh, hi8(var_wdt_cnt)
    ld TMP, x
    inc TMP
    cpi TMP, MAX_WDT_COUNT
    brne WDT_vect_end
    ori FLAGS, FLAG_WDT
    clr TMP
WDT_vect_end:
    st x, TMP
    pop xl
    pop xh
    LOAD_SREG_TMP
    reti

PCINT0_vect: ; update flags
    SAVE_SREG_TMP

    sbic _SFR_IO_ADDR(RCWL_PIN), RCWL_BIT
    ori FLAGS, FLAG_RCWL

    sbic _SFR_IO_ADDR(PIR_PIN), PIR_BIT
    ori FLAGS, FLAG_PIR

    LOAD_SREG_TMP
    reti

PCINT1_vect:                 ; Pouzito jen pro IRR In
    SAVE_SREG_TMP

    out _SFR_IO_ADDR(TCCR0A), ZERO
    ldi TMP, 2
    out _SFR_IO_ADDR(TCCR0A), TMP   ; WGM01 = 2
    out _SFR_IO_ADDR(TCCR0B), TMP   ; CS01 = 2
    out _SFR_IO_ADDR(TIMSK0), TMP   ; OCIE0A = 2 - compare interrupt enable
    ldi TMP, 62
    out _SFR_IO_ADDR(OCR0A), TMP    ; 1/8 bitu
    out _SFR_IO_ADDR(TCNT0), ZERO   ; vynuluj casovac
    clr TICKS

    LOAD_SREG_TMP
    reti

TIMER0_COMPA_vect:
    SAVE_SREG_TMP
    push xh
    push xl

    inc TICKS
    andi TICKS, 7            ; modulo 8
    cpi TICKS, 4             ; cteme uprostred bitu
    brne TIM0_COMPA_vect_end

    ; cteme UART
    clc
    sbic _SFR_IO_ADDR(IRR_PIN), IRR_BIT
    sec                      ; pripravime si posledni bit
    rol UART_BYTE_D          ; posledni bit je ten pripraveny
    rol UART_BYTE_C
    rol UART_BYTE_B
    rol UART_BYTE_A

    ; test_start_symbol
    ldi xl, lo8(start_symbol)
    ldi xh, hi8(start_symbol)   
    ld TMP, x+
    cp TMP, UART_BYTE_A
    brne TIM0_COMPA_vect_end
    ld TMP, x+
    cp TMP, UART_BYTE_B
    brne TIM0_COMPA_vect_end
    ld TMP, x+
    cp TMP, UART_BYTE_C
    brne TIM0_COMPA_vect_end
    ld TMP, x
    cp TMP, UART_BYTE_D
    brne TIM0_COMPA_vect_end

start_symbol_found:
    rjmp bootloader         ; no return

TIM0_COMPA_vect_end:
    pop xl
    pop xh
    LOAD_SREG_TMP
    reti

main:
    cli
    wdr
    clr ZERO

    DEBUG_LED_OFF

    ; nastaveni watchdogu
    out _SFR_IO_ADDR(MCUSR), ZERO
    ldi TMP, (1 << WDCE) | (1 << WDE)
    ldi TMP2, (1 << WDIE) | (1 << WDP3) | (1 << WDP0) ; kazdych 8s se probudime
    out _SFR_IO_ADDR(WDTCSR), TMP
    out _SFR_IO_ADDR(WDTCSR), TMP2
    ; ldi TMP, MAX_WDT_COUNT
    ; mov WDT_COUNTER, TMP
    wdr

    ; inicializace zasobniku
    ldi TMP, hi8(RAMEND)
    out _SFR_IO_ADDR(SPH), TMP
    ldi TMP, lo8(RAMEND)
    out _SFR_IO_ADDR(SPL), TMP

    ; precteme si data z EEPROM
    out _SFR_IO_ADDR(EEARH), ZERO
    ldi xl, lo8(start_symbol)
    ldi xh, hi8(start_symbol)
    clr CNT
read_eeprom:
    out _SFR_IO_ADDR(EEARL), CNT
    sbi _SFR_IO_ADDR(EECR), EERE  ; read byte from EEPROM
    in TMP, _SFR_IO_ADDR(EEDR)
    st x+, TMP
    inc CNT
    ldi TMP, 5
    cp CNT, TMP                    ; precteme <0-4>
    brne read_eeprom

    GPIO_SETUP

    ldi yl, lo8(var_msg_id)
    ldi yh, hi8(var_msg_id)
    st y+, ZERO                     ; msg_id := 0
    st y+, ZERO                     ; msg_wdt_counter := 0

    sei

main_loop:
    tst FLAGS                       ; changed from interrupts
    breq main_loop

    wdr

    cli

    ; pripravime zpravu
    ldi yl, lo8(sensor_id)
    ldi yh, hi8(sensor_id)
    ld TMP, y+
    st y+, TMP              ; ulozime msg_sensor_id

    ldi xl, lo8(var_msg_id)
    ldi xh, hi8(var_msg_id)
    ld TMP, x               ; nacteme aktualni var_msg_id
    inc TMP
    st x+, TMP              ; ulozime zvysenou hodnotu MSG ID, &x == var_wdt_cnt

    st y+, TMP              ; a vlozime msg_id do zpravy
    st y+, ZERO             ; TODO: msg_vcc
    st y+, ZERO             ; TODO: msg_vcc
    st y+, ZERO             ; TODO: msg_temperature
    st y+, ZERO             ; TODO: msg_temperature
    st y+, ZERO             ; TODO: msg_humidity
    st y+, ZERO             ; TODO: msg_humidity
    st y+, FLAGS            ; msg_flags
    ldi TMP, FW_VERSION
    st y+, TMP              ; msg_version

    ld TMP, x+              ; var_wdt_cnt
    st y+, TMP              ; msg_wdt_counter

    ldi r24, lo8(message)
    ldi r25, hi8(message)
    rcall speck_encrypt

    ldi r24, lo8(message+8)
    ldi r25, hi8(message+8)
    rcall speck_encrypt

    ldi r24, lo8(message)
    ldi r25, hi8(message)
    ldi r22, 16
    rcall rf_send

    clr FLAGS
    
    sei

    ; !!! TODO: sleep
    rjmp main_loop

bootloader:
    ldi r30, 0x00
    ldi r31, 0x1D
    ijmp

debug_loop:
    DEBUG_LED_ON
    rjmp debug_loop

.data

; start_symbol a sensor_id musi zustat za sebou - ctou se postupne s EEPPROM
start_symbol:             .skip 4
sensor_id:                .skip 1

message:
    msg_sensor_id:        .skip 1
    msg_id:               .skip 1
    msg_vcc:              .skip 2
    msg_temperature:      .skip 2
    msg_humidity:         .skip 2
    msg_flags:            .skip 1
    msg_version:          .skip 1
    msg_wdt_counter:      .skip 1
    dummy:                .skip 5

var_msg_id:               .skip 1
var_wdt_cnt:              .skip 1
