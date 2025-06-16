# Sensor for ATTINY84 with Data Transmission, Reception, and OTA Bootloader

## Hardware

- **ATTINY84A**
- **RF433 Transmitter** (e.g., FS1000A)
- **IR Receiver** (e.g., IRM-3638T)

## Communication

Data transmission and reception use an oversampled UART protocol from the RadioHead library (formerly known as VirtualWire).  
A key technique is the conversion of 4-bit data into a 6-bit format that frequently alternates between 0s and 1s. This ensures better signal integrity with low-cost RF433 or IR receivers.

- **Transmission**: Messages are encrypted using the [Speck cipher](https://www.cryptolux.org/index.php/FELICS) for security.
- **Reception**: Currently unencrypted, due to the limited range and physical nature of IR communication.

The sensor is designed for **battery-powered operation**.

---

## Project Structure

- **`bootloader.S`**  
  Contains the complete bootloader code. It is flashed once to the end of the ATTINY84’s flash memory. Future firmware updates are performed wirelessly through this bootloader.

- **`uploader`**  
  A PC-side tool for sending `.hex` firmware files to the bootloader. It communicates via an ESP32-C3, which transmits the data using an IR LED and the RMT peripheral.

- **`speck`**  
  Generates the encryption key used in sensor transmissions. The generated key is appended to the end of `encrypt.S`.

---

## EEPROM Layout

- **[0–3]**: START symbol for bootloader activation  
  Detected via UART input on the IR receiver. Once the START symbol is received, the device enters bootloader mode.  
  Multiple sensors can share the same START symbol, enabling simultaneous firmware broadcasting.

- **[4]**: Sensor ID

---

## Future Improvements

- Extend the bootloader to support **CTR mode** encryption using the Speck cipher.  
  Speck would serve as a pseudo-random block generator, XORed with the data stream for secure transmission.

---

## Installation

1. **Flash the bootloader**:
   ```sh
   make deploy
   ```
   This initializes the ATTINY84 in bootloader mode, allowing wireless updates via the IR interface.

2. **Upload a test program (e.g., blink)**:
   ```sh
   cd example
   make deploy
   ```
   The ATTINY84 should blink a few times, indicating successful upload and bootloader reactivation.

---

## Sensor Example Program

Located in `device/movement/`, this example integrates support for two optional motion sensors.  
It periodically sends an "alive" message. Upon detecting the bootloader START symbol, it automatically switches to bootloader mode.

---

## Wirings

```
                 .-----------------.
                 |    ATTINY84     |
             ----| 1  VCC    GND 14|---- 
   RF433 out ----| 2  PB0    PA0 13|---- PIR
   DEBUG led ----| 3  PB1    PA1 12|---- 
             ----| 4  RST    PA2 11|---- RCWL0516
       IR in ----| 5  PB2    PA3 10|---- 
             ----| 6  PA7    PA4  9|---- 
             ----| 7  PA6    PA5  8|---- 
                 '-----------------'
```
