/*
 * Purpose:
 *   Deobfuscate the base64-encoded password
 *   values stored in sys.scheduler$_credential.
 *
 * Date
 *   Aug-07, 2026
 *
 * Author:
 *   Christoph Lutz
 *
 * Usage:
 *   @deobf-cred-pwd.sql
 */

with
  function deobfuscate(p_base64 varchar2)
    return varchar2
  is
    l_raw raw(32767);
    l_key raw(16);
    l_sec raw(32767);
    l_pwd raw(32767);
    l_iv  raw(16) := hextoraw('00000000000000000000000000000000');
  begin
    l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw(p_base64));
    l_key := utl_raw.substr(l_raw, 2, 16);
    l_sec := utl_raw.substr(l_raw, 18);

    l_pwd := dbms_crypto.decrypt(
                 src => l_sec,
                 typ => DBMS_CRYPTO.AES_CBC_PKCS5,
                 key => l_key,
                 iv  => l_iv);

    return utl_i18n.raw_to_char(l_pwd);
  end;
select 
    username,
    password pwd_obfuscated,
    deobfuscate(password) pwd_deobfuscated
from
    sys.scheduler$_credential
/
