# Purpose:
#   Enable and disable the following lgwr features on-demand,
#   as needed:
#     - Log Parallelism (public redo strands)
#     - Fast Log File Sync (Fast Sync)
#     - Adaptive Scalable LGWR (multiple LG worker processes)
#
#   The script provides a bunch of gdb commands that modify
#   various sga variables, causing Oracle to enable or disable
#   these lgwr features as needed.
#
#   Note: to enable or disable the Adaptive Log File Sync (ALFS)
#   mechanism, refer to scripts alfs-enable-polling.gdb and
#   alfs-disable-polling.gdb.
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
#   Oracle 19.26 / Exadata 25.1.7
#
# Notes:
#   The script does not retrieve init.ora parameter values from 
#   SGA structures at runtime. Instead, it relies on predefined
#   defaults, which must be manually adjusted if necessary.
#
#   This script is dangerous and highly experimental, use at 
#   your own risk!

set pagination off
set confirm off

# Addresses can (and will) change between RUs!
set $KSBCPUEFFTHRCNT_STARTUP          = 0x600b9d68

set $ALFS_INFO_POLLING                = 0x60021f38
set $ALFS_INFO_ARBITER                = 0x60021f3c

set $FAST_SYNC_SL_WRITE_COUNT_THRESH  = 128
set $FAST_SYNC_SL_WRITE_US_LO         = 10 
set $FAST_SYNC_SL_WRITE_US_HI         = 101 

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
set $KCRFWSLV_STANDBY_MODE            = 0x60022010
set $KCRFWSLV_SAMPLING_COUNT_PRM      = 128

set $ALWE                             = (uint64_t) klassvp7_
set $ALWE_FLAGS                       = ($ALWE + 0x7c)
set $ALWE_NORMAL_PHASE_FLG            = 0x01
set $ALWE_EVAL_PHASE_FLG              = 0x02
set $ALWE_TRACE_FLG                   = 0x04
set $ALWE_TRACE_VERBOSE_FLG           = 0x08

set $OLRW                             = (uint64_t) klassvp8_ 
set $OLRW_ENABLED_FLG                 = 0x01 
set $OLRW_REMAPPED_FLG                = 0x02 
set $OLRW_THICK_MODE_FLG              = 0x04 
set $OLRW_REEVAL_FLG                  = 0x20

set $OLRW_TRACE_FLG                   = 0x08
set $OLRW_TRACE_VERBOSE_FLG           = 0x10

define show_lgwr_mode

    # Determine lgwr adaptive scalable mode
    set $adaptive_mode = (uint8_t) kcrf_slave_info_

    if ($adaptive_mode == 0)
        set $adaptive_mode_str = "disabled"
    end
   
    if ($adaptive_mode == 2)
        set $adaptive_mode_str = "heuristic"
    end 

    if ($adaptive_mode == 3)
        set $adaptive_mode_str = "evaluative"
    end

    # Determine alwe phase
    if (*(uint8_t *) $ALWE_FLAGS)
        set $alwe_str = "enabled"
    else
        set $alwe_str = "disabled"
    end

    if (*(uint8_t *) $ALWE_FLAGS & $ALWE_NORMAL_PHASE_FLG) 
        set $alwe_phase_str = "(phase: normal)"
    end

    if (*(uint8_t *) $ALWE_FLAGS & $ALWE_EVAL_PHASE_FLG)
        set $alwe_phase_str = "(phase: evaluation)"
    else
        set $alwe_phase_str = ""
    end

    # Determine olrw mode
    if ((*(uint8_t *) $OLRW & $OLRW_ENABLED_FLG))
        set $olrw_str = "enabled"
    else
        set $olrw_str = "disabled"
    end
    
    if ((*(uint8_t *) $OLRW & $OLRW_THICK_MODE_FLG))
        set $olrw_mode_str = "(mode: thick)"
    else
        set $olrw_mode_str = "(mode: thin)"
    end

    printf "\n"
    printf "----- Show LGWR mode -----\n"
    printf "  lgwr mode is                 : %s\n", *(uint32_t *) $KCRFWSLV_LGWR_MODE > 0 ? "parallel" : "serial"
    printf "  adaptive scalable mode is    : %s\n", $adaptive_mode_str
    printf "  alwe is                      : %s %s\n", $alwe_str, $alwe_phase_str
    printf "  olrw is                      : %s %s\n", $olrw_str, $olrw_mode_str
    printf "  kcrfwslv arbiter is          : %u\n", *(uint32_t *) $KCRFWSLV_ARBITER
    printf "  slave pool stdby mode is     : %s\n", *(uint32_t *) $KCRFWSLV_STANDBY_MODE > 0 ? "enabled" : "disabled"
    printf "  fast sync is                 : %s\n", (uint32_t) kcrf_fast_sync_ > 0 ? "enabled" : "disabled"
    printf "  alfs polling mode is         : %s\n", *(uint32_t *) $ALFS_INFO_POLLING > 0 ? "enabled" : "disabled"
    printf "  alfs arbiter is              : %u\n", *(uint32_t *) $ALFS_INFO_ARBITER
    printf "  max log write parallelism is : %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR
    printf "  nr of active redo strands is : %u\n", (uint32_t) kcrf_actv_strands_
    printf "  max nr of redo strands is    : %u\n", (uint32_t) kcrf_max_strands_
    printf "  cpu_count (startup) is       : %u\n", *(uint32_t *) $KSBCPUEFFTHRCNT_STARTUP
    printf "--------------------------\n"
    printf "\n"
end

define set_alfs_polling
    printf "\n"
    printf "----- Changing ALFS polling -----\n"
    if (! $argc || ($arg0 != 0 && $arg0 != 1))
        printf "  no or invalid value supplied, no action!\n"
    else 
        if *(uint32_t *) $ALFS_INFO_POLLING != $arg0
            printf "  alfs polling is: %u\n", *(uint32_t *) $ALFS_INFO_POLLING
            printf "  changing alfs polling to: %u\n", $arg0
            set *(uint32_t *) $ALFS_INFO_POLLING = $arg0
            printf "  changed alfs polling to: %u\n", *(uint32_t *) $ALFS_INFO_POLLING
        else
            printf "  alfs polling already set to: %u\n", $arg0
        end
    end
    printf "---------------------------------\n"
    printf "\n"
end

define set_max_log_write_parallelism
    printf "\n"
    printf "----- Changing max_log_write_parallelism -----\n"
    if (! $argc)
        printf "  target parallelism not supplied, no action!\n"
    else
        if *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR != $arg0
            printf "  max log write parallelism is         : %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR   
            printf "  changing max log write parallelism to: %u\n", $arg0
            set *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR = $arg0
            printf "  changed max log write parallelism to : %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR
        else
            printf "  max log write parallelism already set to: %u\n", $arg0
        end
    end
    printf "----------------------------------------------\n"
    printf "\n"
end

define set_redo_strands
    printf "\n"
    printf "----- Changing kcrf_actv_strands -----\n"
    if  (($arg0 > (int32_t) kcrf_max_strands_) || $arg0 < 1)
        printf "  no or invalid value supplied, no action!\n"
    else
        if ($argc && (uint32_t) kcrf_actv_strands_ != $arg0)
            printf "  max number of redo strands is        : %u\n", (uint32_t) kcrf_max_strands_
            printf "  number of active redo strands is     : %u\n", (uint32_t) kcrf_actv_strands_
            printf "  changing number of active strands to : %u \n", $arg0
            set *(uint32_t*) &kcrf_actv_strands_ = (uint32_t) $arg0
            printf "  changed number of active strands to  : %u\n", (uint32_t) kcrf_actv_strands_
        else
            if (uint32_t) kcrf_max_strands_ == $arg0
                printf "  kcrf_max_strands_ already set to: %u\n", $arg0
            end
        end
    end
    printf "--------------------------------------\n"
    printf "\n"
end

define enable_all_redo_strands
    set $strands = (uint32_t) kcrf_max_strands_
    set_redo_strands $strands
end

define disable_all_redo_strands 
    set_redo_strands 1
end

define _set_fs_sl_write_time
    printf "  fast sync sl write time threshold is: %u us\n", (uint32_t) kspasv4_

    if (uint32_t) kspasv90_ < $FAST_SYNC_SL_WRITE_COUNT_THRESH
        printf "  fast sync sl write count < %u\n", $FAST_SYNC_SL_WRITE_COUNT_THRESH 
        printf "  changing fast sync sl write count to: %u\n", $FAST_SYNC_SL_WRITE_COUNT_THRESH
        set *(uint32_t) &kspasv90_ = $FAST_SYNC_SL_WRITE_COUNT_THRESH
        printf "  changed fast sync sl write count to: %u\n", (uint32_t) kspasv90_ 
    else
        printf "  fast sync sl write count > %u\n",  $FAST_SYNC_SL_WRITE_COUNT_THRESH
    end

    printf "  changing fast sync sl write time to: %u us\n", $arg0
    set *(uint32_t) &kspasv3_ = ($arg0 * 1000)
    printf "  changed fast sync sl write time to: %u us\n", ((uint32_t) kspasv3_ / 1000)
    printf "  lgwr mode is: %s\n", (uint32_t *) $KCRFWSLV_LGWR_MODE > 0 ? "parallel" : "serial"
    printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR 
end

define enable_fast_sync
    printf "\n"
    printf "----- Enabling Fast Sync -----\n"
    printf "  using default low fast sync sl write time: %u us\n", $FAST_SYNC_SL_WRITE_US_LO
    _set_fs_sl_write_time $FAST_SYNC_SL_WRITE_US_LO
    printf "------------------------------\n"
    printf "\n"
end

define disable_fast_sync
    printf "\n"
    printf "----- Disabling Fast Sync -----\n"
    printf "  using default high fast sync sl write time: %u us\n", $FAST_SYNC_SL_WRITE_US_HI
    _set_fs_sl_write_time $FAST_SYNC_SL_WRITE_US_HI
    printf "-------------------------------\n"
    printf "\n"
end

define enable_lg_workers
    set $no_action = 0
    printf "\n"
    printf "----- Enabling LG workers -----\n"

    if (*(uint32_t *) $KCRFWSLV_LGWR_MODE > 0)
        set $no_action = 1
        printf "  lgwr mode is parallel, no action!\n"
    end
 
    if ((!$no_action) && ((uint32_t) kcrf_fast_sync_ > 0)) 
        set $no_action = 1
        printf "  Fast Sync is enabled, disable it first. No action!\n"
    end

    if ((!$no_action) && ((uint8_t) kcrf_slave_info_ != 2))
        set $no_action = 1
        printf "  Not in heuristic lgwr mode, no action!\"
    end

    if (!$no_action)
        printf "  lgwr mode is serial, enabling workers ...\n"
        printf "  write count all is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
        printf "  write count all prev is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL_PRV
        printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR
        printf "  redorate is: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
        printf "  switch threshold is: %lu\n", *(uint64_t *) $KCRFWSLV_SWITCH_THRESH
        printf "  arbiter is: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER
            
        if ((*(uint64_t *) $KCRFWSLV_ALL - *(uint64_t *) $KCRFWSLV_ALL_PRV) < $KCRFWSLV_SAMPLING_COUNT_PRM)
            printf "  changing write count to: %lu\n", (*(uint64_t *) $KCRFWSLV_ALL_PRV + $KCRFWSLV_SAMPLING_COUNT_PRM) 
            set *(uint64_t *) $KCRFWSLV_ALL = (*(uint64_t *) $KCRFWSLV_ALL_PRV + $KCRFWSLV_SAMPLING_COUNT_PRM)
            printf "  changed write count to: %u\n", *(uint64_t *) $KCRFWSLV_ALL
        end

        printf "  changing arbiter from %u to: 1\n", *(uint32_t *) $KCRFWSLV_ARBITER
        set *(uint32_t *) $KCRFWSLV_ARBITER = 1
        printf "  changed arbiter to: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER

        if (*(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR == 1)
            printf "  changing redorate to: (4 x switch threshold) + 1: %lu\n", (4 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            set *(uint64_t *) $KCRFWSLV_REDORATE = (4 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            printf "  changed redorate to: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
        else
            printf "  changing redorate to: (2 x switch threshold) + 1\n"
            set *(uint64_t *) $KCRFWSLV_REDORATE = (2 * *(uint64_t *) $KCRFWSLV_SWITCH_THRESH) + 1
            printf "  changed redorate to: %lu\n", *(uint64_t *) $KCRFWSLV_REDORATE
        end
    end
    printf "-------------------------------\n"
    printf "\n"
end

define disable_lg_workers
    printf "\n"
    printf "----- Disabling LG workers -----\n"

    if ((uint8_t) kcrf_slave_info_ != 2)
    else
        printf "  write count all is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
        printf "  write count all prev is: %lu\n", *(uint64_t *) $KCRFWSLV_ALL_PRV
        printf "  write count group0 is: %lu\n", *(uint64_t *) $KCRFWSLV_GROUP0
        printf "  max log write parallelism is: %u\n", *(uint32_t *) $KCRFWSLV_MAX_LOG_WRITE_PAR

        if (*(uint32_t *) $KCRFWSLV_LGWR_MODE == 0)
            printf "  lgwr mode is serial, no action!\n"
        else
            printf "  lgwr mode is parallel, disabling workers ...\n"

            # When switching from parallal to serial, the
            # all_prv counter is not reset. Therefore, the
            # write count delta can become negative, which
            # is why we need to cast this to int64.
            if ((int64_t) (*(uint64_t *) $KCRFWSLV_ALL - *(uint64_t *) $KCRFWSLV_ALL_PRV)) < 128
                printf "  changing write count to: %lu\n", (*(uint64_t *) $KCRFWSLV_ALL_PRV + 128)
                set *(uint64_t *) $KCRFWSLV_ALL = (*(uint64_t *) $KCRFWSLV_ALL_PRV + 128)
                printf "  changed write count to: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
            end

            printf "  changing arbiter to: 1\n"
            set *(uint32_t *) $KCRFWSLV_ARBITER = 1
            printf "  changed arbiter to: %u\n", *(uint32_t *) $KCRFWSLV_ARBITER

            printf "  changing group0 write count to write count all: %lu\n", *(uint64_t *) $KCRFWSLV_ALL
            set *(uint64_t *) $KCRFWSLV_GROUP0 = *(uint64_t *) $KCRFWSLV_ALL
            printf "  changed write count group0 to: %lu\n", *(uint64_t *) $KCRFWSLV_GROUP0

            printf "  changing redo write time to redo write time avg: %u\n", *(uint32_t *) $KCRFWSLV_RW_AVG
            set *(uint32_t *) $KCRFWSLV_RW = *(uint32_t *) $KCRFWSLV_RW_AVG
            printf "  changed redo write time to redo write time avg: %u\n", *(uint32_t *) $KCRFWSLV_RW
        end
    end
    printf "--------------------------------\n"
    printf "\n"
end

define _enable_alwe_trace 
    set $alwe_trc_flg = 0

    if ($argc && $arg0 == $ALWE_TRACE_FLG) 
        set $alwe_trc_flg = $ALWE_TRACE_FLG 
    end

    if ($argc && $arg0 == $ALWE_TRACE_VERBOSE_FLG)
        set $alwe_trc_flg = $ALWE_TRACE_VERBOSE_FLG
    end

    if (!$alwe_trc_flg) 
        printf "  invalid alwe trace flag, no action.\"
    else
        printf "  alwe_flags are: %d%d%d%d%d%d%d%d\n",     \
               (*(uint8_t *) $ALWE_FLAGS) & 0x80 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x40 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x20 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x10 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x08 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x04 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x02 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x01 ? 1 : 0

        if ((*(uint8_t *) $ALWE_FLAGS) & $alwe_trc_flg)
            printf "  alwe trace already enabled, no action!\n"
        else
            printf "  changing alwe flags ...\n"
            set *(uint8_t *) $ALWE_FLAGS = *(uint8_t *) $ALWE_FLAGS | $alwe_trc_flg
            printf "  alwe_flags are: %d%d%d%d%d%d%d%d\n",     \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x80 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x40 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x20 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x10 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x08 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x04 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x02 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x01 ? 1 : 0
        end
    end
end

define enable_alwe_trace
    printf "\n"
    printf "----- Enabling ALWE trace -----\n"
    _enable_alwe_trace $ALWE_TRACE_FLG
    printf "-------------------------------\n"
    printf "\n"
end

define enable_alwe_verbose_trace
    printf "\n"
    printf "----- Enabling ALWE verbose trace -----\n"
    _enable_alwe_trace $ALWE_TRACE_VERBOSE_FLG
    printf "---------------------------------------\n"
    printf "\n"
end

define _enable_olrw_trace 
    set $olrw_trc_flg = 0

    if ($argc && $OLRW_TRACE_FLG) 
        set $olrw_trc_flg = $OLRW_TRACE_FLG 
    end

    if ($argc && $arg0 == $OLRW_TRACE_VERBOSE_FLG)
        set $olrw_trc_flg = $OLRW_TRACE_VERBOSE_FLG
    end

    if (!$olrw_trc_flg) 
        printf "  invalid olrw trace flag, no action.\"
    else
        # Note: in Oracle 19c, klassvp8_ has
        # a pointer to the olrw_info struct.
        set $olrw_info_p = (uint64_t *) klassvp8_ 

        printf "  olrw_info_p is: %p\n", $olrw_info_p
        printf "  olrw_flags are: %d%d%d%d%d%d%d%d\n",     \
               (*(uint8_t *) $olrw_info_p) & 0x80 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x40 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x20 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x10 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x08 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x04 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x02 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x01 ? 1 : 0

        if (*(uint8_t *) $olrw_info_p) & $olrw_trc_flg
            printf "  olrw trace already enabled, no action!\n"
        else
            printf "  changing olrw flags ...\n"
            set *(uint8_t *) $olrw_info_p = *(uint8_t *) $olrw_info_p | $olrw_trc_flg
            printf "  olrw_flags are: %d%d%d%d%d%d%d%d\n",     \
                   (*(uint8_t *) $olrw_info_p) & 0x80 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x40 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x20 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x10 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x08 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x04 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x02 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x01 ? 1 : 0
        end
    end
end

define enable_olrw_trace
    printf "\n"
    printf "----- Enabling OLRW trace -----\n"
    _enable_olrw_trace $OLRW_TRACE_FLG
    printf "-------------------------------\n"
    printf "\n"
end

define enable_olrw_verbose_trace 
    printf "\n"
    printf "----- Enabling OLRW verbose trace -----\n"
    _enable_olrw_trace $OLRW_TRACE_VERBOSE_FLG
    printf "---------------------------------------\n"
    printf "\n"
end

define _disable_alwe_trace 
    set $alwe_trc_flg = 0

    if ($argc && $ALWE_TRACE_FLG) 
        set $alwe_trc_flg = $ALWE_TRACE_FLG 
    end

    if ($argc && $arg0 == $ALWE_TRACE_VERBOSE_FLG)
        set $alwe_trc_flg = $ALWE_TRACE_VERBOSE_FLG
    end

    if (!$alwe_trc_flg) 
        printf "  invalid alwe trace flag, no action.\"
    else
        printf "  alrw_flags is: %p\n", *(uint8_t *) $ALWE_FLAGS
        printf "  alwe_flags are: %d%d%d%d%d%d%d%d\n",    \
               (*(uint8_t *) $ALWE_FLAGS) & 0x80 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x40 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x20 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x10 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x08 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x04 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x02 ? 1 : 0, \
               (*(uint8_t *) $ALWE_FLAGS) & 0x01 ? 1 : 0
   
        if (! ((*(uint8_t *) $ALWE_FLAGS) & $alwe_trc_flg))
            printf "  alwe trace already disabled, no action!\n"
        else
            printf "  changing alwe flags ...\n"
            set *(uint8_t *) $ALWE_FLAGS = *(uint8_t *) $ALWE_FLAGS & (~$alwe_trc_flg)
            printf "  alwe_flags are: %d%d%d%d%d%d%d%d\n",     \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x80 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x40 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x20 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x10 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x08 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x04 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x02 ? 1 : 0, \
                   (*(uint8_t *) $ALWE_FLAGS) & 0x01 ? 1 : 0
        end
    end
end

define disable_alwe_trace
    printf "\n"
    printf "----- Disabling ALWE trace -----\n"
    _disable_alwe_trace $ALWE_TRACE_FLG
    printf "--------------------------------\n"
    printf "\n"
end

define disable_alwe_verbose_trace 
    printf "\n"
    printf "----- Enabling ALWE verbose trace -----\n"
    _disable_alwe_trace $ALWE_TRACE_VERBOSE_FLG
    printf "---------------------------------------\n"
    printf "\n"
end

define _disable_olrw_trace 
    set $olrw_trc_flg = 0

    if ($argc && $arg0 == $OLRW_TRACE_FLG) 
        set $olrw_trc_flg = $OLRW_TRACE_FLG 
    end

    if ($argc && $arg0 == $OLRW_TRACE_VERBOSE_FLG)
        set $olrw_trc_flg = $OLRW_TRACE_VERBOSE_FLG
    end

    if (!$olrw_trc_flg) 
        printf "  invalid olrw trace flag, no action.\"
    else
        # Note: in Oracle 19c, klassvp8_ has
        # a pointer to the olrw_info struct.
        set $olrw_info_p = (uint64_t *) klassvp8_ 

        printf "  olrw_info_p is: %p\n", $olrw_info_p
        printf "  olrw_flags are: %d%d%d%d%d%d%d%d\n",     \
               (*(uint8_t *) $olrw_info_p) & 0x80 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x40 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x20 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x10 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x08 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x04 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x02 ? 1 : 0, \
               (*(uint8_t *) $olrw_info_p) & 0x01 ? 1 : 0

        if (!((*(uint8_t *) $olrw_info_p) & $olrw_trc_flg))
            printf "  olrw trace already disabled, no action!\n"
        else
            printf "  changing olrw flags ...\n"
            set *(uint8_t *) $olrw_info_p = *(uint8_t *) $olrw_info_p & (~$olrw_trc_flg)
            printf "  olrw_flags are: %d%d%d%d%d%d%d%d\n",     \
                   (*(uint8_t *) $olrw_info_p) & 0x80 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x40 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x20 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x10 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x08 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x04 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x02 ? 1 : 0, \
                   (*(uint8_t *) $olrw_info_p) & 0x01 ? 1 : 0
        end
    end
end

define disable_olrw_trace
    printf "\n"
    printf "----- Disabling OLRW trace -----\n"
    _disable_olrw_trace $OLRW_TRACE_FLG
    printf "--------------------------------\n"
    printf "\n"
end

define disable_olrw_verbose_trace 
    printf "\n"
    printf "----- Disabling OLRW verbose trace -----\n"
    _disable_olrw_trace $OLRW_TRACE_VERBOSE_FLG
    printf "----------------------------------------\n"
    printf "\n"
end

define enable_lgwr_standby_mode 
    printf "\n"
    printf "----- Enabling LGWR standby mode -----\n"

    if (*(uint32_t) $KCRFWSLV_STANDBY_MODE)
        printf "  lgwr standby mode already enabled, no action.\n"
    else
        printf "  Enabling lgwr standby mode ...\n"
        set *(uint32_t *) $KCRFWSLV_STANDBY_MODE = 0x1
        printf "  Enabled lgwr standby mode: %u\n", *(uint32_t *) $KCRFWSLV_STANDBY_MODE
    end
    
    printf "--------------------------------------\n"
    printf "\n"
end

define disable_lgwr_standby_mode 
    printf "\n"
    printf "----- Disabling LGWR standby mode -----\n"

    if (!*(uint32_t) $KCRFWSLV_STANDBY_MODE)
        printf "  lgwr standby mode already disabled, no action.\n"
    else
        printf "  Disabling lgwr standby mode ...\n"
        set *(uint32_t *) $KCRFWSLV_STANDBY_MODE = 0x0
        printf "  Disabled lgwr standby mode: %u\n", *(uint32_t *) $KCRFWSLV_STANDBY_MODE
    end
    
    printf "---------------------------------------\n"
    printf "\n"
end

document show_lgwr_mode
Show current lgwr mode and configuration
Usage: show_lgwr_mode
end

document set_alfs_polling
Enable or disable ALFS polling (0=disable, 1=enable)
Usage: set_alfs_polling <value>
end
    
document set_max_log_write_parallelism
Set the max_log_write_parallelism in kcrf_slave_info_ to a given value. 
Usage: set_max_log_write_parallelism <new_parallelism>
end

document set_redo_strands
Change the number of public redo strands.
Usage: set_redo_strand <nr_of_strands>
end

document enable_all_redo_strands
Enable all public redo strands.
Usage: enable_all_redo_strands
end

document disable_all_redo_strands
Disable all public redo strands.
Usage: disable_all_redo_strands
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
Enable lg worker processes in heuristic mode (adaptive scalable lgwr)
Usage: enable_lg_workers
end

document disable_lg_workers
Disable lg worker processes in heuristic mode (adaptive scalable lgwr)
Usage: disable_lg_workers
end

document enable_olrw_trace
Enable olrw trace
Usage: enable_olrw_trace
end

document disable_olrw_trace
Disable olrw trace
Usage: disable_olrw_trace
end

document enable_olrw_verbose_trace
Enable olrw verbose trace
Usage: enable_olrw_verbose_trace
end

document disable_olrw_verbose_trace
Disable olrw verbose trace
Usage: disable_olrw_verbose_trace
end

document enable_lgwr_standby_mode
Enable lgwr standby mode
Usage: enable_lgwr_standby_mode
end

document disable_lgwr_standby_mode
Disable lgwr standby mode
Usage: disable_lgwr_standby_mode
end
