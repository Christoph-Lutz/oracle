# Purpose:
#   Intercept Oracle setsockopt calls and
#   replace the tcp keepalive defaults with
#   custom (shorter) values for testing pur-
#   poses.
#
# Author:
#   Christoph Lutz
#
# Date:
#   Oct-07 2024
#
# Usage:
#   gdb -x modify-setsockopt.gdb -p <pid>
#
# Notes:
#   Oracle hard codes the tcp keepalive
#   intvl and cnt settings to 10 and 6
#   in nttctl(). For testing error sce-
#   narios it can be useful to change
#   and lower the values.

set pagination off
set confirm off

set $SOL_TCP=6
set $TCP_KEEPIDLE=4    
set $TCP_KEEPINTVL=5 
set $TCP_KEEPCNT=6  

set $tune_ka=0
set $ka_idle=10
set $ka_intvl=1
set $ka_cnt=15

break sntttunekeepalive
command 1
 set $tune_ka=1
 cont
end

break setsockopt if $rsi == $SOL_TCP && $tune_ka == 1
command 2
  if $rdx == $TCP_KEEPIDLE
    printf "setsockopt: TCP_KEEP_IDLE=%d\n", *(int32_t *) $rcx
    set *(int32_t *) $rcx = $ka_idle
    printf "setsockopt: new TCP_KEEP_IDLE=%d\n", *(int32_t *) $rcx
  end

  if $rdx == $TCP_KEEPINTVL
    printf "setsockopt: TCP_KEEPINTVL=%d\n", *(int32_t *) $rcx
    set *(int32_t *) $rcx = $ka_intvl
    printf "setsockopt: new TCP_KEEPINTVL=%d\n", *(int32_t *) $rcx
  end

  if $rdx == $TCP_KEEPCNT
    printf "setsockopt: TCP_KEEPCNT=%d\n", *(int32_t *) $rcx
    set *(int32_t *) $rcx = $ka_cnt
    printf "setsockopt: new TCP_KEEPCNT=%d\n", *(int32_t *) $rcx
    quit
  end

  cont
end

cont
