/*
 * Program:
 *  lost_write.c
 *
 * Author:
 *   Christoph Lutz
 *
 * Date:
 *  Jun-23, 2021
 *
 * Purpose:
 *   This program interposes pwrite64 calls
 *   to simulate lost writes.
 *
 * Notes:
 *   This program is very dangerous, use it at
 *   your own risk!
 *   The program only works when the Oracle instance
 *   uses sync I/O (filesystemio_options=direct or
 *   filesystemio=none).
 *
 * Compilation:
 *  gcc -o lost_write.so -fPIC lost_write.c -shared -ldl
 *
 * Usage:
 *  1. Add $PWD/lost_write.so to /etc/ld.so.preload
 *     (this is needed because the oracle binary is
 *     setuid, which is why setting the LD_PRELOAD
 *     environment vairable will not work).
 *  2. Configure Oracle to use sync I/O
 *     (set filesystemio_options=direct or
 *     filesystemio_options=none)
 *  3. Restart the Oracle instance
 *  4. Add a lost write config to the lost
 *     write config file '/tmp/lost_write.cfg'.
 *     For every write you want to lose, add
 *     a line in the following format to the
 *     config file:
 *     <datafile>,<block_no>,<block_size>
 */

#define _GNU_SOURCE
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <errno.h>
#include <time.h>
#include <limits.h>

#define STR_BUFLEN 512
#define MAX_LOST_WRITES 32
#define LOG_FILE "/tmp/lost_write.log"
#define CFG_FILE "/tmp/lost_write.cfg"

struct
lost_write_dba {
    char datafile[PATH_MAX];
    int block;
    int block_size;
};

int
parse_cfg(struct lost_write_dba *lw_dbas) {
    FILE *f;
    char *str;
    char line[STR_BUFLEN] = {0};
    int line_no = 0;

    f = fopen(CFG_FILE, "r");
    if(f == NULL) {
      return -1;
    }

    while(fgets(line, STR_BUFLEN, f) != NULL
      && line_no < MAX_LOST_WRITES) {

        /* Parse datafile portion */
        str = strtok(line, ",");
        if(str == NULL) {
            return -1;
        }
        /* Ignore comment lines */
        if(str[0] == '#') {
            continue;
        }
        strncpy(lw_dbas[line_no].datafile, str, strlen(str));

        /* Parse block portion */
        str = strtok(NULL, ",");
        if(str == NULL) {
            return -1;
        }
        lw_dbas[line_no].block = atoi(str);

        /* Parse blcok_size protion */
        str = strtok(NULL, ",");
        if(str == NULL) {
            return -1;
        }
        lw_dbas[line_no].block_size = atoi(str);

        line_no++;
    }

    fclose(f);
    return line_no;
}

struct lost_write_dba *
lose_write(char *df, off_t offset, struct lost_write_dba *lw_dbas, int lw_dbas_len) {
    char *lw_df;
    int lw_block;
    int lw_block_size;
    off_t lw_offset;

    int i;
    for(i=0; i<lw_dbas_len; i++) {
        lw_df = lw_dbas[i].datafile;
        lw_block = lw_dbas[i].block;
        lw_block_size = lw_dbas[i].block_size;
        lw_offset = (off_t) (lw_block * lw_block_size);

        if(strncmp(df, lw_df, strlen(df)) == 0 && offset == lw_offset) {
            return &lw_dbas[i];
        }
    }

    return NULL;
}

ssize_t
pwrite64(int fd, const void *buf, size_t count, off_t offset) {
    pid_t pid;
    char *str;
    int log_fd;
    int lost_writes;
    char log_buf[STR_BUFLEN] = {0};
    char line_buf[STR_BUFLEN] = {0};
    char fd_link[PATH_MAX] = {0};
    char datafile[PATH_MAX] = {0};
    struct lost_write_dba *lw_dba;
    struct lost_write_dba lw_dbas[MAX_LOST_WRITES] = {{0}};


    /* Function pointer to point to original libc 'pwrite64' */
    static int (*pwrite64_orig)();

    /* Get symaddr of the original 'pwrite64' libc function */
    if(!pwrite64_orig)
        pwrite64_orig = (int (*)()) dlsym(RTLD_NEXT, "pwrite64");

    pid = getpid();

    /* Open the log file */
    log_fd = open(LOG_FILE, O_RDWR|O_CREAT|O_APPEND, S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP);
    if(log_fd == -1) {
        goto cont_orig;
    }

    /* Parse the lost write configuration file */
    lost_writes = parse_cfg(lw_dbas);
    if(lost_writes == -1) {
        snprintf(log_buf, STR_BUFLEN, "Pid %d: ERROR: Failed to parse config file.\n", pid);
        write(log_fd, log_buf, strlen(log_buf));
        goto cont_orig;
    }

    /* Verbose output. Uncomment if needed */
    /*
    int i=0;
    for(i=0; i<lost_writes; i++) {
        snprintf(log_buf, STR_BUFLEN, "Pid %d: INFO: datafile=%s, block=%d, block_size=%d\n",
          pid, lw_dbas[i].datafile, lw_dbas[i].block, lw_dbas[i].block_size);
        write(log_fd, log_buf, strlen(log_buf));
    }
    */

    /* Get filename from file descriptor */
    snprintf(fd_link, PATH_MAX, "/proc/self/fd/%d", fd);
    readlink(fd_link, datafile, PATH_MAX);

    /* Check if the write will be lost and log a message to the log, if yes */
    lw_dba = lose_write(datafile, offset, lw_dbas, lost_writes);
    if(lw_dba) {
        snprintf(log_buf, STR_BUFLEN, "Pid %d: losing block %d on write of datafile %s\n",
          pid, lw_dba->block, datafile);
        write(log_fd, log_buf, strlen(log_buf));
        close(log_fd);
        return count;
    }

    cont_orig:
    return pwrite64_orig(fd, buf, count, offset);
}