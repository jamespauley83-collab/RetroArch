/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "PerformanceStats.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
   ra_lab_perf_window s;
   uint64_t t;
   unsigned i;
   memset(&s, 0, sizeof(s));
   t = 1000000;
   for (i = 0; i < 61; i++)
   { ra_lab_perf_frame(&s, t - 4000, t, 60, 1); t += 16667; }
   assert(s.frames == 61 && s.intervals == 60 && s.late == 0);
   assert(ra_lab_perf_p95(&s) == 17);
   assert(fabs(s.work_sum / s.frames - 4) < 0.001);
   ra_lab_perf_next_window(&s);
   assert(s.frames == 0 && s.last_end != 0);
   ra_lab_perf_frame(&s, t - 1000, t, 60, 1);
   assert(s.intervals == 1);
   t += 3000000;
   ra_lab_perf_frame(&s, t - 2800000, t, 60, 1);
   assert(s.late == 1 && s.interval_max == 3000 && s.work_max == 2800);
   assert(ra_lab_perf_p95(&s) == 500 && s.worst_at == t);
   s.last_end = 0;
   ra_lab_perf_next_window(&s);
   t += 60000000;
   ra_lab_perf_frame(&s, t - 1000, t, 30, 1);
   assert(s.intervals == 0 && s.late == 0);
   t += 33333;
   ra_lab_perf_frame(&s, t - 1000, t, 30, 1);
   assert(s.late == 0 && ra_lab_perf_p95(&s) == 34);
   t += 100000;
   ra_lab_perf_frame(&s, t - 1000, t, 30, 0);
   assert(s.late == 0 && s.last_end == 0);
   t += 100000;
   ra_lab_perf_frame(&s, t - 1000, t, 30, 1);
   assert(s.late == 0);
   t += 20000;
   ra_lab_perf_frame(&s, t - 1000, t, 50, 1);
   assert(s.late == 0);
   t += 500000;
   ra_lab_perf_frame(&s, t - 1000, t, 0, 1);
   assert(s.late == 0);
   printf("Performance aggregation: 60/50/30 Hz, stalls, pause, speed modes and missing target passed.\n");
   return 0;
}
