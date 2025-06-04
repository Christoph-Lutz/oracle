# Purpose:
#   Proof of concept example that implements a 'utf16-print' command
#   to read and convert raw utf16 bind buffer values from memory at
#   runtime.
# 
# Date:
#   Jun-04 2025
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 19.26 (OEL 8.10)
#
# Usage instructions:
#   1. Turn on sql trace (level 12) in the session you want to trace
#   2. Attach to the target process with gdb: gdb -q -p <pid>
#   3. In gdb, disable pagination: set pagination off
#   4. In gdb, load the python program: source utf16-print.py
#   5. In gdb, add a breakpoint to kxsDumpToHex: break kxsDumpToHex
#   6. In gdb, add a command to call utf16-print when the breakpoint is hit:
#      (gdb) command
#      (gdb) utf16-print $rdx $rcx
#      (gdb) continue
#      (gdb) end
#      (gdb) continue
#
# Notes:
#   This script uses UTF16-BE (Big Endian).
#
#   This script was written to read UTF-16 bind buffers when SQL trace is
#   enabled and kxsDumpToHex is invoked. Alternatively, you could also
#   read from a bind buffer when a bind value is bound before execution,
#   but that code path has not been examined.
#
#   This is experimental - use at your own risk!
#
# Background information:
#   The Oracle sql trace logic handles NVARCHAR2 bind buffers differently than 
#   VARCHAR2 bind buffers.
#
#   VARCHAR2 case (simplified):
#     kxstTraceBinds
#       kxsbnddmp
#         kxsbndinf
#   
#   NVARCHAR2 case (simplified):
#     kxstTraceBinds
#       kxsbnddmp
#         kxsbndinf
#           kghstack_alloc (alloc reason: "kxsbndinf:nchar_buf")
#              kxsDumpToHex   (this dumps the hex values shown in the sql trace value=... )

import gdb

class PrintUTF16(gdb.Command):
    """Example code that prints a UTF-16 (UTF16-BE) bind buffer value
       from memory.

    Usage:
      utf16-print <address> [len_in_bytes]

    - If 'len_in_bytes' is omitted, reads until null terminator (0x0000).
    - 'len_in_bytes' specifies how many bytes to read (should be even).
    """

    def __init__(self):
        super(PrintUTF16, self).__init__("utf16-print", gdb.COMMAND_DATA)

    def _eval_arg(self, arg):
        val = gdb.parse_and_eval(arg)
        # For regs or expressions, try to convert to int
        try:
            return int(val)
        except Exception:
            raise gdb.GdbError(f"Could not convert '{arg}' to int")

    def invoke(self, arg, from_tty):
        args = gdb.string_to_argv(arg)
        if len(args) < 1 or len(args) > 2:
            print("Usage: utf16-print <address> [len_in_bytes]")
            return

        try:
            addr = self._eval_arg(args[0])
            inf = gdb.selected_inferior()

            if len(args) == 2:
                len_bytes = self._eval_arg(args[1])
                if len_bytes % 2 != 0:
                    print("Error: length_in_bytes must be even (UTF-16 code units are 2 bytes).")
                    return
                max_units = len_bytes // 2
                use_null_terminator = False
            else:
                max_units = 65536  # Max limit - increase if needed.
                use_null_terminator = True

            result = []
            for i in range(max_units):
                mem = inf.read_memory(addr + i * 2, 2)
                code_unit = (mem[0][0] << 8) | mem[1][0]

                if use_null_terminator and code_unit == 0x0000:
                    break

                result.append(chr(code_unit))

            print("UTF-16 string:", "".join(result))

        except gdb.error as e:
            print("GDB error:", e)
        except Exception as e:
            print("Error:", e)

PrintUTF16()
