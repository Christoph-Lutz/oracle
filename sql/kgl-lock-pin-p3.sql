/*
 * Purpose:
 *   Extract the idn, namespace, and mode values
 *   from the P3 wait event parameter of the 
 *   library cache lock, "library cache load
 *   lock, and library cache pin wait events.
 *
 * Date
 *   Jan-02 2026
 *
 * Author:
 *   Christoph Lutz
 *
 * Usage:
 *   @kgl-lock-pin-p3.sql <p3_value>
 */

set lines 180 pages 999

column idn        format 9999999999
column namespace  format 99999
column lmode      format 99999

define p3=&&1

select
    bitand(&p3, to_number('ffffffff00000000', 'xxxxxxxxxxxxxxxx')) / power(2, 32) idn,
    bitand(&p3, to_number('0000ffff0000', 'xxxxxxxxxxxxxxxx')) / power(2, 16) namespace,
    bitand(&p3, to_number('000000000000ffff', 'xxxxxxxxxxxxxxxx')) lmode
from 
    dual
/
