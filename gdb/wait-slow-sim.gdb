# Purpose:
#   Little gdb helper script to simulate slow wait
#   events in Oracle by sleepling for a given amount
#   of time when kskthewt is called.
#
#   This can be useful for testing and simulating
#   slowdowns and hangs.
# 
# Date:
#   December 09 2025
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 19.26 (OEL 8.10)
# 
# Usage:
#   gdb -q                                 \
#   -ex 'set $p_wait_event="<wait event>"' \
#   [-ex 'set $p_sleep_sec=<seconds>']?    \
#   -x wait-slow-sim.gdb                   \
#   -p <pid>
# 
# Examples:
#   Slow down wait event "SQL*Net message from client" 
#   by 1.5 sec:
#
#     gdb                                                     \  
#     -ex 'set $p_wait_event = "SQL*Net message from client"' \
#     -ex 'set $p_sleep_sec = 1.5'                            \
#     -x wait-slow-sim.gdb                                    \
#     -p 1234

set pagination off
set confirm off

set $KSLED_SZ = 0x38

# If not specified, default sleep time is 1 sec
set $p_sleep_sec = ( ($p_sleep_sec) ? $p_sleep_sec: 1)

printf "\n"
printf "ksledt_ is    : %p\n", (uint64_t) ksledt_
printf "ksledt_size is: %u\n", (uint32_t) ksledt_size
printf "\n"

printf "\n"
printf "Looking up wait event# for event %s\n", $p_wait_event

set $evnum = -1
set $i = 0
while($i < (uint32_t) ksledt_size)
    set $ev_name = *(uint64_t *) ((uint64_t) ksledt_ + $i * $KSLED_SZ)

    if ((int32_t) strcmp($p_wait_event, (char *) $ev_name) == 0)
        printf "Found wait event#: %u\n", $i
        set $evnum = $i
        
        # Stop loop
        set $i = (uint32_t) ksledt_size
    end
   
    set $i++
end

if ($evnum < 0) 
    printf "Wait event# lookup failed: %s, aborting.\n\n", $p_wait_event
    quit
end

printf "Slowdown time is %.2f sec\n", $p_sleep_sec
printf "\n"

break kskthewt if $rsi == $evnum

command 1

python
import time

arg_sleep_sec = gdb.parse_and_eval("$p_sleep_sec")
sleep_sec = float(arg_sleep_sec.cast(gdb.lookup_type("double")))

arg_wait_event = gdb.parse_and_eval("$p_wait_event")

print(f"Sleeping in wait event {arg_wait_event} for {sleep_sec} sec ...")
time.sleep(sleep_sec)

end 

continue
end

continue
