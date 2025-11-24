# Purpose:
#   Alter and overwrite the "hi_busy_grp_num" that Oracle 
#   dynamically computes at runtime.
#
#   Pipelined Log Writes / Overlapped Redo Writes (OLRW) 
#   on Exadata use the hi_busy_grp num to identify the 
#   highest-numbered active lg worker group and use it 
#   to derive the timeout and write size thresholds that 
#   lgwr uses when waiting on a "target log write size" 
#   event.
#
#   Artificially altering the hi_busy_grp_num value makes 
#   it possible to analyze lgwr behavior with multiple 
#   active lg worker groups.
#
# Author:
#   Christoph Lutz
# 
# Date:
#   Nov-23 2025
#
# Tested on:
#   Oracle 19.26 / Exadata 25.1.7
#
# Usage:
#   gdb -q                                \
#   -ex 'set $p_hi_busy_grp_num = <num>]' \
#   -x olrw-sim-hi_busy_grp_num.gdb       \
#   -p <lgwr_pid>
#
#    Set hi_busy_grp_num to 5:
#     gdb -q                              \
#     -ex 'set $p_hi_busy_grp_num=5'      \
#     -x olrw-sim-hi_busy_grp_num.gdb     \
#     -p 1234 
#
# Notes:
#   The script enables the OLRW verbose trace (event 10468 
#   at level 0x10000), which logs its output to the alert log. 
# 
#   Note that this trace cannot be enabled or disabled dynam-
#   ically via alter session commands at runtime. Therefore, 
#   don't forget to manually switch it off with the following 
#   gdb command after the script completes:
# 
#     (gdb) set *(uint8_t *) klassvp8_ = *(uint8_t *) klassvp8_ & (~0x10)
#
#   This script is highly experimental, use at your own risk!

set confirm off
set pagination off

handle SIGSEGV nostop noprint
handle SIGUSR2 nostop noprint

set $ALWE             = (uint64_t) klassvp7_
set $ALWE_FLAGS       = ($ALWE + 124)

set $OLRW             = (uint64_t) klassvp8_
set $OLRW_TRC         = 0x8
set $OLRW_TRC_VERBOSE = 0x10 

set $LGWR_MODE        = 0x6002200c
set $MAX_LOG_WRI_PAR  = 0x6002202c

printf "\n"
printf "alwe->flags     = 0x%x\n", *(uint32_t *) $ALWE_FLAGS
printf "olrw->flags     = 0x%x\n", *(uint32_t *) $OLRW
printf "lgwr_mode       = %u\n",   *(uint32_t *) $LGWR_MODE
printf "max_log_wri_par = %u\n",   *(uint32_t *) $MAX_LOG_WRI_PAR

if ((int32_t) $p_hi_busy_grp_num > (*(int32_t *) $MAX_LOG_WRI_PAR)-1) 
    printf "p_hi_busy_grp_num > max_log_write_parallelism - 1. Aborting.\n"
    printf "\n"
    quit
end

if (!((*(uint32_t *) $OLRW) & $OLRW_TRC_VERBOSE))
    printf "olrw trace disabled, enabling it\n"
    set *(uint32_t *) $OLRW = (*(uint32_t *) $OLRW) | $OLRW_TRC_VERBOSE
    printf "olrw->flags = 0x%x\n", *(uint32_t *) $OLRW
end

break kcrfw_defer_write
command 1
    printf "-> kcrfw_defer_write\n"
    if (! *(uint32_t *) $LGWR_MODE)
        printf "   lgwr_mode is serial, changing to parallel\n"
        set *(uint32_t *) $LGWR_MODE = 1
        printf "   lgwr_mode = %u\n", *(uint32_t *) $LGWR_MODE
    end
    continue
end

break kcrfw_slave_queue_hi_busy_group
command 2
    printf "-> kcrfw_slave_queue_hi_busy_goup\n"
    continue
end

# kcrfw_slave_queue_hi_busy_group retprobe
break *kcrfw_slave_queue_hi_busy_group+253
command 3
    printf "   Changing hi_busy_grp_num to: %d\n", $p_hi_busy_grp_num
    set $eax = (int32_t) $p_hi_busy_grp_num
    printf "   Changed hi_busy_grp_num to : %d\n", $eax
    printf "<- kcrfw_slave_queue_hi_busy_goup\n"
    continue
end

continue
