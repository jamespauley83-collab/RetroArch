/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RA_LAB_TESTFLIGHT_POLICY_H
#define RA_LAB_TESTFLIGHT_POLICY_H

#include <string.h>

/* These settings select Dolphin's existing native-code-free backends.
 * They are fixed in distribution, including after per-game option reloads. */
static const char *ra_lab_testflight_core_option(const char *key)
{
   if (!key)
      return NULL;
   if (strcmp(key, "dolphin_cpu_core") == 0)
      return "0";
   if (strcmp(key, "dolphin_dsp_hle") == 0)
      return "enabled";
   if (strcmp(key, "dolphin_fastmem") == 0 ||
       strcmp(key, "dolphin_fastmem_arena") == 0 ||
       strcmp(key, "dolphin_dsp_jit") == 0)
      return "disabled";
   return NULL;
}

#endif
