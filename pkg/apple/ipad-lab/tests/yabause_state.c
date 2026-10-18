#include <assert.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#define SCSP_MUTE_SYSTEM 1

static unsigned char pool[16], output[16];
static size_t state_size;
static int fail_phase, fail_allocation, calls, copies, frees, muted, unmuted;

static int YabSaveStateStream(void **buffer)
{
   calls++;
   if (calls == fail_phase)
      return -2;
   if (buffer)
      memset(*buffer, 0x5a, state_size);
   return 0;
}

static size_t MemStateGetOffset(void) { return state_size; }
static void ScspMuteAudio(int flag) { assert(flag == 1); muted++; }
static void ScspUnMuteAudio(int flag) { assert(flag == 1); unmuted++; }
static void *state_malloc(size_t size)
{
   assert(size <= sizeof(pool));
   return fail_allocation ? NULL : pool;
}
static void state_free(void *buffer)
{
   assert(buffer == NULL || buffer == pool);
   if (buffer)
      frees++;
}
static void *state_copy(void *target, const void *source, size_t size)
{
   assert(target && source && size <= state_size);
   copies++;
   return memcpy(target, source, size);
}

#define malloc state_malloc
#define free state_free
#define memcpy state_copy
#include "state_functions.inc"
#undef malloc
#undef free
#undef memcpy

static void reset(void)
{
   state_size = 4;
   fail_phase = fail_allocation = calls = copies = frees = muted = unmuted = 0;
   memset(output, 0xa5, sizeof(output));
}

static void unchanged(void)
{
   size_t i;
   for (i = 0; i < sizeof(output); i++)
      assert(output[i] == 0xa5);
   assert(copies == 0);
   assert(muted == 1 && unmuted == 1);
}

int main(void)
{
   int phase;
   size_t i;
   reset();
   assert(retro_serialize(output, 4));
   assert(copies == 1 && frees == 1 && calls == 2);
   assert(muted == 1 && unmuted == 1);
   for (i = 0; i < 4; i++)
      assert(output[i] == 0x5a);
   assert(output[4] == 0xa5);

   reset();
   assert(retro_serialize(output, 8));
   for (i = 4; i < 8; i++)
      assert(output[i] == 0);
   assert(output[8] == 0xa5 && copies == 1 && frees == 1);

   reset();
   assert(!retro_serialize(output, 2));
   unchanged();
   assert(frees == 1);

   for (phase = 1; phase <= 2; phase++)
   {
      reset();
      fail_phase = phase;
      assert(!retro_serialize(output, 4));
      unchanged();
      assert(frees == (phase == 2));
   }

   reset();
   fail_allocation = 1;
   assert(!retro_serialize(output, 4));
   unchanged();
   assert(frees == 0);

   reset();
   state_size = 0;
   assert(!retro_serialize(output, 4));
   unchanged();
   assert(frees == 1);

   reset();
   assert(!retro_serialize(NULL, 4));
   assert(!retro_serialize(output, 0));
   assert(calls == 0 && copies == 0 && muted == 0 && unmuted == 0);
   return 0;
}
