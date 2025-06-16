EEPROM=0x41,0x42,0x43,0x44,0x11
PORT=/dev/ttyUSB0

CPU=attiny84

all: bootloader.hex eeprom.hex

bootloader.elf: bootloader.S
	avr-gcc -g -mmcu=attiny84 -O0 -Xassembler --gdwarf-2 -nostartfiles -nodefaultlibs -nostdlib -o bootloader.elf bootloader.S
	avr-objdump -d $@ >$@.dump
	avr-size -C --mcu=$(CPU) $@

eeprom.elf: eeprom.c eeprom.S
	avr-gcc -g -mmcu=attiny84 -Os -o $@ eeprom.c eeprom.S
	avr-objdump -d $@ >$@.dump
	avr-size -C --mcu=$(CPU) $@

bootloader.hex: bootloader.elf
	avr-objcopy -O ihex --gap-fill=0xFF $< x.tmp 
	cat x.tmp | grep -v '00000000000000000000000000000000000' >$@
	rm x.tmp

eeprom.hex: eeprom.elf
	avr-objcopy -O ihex --gap-fill=0xFF $< $@
	
%.bin: %.elf
	avr-objcopy -O binary --gap-fill=0xFF $< $@

deploy: bootloader.hex eeprom.hex
	avrdude -p t84a -c avrisp -P $(PORT) -U flash:w:bootloader.hex:i
	avrdude -p t84a -c avrisp -P $(PORT) -U eeprom:w:$(EEPROM):m

clean:
	rm -f *.elf *.hex *.bin *.o *.dump
