#include <stdio.h>
#include <ihex.h>
#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

// ID=11: b8 1 ac e3
// avrdude -p t84a -c avrisp -P net:192.168.15.196:8080 -U eeprom:w:11,0xb8,1,0xac,0xe3:m

// ATTINY84

#define IR_AVR_UPLOADER_IP "192.168.15.197"
#define IR_AVR_UPLOADER_PORT 9999

#define PAGE_SIZE 64
#define PAGE_CNT 128

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static uint8_t start_symbol[4] = {};
static uint8_t data[PAGE_SIZE + 3 + 1];
static struct ihex_object *ihex;

uint8_t calc_crc(uint8_t crc, uint8_t data)
{
    uint8_t i;

    crc = crc ^ data;
    for (i = 0; i < 8; i++)
    {
        if (crc & 0x01)
            crc = (crc >> 1) ^ 0x8C;
        else
            crc >>= 1;
    }

    return crc;
}

void send_packet(uint8_t *data, int size)
{
    struct sockaddr_in server_addr;

    int sock = socket(AF_INET, SOCK_STREAM, 0);

    if (sock == -1)
    {
        perror("socket");
        exit(EXIT_FAILURE);
    }

    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(IR_AVR_UPLOADER_PORT); // cílový port
    if (inet_pton(AF_INET, IR_AVR_UPLOADER_IP, &server_addr.sin_addr) <= 0)
    {
        perror("inet_pton");
        close(sock);
        exit(EXIT_FAILURE);
    }

    if (connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0)
    {
        perror("connect");
        close(sock);
        exit(EXIT_FAILURE);
    }

    if (send(sock, start_symbol, 4, 0) < 0)
    {
        perror("send");
        close(sock);
        exit(EXIT_FAILURE);
    }

    if (send(sock, data, size, 0) < 0)
    {
        perror("send");
        close(sock);
        exit(EXIT_FAILURE);
    }

    close(sock);
}

int send_pages(uint8_t filled_pages)
{
    uint8_t pages_written = 0;

    for (uint16_t page = 0; page < PAGE_CNT; page++)
    {
        uint8_t crc = 0;
        uint16_t page_address = page * PAGE_SIZE;
        data[0] = page_address >> 8;
        crc = calc_crc(crc, data[0]);
        data[1] = page_address & 0xFF;
        crc = calc_crc(crc, data[1]);
        data[2] = filled_pages - pages_written;
        crc = calc_crc(crc, data[2]);

        ihex_get_data(ihex, page * PAGE_SIZE, data + 3, PAGE_SIZE);
        uint8_t empty = 0, full = 0xFF;
        for (int i = 3; i < PAGE_SIZE + 3; i++)
        {
            empty |= data[i];
            full &= data[i];
            crc = calc_crc(crc, data[i]);
        }
        data[PAGE_SIZE + 3] = crc;

        if (empty > 0 && full < 0xFF)
        {
            pages_written++;
            if (filled_pages)
            {
                printf("writing page %X: ", page);
                for (int i = 0; i < sizeof(data); i++)
                    printf("%02X ", data[i]);
                printf("\n");
                send_packet(data, sizeof(data));
                usleep(50000);
            }
        }
    }

    return pages_written;
}

int main(int argc, char *argv[])
{
    if (argc != 2 || strlen(argv[1]) != 4)
    {
        printf("uploader ABCD, where ABCD are 4 characters of START symbol.\n");
        exit(1);
    }

    memcpy(start_symbol, argv[1], 4);
    send_packet(start_symbol, 4);
    sleep(2);

    // bootloader START symbol - 'F'lash 'U'pdate - na pevno v bootloaderu
    start_symbol[0] = 0xCC; // synchron
    start_symbol[1] = 0xCC; // synchron
    start_symbol[2] = 'F';
    start_symbol[3] = 'U';

    ihex = ihex_new();

    FILE *fp;
    fp = stdin;
    ihex_parse_file(ihex, fp);
    fclose(fp);

    uint8_t filled_pages = send_pages(0);
    printf("Pages to send: %d\n", filled_pages);
    send_pages(filled_pages);

    ihex_delete(ihex);

    return 0;
}