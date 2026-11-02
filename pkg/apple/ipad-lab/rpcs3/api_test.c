/* SPDX-License-Identifier: GPL-3.0-or-later */
#include "RPCS3BridgeAPI.h"
#include <assert.h>
#include <stdio.h>
static unsigned version = 30;
static const char *omit;
static uint32_t test_version(void) { return version; }
static void unused_function(void) {}
static void *resolve(void *handle, const char *name)
{
   (void)handle;
   if (omit && !strcmp(name, omit)) return NULL;
   if (!strcmp(name, "rpcs3_ios_abi_version")) return (void *)test_version;
   return (void *)unused_function;
}
int main(void)
{
   RALabPS3API api;
   const char *missing;
   assert(RALabPS3Resolve(&api, NULL, resolve, &missing));
   assert(api.boot_game && api.stop_emulation && !missing);
   version = 29;
   assert(!RALabPS3Resolve(&api, NULL, resolve, &missing));
   assert(!api.boot_game && !api.initialize);
   version = 31;
   assert(!RALabPS3Resolve(&api, NULL, resolve, &missing));
   version = 30;
#define TEST_MISSING(name) \
   omit = "rpcs3_ios_" #name; \
   assert(!RALabPS3Resolve(&api, NULL, resolve, &missing)); \
   assert(!strcmp(missing, omit)); \
   assert(!api.initialize && !api.boot_game && !api.stop_emulation);
   RA_PS3_FUNCTIONS(TEST_MISSING)
#undef TEST_MISSING
   puts("PS3 ABI resolution checks passed (ABI mismatch and every missing export).");
   return 0;
}
