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
# Usage instructions:
#   (gdb) source print-vstr.py
#   (gdb) print_vstr <addr> <len>
#
# Notes:
#   Use at your own risk!

import gdb

class PrintVStrCommand(gdb.Command):
    """Print variable-length string from a pointer and length.
       Usage: print_vstr <ptr> <length>"""

    def __init__(self):
        super(PrintVStrCommand, self).__init__("print_vstr", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        args = gdb.string_to_argv(arg)
        if len(args) != 2:
            print("Usage: print_vstr <ptr> <length>")
            return

        # Evaluate pointer and length
        str_ptr = int(gdb.parse_and_eval(args[0]))
        length = int(gdb.parse_and_eval(args[1]))

        # Raise error for null pointer or zero length
        if str_ptr == 0:
            raise gdb.GdbError("str_ptr is null")
        if length == 0:
            raise gdb.GdbError("length is zero")

        char_ptr_type = gdb.lookup_type('char').pointer()
        ptr = gdb.Value(str_ptr).cast(char_ptr_type)

        # Check if first byte is 0x0
        first_byte = int(ptr.dereference()) & 0xff
        if first_byte == 0x0:
            print("<null or empty>")
            return

        # Read remaining bytes up to length
        data = []
        for i in range(length):
            byte = int((ptr + i).dereference()) & 0xff
            if byte == 0x0:
                break
            data.append(byte)

        print(bytes(data).decode('utf-8', errors='replace'))

PrintVStrCommand()