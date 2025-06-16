#define PC

#include <stdint.h>
#include <stdio.h>
#include "cipher.h"
#include "constants.h"

// Klic - nahodnych 3 x 32 bitu = 96 bitu = 12 bytu
// Round key - number of rounds * 4 = 104
int main()
{
    RAM_DATA_BYTE state[] = "AABBCCDD";   // 8 bytu se koduje
    RAM_DATA_BYTE key[] = "ESPCKOJEC00L"; // pouzije se jen 12 bytu
    RAM_DATA_BYTE roundKeys[ROUND_KEYS_SIZE];

    RunEncryptionKeySchedule(key, roundKeys);

    printf("static const uint8_t roundKeys[] = {");
    char delim = ' ';
    for (int i = 0; i < ROUND_KEYS_SIZE; ++i)
    {
        if (i % 26 == 0)
            printf("\n");
        printf("%c0x%x", delim, roundKeys[i]);
        delim = ',';
    }
    printf("}; \n");

    // Test
    printf("%s\n", (const char *)state);
    Encrypt(state, roundKeys);
    for (int i = 0; i < 8; i++)
    {
        printf("%x ", state[i]);
    }
    printf("\n");
    Decrypt(state, roundKeys);
    printf("%s\n", (const char *)state);

    uint8_t x[] = {0x27, 0xD9, 0x92, 0xD4, 0x36, 0xCA, 0x4D, 0x0B, 0};
    Decrypt(x, roundKeys);
    for (int i = 0; i < 8; i++)
    {
        printf("%x ", x[i]);
    }
    

    /*
        I (9008988) RECVDBG: Data: 0A 27 D9 92 D4 36 CA 4D 0B C7
    I (9009068) RH_ASK: recv:
    I (9009068) LOG_HEX: Data: 10 8C 41 41 42 42 27 27
    I (9009068) RHASKSRV: RF433: publishing to topic:rf/16/140
    I (9009068) MQTT: MQTT event
    */
    return 0;
}
