# Purpose:
#   Trace the oracle listener and the child processes it
#   spawns across fork/exec calls and dump the tns packets
#   received and written by snttread and snttwrite.
#
# Author:
#   Christoph Lutz
#
# Date:
#   Oct-10 2024
#
# Usage:
#   gdb -q -x lsnr-tns-pkt-dmp.gdb -p <lsnr_pid>
# 
# Tested on:
#   Oracle 23ai free (23.5.0.24.07), VirtualBox Image,
#   kernel 5.15.0-210.163.7, bpftrace 0.16
#
# Notes:
#   Run this script against a separate and isolated
#   test listener.
#
#   You may have to adjust the snttread return addr
#   on different versions of oracle.

set pagination off
set confirm off

set follow-fork-mode child

catch exec
command 1
  cont
end

break snttread
command 2
   printf "-> snttread\n"
   p/x $rsi
   set $buf=$rsi
   cont
end

break *snttread+20
command 3
   printf "<- snttread\n"
  x/64xb $buf
  cont
end

break snttwrite
command 4
   printf "-> snttwrite\n"
  x/64xb $rsi
  cont
end

cont
