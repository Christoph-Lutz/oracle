# Purpose:
#   The Adaptive Log File Sync (ALFS) mechanism has a "high
#   frequency check" threshold that checks if mode switches
#   post/wait to polling or vice-versa occur too frequently 
#   (as defined by _adaptive_log_file_sync_high_switch_freq_
#   threshold). If they do, a warning message is printed to
#   the alert log.
#
#   This script triggers the frequence check and simulates
#   the internal metric in such a way that the frequency
#   check is positive and a warning will be printed to the
#   alert log.
#  
#
# Author:
#   Christoph Lutz
#
# Date:
#   Aug-08 2025
#
# Usage:
#   gdb -q -x alfs-sim-freq-check-warning.gdb -p <ckpt_pid>
# 
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2 (X8M-2)
#
# Notes:
#   This script is dangerous and higly experimental, use at 
#   your own risk!
#
# Background information:
#   The "high frequency check" is performed by ckpt every
#   3 sec (via kcrfw_alfs_cron_job -> kcrfw_alfs_check_mode_
#   switch_freq).
#
#   The check function only performs a check on every 32nd
#   invocation. Since the ckpt cron job runs every 3 sec,
#   this results in a check interval of 96 sec (3 x 32 = 96).
#   When the check is performed, the check function normal-
#   izes the number of mode switches that have occured over
#   the last 96 sec to a per-minute rate. 
#
#     (mode_switches * 60) / 96
#
#   With the high switch frequency threshold defaulting to 
#   3, we therefore need at least 5 mode switches during a 
#   96 sec interval to trigger a warning.

set pagination off
set confirm off

set $SIM_MODE_SWITCH_CNT          = 5
set $CHECK_INTERVAL               = 32
set $MEASUREMENT_INTERVAL         = 96

set $ALFS_MODE_SWITCH_CNT         = 0x60021fa0
set $ALFS_MODE_SWITCH_CNT_PRV     = 0x60021fa8
set $ALFS_MODE_SWITCH_CHK_CNT     = 0x60021fb0
set $ALFS_MODE_SWITCH_THRESH_PRM  = 3

printf "\n"
printf "----- Simulating High Frequency Switch Warning -----\n"
printf "  simulated mode switch count is %u\n", $SIM_MODE_SWITCH_CNT
printf "  mode switch count is %u\n", *(uint32_t *) $ALFS_MODE_SWITCH_CNT
printf "  mode switch count prev is %u\n", *(uint32_t *) $ALFS_MODE_SWITCH_CNT_PRV
printf "  mode switch count delta is %u\n", (*(uint32_t *) ($ALFS_MODE_SWITCH_CNT)) - *(uint32_t*) ($ALFS_MODE_SWITCH_CNT_PRV)
printf "  mode switch check count is %u\n", *(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT

printf "  changing mode switch count prev to %u\n", $SIM_MODE_SWITCH_CNT
set *(uint32_t *) $ALFS_MODE_SWITCH_CNT_PRV = ((*(uint32_t*) $ALFS_MODE_SWITCH_CNT) - $SIM_MODE_SWITCH_CNT)
printf "  changed mode switch count prev to %u\n", *(uint32_t *) $ALFS_MODE_SWITCH_CNT_PRV

if (*(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT) % $CHECK_INTERVAL != 0
    printf "  changing check count to next multiple of %u ...\n", $CHECK_INTERVAL 
    printf "  changing check count to %u\n", (((*(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT) + $CHECK_INTERVAL - 1) / $CHECK_INTERVAL) * $CHECK_INTERVAL
    set *(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT =  (((*(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT) + $CHECK_INTERVAL - 1) / $CHECK_INTERVAL) * $CHECK_INTERVAL 
    printf "  changed check count to %u\n", *(uint32_t *) $ALFS_MODE_SWITCH_CHK_CNT
end

printf "  calling kcrfw_alfs_check_mode_switch_freq ...\n"
call (void) kcrfw_alfs_check_mode_switch_freq()
printf "\n"

quit
