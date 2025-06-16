START=ABCD

CPU=attiny84

all: blink.hex

blink.elf: blink.S
	avr-gcc -mmcu=attiny84 -Os -I.. -o blink.elf blink.S 

%.hex: %.elf
	avr-objcopy -O ihex blink.elf blink.hex

deploy: blink.hex
	cat blink.hex | ../uploader/build/uploader $(START)

clean:
	rm -f *.elf *.hex *.bin *.owl *.o *.dump
