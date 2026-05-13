#!/usr/bin/env bash
#
# Purpose:
#   Extract the v$ fixed view definitions from the oracle binary.
#
# Author:
#   Christoph Lutz
#
# Date:
#   May-13 2026
#
# Usage:
#   gdb -q -x kqfvi.gdb [view_name]
#
#     view_name: name of the fixed view to retrieve
#                the definition for (optional)
# 
# Tested on:
#   Oracle 19.26 / Exadata 25.2.1
#   Oracle 23.26.0.0 / Exadata 25.2.1
#   Oracle 23.26.1.0 / Exadata 25.2.1
#
# Notes:
#   This script is dangerous, use at your own risk!

# Prechecks
if [[ -z "$ORACLE_HOME" ]] ; then
    printf "\nORACLE_HOME not set. Aborting.\n\n"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/oracle" ]] ; then
    printf "\nOracle executable not found: $ORACLE_HOME/bin/oracle. Aborting.\n\n"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/oracle" ]] ; then
    printf "\nOracle executable not found: $ORACLE_HOME/bin/oracle. Aborting.\n\n"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/oracle" ]] ; then
    printf "\nOracle executable not found: $ORACLE_HOME/bin/oracle. Aborting.\n\n"
    exit 1
fi

if [[ ! -x "$ORACLE_HOME/bin/oraversion" ]] ; then
    printf "\nOraversion executable not found: $ORACLE_HOME/bin/oraversion. Aborting.\n\n"
    exit 1
fi

# Globals and input args
VIEW_NAME="$1"
MAJ_VER="$($ORACLE_HOME/bin/oraversion -majorVersion)"

readonly VIW_ELM_SZ="0x50"
readonly VIW_NAME_OFF="0x08"
readonly VIP_TXT_OFF="0x00"

printf "\nOracle version is: $MAJ_VER\n"

if [[ "$MAJ_VER" == "23" ]] ; then
    readonly VIP_ELM_SZ="0x28"

elif [[ "$MAJ_VER" == "19" ]]; then
    readonly VIP_ELM_SZ="0x20"

else
    printf "\nThis Oracle version is not supported. Aborting.\n"
    exit 1
fi

if [[ -n "$VIEW_NAME" ]] ; then
    printf "Retrieving fixed view definition for $VIEW_NAME ...\n\n"
else
    printf "Retrieving all fixed view definitions ...\n\n"
fi

# gdb script
SCRIPT="$(cat <<EOF

set confirm off
set pagination off
set verbose off
set print symbol-loading off

python
import gdb

class FixedViewDefinitionsPrinter(gdb.Command):
    """
    FixedViewDefinitionsPrinter 
    
    Usage: printFixedViewDefinitions kqfviw kqfvip kqfvpsz [view_name]

    kqfviw   : address of kqfviw array
    kqfvip   : address of kqfvip array
    kqfvpsz  : number of kqfviw and kqfvip arrays
    view_name: view name (optional)
    """

    VIW_ELM_SZ   = $VIW_ELM_SZ
    VIW_NAME_OFF = $VIW_NAME_OFF

    VIP_ELM_SZ   = $VIP_ELM_SZ
    VIP_TXT_OFF  = $VIP_TXT_OFF

    def __init__(self):
        super(FixedViewDefinitionsPrinter, self).__init__(
            "printFixedViewDefinitions",
            gdb.COMMAND_USER
        )

    def _read_cstring(self, addr, maxlen=16384):
        if addr == 0:
            return None

        try:
            inferior = gdb.selected_inferior()
            raw = inferior.read_memory(addr, maxlen).tobytes()

            # find null terminator safely
            end = raw.find(b'\x00')
            if end == -1:
                end = len(raw)

            return raw[:end].decode('latin-1', errors='replace')

        except gdb.error:
            return None

    def invoke(self, arg, from_tty):
        argv = gdb.string_to_argv(arg)

        if len(argv) < 3:
            raise gdb.GdbError(
                "Usage: printFixedViewDefinitions kqfviw kqfvip kqfvpsz [view_name]"
            )

        kqfviw = int(gdb.parse_and_eval(argv[0]))
        kqfvip = int(gdb.parse_and_eval(argv[1]))
        kqfvpsz = int(gdb.parse_and_eval(argv[2]))

        view_name = None
        if len(argv) >= 4:
            val = gdb.parse_and_eval(argv[3])

            try:
                s = val.string()
            except:
                s = str(val).strip('"')

            s = s.upper()

            if s:
                view_name = s

            # treat empty string as None
            #if s == "":
            #    view_name = None
            #else:
            #    view_name = s

            #print(f"DEBUG: view_name {view_name}")


        found = False
        for i in range(kqfvpsz - 1):
            viw_elem = kqfviw + i * self.VIW_ELM_SZ
            vip_elem = kqfvip + i * self.VIP_ELM_SZ

            name_ptr = int(
                gdb.parse_and_eval(f"*(void **)({viw_elem + self.VIW_NAME_OFF})")
            )
            current_name = self._read_cstring(name_ptr)

            text_ptr = int(
                gdb.parse_and_eval(f"*(void **)({vip_elem + self.VIP_TXT_OFF})")
            )
            current_text = self._read_cstring(text_ptr)

            if current_name is None:
                continue

            if view_name is not None:
                if current_name == view_name:
                    print("")
                    print("--")
                    print(f"Name  : {current_name}")
                    print(f"Length: {len(current_text)}")
                    print(f"{current_text}")
                    found = True
                    break
            else:    
                print("")
                print("--")
                print(f"Name  : {current_name}")
                print(f"Length: {len(current_text)}")
                print(f"{current_text}")

        print("--")

        if view_name is not None and not found:
            print(f"View definition for {view_name} not found!")

FixedViewDefinitionsPrinter()
end

file $ORACLE_HOME/bin/oracle

set \$kqfviw  = (unsigned long) &kqfviw
set \$kqfvip  = (unsigned long) &kqfvip
set \$kqfvpsz = *(unsigned int *) &kqfvpsz
set \$vw_name = "$VIEW_NAME"
printFixedViewDefinitions \$kqfviw \$kqfvip \$kqfvpsz \$vw_name
quit
EOF
)"

# Pipe the script into gdb and format the output
echo "$SCRIPT" | gdb -q |  grep -vE '^[[:space:]]*\(gdb\)|^[[:space:]]*$'
ret=$?

echo
exit $ret
