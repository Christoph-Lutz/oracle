# Purpose:
#   Manually toggle on the Fast Log File Sync mechanism by
#   changing the following sga variables:
# 
#     kspasv3_: 
#     Moving average of the redo write time (note that kspasv3_ 
#     tracks time in ns). The value of kspasv3_ is compared against
#     _smart_log_threshold_us in kcrfw_alfs_sl_update_mode.
#
#     kspasv90_: 
#     alfs sl write count (kcrfw_alfs_sl_update_mode uses a hard-coded 
#     threshold of 128).
#
# Author:
#   Christoph Lutz
#
# Date:
#   May-15 2025
#
# Usage:
#   gdb -q -x enabled-fast-sync -p <lgwr_pid>
# 
# Tested on:
#   Oracle 19.26 / Exadata 24.1.2 (X8M-2)
#
# Notes:
#   This is dangerous and higly experimental, use at your own risk!

set pagination off
set confirm off

break kcrfw_alfs_sl_update_mode

command 1
set *(uint32_t *) &kspasv3_ = 50000
set *(uint32_t *) &kspasv90_ = 128
printf "kspasv3_ = %u\n", *(uint32_t *) &kspasv3_ 
printf "kspasv90_ = %u\n", *(uint32_t *) &kspasv90_
quit
end
c
