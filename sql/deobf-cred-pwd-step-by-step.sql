/*
 * Purpose:
 *   Illustrate how to deobfuscate the base64-encoded
 *   password value stored in sys.scheduler$_credential.
 *
 * Date
 *   Aug-07, 2026
 *
 * Author:
 *   Christoph Lutz
 *
 * Usage:
 *   @deobf-cred-pwd-step-by-step.sql <base64_string>
 */

set serveroutput on size unlimited

define base64=&1

declare
    l_raw  raw(32767) := utl_encode.base64_decode(utl_raw.cast_to_raw('&base64'));
    l_pfx  raw(1);
    l_key  raw(16);
    l_sec  raw(32767);
    l_pwd  raw(32767);
    l_iv   raw(16) := hextoraw('00000000000000000000000000000000');
begin

    l_pfx := utl_raw.substr(l_raw, 1, 1);
    l_key := utl_raw.substr(l_raw, 2, 16);
    l_sec := utl_raw.substr(l_raw, 18);
    l_pwd := dbms_crypto.decrypt(
               src => l_sec,
               typ => DBMS_CRYPTO.AES_CBC_PKCS5,
               key => l_key,
               iv  => l_iv);
    
    dbms_output.put_line('Base64  : &base64');
    dbms_output.put_line('Dec b64 : ' ||rawtohex(l_raw));
    dbms_output.put_line('Prefix  : ' ||rawtohex(l_pfx));
    dbms_output.put_line('Key     : ' ||rawtohex(l_key));
    dbms_output.put_line('Secret  : ' ||rawtohex(l_sec));
    dbms_output.put_line('Pwd     : ' ||utl_raw.cast_to_varchar2(l_pwd));
end;
/
