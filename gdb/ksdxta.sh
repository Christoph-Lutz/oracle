# Purpose:
#   Extract and display information about all 
#   oradebug commands from the ksdxta and
#   skdxta structures in the oracle binary.
#   This also shows restricted and undocumened
#   oradebug commands.
#
# Author:
#   Christoph Lutz
#
# Date:
#   May-17 2026
#
# Usage
#   ./ksdxta.sh [compact]?
#
#   compact: Only show minimal output (optional)
#
# Tested on:
#   Oracle 19.26 / Exadata 25.2.6
#   Oracle 23.26.0.0 / Exadata 25.2.6
#
# Notes:
#   This script is dangerous and higly experimental, 
#   use at your own risk!

# Prechecks
if [[ -z "$ORACLE_HOME" ]] ; then
    printf "\nORACLE_HOME not set. Aborting.\n\n"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/oracle" ]] ; then
    printf "\nOracle executable not found: $ORACLE_HOME/bin/oracle. Aborting.\n\n"
    exit 1
fi

# Inputs
if [[ "$1" == "compact" ]]; then
    COMPACT=True
else
    COMPACT=False
fi

# gdb script
GDB_FILE="/tmp/$$.gdb"
GDB_SCRIPT="$(cat <<EOF

set confirm off
set pagination off
set verbose off
set print symbol-loading off

python
import gdb
import shlex
import re

class CmdPrinter(gdb.Command):
    """ 
    CmdPrinter

    Usage: print_cmd src idx cmd restr doc cbk help

    src  : Data source, ksdxta or skdxta
    idx: : Index in ksdxsta or skdxta
    cmd  : Oradebug command string
    restr: Command restricted (YES or NO)
    doc  : Command documented (YES or NO)
    cbk  : Address of the oradebug command callback function
    """

    COMPACT = $COMPACT
    HEADER_PRINTED = False

    def __init__(self):
        super(CmdPrinter, self).__init__("print_cmd", gdb.COMMAND_USER)

    # Note:
    # oradebug has been written for 80 character wide
    # terminals, therefore the help and arg strings
    # are a bit messy. The extract functions attempt 
    # normalize the strings and print one help line
    # for each oradebug command. This is all based on 
    # the assumption that help descriptions don't 
    # contain brackets and always start with an upper-
    # case word (this may be brittle and no longer 
    # work in future versions).
    def extract_args(self, line):
        m = re.search(r'\s(?=[A-Z])', line)
        if m:
            result = line[:m.start()]
        else:
            result = line

        return result.replace("\n", " ").lstrip().rstrip()

    def extract_desc(self, text):
        def extract_line(line):
            m = re.search(r'\s([A-Z].*)', line)
            return m.group(1).strip() if m else ""

        if isinstance(text, str):
            lines = text.splitlines()
        else:
            lines = text

        return "".join(extract_line(line) for line in lines).lstrip()

    def invoke(self, cmd_args, from_tty):
        args = shlex.split(cmd_args)

        # Print header 
        #if not CmdPrinter.header_printed:
        if not self.HEADER_PRINTED:
            print(f"\n")
            if self.COMPACT:
                print(
                    f"{'Command':<20} "
                    f"{'Restricted?':<11} "
                    f"{'Documented?':<11} "
                )
            else:
                print(
                    f"{'Src':<6} "
                    f"{'Indx':<5} "
                    f"{'Command':<20} "
                    f"{'Arguments':<57} "
                    f"{'Description':<48} "
                    f"{'Restricted?':<11} "
                    f"{'Documented?':<11} "
                    f"{'Callback':<30}"
                )
            self.HEADER_PRINTED = True

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

        # Evaluate args
        src   = eval_arg(args[0]) if len(args) > 0 else None
        idx   = eval_arg(args[1]) if len(args) > 1 else None
        cmd   = eval_arg(args[2]) if len(args) > 2 else None
        restr = eval_arg(args[3]) if len(args) > 3 else None
        doc   = eval_arg(args[4]) if len(args) > 4 else None
        cbk   = eval_arg(args[5]) if len(args) > 5 else None
        hlp   = eval_arg(args[6]) if len(args) > 6 else None
        args  = self.extract_args(hlp)
        desc  = self.extract_desc(hlp)

        # Lookup symbol at callback addr
        output = gdb.execute(f"info symbol {cbk}", to_string=True)
        match = re.match(r"(\S+)", output)
        sym = match.group(1) if match else None

        if self.COMPACT:
            print(f"{cmd:<20} {restr:<11} {doc:<11}")
        else:
            print(f"{src:<6} {idx:<5} {cmd:<20} {args:<57} {desc:<48} {restr:<11} {doc:<11} {sym:<30}")

CmdPrinter()
end

set \$KSDXTA_ELEMS   = 69
set \$SKDXTA_ELEMS   = 2

set \$FLG_HIDDENCMD  = 0x020
set \$FLG_RESTRICTED = 0x200

set \$elem_sz = 0x30
set \$cbk_off = 0x10
set \$hlp_off = 0x18
set \$flg_off = 0x22

file $ORACLE_HOME/bin/oracle

# Loop over ksdxta entries
set \$i = 0
while(\$i < \$KSDXTA_ELEMS)
    set \$elem = ((char *) &ksdxta) + (\$i * \$elem_sz)
    set \$cmd  = *(char **) (\$elem)
    set \$cbk  = *(unsigned long long *) (\$elem + \$cbk_off)
    set \$flg  = *(unsigned int *) (\$elem + \$flg_off)
    set \$hlp  = *(char **) (\$elem + \$hlp_off)

    # Restricted command?
    set \$restr = (\$flg & \$FLG_RESTRICTED) ? "YES" : "NO" 

    # Documented command? 
    set \$doc = (\$flg & \$FLG_HIDDENCMD) ? "NO" : "YES"
    print_cmd "ksdxta" \$i \$cmd \$restr \$doc \$cbk \$hlp
    set \$i++
end

# Loop over skdxta entries
set \$j = 0
while(\$j < \$SKDXTA_ELEMS)
    set \$src  = "skdxta"
    set \$elem = ((char *) &skdxta) + (\$j * \$elem_sz)
    set \$cmd  = *(char **) (\$elem)
    set \$cbk  = *(unsigned long long *) (\$elem + \$cbk_off)
    set \$flg  = *(unsigned int *) (\$elem + \$flg_off)
    set \$hlp  = *(char **) (\$elem + \$hlp_off)

    # Restricted command?
    set \$restr = (\$flg & \$FLG_RESTRICTED) ? "YES" : "NO" 

    # Documented command? 
    set \$doc = (\$flg & \$FLG_HIDDENCMD) ? "NO" : "YES"
    print_cmd "skdxta" \$j \$cmd \$restr \$doc \$cbk \$hlp

    set \$j++
end
quit
EOF
)"

# Create a temporary script file and run it in gdb
echo "$GDB_SCRIPT" | sed '/^[[:space:]]*$/d' > $GDB_FILE

if [[ -f "$GDB_FILE" ]] ; then 
    gdb -q -x "$GDB_FILE" 
    rm -f "$GDB_FILE"
else
    echo "gdb file not found: $GDB_FILE"
    exit 1
fi

echo
exit 0
