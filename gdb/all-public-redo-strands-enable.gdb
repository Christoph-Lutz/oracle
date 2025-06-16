# Purpose:
#   Enable all public redo strands by setting
#   kcrf_actv_strands_ = kcrf_max_strands.
#
#   SGA variable kcrf_actv_strands_ tracks the 
#   number of active public redo strands while 
#   kcrf_max_strands defines the maximum number
#   of public redo stradnds.
#
# Date:
#   Jun-12 2025
#
# Author:
#   Christoph Lutz
#
# Usage:
#   gdb -q -x all-public-redo-strands-enable.gdb -p <pid>
#
# Tested on:
#   Oracle 19.26, OEL 8.10, gdb 8.2-20.0.2
#
# Notes:
#   Attach this script to any oracle process, pref-
#   erably a fg process.
#
#   This script may be dangerous, use at your own 
#   risk!

set pagination off
set confirm off

printf "\n"
printf "kcrf_max_strands_  = %u\n", (uint32_t) kcrf_max_strands_
printf "kcrf_actv_strands_ = %u\n", (uint32_t) kcrf_actv_strands_
printf "Setting kcrf_actv_strands_ = kcrf_max_strands_\n"
set *(uint32_t *) &kcrf_actv_strands_ = *(uint32_t *) &kcrf_max_strands_
printf "kcrf_actv_strands = %u\n", (uint32_t) kcrf_actv_strands_
printf "\n"

quit
