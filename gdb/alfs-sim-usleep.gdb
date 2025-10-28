# Purpose:
#   Manually modify rw_avg and the bcast_avg metrics
#   to test how Oracle changes the usleep time in 
#   Adaptive Log File Sync (ALFS) polling mode.
#
# Author:
#   Christoph Lutz
#
# Date:
#   Aug-15 2025
#
# Usage:
#   gdb                                  \
#   -ex 'set $p_rw_avg = <rw_avg>'       \
#   -ex 'set $p_bcast_avg = <bcast_avg>' \
#   -ex 'set $p_lwn_scn = <adj>'         \
#   -x  alfs-sim-usleep.gdb              \
#   -p <pid>
#
#   Parameters:
#     p_rw_avg   : redo write average (us)
#     p_bcast_avg: broadcast on commit avg (us)
#     p_lwn_scn  : how to adjust the lwn scn
#                  ("lower", "equal", or "greater")
#
#   Example:
#     gdb                             \
#     -ex 'set $rw_avg = 1234'        \
#     -ex 'set $bcast_avg = 1234'     \
#     -ex 'set $lwn_scn = "lower"'   \
#     -x  alfs-sim-usleep.gdb         \
#     -p 1234 
#
# Important:
#   The breakpoints in this script will slow the 
#   FG down to the  extent that you also need to 
#   temporarily stop the lgwr process for the test, 
#   as otherwise the _log_file_sync_timeout check 
#   will find the on-disk scn has progressed so far 
#   that there is no more need for a poll/sleep.
# 
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2 (X8M-2)
#
# Notes:
#   This script is dangerous and higly experimental.
#   Use at your own risk!
#
# Background information:
#   Oracle computes the usleep (poll) time as 
#   follows, depending on whether or not the 
#   lwn scn is greater than the sync scn.
#
#    delay = max(rw_avg, bcast_avg)
#    aggressiveness = sched_delay * poll_aggressiveness/100
#
#    if lwn_scn > sync_scn
#      usleep = delay - aggressiveness - sleep_overhead
#
#    if lwn_scn <= sync_scn:
#      usleep = (delay * 2) - aggressiveness - sleep_overhead
#
#    delay:
#    Greater of rw_avg or bcast_avg
#
#    sched_delay:
#    Current scheduling delay
#
#    poll_aggressiveness:
#    _adaptive_log_file_sync_poll_aggressiveness 
#    (default: 0)
#
#    sleep_overhead:
#    Sleep overhead as determined on instance 
#    startup

set pagination off
set confirm off

# Defaults
set $RW_AVG_DEFAULT               = 1234
set $BCAST_AVG_DEFAULT            = 1234
set $LWN_SCN_DEFAULT             = "equal"

set $ALFS_POLL_AGGRESSIVENESS_PRM = 0

# Addresses can and will change across RUs!
set $ALFS_INFO_POLLING            = 0x60021f38
set $ALFS_INFO_RW_AVG             = 0x60021f88
set $ALFS_INFO_BCAST_AVG          = 0x60021f8c
set $ALFS_INFO_SCHED_DELAY        = 0x60021f78
set $ALFS_INFO_SLEEP_OH           = 0x60021f44

set $KCRF_FAST_SYNC               = 0x60021f1c

set $LWN_SCN_P                   = 0x0
set $SYNC_SCN_P                   = 0x0
set $IN_COMMIT                    = 0x0

# Conditional breakpoint (for 2nd invocation of
# kcrf_commit_force_int with arg1 set to 0x1)
# Note that the breakpoint is on offset +2,
# as this will allow using gdb and bpftrace
# at the same time.
break *kcrf_commit_force_int+2 if $rsi == 0x1
command 1
    if $rsi == 0x1
        set $IN_COMMIT = 1
        set $SYNC_SCN_P = (uint64_t) $rdi

        printf "***  Changing rw_avg to %u\n", $p_rw_avg
        set *(uint32_t *) $ALFS_INFO_RW_AVG = $p_rw_avg
        printf "***  Changed rw_avg to %u\n", *(uint32_t *) $ALFS_INFO_RW_AVG

        printf "***  Changing bcast_avg to %u\n", $p_bcast_avg
        set *(uint32_t *) $ALFS_INFO_BCAST_AVG = $p_bcast_avg
        printf "***  Changed bcast_avg to %u\n", *(uint32_t *) $ALFS_INFO_BCAST_AVG
    end
    continue
end

# Ret probes kcrf_commit_force_int
break *kcrf_commit_force_int+1301
break *kcrf_commit_force_int+3201
commands 2-3
    if $IN_COMMIT
        set $IN_COMMIT = 0
        printf "***  Done, exiting\n\n"
        quit
    end
    continue
end

break *kcscu8+2
command 4
   if $IN_COMMIT
       set $LWN_SCN_P = (uint64_t) $rsi
   end
   continue
end

# Ret probes kcscu8
break *kcscu8+59
break *kcscu8+117
break *kcscu8+175
break *kcscu8+194

commands 5-8
    if $IN_COMMIT && ! $LWN_SCN_P 
        printf "***  Error. LWN_SCN_P not set, aborting!\n"
    end

    if $IN_COMMIT && ! $ksccu8_called
        set $ksccu8_called = 1

        printf "***  lwn scn pointer is %p\n", $LWN_SCN_P
        printf "***  lwn scn is %p\n", *(uint64_t *) $LWN_SCN_P
        printf "***  sync sync pointer is %p\n", $SYNC_SCN_P
        printf "***  sync scn is %p\n", *(uint64_t *) $SYNC_SCN_P

        set $delay = (*(uint64_t *) $ALFS_INFO_RW_AVG < *(uint64_t *) $ALFS_INFO_BCAST_AVG) ? \
                      *(uint64_t *) $ALFS_INFO_BCAST_AVG                                    : \
                      *(uint64_t *) $ALFS_INFO_RW_AVG

        printf "***  delay is %u\n", $delay

        if (int32_t) strcmp($p_lwn_scn, "lower") == 0 && (*(uint64_t *) $LWN_SCN_P > *(uint64_t *) $SYNC_SCN_P)
            printf "***  decreasing lwn scn to %p\n", (*(uint64_t *) $SYNC_SCN_P) - 1
            set *(uint64_t *) $LWN_SCN_P = (*(uint64_t *) $SYNC_SCN_P) - 1
            printf "***  decreased lwn scn to %p\n", *(uint64_t *) $LWN_SCN_P
        end

        if (int32_t) strcmp($p_lwn_scn, "higher") == 0 && (*(uint64_t *) $LWN_SCN_P <= *(uint64_t *) $SYNC_SCN_P) 
            printf "***  increasing lwn scn to %p\n", (*(uint64_t *) $SYNC_SCN_P) + 1 
            set *(uint64_t *) $LWN_SCN_P = (*(uint64_t *) $SYNC_SCN_P) + 1
            printf "***  increased lwn scn to %p\n", *(uint64_t *) $LWN_SCN_P
        end

        if (int32_t) strcmp($p_lwn_scn, "equal") == 0 && (*(uint64_t *) $LWN_SCN_P != *(uint64_t *) $SYNC_SCN_P)
            printf "***  setting lwn scn to %p\n", *(uint64_t *) $SYNC_SCN_P
            set *(uint64_t *) $LWN_SCN_P = *(uint64_t *) $SYNC_SCN_P
            printf "***  set lwn scn to %p\n", *(uint64_t *) $LWN_SCN_P 
        end

        if *(uint64_t *) $LWN_SCN_P > *(uint64_t *) $SYNC_SCN_P
            printf "***  lwn scn > sync_scn\n"

            set $sleep_time = $delay - $ALFS_POLL_AGGRESSIVENESS_PRM - *(uint32_t *) $ALFS_INFO_SLEEP_OH

            printf "***  sleep_time = delay - aggressiveness_prm - sleep_overhead = %u - %u - %u = %u\n", \
                   $delay, $ALFS_POLL_AGGRESSIVENESS_PRM, *(uint32_t *) $ALFS_INFO_SLEEP_OH, $sleep_time
        end

        if *(uint64_t *) $LWN_SCN_P <= *(uint64_t *) $SYNC_SCN_P
            printf "***  lwn scn <= sync scn\n"

            set $sleep_time = ($delay * 2) - $ALFS_POLL_AGGRESSIVENESS_PRM - *(uint32_t *) $ALFS_INFO_SLEEP_OH

            printf "***  sleep_time = (delay * 2) - aggressiveness_prm - sleep_overhead = %u - %u - %u = %u\n", \
                   ($delay * 2), $ALFS_POLL_AGGRESSIVENESS_PRM, *(uint32_t *) $ALFS_INFO_SLEEP_OH, $sleep_time
        end
    end

    continue
end

break *nanosleep+2
command 9
    if $IN_COMMIT
        printf "*** nanosleep(): usleep = %u\n", *(uint64_t *) ($rdi + 0x8)
    end
    continue
end

printf "\n"
printf "----- Simulating ALFS usleep Time -----\n"
printf "***  Fast sync is %s\n", *(uint32_t *) $KCRF_FAST_SYNC > 0 ? "active" : "inactive"
printf "***  ALFS polling is %s\n", *(uint32_t *) $ALFS_INFO_POLLING > 0 ? "active" : "inactive"
printf "***  rw_avg is %u\n", *(uint32_t *) $ALFS_INFO_RW_AVG
printf "***  bcast_avg is %u\n", *(uint32_t *) $ALFS_INFO_BCAST_AVG
printf "***  sleep_overhead is %u\n", *(uint32_t *) $ALFS_INFO_SLEEP_OH

# Check preconditions
if *(uint32_t *) $KCRF_FAST_SYNC
    printf "***  No action, fast sync is active, aborting!\n"
    quit
end

if ! *(uint32_t *) $ALFS_INFO_POLLING
    printf "***  No action, ALFS polling is not active, aborting!\n"
    quit
end

# Check inputs
if ! $p_rw_avg
    printf "***  p_rw_avg not set, using default of %u\n", $RW_AVG_DEFAULT
    set $p_rw_avg = $RW_AVG_DEFAULT
else
    printf "***  p_rw_avg is %u\n", $p_rw_avg
end

if ! $p_bcast_avg
    printf "***  p_bcast_avg not set, using default of %u\n", $BCAST_AVG_DEFAULT
    set $p_bcast_avg = $BCAST_AVG_DEFAULT
else
    printf "***  p_bcast_avg is %u\n", $p_bcast_avg
end

if (int32_t) strcmp($p_lwn_scn, "") == 0
    printf "***  p_lwn_scn not set, using default of '%s'\n", $LWN_SCN_DEFAULT
    set $p_lwn_scn = $LWN_SCN_DEFAULT
else
    printf "***  p_lwn_scn is %s\n", $p_lwn_scn
end

printf "***  Ready. Stop lgwr and run a transaction now ...\n"

continue
