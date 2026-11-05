/* SPDX-License-Identifier: GPL-3.0-or-later */
#import "RetroArchLabPerformance.h"
#include "../../../pkg/apple/ipad-lab/performance/PerformanceStats.h"
#include <os/lock.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static int ra_perf_enabled;
static double ra_perf_time_scale;
static os_unfair_lock ra_perf_lock = OS_UNFAIR_LOCK_INIT;
static struct
{
   ra_lab_perf_window window;
   uint64_t begin, session, audio_total, audio_at, ps3_at, heartbeat;
   double target, video_ms, audio_ms, ps3_fps, ps3_rsx;
   unsigned video_calls, audio_calls, ps3_valid;
   int mode, threaded_video, audio_valid, foreground;
   char core[128], game[256], video[64], audio[64], ps3_state[128];
} ra_perf;

static uint64_t RALabPerfNow(void)
{ return (uint64_t)(mach_absolute_time() * ra_perf_time_scale); }
uint64_t ra_lab_perf_clock(void)
{ return __atomic_load_n(&ra_perf_enabled, __ATOMIC_RELAXED) ? RALabPerfNow() : 0; }
void ra_lab_perf_begin(const char *core, const char *game, double hz,
      int mode, const char *video, const char *audio, int threaded_video)
{
   uint64_t now = ra_lab_perf_clock();
   if (!now) return;
   os_unfair_lock_lock(&ra_perf_lock);
   if (strcmp(ra_perf.core, core ?: "") || strcmp(ra_perf.game, game ?: "") || ra_perf.mode != mode)
      ra_perf.window.last_end = 0;
   strlcpy(ra_perf.core, core ?: "", sizeof(ra_perf.core));
   strlcpy(ra_perf.game, game ?: "", sizeof(ra_perf.game));
   strlcpy(ra_perf.video, video ?: "", sizeof(ra_perf.video));
   strlcpy(ra_perf.audio, audio ?: "", sizeof(ra_perf.audio));
   ra_perf.begin = now; ra_perf.target = hz; ra_perf.mode = mode;
   ra_perf.threaded_video = threaded_video;
   os_unfair_lock_unlock(&ra_perf_lock);
}
void ra_lab_perf_end(void)
{
   uint64_t now = ra_lab_perf_clock();
   if (!now) return;
   os_unfair_lock_lock(&ra_perf_lock);
   if (ra_perf.begin >= ra_perf.session && ra_perf.begin && now >= ra_perf.begin)
      ra_lab_perf_frame(&ra_perf.window, ra_perf.begin, now, ra_perf.target, ra_perf.mode == 0);
   ra_perf.begin = 0;
   os_unfair_lock_unlock(&ra_perf_lock);
}
void ra_lab_perf_idle(void)
{
   if (!__atomic_load_n(&ra_perf_enabled, __ATOMIC_RELAXED)) return;
   os_unfair_lock_lock(&ra_perf_lock);
   ra_perf.window.last_end = 0; ra_perf.begin = 0;
   os_unfair_lock_unlock(&ra_perf_lock);
}
void ra_lab_perf_stage(uint64_t start, int audio)
{
   uint64_t now = ra_lab_perf_clock();
   if (!start || !now || now < start) return;
   os_unfair_lock_lock(&ra_perf_lock);
   if (start >= ra_perf.session)
   {
      if (audio) { ra_perf.audio_ms += (now - start) / 1000.0; ra_perf.audio_calls++; }
      else { ra_perf.video_ms += (now - start) / 1000.0; ra_perf.video_calls++; }
   }
   os_unfair_lock_unlock(&ra_perf_lock);
}
void ra_lab_perf_audio(uint64_t underruns, int valid)
{
   if (!__atomic_load_n(&ra_perf_enabled, __ATOMIC_RELAXED)) return;
   os_unfair_lock_lock(&ra_perf_lock);
   ra_perf.audio_total = underruns; ra_perf.audio_valid = valid;
   ra_perf.audio_at = RALabPerfNow();
   os_unfair_lock_unlock(&ra_perf_lock);
}
void RALabPerfPS3(NSString *state, unsigned valid, double fps, double rsx)
{
   if (!__atomic_load_n(&ra_perf_enabled, __ATOMIC_RELAXED)) return;
   os_unfair_lock_lock(&ra_perf_lock);
   ra_perf.ps3_at = RALabPerfNow(); ra_perf.ps3_valid = valid;
   ra_perf.ps3_fps = fps; ra_perf.ps3_rsx = rsx;
   strlcpy(ra_perf.ps3_state, state.UTF8String ?: "", sizeof(ra_perf.ps3_state));
   os_unfair_lock_unlock(&ra_perf_lock);
}

@interface RALabPerformance : NSObject
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) dispatch_source_t timer;
@property(nonatomic, strong) UIButton *badge;
@property(atomic, copy) NSString *summary;
@property(atomic, copy) NSString *failure;
@property(nonatomic) int descriptor;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) uint64_t started, lastSample, lastAudio;
@property(nonatomic) double lastCPU;
@property(nonatomic) BOOL audioBaseline, pingPending;
+ (instancetype)shared;
- (void)start;
- (void)stop:(NSString *)reason;
- (void)event:(NSString *)message;
- (NSArray<NSURL *> *)reports;
@end

static double RALabPerfCPU(void)
{
   struct rusage usage;
   if (getrusage(RUSAGE_SELF, &usage)) return -1;
   return usage.ru_utime.tv_sec + usage.ru_stime.tv_sec +
         (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1000000.0;
}
static id RALabPerfNumber(double value)
{ return isfinite(value) && value >= 0 ? @(value) : NSNull.null; }

@implementation RALabPerformance
+ (instancetype)shared
{
   static RALabPerformance *instance;
   static dispatch_once_t once;
   dispatch_once(&once, ^{ instance = [[self alloc] init]; });
   return instance;
}
- (instancetype)init
{
   if ((self = [super init]))
   {
      mach_timebase_info_data_t timebase;
      mach_timebase_info(&timebase);
      ra_perf_time_scale = (double)timebase.numer / timebase.denom / 1000.0;
      self.queue = dispatch_queue_create("lab.performance", DISPATCH_QUEUE_SERIAL);
      self.descriptor = -1;
      self.summary = @"Ready to record. Open a game after starting, then play the same section for 2–3 minutes.";
      NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
      [center addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
      [center addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
      [center addObserver:self selector:@selector(memoryWarning) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
      [center addObserver:self selector:@selector(thermal) name:NSProcessInfoThermalStateDidChangeNotification object:nil];
   }
   return self;
}
- (NSURL *)directory
{
   NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
   return [documents URLByAppendingPathComponent:@"Performance" isDirectory:YES];
}
- (NSArray<NSURL *> *)reports
{
   NSArray *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:self.directory includingPropertiesForKeys:nil options:0 error:nil];
   NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
      return [url.lastPathComponent hasPrefix:@"LabPerf-"] && [url.pathExtension isEqualToString:@"jsonl"];
   }];
   return [[files filteredArrayUsingPredicate:filter] sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
      return [b.lastPathComponent compare:a.lastPathComponent];
   }] ?: @[];
}
- (void)write:(NSDictionary *)row
{
   if (self.descriptor < 0) return;
   NSData *json = [NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:nil];
   if (!json) { self.failure = @"The diagnostic report could not encode a sample."; [self stopOnQueue:@"encoding_error"]; return; }
   NSMutableData *line = [json mutableCopy];
   [line appendBytes:"\n" length:1];
   const char *bytes = line.bytes;
   NSUInteger remaining = line.length;
   while (remaining)
   {
      ssize_t count = write(self.descriptor, bytes, remaining);
      if (count < 0 && errno == EINTR) continue;
      if (count <= 0)
      {
         self.failure = @"Recording stopped because the report could not be saved. Check available storage.";
         __atomic_store_n(&ra_perf_enabled, 0, __ATOMIC_RELAXED);
         close(self.descriptor); self.descriptor = -1;
         if (self.timer) dispatch_source_cancel(self.timer);
         self.timer = nil;
         dispatch_async(dispatch_get_main_queue(), ^{ if (!ra_lab_perf_clock()) [self.badge removeFromSuperview]; });
         return;
      }
      bytes += count; remaining -= count;
   }
   self.bytes += line.length;
}
- (void)start
{
   dispatch_sync(self.queue, ^{
      if (self.descriptor >= 0) return;
      self.failure = nil;
      NSError *error = nil;
      if (![NSFileManager.defaultManager createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:nil error:&error])
      { self.failure = error.localizedDescription; return; }
      [self.directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
      NSArray *reports = self.reports;
      for (NSUInteger i = 4; i < reports.count; i++)
         [NSFileManager.defaultManager removeItemAtURL:reports[i] error:nil];
      NSDateFormatter *format = [[NSDateFormatter alloc] init];
      format.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
      format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
      format.dateFormat = @"yyyyMMdd-HHmmss-SSS";
      NSString *name = [NSString stringWithFormat:@"LabPerf-%@-%@.jsonl", [format stringFromDate:NSDate.date], NSUUID.UUID.UUIDString];
      self.descriptor = open([[self.directory URLByAppendingPathComponent:name] fileSystemRepresentation], O_WRONLY | O_CREAT | O_EXCL, 0600);
      if (self.descriptor < 0) { self.failure = @"Could not create a performance report. Check available storage."; return; }
      self.bytes = 0; self.audioBaseline = NO; self.pingPending = NO;
      self.started = self.lastSample = RALabPerfNow(); self.lastCPU = RALabPerfCPU();
      os_unfair_lock_lock(&ra_perf_lock);
      memset(&ra_perf, 0, sizeof(ra_perf));
      ra_perf.session = self.started; ra_perf.heartbeat = self.started; ra_perf.foreground = 1;
      os_unfair_lock_unlock(&ra_perf_lock);
      [self write:@{@"type": @"session", @"schema": @1, @"started_utc": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
            @"build": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
            @"os": UIDevice.currentDevice.systemVersion, @"device": UIDevice.currentDevice.model,
            @"logical_cpus": @(NSProcessInfo.processInfo.processorCount), @"sample_seconds": @1,
            @"limits": @"10 minutes, 1.5 MB per report, latest 5 reports",
            @"metric_notes": @"CPU: 100% is one logical core. Core work includes callbacks/waits. Video submission includes synchronization, not GPU execution. Audio writes may intentionally block. PS3 RSX is an estimate. Frame cadence is libretro iterations, not unique displayed frames. P95 is a 1 ms histogram capped at 500 ms; maximum is uncapped. Missing metrics are null. Slow frame means >1.5x the core frame budget in normal speed."}];
      if (self.descriptor < 0) return;
      __atomic_store_n(&ra_perf_enabled, 1, __ATOMIC_RELAXED);
      self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
      dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
      dispatch_source_set_event_handler(self.timer, ^{ [self sample]; });
      dispatch_resume(self.timer);
      self.summary = @"Recording. Return to your game. Tap the red badge when you notice a slowdown.";
   });
   if (!ra_lab_perf_clock()) return;
   UIWindow *window = nil;
   for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
      if ([scene isKindOfClass:UIWindowScene.class])
         for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
            if (candidate.isKeyWindow) window = candidate;
   if (!window) return;
   if (!self.badge)
   {
      self.badge = [UIButton buttonWithType:UIButtonTypeSystem];
      self.badge.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.8];
      [self.badge setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
      self.badge.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
      self.badge.layer.cornerRadius = 8;
      self.badge.accessibilityLabel = @"Mark slowdown in performance recording";
      [self.badge addTarget:self action:@selector(mark) forControlEvents:UIControlEventTouchUpInside];
   }
   [self.badge setTitle:@"● REC · Mark slowdown" forState:UIControlStateNormal];
   self.badge.translatesAutoresizingMaskIntoConstraints = NO;
   [window addSubview:self.badge];
   [NSLayoutConstraint activateConstraints:@[
      [self.badge.centerXAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.centerXAnchor],
      [self.badge.bottomAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.bottomAnchor constant:-4],
      [self.badge.widthAnchor constraintEqualToConstant:245], [self.badge.heightAnchor constraintEqualToConstant:36]]];
}
- (void)mark { [self event:@"USER: slowdown noticed"]; }
- (void)event:(NSString *)message
{
   uint64_t now = ra_lab_perf_clock();
   if (!now) return;
   NSString *limited = message.length > 512 ? [message substringToIndex:512] : message;
   dispatch_async(self.queue, ^{
      if (now < self.started || self.descriptor < 0) return;
      [self write:@{@"type": @"event", @"elapsed_s": @((now - self.started) / 1000000.0), @"message": limited ?: @""}];
   });
}
- (void)stopOnQueue:(NSString *)reason
{
   __atomic_store_n(&ra_perf_enabled, 0, __ATOMIC_RELAXED);
   if (self.timer) dispatch_source_cancel(self.timer);
   self.timer = nil;
   if (self.descriptor >= 0)
   {
      [self write:@{@"type": @"end", @"elapsed_s": @((RALabPerfNow() - self.started) / 1000000.0), @"reason": reason}];
      if (self.descriptor >= 0) { fsync(self.descriptor); close(self.descriptor); self.descriptor = -1; }
   }
   dispatch_async(dispatch_get_main_queue(), ^{ if (!ra_lab_perf_clock()) [self.badge removeFromSuperview]; });
}
- (void)stop:(NSString *)reason
{ dispatch_sync(self.queue, ^{ if (self.descriptor >= 0) { [self sample]; [self stopOnQueue:reason]; } }); }
- (void)background
{
   [self event:@"App inactive; cadence suspended"];
   os_unfair_lock_lock(&ra_perf_lock); ra_perf.foreground = 0; ra_perf.window.last_end = 0; ra_perf.begin = 0; os_unfair_lock_unlock(&ra_perf_lock);
}
- (void)foreground
{
   os_unfair_lock_lock(&ra_perf_lock); ra_perf.foreground = 1; ra_perf.window.last_end = 0; ra_perf.heartbeat = RALabPerfNow(); os_unfair_lock_unlock(&ra_perf_lock);
   [self event:@"App active"];
}
- (void)memoryWarning { [self event:@"MEMORY WARNING received from iOS"]; }
- (void)thermal { [self event:[NSString stringWithFormat:@"Thermal state changed: %ld", (long)NSProcessInfo.processInfo.thermalState]]; }
- (void)sample
{
   if (self.descriptor < 0) return;
   os_unfair_lock_lock(&ra_perf_lock);
   __typeof__(ra_perf) s = ra_perf;
   ra_lab_perf_next_window(&ra_perf.window);
   ra_perf.video_ms = ra_perf.audio_ms = 0; ra_perf.video_calls = ra_perf.audio_calls = 0;
   uint64_t now = RALabPerfNow();
   os_unfair_lock_unlock(&ra_perf_lock);
   double seconds = (now - self.lastSample) / 1000000.0;
   if (seconds <= 0) return;
   double cpu = RALabPerfCPU();
   id cpuPercent = cpu >= self.lastCPU && self.lastCPU >= 0 ? @((cpu - self.lastCPU) / seconds * 100.0) : NSNull.null;
   self.lastCPU = cpu; self.lastSample = now;
   struct task_vm_info memory;
   mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
   id footprint = task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&memory, &count) == KERN_SUCCESS ? @(memory.phys_footprint) : NSNull.null;
   BOOL audioFresh = s.audio_valid && now - s.audio_at < 2000000;
   id underruns = audioFresh && self.audioBaseline && s.audio_total >= self.lastAudio ? @(s.audio_total - self.lastAudio) : NSNull.null;
   self.audioBaseline = audioFresh; self.lastAudio = s.audio_total;
   BOOL ps3 = s.ps3_at && now - s.ps3_at < 2500000;
   double fps = s.window.intervals && s.window.interval_sum > 0 ? s.window.intervals * 1000.0 / s.window.interval_sum : -1;
   double uiGap = s.foreground ? (now - s.heartbeat) / 1000000.0 : 0;
   NSArray *thermalNames = @[@"nominal", @"fair", @"serious", @"critical"];
   NSUInteger thermal = NSProcessInfo.processInfo.thermalState;
   NSMutableArray *signals = [NSMutableArray array];
   if (s.window.late) [signals addObject:@"slow_frames"];
   if ([underruns respondsToSelector:@selector(unsignedLongLongValue)] && [underruns unsignedLongLongValue]) [signals addObject:@"audio_underruns"];
   if (thermal >= 2) [signals addObject:@"thermal_pressure"];
   if (uiGap > 2) [signals addObject:@"main_thread_unresponsive"];
   if (s.foreground && s.begin && now - s.begin > 250000) [signals addObject:@"core_call_in_progress_over_250ms"];
   NSString *state = ps3 ? @(s.ps3_state) : (s.begin ? @"core call in progress" : (s.window.frames ? @"libretro" : @"menu, paused, loading or no completed core calls"));
   NSMutableDictionary *row = [@{@"type": @"sample", @"elapsed_s": @((now - self.started) / 1000000.0), @"window_s": @(seconds),
      @"foreground": @(s.foreground), @"core": @(s.core), @"game": @(s.game), @"state": state,
      @"target_hz": RALabPerfNumber(s.target > 0 ? s.target : -1), @"speed_mode": @(s.mode),
      @"libretro_fps": RALabPerfNumber(fps), @"core_calls": @(s.window.frames),
      @"slow_frames": @(s.window.late), @"frame_p95_ms": s.window.intervals ? @(ra_lab_perf_p95(&s.window)) : NSNull.null,
      @"frame_max_ms": s.window.intervals ? @(s.window.interval_max) : NSNull.null,
      @"worst_frame_at_s": s.window.worst_at ? @((s.window.worst_at - self.started) / 1000000.0) : NSNull.null,
      @"core_work_mean_ms": s.window.frames ? @(s.window.work_sum / s.window.frames) : NSNull.null,
      @"core_work_max_ms": s.window.frames ? @(s.window.work_max) : NSNull.null,
      @"core_inflight_ms": s.begin ? @((now - s.begin) / 1000.0) : NSNull.null,
      @"video_submit_ms_total": @(s.video_ms), @"video_calls": @(s.video_calls), @"video_driver": @(s.video), @"threaded_video": @(s.threaded_video),
      @"audio_write_ms_total": @(s.audio_ms), @"audio_calls": @(s.audio_calls), @"audio_driver": @(s.audio), @"audio_underruns_delta": underruns,
      @"process_cpu_percent_one_core": cpuPercent, @"memory_footprint_bytes": footprint,
      @"thermal": thermal < thermalNames.count ? thermalNames[thermal] : @"unknown", @"low_power": @(NSProcessInfo.processInfo.lowPowerModeEnabled),
      @"main_thread_gap_s": @(uiGap), @"signals": signals,
      @"ps3_fps": ps3 && (s.ps3_valid & 1) ? RALabPerfNumber(s.ps3_fps) : NSNull.null,
      @"ps3_rsx_estimate_percent": ps3 && (s.ps3_valid & 4) ? RALabPerfNumber(s.ps3_rsx) : NSNull.null} mutableCopy];
   [self write:row];
   double displayedFPS = ps3 && (s.ps3_valid & 1) ? s.ps3_fps : fps;
   NSString *fpsText = displayedFPS >= 0 && isfinite(displayedFPS) ? [NSString stringWithFormat:@"%.1f fps", displayedFPS] : @"FPS unavailable";
   self.summary = [NSString stringWithFormat:@"%.0f seconds · %@\n%@\nCPU %@%% (100%% = one core) · Memory %@ MB\nHeat: %@ · Slow frames this window: %llu\nSignals: %@\n\nCore work max: %.1f ms · Frame max: %.1f ms\nVideo submission: %.1f ms · Audio writes: %.1f ms (window totals)",
      (now - self.started) / 1000000.0, fpsText, state,
      cpuPercent == NSNull.null ? @"—" : [NSString stringWithFormat:@"%.0f", [cpuPercent doubleValue]],
      footprint == NSNull.null ? @"—" : [NSString stringWithFormat:@"%.0f", [footprint doubleValue] / 1048576.0],
      row[@"thermal"], (unsigned long long)s.window.late, signals.count ? [signals componentsJoinedByString:@", "] : @"none observed",
      s.window.work_max, s.window.interval_max, s.video_ms, s.audio_ms];
   if (!self.pingPending)
   {
      self.pingPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
         os_unfair_lock_lock(&ra_perf_lock); ra_perf.heartbeat = RALabPerfNow(); os_unfair_lock_unlock(&ra_perf_lock);
         [self.badge setTitle:[NSString stringWithFormat:@"● %@ · Mark slowdown", fpsText] forState:UIControlStateNormal];
         [self.badge.superview bringSubviewToFront:self.badge];
         dispatch_async(self.queue, ^{ self.pingPending = NO; });
      });
   }
   if (now - self.started >= 600000000 || self.bytes >= 1500000)
      [self stopOnQueue:@"recording_limit"];
}
@end

void RALabPerfEvent(NSString *event)
{ if (ra_lab_perf_clock()) [[RALabPerformance shared] event:event]; }

@interface RALabPerformanceController : UIViewController
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UIButton *toggle;
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation RALabPerformanceController
- (void)viewDidLoad
{
   [super viewDidLoad]; self.title = @"Performance";
   self.view.backgroundColor = UIColor.systemBackgroundColor;
   self.toggle = [UIButton buttonWithType:UIButtonTypeSystem];
   self.toggle.accessibilityIdentifier = @"Performance recording";
   [self.toggle addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
   UIButton *mark = [UIButton buttonWithType:UIButtonTypeSystem];
   [mark setTitle:@"Mark slowdown" forState:UIControlStateNormal];
   [mark addTarget:self action:@selector(mark) forControlEvents:UIControlEventTouchUpInside];
   UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
   [share setTitle:@"Share a report…" forState:UIControlStateNormal];
   [share addTarget:self action:@selector(share:) forControlEvents:UIControlEventTouchUpInside];
   self.text = [[UITextView alloc] init]; self.text.editable = NO;
   self.text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
   self.text.accessibilityIdentifier = @"Performance summary";
   UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.toggle, mark, share, self.text]];
   stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12;
   stack.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:stack];
   [NSLayoutConstraint activateConstraints:@[
      [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
      [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-48],
      [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
      [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16]]];
   for (UIButton *button in @[self.toggle, mark, share]) [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
   [self refresh];
}
- (void)viewDidAppear:(BOOL)animated
{
   [super viewDidAppear:animated];
   __weak RALabPerformanceController *weakSelf = self;
   self.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
}
- (void)viewWillDisappear:(BOOL)animated
{ [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer = nil; }
- (void)refresh
{
   RALabPerformance *recorder = RALabPerformance.shared;
   BOOL active = ra_lab_perf_clock() != 0;
   [self.toggle setTitle:active ? @"Stop recording" : @"Start recording" forState:UIControlStateNormal];
   self.text.text = [NSString stringWithFormat:@"%@\n\n%@\n\nRecord the same game section for 2–3 minutes. Tap the red badge at a slowdown, then return here and stop. Reports stay on this device until you share them; they include game filenames, not game data.\n\nRecording stops after 10 minutes or 1.5 MB. The latest 5 reports are kept in Files > RetroArch Lab > Performance. A report without an end row was interrupted.\n\nFrame cadence counts libretro calls, not unique frames. Audio/video timing includes normal synchronization waits. GPU timing and per-core internals need a separate profiler; PS3 RSX utilization is an estimate. Missing metrics are unavailable, not zero.",
      recorder.failure ?: (active ? @"RECORDING" : @"Recording off"), recorder.summary];
}
- (void)toggleRecording
{
   if (ra_lab_perf_clock()) [RALabPerformance.shared stop:@"user_stopped"];
   else [RALabPerformance.shared start];
   [self refresh];
}
- (void)mark { [RALabPerformance.shared mark]; }
- (void)share:(UIButton *)button
{
   if (ra_lab_perf_clock()) [RALabPerformance.shared stop:@"shared_report"];
   NSArray *reports = RALabPerformance.shared.reports;
   UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Performance reports" message:reports.count ? @"Choose a recording to share." : @"Start a recording first." preferredStyle:UIAlertControllerStyleActionSheet];
   for (NSURL *url in reports)
      [picker addAction:[UIAlertAction actionWithTitle:[url.lastPathComponent substringToIndex:MIN(27, url.lastPathComponent.length)] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
         UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
         share.popoverPresentationController.sourceView = button;
         share.popoverPresentationController.sourceRect = button.bounds;
         [self presentViewController:share animated:YES completion:nil];
      }]];
   [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
   picker.popoverPresentationController.sourceView = button; picker.popoverPresentationController.sourceRect = button.bounds;
   [self presentViewController:picker animated:YES completion:nil];
   [self refresh];
}
@end
void RALabPerfShow(UIViewController *parent)
{ [parent.navigationController pushViewController:[RALabPerformanceController new] animated:YES]; }
