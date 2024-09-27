/*
 * Program:
 *  dba.c
 *
 * Date:
 *  May-08, 2021
 *
 * Author:
 *   Christoph Lutz
 *
 * Purpose:
 *   This program encodes and decodes an Oracle
 *   data block address (dba).
 *
 * Notes:
 *  This program was written for illustrative
 *  purposes only, use it at your own risk!
 *  It does not support encoding or decoding
 *  of Bigfile datafiles (encoding and decoding
 *  them is kind of a no-brainer).
 *
 * Compilation:
 *  gcc -o dba dba.c
 *
 * Usage:
 *  ./dba <value>
 *
 *  <value> can be any of the following:
 *    - dba in decimal or in hex
 *    - file,block combination
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <arpa/inet.h>

#define DBA_STR_LEN 40
#define FNO_BITS 22

#define FNO_MASK 0b11111111110000000000000000000000
#define BNO_MASK 0b00000000001111111111111111111111

void
usage(char *prog)
{
    printf("\nUsage: %s <value>\n\n", prog);
    printf("<value> can either be a dba or a file,block combination.\n\n");
    printf("Examples:\n");
    printf("  %s 15,139\n", prog);
    printf("  %s 15/139\n", prog);
    printf("  %s 62914699\n", prog);
    printf("  %s 0x03c0008b\n", prog);
    printf("\n");
}

int
str2int(char *str)
{
    return atoi(str);
}

int
hex2int(char *str)
{
    int dba = 0;

    if(str[0] == '0' && (str[1] == 'x' || str[1] == 'X')) {
        dba = (int) strtol(str, NULL, 0);
    }

    return dba;
}

int
encode_dba(char *str, char *delim)
{
    char *s;
    unsigned int dba = 0;
    unsigned fno = 0;
    unsigned bno = 0;

    /* Return zero dba if delim not found in str */
    if(strchr(str, delim[0]) == NULL) {
        return dba;
    }

    /* Parse file and block nr from str */
    s = strtok(str, delim);
    if(s == NULL) {
    }

    fno = atoi(s);
    if(fno == 0) {
        printf("ERROR: Invalid fno: %llu\n", fno);
        exit(EXIT_FAILURE);
    }

    s = strtok(NULL, delim);
    if(s == NULL) {
    }

    bno = atoi(s);
    if(bno == 0) {
        printf("ERROR: Invalid bno: %llu\n", bno);
        exit(EXIT_FAILURE);
    }

   /*
    * Set the file and block number bits in dba:
    *   - file nr:  leading 10 bits
    *   - block nr: trailing 22 bits
    */
   dba = (dba & ~FNO_MASK) | ((fno << FNO_BITS) & FNO_MASK);
   dba = (dba & ~BNO_MASK) | (bno & BNO_MASK);

   return dba;
}

int
dba2str(unsigned int dba, char *str)
{
    int fno = 0, bno = 0;

   /*
    * Extract the file and block number bits:
    *   - file nr:  leading 10 bits
    *   - block nr: trailing 22 bits
    */
    fno = (dba & FNO_MASK) >> FNO_BITS;
    bno = (dba & BNO_MASK);
    return snprintf(str, DBA_STR_LEN, "%llu,%llu\n", fno, bno);
}

/* Note: This assumes little endian! */
int
dba2bin(unsigned int dba, char *str)
{
    unsigned char *b = (unsigned char *) &dba;
    unsigned char byte;
    int i, j;
    size_t size = sizeof(unsigned int);

    for (i = size-1; i >= 0; i--) {
        for (j = 7; j >= 0; j--) {
            byte = (b[i] >> j) & 1;
            if(byte) {
                strncat(str, "1", 1);
            } else {
                strncat(str, "0", 1);
            }
        }
        strncat(str, " ", 1);
    }
}

void
print_dba(unsigned int dba)
{
    char dba_str[DBA_STR_LEN] = {0};
    char dba_bin[DBA_STR_LEN] = {0};
    char fno_bin[DBA_STR_LEN] = {0};
    char bno_bin[DBA_STR_LEN] = {0};

    dba2str(dba, dba_str);
    dba2bin(dba, dba_bin);
    dba2bin(FNO_MASK, fno_bin);
    dba2bin(BNO_MASK, bno_bin);

    printf("\n");
    printf("dba decimal         : %llu\n", dba);
    printf("dba hex             : 0x%x\n", dba);
    printf("dba binary          : %s\n", dba_bin);
    printf("file mask (binary)  : %s\n", fno_bin);
    printf("block mask (binary) : %s\n", bno_bin);
    printf("dba file,block      : %s\n", dba_str);
    printf("\n");
}

int
main(int argc, char *argv[])
{
    unsigned int dba = 0;
    char *input = argv[1];

    if(argc != 2) {
        usage(argv[0]);
        exit(EXIT_FAILURE);
    }

    printf("\nEncoding/decoding input: %s\n\n", input);
    if(dba = encode_dba(input, ",")) {
        print_dba(dba);
        return 0;
    }

    if(dba = encode_dba(input, "/")) {
        print_dba(dba);
        return 0;
    }

    if(dba = hex2int(input)) {
        print_dba(dba);
        return 0;
    }

    if(dba = str2int(input)) {
        print_dba(dba);
        return 0;
    }
}

