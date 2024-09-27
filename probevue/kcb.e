#!/usr/bin/probevue
/* 
 * Purpose:
 *   Measure function call times of kcbgtcr (Consistent Read)
 *   and kcbgcur (Current Read) functions in Oracle. 
 *
 * Author:
 *   Christoph Lutz
 *
 * Date:
 *   Feb-17 2020
 */

__thread probev_timestamp_t s_time;
__list   s_timeListCr;
__list   l_timeListCr;
__list   s_timeListCur;
__list   l_timeListCur;

@@uft:$1:*:kcbgtcr:entry {
#  printf("kcbgtcr Entry\n");
  s_time = timestamp();
}

@@uft:$1:*:kcbgtcr:exit {
   __auto e_time;
   __auto long d_time;
   e_time = timestamp();
   d_time = diff_time(s_time,
                      e_time,
                      MICROSECONDS);
   if (d_time > 0) {
      time_array_cr[d_time]++;
      append( s_timeListCr, d_time);
      append( l_timeListCr, d_time);
   }
  printf("kcbgtcr %lld us\n",d_time);
}

@@uft:$1:*:kcbgcur:entry {
#  printf("kcbgcur Entry\n");
  s_time = timestamp();
}

@@uft:$1:*:kcbgcur:exit {
   __auto e_time;
   __auto long d_time;
   e_time = timestamp();
   d_time = diff_time(s_time,
                      e_time,
                      MICROSECONDS);
   if (d_time > 0) {
      time_array_cur[d_time]++;
      append( s_timeListCur, d_time);
      append( l_timeListCur, d_time);
   }
  printf("kcbgcur %lld us\n",d_time);
}
@@END
{
  printf("kcbgtcr: Total=%lld Max=%lld Min=%lld Avg=%lld\n ",
  count(l_timeListCr),
  max(l_timeListCr),
  min(l_timeListCr),
  avg(l_timeListCr));

  printf("kcbgcur: Total=%lld Max=%lld Min=%lld Avg=%lld\n ",
  count(l_timeListCur),
  max(l_timeListCur),
  min(l_timeListCur),
  avg(l_timeListCur));

  quantize(time_array_cr,40 );
  quantize(time_array_cur,40 );
  s_timeListCr = list();
  l_timeListCr = list();
  s_timeListCur = list();
  l_timeListCur = list();
}

