# Purpose:
#   Extract all Oracle parameters from ksptii and 
#   print their associated callback functions (if 
#   any).
#
# Author:
#   Christoph Lutz
#
# Date:
#   Oct-17 2025
#
# Usage:
#   gdb -q -x ./ksptii.gdb -p <oracle_pid>
#
# Tested on:
#   Oracle 19.26 / Exadata 25.1.7
#
# Notes:
#   This script doesn't print string and list params.
#
#   This script is dangerous and higly experimental, 
#   use at your own risk!

set confirm off
set pagination off

python
import gdb
import shlex
import re

class ParamPrinter(gdb.Command):
    """Lookup symbol by addr"""

    def __init__(self):
        super(ParamPrinter, self).__init__("print_param", gdb.COMMAND_USER)

    def invoke(self, cmd_args, from_tty):
        args = shlex.split(cmd_args)

        # Evaluate $vars or return literal
        def eval_arg(arg):
            if arg.startswith("$"):
                try:
                    val = gdb.parse_and_eval(arg)
                    try:
                        return val.string()
                    except:
                        return str(val)
                except gdb.error:
                    return arg
            return arg

        def truncate(s, max_len):
            s = "" if s is None else str(s)
            return s if len(s) <= max_len else s[:max_len-3] + "..."

        # Evaluate args
        idx = eval_arg(args[0]) if len(args) > 0 else None
        param = eval_arg(args[1]) if len(args) > 1 else None
        desc = truncate(eval_arg(args[2]), 80) if len(args) > 2 else None
        callback = eval_arg(args[3]) if len(args) > 3 else None
        value = eval_arg(args[4]) if len(args) > 4 and eval_arg(args[4]) is not None else None

        # Lookup symbol at callback addr
        output = gdb.execute(f"info symbol {callback}", to_string=True)
        match = re.match(r"(\S+)", output)
        symbol_name = match.group(1) if match else None

        print(f"{idx:<5} {param:<60} {desc:<80} {symbol_name:<40} {value:<20}")

ParamPrinter()
end

set $elem_sz = 0x58
set $type_off = 0xc
set $default_off = 0x14
set $strp_off = 0x18
set $cb_off = 0x40
set $desc_off = 0x48
set $i = 0

printf "\n%-5s %-60s %-80s %-40s %-20s\n", "Indx", "Parameter", "Description", "Callback", "Default?"

while($i < (uint32_t) ksptot_)
    set $addr = (uint64_t) &ksptii + ($i * $elem_sz)
    set $name = *(char **) ($addr) 
    set $desc = *(char **) ($addr + $desc_off)
    set $callback = *(uint64_t *) ($addr + $cb_off)
    set $default = *(uint32_t *) ($addr + $default_off)
    set $type = *(uint32_t *) ($addr + $type_off)

    # Note:
    # We assume parameters are int by default.
    set $value = *(int32_t *) ($addr + $default_off)
 
    # Bool parameter
    if ($type == 1)
       set $value = ($default == 1) ? "TRUE" : "FALSE" 
    end

    # String parameter
    if ($type == 2)
        set $value = *(char **) ($addr + $strp_off)
    end

    print_param $i $name $desc $callback $value

    set $i=$i+1
end

printf "\n"

quit
