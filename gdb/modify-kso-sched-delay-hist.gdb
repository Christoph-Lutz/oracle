# Purpose:
#   Modify the sched_delay in the sga structure 
#   underlying x$kso_sched_delay_history.
#
#   Changing the sched_delay can be useful for
#   testing purposes.
#
#  Date:
#    Aug-05 2025
#
# Author:
#   Christoph Lutz
#
# Usage:
#   gdb -q -x ./modify-kso-sched-delay-hist.gdb -p <pid>
#
# Tested on:
#   Oracle 19.26, OEL 8.10, gdb 8.2-20.0.2
#
# Notes:
#   This script is unsafe and experimental, as
#   it modifies internal sga structures.
# 
#   Use at your own risk!

set pagination off
set confirm off

# Addresses and offsets can change between RUs!
set $KSO_SCHED_HIST_TAB       = 0x6000bd20 
set $KSO_SCHED_HIST_POS       = 0x6000bd28
set $KSO_SCHED_HIST_LEN       = 0x6000bd18

set $KSO_SCHED_HIST_ELEM_SZ        = 0x20
set $KSO_SCHED_HIST_DELAY_ELEM_OFF = 0x10

define set_most_recent
    if $argc != 2
        printf "\n"
        printf "Usage: set_most_recent <cnt> <value>\n"
        printf "\n"
        quit
    end

    set $cnt = $arg0
    set $val = $arg1
    set $i = 0
    set $start = *(uint32_t *) $KSO_SCHED_HIST_POS
    set $len = (*(uint32_t *) $KSO_SCHED_HIST_LEN -1)

    if $cnt > $len 
        printf "\n"
        printf "Error cnt must not be > array size (%u). Aborting.\n", $len
        printf "\n"
        quit
    end

    printf "\n"
    printf "----- Changing most recent %u entries  -----\n", $cnt

    printf "array size is %u\n", $len
    printf "start position is: %u\n", $start

    while($i < $cnt)
        set $idx = ($start - $i) % $len
        set $elem_p = ((*(uint64_t *)($KSO_SCHED_HIST_TAB)) + ($idx * $KSO_SCHED_HIST_ELEM_SZ) + $KSO_SCHED_HIST_DELAY_ELEM_OFF)
        printf "Entry %u@%p is %u:\n", $idx, $elem_p, *(uint32_t *) $elem_p
        set *(uint32_t *) $elem_p = $val
        printf "Changed entry %u@%p to: %u\n", $idx, $elem_p, *(uint32_t *) $elem_p
        set $i = $i + 1
    end
end

document set_most_recent
Change the most recent <cnt> entries to <val>
Usage: set_most_recent <cnt> <val>
end
