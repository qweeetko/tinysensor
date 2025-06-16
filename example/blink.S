.global main

#include <avr/io.h>

main:
    rjmp start

start:
    cli
    sbi _SFR_IO_ADDR(DDRB), 1
    ldi r24, 30

loop:        
    sbi _SFR_IO_ADDR(PORTB), 1
    rcall delay
    cbi _SFR_IO_ADDR(PORTB), 1
    rcall delay
    dec r24
    brne loop

    ldi  r30, 0x00
    ldi  r31, 0x1D
    ijmp

delay:
    ldi  r18, 4
    ldi  r19, 43
    ldi  r20, 0
L1: dec  r20
    brne L1
    dec  r19
    brne L1
    dec  r18
    brne L1
    lpm
    ret
