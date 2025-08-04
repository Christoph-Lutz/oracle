# Purpose:
#   Manually disable the Adaptive Log File Sync (ALFS) polling 
#   mode by changing the following kcrf_alfs_info_ members:
#
#     sched_delay:
#     Current scheduling delay (moving average). 
#     The scheduling delay is measured by ckpt every 3 sec 
#     in kcrfw_alfs_cron_job (via helper function kso_sched_
#     delay_avg_ms).
#
#     sched_delay_switch:
#     Scheduling delay measured at the time of the last mode
#     switch.
#
#     sync_writes_delta:
#     Number of "redo synch writes" since the last mea-
#     surement.
#     The delta is calculated by ckpt every 3 sec in 
#     kcrfw_alfs_cron_job (via helper function kcrfw_alfs_
#     save_sync_time).
#
#     sync_writes_delta_switch:
#     Number of "redo synch writes" measured at the time 
#     of the last mode switch.
#
#   To observe log file sync mode switches when using this script,
#   enable event 10468 in the lgwr process as follows:
#
#     SQL> oradebug setorapname lgwr
#
#     SQL> oradebug event 10468 trace name context forever, level 32;
#
#     SQL> oradebug event 10468 trace name context off;
#
# Author:
#   Christoph Lutz
#
# Date:
#   Aug-03 2025
#
# Usage:
#   gdb -q -x alfs-enable.gdb -p <lgwr_pid>
# 
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2 (X8M-2)
#
# Notes:
#   The script modifies various values in the kcrf_alfs_info_ sga
#   structure without atomic safeguards. So, if there's concurrent
#   activity and your timing is unlucky, this script may not work
#   as expected.
#
#   ALFS will not kick in on Exadata X8-M/X9-M systems with pmemlog
#   enabled. In that case, you could enable Data Guard sync logxpt,
#   to enable ALFS.
#
#   This script is dangerous and higly experimental, use at your own
#   risk!

set pagination off
set confirm off

# Addrs can and will change between RUs!
set $KCRFWSLV_LGWR_MODE                 = 0x6002200c

set $ALFS_INFO_ARBITER                  = 0x60021f3c
set $ALFS_INFO_POLLING                  = 0x60021f38 
set $ALFS_INFO_SCHED_DELAY              = 0x60021f78
set $ALFS_INFO_SCHED_DELAY_SWITCH       = 0x60021f70
set $ALFS_INFO_SYNC_WRITES_DELTA        = 0x60021f7c
set $ALFS_INFO_SYNC_WRITES_DELTA_SWITCH = 0x60021f74

set $ALFS_INFO_SYNC_WRITES_DELTA_DEF    = 63
set $ALFS_INFO_LONG_SYNCS_DELTA_DEF     = 8

set $POST_WAIT_THRESH_PARAM             = 50

printf "\n"
printf "----- Disabling ALFS Polling -----\n"
printf "  lgwr mode is: %s\n", (uint32_t *) $KCRFWSLV_LGWR_MODE > 0 ? "parallel" : "serial"
printf "  sched delay is: %u\n", *(uint32_t *) $ALFS_INFO_SCHED_DELAY  
printf "  sched delay (switch) is: %u\n", *(uint32_t *) $ALFS_INFO_SCHED_DELAY_SWITCH 
printf "  redo synch writes delta is: %u\n", *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA
printf "  redo synch writes delta (switch) is: %u\n", *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA_SWITCH

if ! *(uint32_t *) $ALFS_INFO_POLLING
    printf "  ALFS polling already disabled, no action!\n\n"
    quit
end

if (uint32_t) kcrf_fast_sync_
    printf "  Fast sync is enabled, no action!\n"
    quit
end

if *(uint32_t *) $ALFS_INFO_POLLING
    printf "  ALFS polling is enabled, disabling it ...\n"

    if *(uint32_t *) $ALFS_INFO_ARBITER > 1
        printf "  changing arbiter to: 1\n"
        set *(uint32_t *) $ALFS_INFO_ARBITER = 1
        printf "  changed arbiter to: %u\n", *(uint32_t *) $ALFS_INFO_ARBITER
    end

    # Use integer ceiling division to always set sched_delay_switch > sched_delay:
    # sched_delay_switch = ((100 * (sched_delay + 1)) + post_wait_thresh - 1) / post_wait_thresh;
    if *(uint32_t *) $ALFS_INFO_SCHED_DELAY >= ((*(uint32_t *) $ALFS_INFO_SCHED_DELAY_SWITCH) * $POST_WAIT_THRESH_PARAM/100)
      printf "  changing sched delay (switch) to: %u\n", (100 * ((*(uint32_t *) $ALFS_INFO_SCHED_DELAY) + 1) + $POST_WAIT_THRESH_PARAM - 1) / $POST_WAIT_THRESH_PARAM 
      set *(uint32_t *) $ALFS_INFO_SCHED_DELAY_SWITCH = (100 * ((*(uint32_t *) $ALFS_INFO_SCHED_DELAY) + 1) + $POST_WAIT_THRESH_PARAM - 1) / $POST_WAIT_THRESH_PARAM
      printf "  changed sched delay (switch) to: %u\n", *(uint32_t *) $ALFS_INFO_SCHED_DELAY_SWITCH 
    end

    # Use integer ceiling division to always set sync_writes_delta_switch > sync_writes_delta:
    # sync_write_delta_switch = (100 * (sync_writes_delta + 1) + post_wait_thresh - 1) / post_wait_thresh;
    if *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA >= ((*(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA_SWITCH) * $POST_WAIT_THRESH_PARAM/100)
      printf "  changing redo synch writes delta (switch) to: %u\n", (100 * ((*(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA) + 1) + $POST_WAIT_THRESH_PARAM - 1) / $POST_WAIT_THRESH_PARAM
      set *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA_SWITCH = (100 * ((*(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA) + 1) + $POST_WAIT_THRESH_PARAM - 1) / $POST_WAIT_THRESH_PARAM
      printf "  changed redo synch writes delta (switch) to: %u\n", *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA_SWITCH
    end

    # Note:
    # The ALFS sampling_count and sampling_time
    # checks are performed in kcrfw_post, not in
    # kcrfw_alfs_update_mode. Therefore, we call
    # the function directly to trigger a mode switch
    # immediately, avoiding the need to wait for
    # another 128 redo writes or 3 seconds,
    # respectively.
    printf "  calling kcrfw_alfs_update_mode() ...\n"
    set $ret = (int32_t) kcrfw_alfs_update_mode()
    printf "  return code is: %d\n", $ret
end

printf "\n"
quit
