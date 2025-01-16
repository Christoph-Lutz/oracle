set echo on

drop package pkg_tc_restart_01a;
@pkg_tc_restart_01a.sql

drop table tc_restart purge;
create table tc_restart(n number not null, v varchar2(30));

insert into tc_restart select level n, null from dual connect by level <= 2;
insert into tc_restart values(3, 'HIGHVAL');
commit;

create index i_v_tc_restart on tc_restart(v);

exec dbms_stats.gather_table_stats(ownname=>user, tabname=>'TC_RESTART', cascade=>true, estimate_percent=>null);

@reset.sql
