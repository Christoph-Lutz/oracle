# Purpose:
#   Manually enable the Adaptive Log File Sync (ALFS) polling
#   mode by changing the following kcrf_alfs_info_ members:
# 
#     sync_writes_delta:
#     Number of "redo synch writes" since the last measurement.
#     The delta is calculated by ckpt every 3 sec in kcrfw_alfs_
#     cron_job (via helper function kcrfw_alfs_save_sync_time).
#     
#     long_waits_delta:
#     Number of "redo synch long waits" since that last measurement.
#     The delta is calculated by ckpt every 3 sec in kcrfw_alfs_
#     cron_job (via helper function kcrfw_alfs_save_sync_time).
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
#   gdb -q -x alfs-enable-polling.gdb -p <lgwr_pid>
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
set $KCRFWSLV_LGWR_MODE              = 0x6002200c

set $ALFS_INFO_ARBITER               = 0x60021f3c
set $ALFS_INFO_POLLING               = 0x60021f38 
set $ALFS_INFO_SYNC_WRITES_DELTA     = 0x60021f7c
set $ALFS_INFO_LONG_SYNCS_DELTA      = 0x60021f64
set $ALFS_INFO_SYNC_WRITES_DELTA_DEF = 63
set $ALFS_INFO_LONG_SYNCS_DELTA_DEF  = 8


printf "\n"
printf "----- Enabling ALFS Polling -----\n"
printf "  lgwr mode is: %s\n", *(uint32_t *) $KCRFWSLV_LGWR_MODE > 0 ? "parallel" : "serial"
printf "  redo synch writes delta is: %u\n", *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA
printf "  redo synch long waits delta is: %u\n", *(uint32_t *) $ALFS_INFO_LONG_SYNCS_DELTA

if *(uint32_t *) $ALFS_INFO_POLLING
    printf "  ALFS polling already enabled, no action!\n\n"
    quit
end

if (uint32_t ) kcrf_fast_sync_
    printf "  Fast sync is enabled, no action!\n"
    quit
end

if ! *(uint32_t *) $ALFS_INFO_POLLING
    printf "  ALFS polling is disabled, enabling it ...\n"

    if *(uint32_t *) $ALFS_INFO_ARBITER > 1
        printf "  changing arbiter to: 1\n"
        set *(uint32_t *) $ALFS_INFO_ARBITER = 1
        printf "  changed arbiter to: %u\n", *(uint32_t *) $ALFS_INFO_ARBITER
    end

    # Note: treshold of 5 is hardcoded in kcrfw_alfs_update_mode 
    if *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA >= 5
      printf "  changing redo synch long waits delta to: %u\n", ((*(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA) / 8) + 1 
      set *(uint32_t *) $ALFS_INFO_LONG_SYNCS_DELTA = ((*(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA) / 8) + 1
      printf "  changed redo synch long waits delta to: %u\n", *(uint32_t *) $ALFS_INFO_LONG_SYNCS_DELTA
    end

    if *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA == 0 || *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA < 5
      printf "  redo synch writes delta 0 or < 5, using default values.\n" 

      printf "  changing redo synch writes delta to: %u\n", $ALFS_INFO_SYNC_WRITES_DELTA_DEF
      set *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA = $ALFS_INFO_SYNC_WRITES_DELTA_DEF
      printf "  changed redo synch writes delta to: %u\n", *(uint32_t *) $ALFS_INFO_SYNC_WRITES_DELTA

      printf "  changing redo synch long waits delta to: %u\n", $ALFS_INFO_LONG_SYNCS_DELTA_DEF
      set *(uint32_t *) $ALFS_INFO_LONG_SYNCS_DELTA = $ALFS_INFO_LONG_SYNCS_DELTA_DEF
      printf "  changed redo synch long waits delta to: %u\n", *(uint32_t *) $ALFS_INFO_LONG_SYNCS_DELTA
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
    set $ret =  (int32_t) kcrfw_alfs_update_mode()
    printf "  return code is: %d\n", $ret
end

printf "\n"
quit
