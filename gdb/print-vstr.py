# Purpose:
#   Print variable-length strings located in memory at a given address
#   that are not null-terminated (i.e. strings without a trailing '\0').
# 
# Date:
#   Dec-20 2025
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 19.26 (OEL 8.10)
#
# Usage:
#   (gdb) source print-vstr.py
#   (gdb) print_vstr <str_p> <str_len> [<var>]
#
# Notes:
#   Use at your own risk!

import gdb

gdb.execute("set pagination off")

class PrintVStrCommand(gdb.Command):
    """Print a non-null terminated variable-length string from a pointer and length.
Optionally, assign the variable-length string to a gdb convenience variable.
Usage: print_vstr <str_p> <str_len> [<var>]"""

    def __init__(self):
        super(PrintVStrCommand, self).__init__("print_vstr", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        args = gdb.string_to_argv(arg)
        if len(args) not in (2, 3):
            print("Usage: print_vstr <str_p> <len> [<var>]")
            return

        # Evaluate pointer and length
        str_p   = int(gdb.parse_and_eval(args[0]))
        str_len = int(gdb.parse_and_eval(args[1]))

        # Raise error for null pointer or zero length
        if str_p == 0:
            raise gdb.GdbError("str_p is null")
        if str_len == 0:
            raise gdb.GdbError("str_len is zero")

        char_ptr_type = gdb.lookup_type('char').pointer()
        ptr = gdb.Value(str_p).cast(char_ptr_type)

        # Check if first byte is 0x0
        first_byte = int(ptr.dereference()) & 0xff
        if first_byte == 0x0:
            print("<null>")
            return

        # Read remaining bytes up to length
        data = []
        for i in range(str_len):
            byte = int((ptr + i).dereference()) & 0xff
            if byte == 0x0:
                break
            data.append(byte)
        result = bytes(data).decode('utf-8', errors='replace')

        # If a third argument is provided, assign the string
        # value to a gdb convenience variable. In that case,
        # escape quotes to avoid gdb syntax errors.
        if len(args) == 3:
            varname = args[2]
            escaped = result.replace('"', '\\"')
            gdb.execute(f'set {varname} = (char *) "{escaped}"')
        else:
            print(result)

PrintVStrCommand()
