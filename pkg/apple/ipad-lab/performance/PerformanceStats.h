/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RA_LAB_PERFORMANCE_STATS_H
#define RA_LAB_PERFORMANCE_STATS_H
#include <stdint.h>
#include <string.h>
#include <math.h>

typedef struct ra_lab_perf_window
{
   uint64_t frames, intervals, late, last_end, worst_at;
   double work_sum, work_max, interval_sum, interval_max;
   unsigned histogram[501];
} ra_lab_perf_window;

static void ra_lab_perf_frame(ra_lab_perf_window *s, uint64_t begin,
      uint64_t end, double hz, int normal)
{
   double work = (end - begin) / 1000.0;
   s->frames++;
   s->work_sum += work;
   if (work > s->work_max) s->work_max = work;
   if (normal && s->last_end && end > s->last_end)
   {
      double ms = (end - s->last_end) / 1000.0;
      unsigned bucket = ms >= 500 ? 500 : (unsigned)ceil(ms);
      s->intervals++;
      s->interval_sum += ms;
      s->histogram[bucket]++;
      if (ms > s->interval_max) { s->interval_max = ms; s->worst_at = end; }
      if (hz > 0 && isfinite(hz) && ms > 1500.0 / hz) s->late++;
   }
   s->last_end = normal ? end : 0;
}

static unsigned ra_lab_perf_p95(const ra_lab_perf_window *s)
{
   uint64_t count = 0, rank = (s->intervals * 95 + 99) / 100;
   unsigned i;
   if (!rank) return 0;
   for (i = 0; i <= 500; i++)
   {
      count += s->histogram[i];
      if (count >= rank) return i;
   }
   return 500;
}

static void ra_lab_perf_next_window(ra_lab_perf_window *s)
{
   uint64_t last = s->last_end;
   memset(s, 0, sizeof(*s));
   s->last_end = last;
}
#endif
