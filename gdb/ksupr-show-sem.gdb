# Purpose:
#  Sometimes we need to know the semid and semnum of 
#  Oracle processes. This script iterates over the
#  processes array (ksupr) and prints the semid, 
#  semnum, and additional session context information 
#  (from v$session / x$ksuse).
#
# Author:
#   Christoph Lutz
# 
# Date:
#   Dec-07 2025
#
# Tested on:
#   Oracle 19.26 / Exadata 25.1.7
#
# Usage:
#   gdb -q                \
#   -x ksupr-show-sem.gdb \
#   -p <pid>
#
# Note:
#   This is highly experimental, use at your own risk!

set confirm off
set pagination off

handle SIGSEGV nostop noprint
handle SIGUSR2 nostop noprint

# Offsets can and will change across RUs!
set $KSUSGA_KSUPR_OFF     = 0x08
set $KSUSGA_KSUPR_NUM_OFF = 0x10
set $KSUSGA_KSUSE_OFF     = 0x48
set $KSUSGA_KSUSE_NUM_OFF = 0x50

set $KSUPR_SADDR_OFF      = 0x70
set $KSUPR_SEM_OFF        = 0x640
set $KSUPR_KSUPROSID_OFF  = 0xb78

set $SEM_SEMID_OFF        = 0x4
set $SEM_SEMNUM_OFF       = 0x8 

set $KSUSE_KSUSENUM_OFF   = 0x878
set $KSUSE_KSUSEPNM_OFF   = 0xb60


set $ksupr_p   = *(uint64_t *) ((uint64_t) &ksusga_ + $KSUSGA_KSUPR_OFF)
set $ksupr_num = *(uint32_t *) ((uint64_t) &ksusga_ + $KSUSGA_KSUPR_NUM_OFF)

printf "\n"
printf "%-16s %-16s %16s %8s %8s %8s %-48s\n", "PADDR", "SADDR", "OSPID", "SID", "SEMID", "SEM_NUM", "PROGRAM"

set $i=0
while($i < $ksupr_num)
    set $sid = 0
    set $prog = "(none)"

    set $paddr  = ((uint64_t *) $ksupr_p)[$i]
    set $semid  = *(uint32_t *) ($paddr + $KSUPR_SEM_OFF + $SEM_SEMID_OFF)
    set $semnum = *(uint16_t *) ($paddr + $KSUPR_SEM_OFF + $SEM_SEMNUM_OFF)
    set $ospid  =  (char *) ($paddr + $KSUPR_KSUPROSID_OFF)

    set $saddr  = *(uint64_t *) ($paddr + $KSUPR_SADDR_OFF)

    # Only print something if paddr and saddr are set.
    if ($paddr && $saddr)
        set $sid  = *(uint64_t *) ($saddr + $KSUSE_KSUSENUM_OFF)
        set $prog =  (char *) ($saddr + $KSUSE_KSUSEPNM_OFF)

        printf "%-16p %-16p %16s %8u %8u %8u %-48s\n", $paddr, $saddr, $ospid, $sid, $semid, $semnum, $prog
    end

    set $i=$i+1
end

printf "\n"

quit
