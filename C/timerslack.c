/*
 * Purpose:
 *   Show how nanosleep behaves with default and non-default 
 *   timerslack settings
 *
 * Date:
 *   Sep-17 2025
 *
 * Author:
 *   Christoph Lutz
 *
 * Program:
 *   timerslack.c
 *
 * Compile:
 *   gcc -o timerslack timerslack.c
 *
 * Usage:
 *   ./timerslack <sleep_us> [<slack_us>]
 *
 */

#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/prctl.h>

int main(int argc, char *argv[]) {
    struct timespec req, start, end;
    long timerslack = 0;
    long new_slack = 0;

    if (argc < 2 || argc > 3) {
        fprintf(stderr, "\nUsage: %s <sleep_us> [<slack_us>]\n\n", argv[0]);
        return 1;
    }

    long sleep_us = atol(argv[1]);
    if (sleep_us < 0) {
        fprintf(stderr, "Sleep us must be non-negative\n");
        return 1;
    }

    if(argc > 2) {
       new_slack = atol(argv[2]) * 1000; 
       fprintf(stdout, "Changing timerslack to %ld\n", new_slack);

       if (prctl(PR_SET_TIMERSLACK, new_slack) == -1) {
           perror("prctl(PR_SET_TIMERSLACK) failed");
           return 1;
        }
    }

    req.tv_sec = 0;
    req.tv_nsec = sleep_us * 1000; 

    timerslack = prctl(PR_GET_TIMERSLACK);
    if (timerslack == -1) {
        perror("prctl(PR_GET_TIMERSLACK) failed");
        return 1;
    }

    printf("%-10s %10s %10s\n", "Iteration", "Elapsed us", "Slack us");

    for (int i = 0; i < 10; i++) {
        if (clock_gettime(CLOCK_MONOTONIC, &start) != 0) {
            perror("clock_gettime start");
            return 1;
        }

        if (nanosleep(&req, NULL) != 0) {
            perror("nanosleep");
            return 1;
        }

        if (clock_gettime(CLOCK_MONOTONIC, &end) != 0) {
            perror("clock_gettime end");
            return 1;
        }

        long ela_ns = (end.tv_sec - start.tv_sec) * 1000000000L +
                          (end.tv_nsec - start.tv_nsec);

        printf("%-10d %10.3f %10u\n",i + 1, ela_ns / 1000.0, timerslack / 1000);
    }

    return 0;
}
