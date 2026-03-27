# Purpose:
#   Show the signal handler functions in a process.
#
# Author:
#   Christoph Lutz
#
# Date:
#   Mar-27 2026
#
# Tested on:
#   Oracle 23.26 / Exadata 25.2.6
#
# Usage:
#   gdb -q                        \
#   [-ex 'set $p_signal = <sig>'] \
#   -x print-signal-handlers.gdb  \
#   -p <pid>
#
# Notes:
#  The script needs a "sigaction.o" symbol file with
#  the following two lines of code:
#
#    #include <signal.h>
#    struct sigaction sa;
# 
#  To compile the symbol file, use the following command:
#    gcc -c -g sigaction.c -o sigaction.o
#

set confirm off
set pagination off

add-symbol-file sigaction.o

set $SIG_DFL    = 0x0
set $SIG_IGN    = 0x1     
set $SA_SIGINFO = 0x4

python
import gdb
import re

def get_symbol(addr):
    """Return the symbol name at a given address, or None if none exists."""
    try:
        out = gdb.execute(f"info symbol {addr}", to_string=True).strip()
        if out.startswith("No symbol"):
            return None
        # Extract symbol name (stop at first whitespace or '+')
        m = re.match(r"([^\s+]+)", out)
        return m.group(1) if m else None
    except gdb.error:
        return None

class GetSymbolCommand(gdb.Command):
    """Translate an address to a symbol name and print it.
    Usage: get_symbol <address>"""

    def __init__(self):
        super(GetSymbolCommand, self).__init__("get_symbol", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        arg = arg.strip()
        if not arg:
            print("Usage: get_symbol <address>")
            return

        try:
            # Evaluate gdb expression (literal or variable)
            addr_val = gdb.parse_and_eval(arg)
            addr = int(addr_val)
        except gdb.error:
            print(f"Invalid gdb expression: {arg}")
            return
        except ValueError:
            print(f"Invalid address: {arg}")
            return

        symbol = get_symbol(addr)
        if symbol:
            # Store symbol in gdb convenience variable for later use
            gdb.execute(f'set $sym_name="{symbol}"')
        else:
            gdb.execute(f'set $sym_name="not found"')

# Register the command
GetSymbolCommand()
end

# Allocate memory for struct sigaction data
set $sa = (struct sigaction *) malloc(sizeof(struct sigaction))

# Show signal handler for specified signal only
if ($p_signal) 
    printf "Signal %2d: ", $p_signal
    set $ret = (int) sigaction($p_signal, 0, $sa)

    if ($sa->sa_flags & $SA_SIGINFO)
        if ($sa->__sigaction_handler.sa_sigaction == $SIG_DFL)
            printf "default (SIG_DFL)\n"
        end

        if ($sa->__sigaction_handler.sa_sigaction == $SIG_IGN)
            printf "ignored (SIG_IGN)\n"
        end

        if ($sa->__sigaction_handler.sa_sigaction != $SIG_DFL && $sa->__sigaction_handler.sa_sigaction != $SIG_IGN)
            get_symbol $sa->__sigaction_handler.sa_sigaction
            printf "%s\n", $sym_name
        end
    else
        if ($sa->__sigaction_handler.sa_handler == $SIG_DFL)
            printf "default (SIG_DFL)\n"
        end

        if ($sa->__sigaction_handler.sa_handler == $SIG_IGN)
            printf "ignored (SIG_IGN)\n"
        end

        if ($sa->__sigaction_handler.sa_handler != $SIG_DFL && $sa->__sigaction_handler.sa_handler != $SIG_IGN)
            get_symbol $sa->__sigaction_handler.sa_handler
            printf "%s\n", $sym_name
        end
    end

   quit
end

# Show all signal handlers
set $i = 1
while $i < 65
    set $ret = (int) sigaction($i, 0, $sa)
    printf "Signal %2d: ", $i

    if ($sa->sa_flags & $SA_SIGINFO) 
        if ($sa->__sigaction_handler.sa_sigaction == $SIG_DFL)
            printf "default (SIG_DFL)\n"
        end

        if ($sa->__sigaction_handler.sa_sigaction == $SIG_IGN) 
            printf "ignored (SIG_IGN)\n"
        end

        if ($sa->__sigaction_handler.sa_sigaction != $SIG_DFL && $sa->__sigaction_handler.sa_sigaction != $SIG_IGN)
            get_symbol $sa->__sigaction_handler.sa_sigaction
            printf "%s\n", $sym_name
        end
    else
        if ($sa->__sigaction_handler.sa_handler == $SIG_DFL)
            printf "default (SIG_DFL)\n"
        end

        if ($sa->__sigaction_handler.sa_handler == $SIG_IGN) 
            printf "ignored (SIG_IGN)\n"
        end

        if ($sa->__sigaction_handler.sa_handler != $SIG_DFL && $sa->__sigaction_handler.sa_handler != $SIG_IGN)
            get_symbol $sa->__sigaction_handler.sa_handler
            printf "%s\n", $sym_name
        end
    end

    set $i = $i + 1
end

# Free malloc'ed memory
set $ret = (void) free($sa)

quit
