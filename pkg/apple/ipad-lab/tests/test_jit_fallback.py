"""Compile the actual LAN-bless policy and guard its coordinator wiring."""
from pathlib import Path
import os
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
SUPPORT = ROOT / 'pkg/apple/JITSupport.m'
COORDINATOR = ROOT / 'ui/drivers/cocoa/RetroArchLabJIT.m'


def method(source, start, end):
    return source.split(start, 1)[1].split(end, 1)[0]


class JITFallbackTests(unittest.TestCase):
    def compile_policy(self, lab, concurrent=False):
        compiler = shlex.split(os.environ.get('CC', 'cc'))
        if not shutil.which(compiler[0]):
            self.skipTest('a C compiler is required')
        source = SUPPORT.read_text(encoding='utf-8')
        state = source[source.index('#ifdef HAVE_RETROARCH_LAB_STIKJIT\nenum {'):]
        state = state.split('#endif', 1)[0] + '#endif\n'
        policy = source[source.index('static bool remote_bless_allowed(void)'):]
        policy = policy.split('static bool device_has_txm(void)', 1)[0]
        # Substitute only the platform preferences read; execute the real policy.
        policy, count = re.subn(
            r'const char \*method = \[\[NSUserDefaults\.standardUserDefaults\s+'
            r'stringForKey:@"RALabJITMethod"\] UTF8String\];',
            'const char *method = test_method;', policy)
        self.assertEqual(count, 1)
        harness = '''
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#ifdef TEST_CONCURRENT
#include <pthread.h>
#include <sched.h>
#endif
#ifdef HAVE_RETROARCH_LAB_STIKJIT
static const char *test_method;
#endif
''' + state + policy + '''
#ifdef TEST_CONCURRENT
static unsigned active;
static void *contend(void *builtin)
{
   unsigned i;
   for (i = 0; i < 10000; ++i)
   {
      bool acquired = builtin ? exec_mem_begin_builtin_jit() : remote_bless_acquire();
      if (!acquired) continue;
      assert(__atomic_fetch_add(&active, 1, __ATOMIC_SEQ_CST) == 0);
      sched_yield();
      assert(__atomic_fetch_sub(&active, 1, __ATOMIC_SEQ_CST) == 1);
      if (builtin) exec_mem_end_builtin_jit();
      else remote_bless_release(false);
   }
   return NULL;
}
#endif
int main(void)
{
#ifdef HAVE_RETROARCH_LAB_STIKJIT
   const char *methods[] = {NULL, "builtin", "stikdebug", "external", "unknown", "STIKDEBUG"};
   unsigned i;
   for (i = 0; i < sizeof(methods) / sizeof(methods[0]); ++i)
   {
      test_method = methods[i];
      assert(remote_bless_allowed() == (i == 2 || i == 3));
      assert(exec_mem_begin_builtin_jit());
      assert(!remote_bless_allowed());
      assert(!remote_bless_acquire());
      remote_bless_release(false);
      assert(!remote_bless_allowed());
      exec_mem_end_builtin_jit();
      assert(remote_bless_allowed() == (i == 2 || i == 3));
   }
   test_method = "external";
   assert(remote_bless_acquire());
   assert(!exec_mem_begin_builtin_jit());
   assert(!remote_bless_acquire());
   exec_mem_end_builtin_jit();
   assert(!exec_mem_begin_builtin_jit());
   remote_bless_release(false);
   assert(exec_mem_begin_builtin_jit());
   exec_mem_end_builtin_jit();
#ifdef TEST_CONCURRENT
   {
      pthread_t builtin, remote;
      assert(pthread_create(&builtin, NULL, contend, (void *)1) == 0);
      assert(pthread_create(&remote, NULL, contend, NULL) == 0);
      assert(pthread_join(builtin, NULL) == 0);
      assert(pthread_join(remote, NULL) == 0);
      assert(active == 0);
   }
#endif
   assert(remote_bless_acquire());
   remote_bless_release(true);
   assert(!remote_bless_allowed());
   assert(!remote_bless_acquire());
   assert(!exec_mem_begin_builtin_jit());
   exec_mem_end_builtin_jit();
   assert(!exec_mem_begin_builtin_jit());
#else
   assert(remote_bless_allowed());
   assert(remote_bless_acquire());
   remote_bless_release(true);
   assert(remote_bless_allowed());
#endif
   return 0;
}
'''
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'policy.c').write_text(harness, encoding='utf-8')
            command = compiler + ['-std=c99', '-Wall', '-Wextra', '-Werror']
            if lab:
                command.append('-DHAVE_RETROARCH_LAB_STIKJIT')
            if concurrent:
                command += ['-DTEST_CONCURRENT', '-pthread']
            subprocess.run(command + [str(path / 'policy.c'), '-o', str(path / 'policy')],
                           check=True, capture_output=True, text=True)
            subprocess.run([str(path / 'policy')], check=True)

    def test_external_choices_resume_after_builtin_attempt(self):
        self.compile_policy(lab=True)

    def test_non_lab_build_retains_existing_fallback(self):
        self.compile_policy(lab=False)

    def test_builtin_and_remote_contenders_cannot_overlap(self):
        self.compile_policy(lab=True, concurrent=True)

    def test_discovery_retry_and_queued_connections_recheck_policy(self):
        source = SUPPORT.read_text(encoding='utf-8')
        request = method(source, 'static void exec_mem_request_remote_bless(void)\n{', '\n}\n')
        self.assertLess(request.index('!remote_bless_allowed()'), request.index('dispatch_once('))
        start = method(source, '- (void)start\n{', '\n- (void)netServiceBrowser:')
        self.assertLess(start.index('remote_bless_allowed()'), start.index('searchForServicesOfType:'))
        retry = method(source, '- (void)scheduleRetry\n{', '\n- (void)netServiceBrowser:')
        self.assertLess(retry.index('remote_bless_allowed()'), retry.index('searchForServicesOfType:'))
        resolve = method(source, '- (void)netServiceDidResolveAddress:', '\n/* A service already reported')
        self.assertIn('!remote_bless_acquire()', resolve)
        self.assertLess(resolve.index('!remote_bless_acquire()'), resolve.index('[self ask:'))
        self.assertLess(resolve.index('[self ask:'),
                        resolve.index('dispatch_sync(dispatch_get_main_queue()'))
        self.assertLess(resolve.index('dispatch_sync(dispatch_get_main_queue()'),
                        resolve.index('remote_bless_finish(&uncertain)'))
        self.assertLess(resolve.index('remote_bless_finish(&uncertain)'),
                        resolve.index('remote_bless_release(uncertain)'))
        ask = source.rsplit('- (BOOL)ask:', 1)[1].split('\n@end', 1)[0]
        self.assertLess(ask.index('!remote_bless_allowed()'), ask.index('socket('))
        connected = ask.split('connect_bounded(fd', 1)[1]
        self.assertLess(connected.index('!remote_bless_allowed()'), connected.index('send(fd'))
        self.assertIn('*uncertain = sent > 0', ask)
        self.assertIn('if (!complete || received == 0)', ask)
        self.assertIn('CFBooleanGetTypeID()', ask)

    def test_coordinator_suppresses_setup_and_activation_before_pool_probe(self):
        source = COORDINATOR.read_text(encoding='utf-8')
        begin = method(source, '- (void)beginOperation:', '\n@end')
        self.assertIn('BOOL builtin = !enabling || [[self method] isEqualToString:@"builtin"]', begin)
        self.assertLess(begin.index('!exec_mem_begin_builtin_jit()'),
                        begin.index('exec_mem_pool_init()'))
        self.assertEqual(begin.count('if (builtin) exec_mem_end_builtin_jit()'), 2)
        finish = method(source, '- (void)finish:', '\n- (void)poll:')
        self.assertLess(finish.index('generation != self.generation'),
                        finish.index('exec_mem_end_builtin_jit()'))


if __name__ == '__main__':
    unittest.main()
