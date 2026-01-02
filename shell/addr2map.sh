#!/usr/bin/bash
# set -x
# Purpose:
#   Scan the memory mappings of a process and prints the 
#   /proc/<pid>/maps entry whose address range contains 
#   the specified address
#
# Date:
#   Jan-02 2026
#
# Author:
#   Christoph Lutz
#
# Usage:
#   ./addr2map.sh <pid> <addr>
#

if [[ $# -ne 2 ]]
 then
    echo
    echo "Usage: $0 <pid> <addr>"
    echo
    exit 1
fi

PID="$1"
ADDR="$2"

if ! ps -p "$PID" >/dev/null
then
    echo "No such process: $PID"
    exit 1
fi

if [[ $ADDR =~ ^0[xX][0-9a-fA-F]+$ ]]
 then
    echo "Pid $PID, looking up addr $ADDR ..."

elif [[ $ADDR =~ ^[0-9a-fA-F]+$ ]]
 then
    ADDR="0x$ADDR"
else
    echo "Invalid hex address: $ADDR"
    exit 1
fi

cat /proc/$PID/maps | while read line; do
    start=$(echo $line | cut -d- -f1)
    end=$(echo $line | cut -d' ' -f1 | cut -d- -f2)
    start=$((0x$start))
    end=$((0x$end))
    if ((ADDR >= start && ADDR < end))
     then
        echo "Found addr $ADDR in line:"
        echo "$line"
    fi
done

exit 0
