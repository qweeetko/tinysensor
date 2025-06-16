CPU=attiny84
BOOTSYM = ABCD

all: main.hex

main.elf: main.S sender.S encrypt.S
	avr-gcc -g -mmcu=attiny84 -O0 -nostartfiles -nodefaultlibs -nostdlib -o $@ main.S sender.S encrypt.S
	avr-objdump -d $@ >main.dump
	avr-size -C --mcu=$(CPU) $@

%.hex: %.elf
	avr-objcopy -O ihex $< $@

deploy: main.hex
	cat main.hex | ../../uploader/build/uploader $(BOOTSYM)

clean:
	rm -f *.elf *.hex *.bin *.owl *.o *.dump
