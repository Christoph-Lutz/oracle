/*
 * Purpose:
 *   Demonstrate how Oracle uses the ksmg_sga_sz and 
 *   ksmg_gran_sz arrays to determine the granule size 
 *   for a given sga size.
 *
 * Date:
 *   May-01 2026
 *
 * Author:
 *   Christoph Lutz
 *
 * Program:
 *   sga-sz-gran-sz-mapping.c
 *
 * Compile:
 *   gcc -o sga-sz-gran-sz-mapping sga-sz-gran-sz-mapping.c 
 *
 * Usage:
 *   The program will print the sga-size-to 
 *   granule-size mapping by default. When
 *   the "examples" option is supplied, it 
 *   will additionally perform some example
 *   calculations:
 *
 *     ./sga-sz-gran-sz-mapping ["examples"]?
 *
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>

/* granule size lookup table */
uint64_t ksmg_gran_sz[] = {
    1ULL << 29,  /* 512M */
    1ULL << 28,  /* 256M */
    1ULL << 27,  /* 128M */
    1ULL << 26,  /*  64M */
    1ULL << 25,  /*  32M */
    1ULL << 24,  /*  16M */
    1ULL << 22,  /*   4M */
    0ULL
};

/* sga size threshold array */
uint64_t ksmg_sga_sz[] = {
    1ULL << 37,  /* 128G */
    1ULL << 36,  /*  64G */
    1ULL << 35,  /*  32G */
    1ULL << 34,  /*  16G */
    1ULL << 33,  /*   8G */
    1ULL << 30,  /*   1G */
    1ULL,
    0ULL
};

static void print_granule_mapping(void)
{
    printf("\n%-5s %-15s %-15s\n", "Idx", "SGA Threshold", "Granule Size");
    printf("---   -------------   ------------\n");

    for (int i = 0; ksmg_sga_sz[i] != 0; i++) {

        uint64_t gb = ksmg_sga_sz[i]  / (1<<30);
        uint64_t mb = ksmg_gran_sz[i] / (1<<20);

        if(ksmg_sga_sz[i] != 1) {
            printf("%-5d %8s %3lluG %13lluM\n", i, ">", gb, mb);
        } else {
            printf("%-5d %8s %3lluG %13lluM\n", i, "<", 1, mb);
        }
    }

    printf("\n");
}

static uint64_t get_granule_size(uint64_t sga_sz)
{
    int i = 0;

    while (ksmg_sga_sz[i] != 0 &&
           sga_sz <= ksmg_sga_sz[i])
    {
        i++;
    }

    return ksmg_gran_sz[i];
}

int main(int argc, char *argv[])
{
    print_granule_mapping();

    /* Print a bunch of examples if specified */
    if (argc > 1 && strncmp(argv[1], "examples", 8) == 0) {

        uint64_t test_sizes[] = {
            512ULL << 30,
            64ULL << 30,
            10ULL << 30,
            1ULL << 30,
            512ULL << 20
        };

        printf("Examples:\n");
        printf("---------\n");

        int n = sizeof(test_sizes) / sizeof(test_sizes[0]);

        for (int i = 0; i < n; i++) {
            uint64_t sga = test_sizes[i];
            uint64_t gran = get_granule_size(sga);

            printf("SGA size: %lluM (%lluG)\n", (sga / (1<<20)), (sga / (1<<30)));

            printf("-> granule size: %lluM\n\n", (gran / (1<<20)));
        }
    }

    return 0;
}
