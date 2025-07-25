# Purpose:
#   Simple helper script that sets a breakpoint at a specified 
#   location (function name or memory address) and then pauses 
#   execution for a given amount of time. Useful for testing 
#   purposes.
# 
# Date:
#   Jul-25 2025
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 19.26 (OEL 8.10)
# 
# Usage:
#   gdb                               \
#   -ex 'set $location = "location"'  \
#   -ex 'set $sleep_sec = 1'          \
#   -x sleep-on-break.py              \
#   -p <pid>
# 
# Examples:
#   Break at kcrf_commit_force_int+2 and sleep 1.5 sec:
#
#     gdb                                              \  
#     -ex 'set $location = "*kcrf_commit_force_int+2"' \
#     -ex 'set $sleep_sec = 1.5'                       \
#     -x sleep-on-break.py                             \
#     -p 1234
#
#   Break at *0x13842a30 and sleep 2.2 sec
# 
#     gdb                                 \
#     -ex 'set $location = "*0x13842a30"' \
#     -ex 'set $sleep_sec = 2.2'          \
#     -x sleep-on-break.py                \
#     -p 1234

import gdb
import time

gdb.execute("set pagination off", to_string=True)
gdb.execute("set confirm  off", to_string=True)

def resolve_location(arg):
    """
    Convert location into a valid breakpoint ("*0x12345") string.
    Handles the following formats:
      - "function"
      - "*function"
      - "*function+2"
      - "0x12345"
      - "*0x12345"
    """
    try:
        s = arg.string().strip()

        # Always evaluate the expression whether 
        # it's "func", "*func+2", "0x12345"
        val = gdb.parse_and_eval(s)

        # Get the address of the expression
        if val.address:
            addr = int(val.address)
        else:
            # Fallback: 
            # try converting expression 
            # to an int (e.g. 0x12345)
            addr = int(val)

        return f"*0x{addr:x}"

    except gdb.error as e:
        print(f">>> Error parsing location. Aborting.'{s}': {e}")
        gdb.execute("quit")

    except Exception as e:
        print(f">>> Unexpected error: {e} Aborting.")
        gdb.execute("quit")

# Parse location
arg_location = gdb.parse_and_eval("$location")
location = resolve_location(arg_location)

# Parse sleep_sec
arg_sleep_sec = gdb.parse_and_eval("$sleep_sec")

if arg_sleep_sec.type.code == gdb.TYPE_CODE_VOID:
   print(">>> Warning: sleep_sec not provided. Using default of 1 sec")
   sleep_sec = 1
else:
    sleep_sec = float(arg_sleep_sec.cast(gdb.lookup_type("double")))

# Set breakpoint
class SleepBreakpoint(gdb.Breakpoint):
    def stop(self):
        print(f">>> Hit {location}, sleeping for {sleep_sec} sec...")
        time.sleep(sleep_sec)
        return False  # auto-continue

SleepBreakpoint(location)
print(f">>> Breakpoint set on '{location}', sleep {sleep_sec} sec")

gdb.execute("continue")
