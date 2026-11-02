/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RA_LAB_RPCS3_JIT_PROBE_H
#define RA_LAB_RPCS3_JIT_PROBE_H
#include <TargetConditionals.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/ucontext.h>
#include <unistd.h>
#include <stdint.h>

#if defined(__arm64__) && !TARGET_OS_SIMULATOR
static struct sigaction ra_ps3_previous_trap;
static void ra_ps3_probe_trap(int signal, siginfo_t *info, void *raw)
{
   ucontext_t *context = (ucontext_t *)raw;
   if (context && context->uc_mcontext)
   {
      __uint64_t pc = context->uc_mcontext->__ss.__pc;
      if (pc && *(const uint32_t *)pc == (0xd4200000u | (0xf00du << 5)) &&
            context->uc_mcontext->__ss.__x[16] == 1)
      {
         context->uc_mcontext->__ss.__x[0] = 0;
         context->uc_mcontext->__ss.__pc += 4;
         return;
      }
   }
   if (ra_ps3_previous_trap.sa_flags & SA_SIGINFO)
      ra_ps3_previous_trap.sa_sigaction(signal, info, raw);
   else if (ra_ps3_previous_trap.sa_handler != SIG_DFL &&
         ra_ps3_previous_trap.sa_handler != SIG_IGN)
      ra_ps3_previous_trap.sa_handler(signal);
   else if (ra_ps3_previous_trap.sa_handler != SIG_IGN)
   { sigaction(SIGTRAP, &ra_ps3_previous_trap, NULL); raise(signal); }
}

/* Must run under the Lab activation lease; leaves Universal attached. */
static BOOL RALabPS3JITAttached(void)
{
   size_t length = (size_t)getpagesize();
   void *probe = mmap(NULL, length, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
   struct sigaction action;
   uintptr_t result;
   if (probe == MAP_FAILED) return NO;
   memset(&action, 0, sizeof(action));
   action.sa_sigaction = ra_ps3_probe_trap;
   action.sa_flags = SA_SIGINFO;
   sigemptyset(&action.sa_mask);
   if (sigaction(SIGTRAP, &action, &ra_ps3_previous_trap))
   { munmap(probe, length); return NO; }
   __asm__ volatile("mov x0, %1\nmov x1, %2\nmov x16, #1\nbrk #0xf00d\nmov %0, x0"
         : "=r"(result) : "r"(probe), "r"(length) : "x0", "x1", "x16", "memory");
   sigaction(SIGTRAP, &ra_ps3_previous_trap, NULL);
   munmap(probe, length);
   return result == (uintptr_t)probe;
}
#else
static BOOL RALabPS3JITAttached(void) { return NO; }
#endif
#endif
