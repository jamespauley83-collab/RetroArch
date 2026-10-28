/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RA_LAB_RPCS3_BRIDGE_API_H
#define RA_LAB_RPCS3_BRIDGE_API_H
#include "RPCS3IOS.h"
#include <string.h>

#define RA_PS3_FUNCTIONS(X) \
   X(abi_version) X(build_info) X(initialize) X(last_error) \
   X(firmware_version) X(install_firmware) X(install_package) \
   X(install_rap) X(install_iso) X(install_folder) X(enumerate_games) \
   X(set_display_surface) X(set_pad_state) X(boot_game) \
   X(get_emulation_state) X(get_boot_progress) \
   X(pause_emulation) X(resume_emulation) X(stop_emulation)

typedef struct RALabPS3API
{
#define RA_PS3_FIELD(name) __typeof__(&rpcs3_ios_##name) name;
   RA_PS3_FUNCTIONS(RA_PS3_FIELD)
#undef RA_PS3_FIELD
} RALabPS3API;

typedef void *(*RALabPS3Resolver)(void *, const char *);
static inline int RALabPS3Resolve(RALabPS3API *api, void *handle,
      RALabPS3Resolver resolve, const char **missing)
{
   RALabPS3API candidate;
   memset(api, 0, sizeof(*api));
   memset(&candidate, 0, sizeof(candidate));
#define RA_PS3_LOAD(name) \
   candidate.name = (__typeof__(candidate.name))resolve(handle, "rpcs3_ios_" #name); \
   if (!candidate.name) { *missing = "rpcs3_ios_" #name; return 0; }
   RA_PS3_FUNCTIONS(RA_PS3_LOAD)
#undef RA_PS3_LOAD
   if (candidate.abi_version() != RPCS3_IOS_ABI_VERSION)
   { *missing = "RPCS3 ABI 30 required"; return 0; }
   *api = candidate;
   *missing = NULL;
   return 1;
}
#endif
