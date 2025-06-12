# Purpose:
#   Set a watchpoint on the memory offset where 
#   a sesstat counter is stored and take a stack
#   trace when the watchpoint is hit.
#   
#   This is useful for analyzing which code paths
#   increment a stats counter. 
#
# Date:
#   Jun-07 2025
#
# Author:
#   Christoph Lutz
#
# Usage:
#   gdb -q -ex 'set $STAT_NAME="<stat_name>"' \
#   -x sesstat-wp.gdb -p <pid>
#
# Usage example:
#     gdb -q -ex 'set $STAT_NAME="ASSM cbk:blocks examined"' \
#     -x sesstat-wp.gdb -p 1234
#
# Tested on:
#   Oracle 19.26, OEL 8.10, gdb 8.2-20.0.2
#
# Notes:
#   Oracle tracks different sesstat counters:
#   - ksusta: Kernel Service User STAtistics
#   - stat_info: "OS & Server" related counters
#   - ksu_inststat: KSU INSTance STATistics
#
#   The v$ views expose the following stats:
#   - v$sesstat / v$mystat: ksusta + stat_info
#   - v$sysstat: ksusta + stat_info + ksu_inststat
#
#   ksusta and ksu_inststat variable names are 
#   exposed by "global_area 2" dumps (Namespace 
#   ksusta  and  ksu_inststat), but no traces of 
#   stat_info.
#
#   The length of the ksusta array is stored in 
#   the ksusga_ struct (at offset 0x54 in 19.26). 
#   The stats descriptions themselves are held in 
#   the ksusdt array and the number of elements in 
#   that array is stored in ksusdn.
#
#   The memory addresses and offsets used by this 
#   script may change with each RU, so you may need
#   adjust them based on your specific version.
#
#   This script may be dangerous, use at your own 
#   risk!

set pagination off
set confirm off

set $KSUSTA_OFF=0x7f8
set $KSUSDT_SZ=0x20
set $TLS_SADDR_OFF=0xff78

set $saddr=*(uint64_t *)($fs_base-$TLS_SADDR_OFF)
set $ksusta=*(uint64_t *)($saddr + $KSUSTA_OFF)
set $len=*(uint64_t *)(&ksusdn)

# printf "DEBUG: name=%s\n", $name
# printf "DEBUG: saddr=%p, ksusta=%p, len=%u\n", $saddr, $ksusta, $len

set $i=0
while ($i < $len)
  set $off=(uint64_t)($i * 8)
  set $addr=(uint64_t)($ksusta + $off)
  set $value=*(uint64_t *)($addr)
  set $name=*(char **)((uint64_t) &ksusdt + ($i * $KSUSDT_SZ))

  if (int) strcmp($STAT_NAME, $name) == 0
    printf "\nstatistic#=%u, name=%s, value=%u, addr=%p, off=%p\n\n", $i, $name, $value, $addr, $off
    set $wp=$addr
  end
  set $i++
end

printf "setting watchpoint on *%p\n\n", $wp
awatch -l *$wp

command 1
  bt
  quit
end

continue
