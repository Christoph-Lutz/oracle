# Purpose:
#   Enable and disable the following lgwr features on-demand,
#   as needed:
#     - Log Parallelism (Public Redo Strands)
#     - Fast Log File Sync (Fast Sync)
#     - Adaptive Scalable LGWR (multiple LG Worker Processes)
#
#   The script provides a bunch of gdb commands that modify
#   various sga variables, causing Oracle to enable or disable
#   lgwr features as needed.
#
# Author:
#   Christoph Lutz
#
# Date:
#   Jul-21 2025
#
# Usage:
#   gdb -q -x lgwr-control.gdb -p <fg_pid>
# 
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2 (X8M-2)
#
# Notes:
#   This is dangerous and higly experimental, use at your own 
#   risk!

set pagination off
set confirm off

set $FAST_SYNC_SL_WRITE_COUNT_THRESH  = 128
set $FAST_SYNC_SL_WRITE_US_LO         = 10 
set $FAST_SYNC_SL_WRITE_US_HI         = 101 

# Addresses can (and will) change between RUs!
set $KCRFWSLV_ALL                     = 0x600222c0
set $KCRFWSLV_ALL_PRV                 = 0x60022298
set $KCRFWSLV_GROUP0                  = 0x600222b8
set $KCRFWSLV_RW                      = 0x600222e0
set $KCRFWSLV_RW_AVG                  = 0x600222b0
set $KCRFWSLV_LGWR_MODE               = 0x6002200c
set $KCRFWSLV_ARBITER                 = 0x600222ac
set $KCRFWSLV_MAX_LOG_WRITE_PAR       = 0x60022274
set $KCRFWSLV_SWITCH_THRESH           = 0x600222d8
set $KCRFWSLV_REDORATE                = 0x600222d0
set $KCRFWSLV_SAMPLING_COUNT_PRM      = 128

define set_max_log_write_parallelism
    if ! $argc 
        printf "  target parallelism not supplied, no action!\n"
    else
        printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR   
        printf "  changing max log write parallelism to: %u\n", $arg0
        set *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR = $arg0
        printf "  changed max log write parallelism to: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR
    end
end

define set_fs_sl_write_time
    printf "  fast sync sl write time threshold is: %u us\n", (uint32_t) kspasv4_

    if (uint32_t) kspasv90_ < $FAST_SYNC_SL_WRITE_COUNT_THRESH
        printf "  fast sync sl write count < %u\n", $FAST_SYNC_SL_WRITE_COUNT_THRESH 
        printf "  changing fast sync sl write count to: %u\n", $FAST_SYNC_SL_WRITE_COUNT_THRESH
        set *(uint32_t) &kspasv90_ = $FAST_SYNC_SL_WRITE_COUNT_THRESH
    else
        printf "  fast sync sl write count > %u\n",  $FAST_SYNC_SL_WRITE_COUNT_THRESH
    end

    printf "  changing fast sync sl write time to: %u us\n", $arg0
    set *(uint32_t) &kspasv3_ = ($arg0 * 1000)

    printf "  changed fast sync sl write time to: %u us\n", ((uint32_t) kspasv3_ / 1000)

    if *(uint32_t *) $KCRFWSLV_LGWR_MODE > 0
        printf "  lgwr mode is parallel\n"
    else
        printf "  lgwr mode is serial\n"
    end

    printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR 
end

define enable_redo_strands
    printf "\n"
    printf "----- Enabling All Redo Strands -----\n"
    printf "  max number of redo strands is: %u\n", (uint32_t) kcrf_max_strands_
    printf "  number of active redo strands is: %u\n", (uint32_t) kcrf_actv_strands_
    printf "  enabling all redo strands ...\n"
    set *(uint32_t*) &kcrf_actv_strands_ = (uint32_t) kcrf_max_strands_
    printf "  number of active redo strands is: %u\n", (uint32_t) kcrf_actv_strands_
    printf "\n"
end

define disable_redo_strands
    printf "\n"
    printf "----- Disabling All Redo Strands -----\n"
    printf "  max number of redo strands is: %u\n", (uint32_t) kcrf_max_strands_
    printf "  number of active redo strands is: %u\n", (uint32_t) kcrf_actv_strands_
    printf "  disabling all redo strands ...\n"
    set *(uint32_t*) &kcrf_actv_strands_ = 1
    printf "  number of active redo strands is: %u\n", (uint32_t) kcrf_actv_strands_
    printf "\n"
end

define enable_fast_sync
    printf "\n"
    printf "----- Enabling Fast Sync -----\n"
    printf "  using default low fast sync sl write time: %u us\n", $FAST_SYNC_SL_WRITE_US_LO
    set_fs_sl_write_time $FAST_SYNC_SL_WRITE_US_LO
    printf "\n"
end

define disable_fast_sync
    printf "\n"
    printf "----- Disabling Fast Sync -----\n"
    printf "  using default high fast sync sl write time: %u us\n", $FAST_SYNC_SL_WRITE_US_HI
    set_fs_sl_write_time $FAST_SYNC_SL_WRITE_US_HI
    printf "\n"
end

define enable_lg_workers
    printf "\n"
    printf "----- Enabling LG workers -----\n"
    printf "  write count all is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
    printf "  write count all prev is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL_PRV
    printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR
    printf "  redorate is: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
    printf "  switch threshold is: %lu\n", *(uint64_t *) $KCRFWSLV_SWITCH_THRESH
    printf "  arbiter is: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER

    if *(uint32_t *) $KCRFWSLV_LGWR_MODE > 0
        printf "  lgwr mode is parallel, no action!\n"
    else
        printf "  lgwr mode is serial, enabling workers ...\n"

        if (*(uint64_t *) $KCRFWSLV_ALL - *(uint64_t *) $KCRFWSLV_ALL_PRV) < $KCRFWSLV_SAMPLING_COUNT_PRM
            printf "  changing write count to: %lu\n", (*(uint64_t *) $KCRFWSLV_ALL_PRV + $KCRFWSLV_SAMPLING_COUNT_PRM) 
            set *(uint64_t *) $KCRFWSLV_ALL = (*(uint64_t *) $KCRFWSLV_ALL_PRV + $KCRFWSLV_SAMPLING_COUNT_PRM)
            printf "  changed write count to: %u\n", *(uint64_t *) $KCRFWSLV_ALL
        end

        printf "  changing arbiter to: 1\n"
        set *(uint32_t *) $KCRFWSLV_ARBITER = 1
        printf "  changed arbiter to: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER

        if *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR == 1
            printf "  changing redorate to: (4 x switch threshold) + 1: %lu\n", (4 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            set *(uint64_t *) $KCRFWSLV_REDORATE = (4 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            printf "  changed redorate to: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
        else
            printf "  changing redorate to: (2 x switch threshold) + 1\n"
            set *(uint64_t *) $KCRFWSLV_REDORATE = (2 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            printf "  changed redorate to: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
        end
    end 
    printf "\n"
end

define disable_lg_workers
    printf "\n"
    printf "----- Disabling LG workers -----\n"
    printf "  write count all is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
    printf "  write count all prev is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL_PRV
    printf "  write count group0 is: %lu\n", *(uint64_t *) $KCRFWSLV_GROUP0
    printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR

    if *(uint32_t *) $KCRFWSLV_LGWR_MODE == 0
        printf "  lgwr mode is serial, no action!\n"
    else
        printf "  lgwr mode is parallel, disabling workers ...\n"

        # When switching from parallal to serial, the
        # all_prv counter is not reset. Therefore, the
        # write count detla can become negative, which
        # is why we need to cast this to int64.
        if ((int64_t) (*(uint64_t *) $KCRFWSLV_ALL - *(uint64_t *) $KCRFWSLV_ALL_PRV)) < 128
            printf "  changing write count to: %lu\n", (*(uint64_t *) $KCRFWSLV_ALL_PRV + 128)
            set *(uint64_t *) $KCRFWSLV_ALL = (*(uint64_t *) $KCRFWSLV_ALL_PRV + 128)
            printf "  changed write count to: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
        end

        printf "  changing arbiter to: 1\n"
        set *(uint32_t *) $KCRFWSLV_ARBITER = 1
        printf "  changed arbiter to: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER

        #printf "  changing write count all to group0: %lu\n", *(uint64_t *) $KCRFWSLV_GROUP0
        #set *(uint64_t *) $KCRFWSLV_ALL = *(uint64_t *) $KCRFWSLV_GROUP0 
        #printf "  changed write count all to: %lu\n", *(uint64_t *) $KCRFWSLV_ALL

        printf "  changing group0 write count to write count all: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
        set *(uint64_t *) $KCRFWSLV_GROUP0 = *(uint64_t *) $KCRFWSLV_ALL
        printf "  changed write count group0 to: %lu\n", *(uint64_t *) $KCRFWSLV_GROUP0


        printf "  changing redo write time to redo write time avg: %u\n", *(uint32_t *) $KCRFWSLV_RW_AVG
        set *(uint32_t *) $KCRFWSLV_RW = *(uint32_t *) $KCRFWSLV_RW_AVG
        printf "  changed redo write time to redo write time avg: %u\n", *(uint32_t *) $KCRFWSLV_RW
    end
    printf "\n"
end
    
document set_max_log_write_parallelism
Set the max_log_write_parallelism in kcrf_slave_info_ to a given value. 
Usage: set_max_log_write_parallelism <new_parallelism>
end

document set_fs_sl_write_time
Set the fast sync write_time to a given value (in us)
Usage: set_fs_sl_write_time <write_time_us>
end

document enable_redo_strands
Enable all public redo strands (set kcrf_actv_strands_ = kcrf_max_strands).
Usage: enable_redo_strands
end

document disable_redo_strands
Disable all public redo strands, except one (set kcrf_actv_strands = 1).
Usage: disable_redo_strands
end

document enable_fast_sync 
Helper function to enable fast sync (using a default sl_write_time value).
Usage: enable_fast_sync
end

document disable_fast_sync
Helper function to disable fast sync (using a default sl_write_time value).
Usage: disable_fast_sync
end

document enable_lg_workers
Enable lg worker processes (adaptive scalable lgwr)
Usage: enable_lg_workers
end

document disable_lg_workers
Disable lg worker processes (adaptive scalable lgwr)
Usage: disable_lg_workers
end
