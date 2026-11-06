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
#import <QuartzCore/QuartzCore.h>

@interface RALabPerformanceGauge : UIView
@property(nonatomic, strong) CAShapeLayer *track, *fill;
@property(nonatomic, strong) UILabel *value, *caption;
- (instancetype)initWithTitle:(NSString *)title color:(UIColor *)color;
- (void)setPercent:(id)percent;
@end
@implementation RALabPerformanceGauge
- (instancetype)initWithTitle:(NSString *)title color:(UIColor *)color
{
   if ((self = [super initWithFrame:CGRectZero]))
   {
      self.track = [CAShapeLayer layer]; self.fill = [CAShapeLayer layer];
      for (CAShapeLayer *layer in @[self.track, self.fill])
      {
         layer.fillColor = UIColor.clearColor.CGColor; layer.lineWidth = 3;
         layer.lineCap = kCALineCapRound; [self.layer addSublayer:layer];
      }
      self.track.strokeColor = [UIColor.blackColor colorWithAlphaComponent:0.15].CGColor;
      self.fill.strokeColor = color.CGColor;
      self.value = [UILabel new]; self.caption = [UILabel new];
      self.value.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightHeavy];
      self.caption.font = [UIFont systemFontOfSize:8 weight:UIFontWeightHeavy];
      self.caption.text = title;
      for (UILabel *label in @[self.value, self.caption])
      {
         label.textColor = UIColor.blackColor; label.textAlignment = NSTextAlignmentCenter;
         label.adjustsFontSizeToFitWidth = YES; label.minimumScaleFactor = 0.7;
         [self addSubview:label];
      }
      [self setPercent:nil];
   }
   return self;
}
- (void)layoutSubviews
{
   [super layoutSubviews];
   CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
   UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(width / 2, height / 2 - 2)
         radius:MAX(1, MIN(width, height) / 2 - 4) startAngle:M_PI * 0.75 endAngle:M_PI * 2.25 clockwise:YES];
   self.track.path = self.fill.path = arc.CGPath;
   self.value.frame = CGRectMake(2, height / 2 - 11, width - 4, 15);
   self.caption.frame = CGRectMake(0, height - 13, width, 11);
}
- (void)setPercent:(id)percent
{
   BOOL valid = [percent isKindOfClass:NSNumber.class] && isfinite([percent doubleValue]) && [percent doubleValue] >= 0;
   self.value.text = valid ? [NSString stringWithFormat:@"%.0f%%", [percent doubleValue]] : @"—";
   [CATransaction begin]; [CATransaction setDisableActions:YES];
   self.fill.strokeEnd = valid ? MIN(1, [percent doubleValue] / 100.0) : 0;
   [CATransaction commit];
}
@end

@interface RALabPerformanceHUD : UIControl
@property(nonatomic, strong) UILabel *fps, *unit;
@property(nonatomic, strong) UIView *recordingDot;
@property(nonatomic, strong) RALabPerformanceGauge *cpu, *gpu, *ram;
- (void)update:(NSDictionary *)sample recording:(BOOL)recording;
@end
@implementation RALabPerformanceHUD
- (instancetype)initWithFrame:(CGRect)frame
{
   if ((self = [super initWithFrame:frame]))
   {
      self.layer.cornerRadius = 32; self.clipsToBounds = YES;
      self.backgroundColor = [UIColor colorWithWhite:0.7 alpha:UIAccessibilityIsReduceTransparencyEnabled() ? 1 : 0.82];
      self.accessibilityIdentifier = @"Performance overlay"; self.isAccessibilityElement = YES;
      self.fps = [UILabel new]; self.unit = [UILabel new];
      self.fps.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightHeavy];
      self.unit.font = [UIFont systemFontOfSize:11 weight:UIFontWeightHeavy]; self.unit.text = @"FPS";
      for (UILabel *label in @[self.fps, self.unit])
      { label.textColor = UIColor.blackColor; label.textAlignment = NSTextAlignmentCenter; label.adjustsFontSizeToFitWidth = YES; }
      UIStackView *fps = [[UIStackView alloc] initWithArrangedSubviews:@[self.fps, self.unit]];
      fps.axis = UILayoutConstraintAxisVertical; fps.spacing = -2;
      self.cpu = [[RALabPerformanceGauge alloc] initWithTitle:@"CPU" color:UIColor.systemCyanColor];
      self.gpu = [[RALabPerformanceGauge alloc] initWithTitle:@"GPU≈" color:UIColor.systemPurpleColor];
      self.ram = [[RALabPerformanceGauge alloc] initWithTitle:@"RAM" color:UIColor.systemOrangeColor];
      UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[fps, self.cpu, self.gpu, self.ram]];
      stack.distribution = UIStackViewDistributionFillEqually; stack.alignment = UIStackViewAlignmentCenter; stack.spacing = 6;
      stack.userInteractionEnabled = NO; stack.translatesAutoresizingMaskIntoConstraints = NO;
      [self addSubview:stack];
      [NSLayoutConstraint activateConstraints:@[
         [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
         [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
         [stack.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
         [self.cpu.heightAnchor constraintEqualToConstant:48], [self.gpu.heightAnchor constraintEqualToConstant:48],
         [self.ram.heightAnchor constraintEqualToConstant:48]]];
      self.recordingDot = [[UIView alloc] initWithFrame:CGRectMake(8, 8, 6, 6)];
      self.recordingDot.backgroundColor = UIColor.systemRedColor; self.recordingDot.layer.cornerRadius = 3;
      self.recordingDot.userInteractionEnabled = NO; [self addSubview:self.recordingDot];
      [self update:nil recording:NO];
   }
   return self;
}
- (void)update:(NSDictionary *)sample recording:(BOOL)recording
{
   id fps = sample[@"ps3_fps"];
   BOOL ps3 = [fps isKindOfClass:NSNumber.class];
   if (!ps3) fps = sample[@"libretro_fps"];
   self.fps.text = [fps isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"%.1f", [fps doubleValue]] : @"—";
   [self.cpu setPercent:sample[@"process_cpu_percent_device"]];
   [self.gpu setPercent:sample[@"ps3_rsx_estimate_percent"]];
   [self.ram setPercent:sample[@"memory_footprint_percent_physical"]];
   self.recordingDot.hidden = !recording;
   self.userInteractionEnabled = recording;
   self.accessibilityLabel = recording ? @"Performance overlay, recording" : @"Live performance overlay";
   self.accessibilityHint = recording ? @"Double tap to mark a slowdown" : @"Enable recording in Performance to save a report";
   self.accessibilityValue = [NSString stringWithFormat:@"%@ %@ FPS, CPU %@ of device, estimated GPU %@, RAM %@ of physical memory",
         ps3 ? @"PS3" : @"Libretro cadence", self.fps.text, self.cpu.value.text, self.gpu.value.text, self.ram.value.text];
}
@end

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
@property(nonatomic, strong) RALabPerformanceHUD *badge;
@property(nonatomic, copy) NSArray<NSLayoutConstraint *> *badgeConstraints;
@property(nonatomic, weak) UIView *ps3Surface;
@property(atomic, copy) NSString *summary;
@property(atomic, copy) NSString *failure;
@property(atomic, copy) NSDictionary *latestSample;
@property(atomic) BOOL recording, overlayEnabled;
@property(nonatomic) int descriptor;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) uint64_t started, lastSample, lastAudio;
@property(nonatomic) double lastCPU;
@property(nonatomic) BOOL audioBaseline, pingPending;
+ (instancetype)shared;
- (void)start;
- (void)stop:(NSString *)reason;
- (void)event:(NSString *)message;
- (void)showOverlay:(BOOL)enabled;
- (void)updateSamplingOnQueue;
- (void)updateOverlay;
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
static NSString *RALabPerfValue(id value, NSString *format)
{ return [value isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:format, [value doubleValue]] : @"Unavailable"; }

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
         close(self.descriptor); self.descriptor = -1;
         self.recording = NO;
         [self updateSamplingOnQueue];
         return;
      }
      bytes += count; remaining -= count;
   }
   self.bytes += line.length;
}
- (void)resetSamplingOnQueue
{
   self.audioBaseline = NO; self.latestSample = nil;
   self.started = self.lastSample = RALabPerfNow(); self.lastCPU = RALabPerfCPU();
   os_unfair_lock_lock(&ra_perf_lock);
   memset(&ra_perf, 0, sizeof(ra_perf));
   ra_perf.session = self.started; ra_perf.heartbeat = self.started; ra_perf.foreground = 1;
   os_unfair_lock_unlock(&ra_perf_lock);
}
- (void)updateSamplingOnQueue
{
   BOOL enabled = self.recording || self.overlayEnabled;
   if (enabled && !self.timer)
   {
      __atomic_store_n(&ra_perf_enabled, 1, __ATOMIC_RELAXED);
      self.timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
      dispatch_source_set_timer(self.timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 10);
      dispatch_source_set_event_handler(self.timer, ^{ [self sample]; });
      dispatch_resume(self.timer);
   }
   else if (!enabled)
   {
      __atomic_store_n(&ra_perf_enabled, 0, __ATOMIC_RELAXED);
      if (self.timer) dispatch_source_cancel(self.timer);
      self.timer = nil;
   }
   dispatch_async(dispatch_get_main_queue(), ^{ [self updateOverlay]; });
}
- (void)showOverlay:(BOOL)enabled
{
   dispatch_sync(self.queue, ^{
      if (enabled && !self.timer) [self resetSamplingOnQueue];
      self.overlayEnabled = enabled;
      [self updateSamplingOnQueue];
   });
   [self updateOverlay];
}
- (void)updateOverlay
{
   UIViewController *owner = nil;
   if ((self.recording || self.overlayEnabled) && UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
      for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
         if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive)
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
               if (window.isKeyWindow) owner = window.rootViewController;
   while (owner)
   {
      if (owner.presentedViewController) owner = owner.presentedViewController;
      else if ([owner isKindOfClass:UINavigationController.class]) owner = ((UINavigationController *)owner).visibleViewController;
      else if ([owner isKindOfClass:UITabBarController.class]) owner = ((UITabBarController *)owner).selectedViewController;
      else break;
   }
   if ([owner isKindOfClass:UIAlertController.class] || [owner isKindOfClass:UIActivityViewController.class] ||
         [owner isKindOfClass:NSClassFromString(@"RALabPerformanceController")] ||
         [owner isKindOfClass:NSClassFromString(@"RALabPS3LogController")]) owner = nil;
   for (UIViewController *child in owner.childViewControllers)
      if ([child isKindOfClass:NSClassFromString(@"RALabPS3LogController")]) { owner = nil; break; }
   if (!owner)
   {
      [NSLayoutConstraint deactivateConstraints:self.badgeConstraints ?: @[]]; self.badgeConstraints = nil;
      [self.badge removeFromSuperview]; return;
   }
   if (!self.badge)
   {
      self.badge = [[RALabPerformanceHUD alloc] initWithFrame:CGRectZero];
      [self.badge addTarget:self action:@selector(mark) forControlEvents:UIControlEventTouchUpInside];
      self.badge.translatesAutoresizingMaskIntoConstraints = NO;
   }
   UIView *host = self.ps3Surface && !self.ps3Surface.hidden &&
         [self.ps3Surface isDescendantOfView:owner.view] ? self.ps3Surface : owner.view;
   if (self.badge.superview != host)
   {
      [NSLayoutConstraint deactivateConstraints:self.badgeConstraints ?: @[]];
      [self.badge removeFromSuperview]; [host addSubview:self.badge];
      NSLayoutConstraint *width = [self.badge.widthAnchor constraintEqualToConstant:232]; width.priority = 999;
      self.badgeConstraints = @[
         [self.badge.leadingAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.leadingAnchor constant:12],
         [self.badge.topAnchor constraintEqualToAnchor:host.safeAreaLayoutGuide.topAnchor constant:8],
         width, [self.badge.widthAnchor constraintLessThanOrEqualToAnchor:host.safeAreaLayoutGuide.widthAnchor constant:-24],
         [self.badge.heightAnchor constraintEqualToConstant:64]];
      [NSLayoutConstraint activateConstraints:self.badgeConstraints];
   }
   [self.badge update:self.latestSample recording:self.recording];
   [host bringSubviewToFront:self.badge];
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
      self.bytes = 0;
      [self resetSamplingOnQueue];
      [self write:@{@"type": @"session", @"schema": @1, @"started_utc": [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
            @"build": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
            @"os": UIDevice.currentDevice.systemVersion, @"device": UIDevice.currentDevice.model,
            @"logical_cpus": @(NSProcessInfo.processInfo.processorCount), @"sample_seconds": @1,
            @"physical_memory_bytes": @(NSProcessInfo.processInfo.physicalMemory),
            @"limits": @"10 minutes, 1.5 MB per report, latest 5 reports",
            @"metric_notes": @"CPU: 100% is one logical core. Core work includes callbacks/waits. Video submission includes synchronization, not GPU execution. Audio writes may intentionally block. PS3 RSX is an estimate. Frame cadence is libretro iterations, not unique displayed frames. P95 is a 1 ms histogram capped at 500 ms; maximum is uncapped. Missing metrics are null. Slow frame means >1.5x the core frame budget in normal speed."}];
      if (self.descriptor < 0) return;
      self.recording = YES;
      [self updateSamplingOnQueue];
      self.summary = @"Recording. Return to your game. Tap the performance overlay when you notice a slowdown.";
   });
   [self updateOverlay];
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
   self.recording = NO;
   if (self.descriptor >= 0)
   {
      [self write:@{@"type": @"end", @"elapsed_s": @((RALabPerfNow() - self.started) / 1000000.0), @"reason": reason}];
      if (self.descriptor >= 0) { fsync(self.descriptor); close(self.descriptor); self.descriptor = -1; }
   }
   [self updateSamplingOnQueue];
}
- (void)stop:(NSString *)reason
{ dispatch_sync(self.queue, ^{ if (self.descriptor >= 0) { [self sample]; [self stopOnQueue:reason]; } }); }
- (void)background
{
   [self event:@"App inactive; cadence suspended"];
   os_unfair_lock_lock(&ra_perf_lock); ra_perf.foreground = 0; ra_perf.window.last_end = 0; ra_perf.begin = 0; os_unfair_lock_unlock(&ra_perf_lock);
   [self updateOverlay];
}
- (void)foreground
{
   os_unfair_lock_lock(&ra_perf_lock); ra_perf.foreground = 1; ra_perf.window.last_end = 0; ra_perf.heartbeat = RALabPerfNow(); os_unfair_lock_unlock(&ra_perf_lock);
   [self event:@"App active"];
   [self updateOverlay];
}
- (void)memoryWarning { [self event:@"MEMORY WARNING received from iOS"]; }
- (void)thermal { [self event:[NSString stringWithFormat:@"Thermal state changed: %ld", (long)NSProcessInfo.processInfo.thermalState]]; }
- (void)sample
{
   if (!ra_lab_perf_clock()) return;
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
      @"slow_frames": s.window.intervals ? @(s.window.late) : NSNull.null, @"frame_p95_ms": s.window.intervals ? @(ra_lab_perf_p95(&s.window)) : NSNull.null,
      @"frame_max_ms": s.window.intervals ? @(s.window.interval_max) : NSNull.null,
      @"worst_frame_at_s": s.window.worst_at ? @((s.window.worst_at - self.started) / 1000000.0) : NSNull.null,
      @"core_work_mean_ms": s.window.frames ? @(s.window.work_sum / s.window.frames) : NSNull.null,
      @"core_work_max_ms": s.window.frames ? @(s.window.work_max) : NSNull.null,
      @"core_inflight_ms": s.begin ? @((now - s.begin) / 1000.0) : NSNull.null,
      @"video_submit_ms_total": s.video_calls ? @(s.video_ms) : NSNull.null, @"video_calls": @(s.video_calls), @"video_driver": @(s.video), @"threaded_video": @(s.threaded_video),
      @"audio_write_ms_total": s.audio_calls ? @(s.audio_ms) : NSNull.null, @"audio_calls": @(s.audio_calls), @"audio_driver": @(s.audio), @"audio_underruns_delta": underruns,
      @"process_cpu_percent_one_core": cpuPercent, @"memory_footprint_bytes": footprint,
      @"process_cpu_percent_device": cpuPercent != NSNull.null && NSProcessInfo.processInfo.processorCount ?
            RALabPerfNumber([cpuPercent doubleValue] / NSProcessInfo.processInfo.processorCount) : NSNull.null,
      @"memory_footprint_percent_physical": footprint != NSNull.null && NSProcessInfo.processInfo.physicalMemory ?
            RALabPerfNumber([footprint doubleValue] / NSProcessInfo.processInfo.physicalMemory * 100.0) : NSNull.null,
      @"thermal": thermal < thermalNames.count ? thermalNames[thermal] : @"unknown", @"low_power": @(NSProcessInfo.processInfo.lowPowerModeEnabled),
      @"main_thread_gap_s": @(uiGap), @"signals": signals,
      @"ps3_fps": ps3 && (s.ps3_valid & 1) ? RALabPerfNumber(s.ps3_fps) : NSNull.null,
      @"ps3_rsx_estimate_percent": ps3 && (s.ps3_valid & 4) ? RALabPerfNumber(s.ps3_rsx) : NSNull.null} mutableCopy];
   self.latestSample = row;
   [self write:row];
   double displayedFPS = ps3 && (s.ps3_valid & 1) ? s.ps3_fps : fps;
   NSString *fpsText = displayedFPS >= 0 && isfinite(displayedFPS) ? [NSString stringWithFormat:@"%.1f fps", displayedFPS] : @"FPS unavailable";
   self.summary = [NSString stringWithFormat:@"%.0f seconds · %@\n%@\nCPU %@ (100%% = one core) · Memory %@\nHeat: %@ · Slow frames this window: %@\nSignals: %@\n\nCore work max: %@ · Frame max: %@\nVideo submission: %@ · Audio writes: %@ (window totals)",
      (now - self.started) / 1000000.0, fpsText, state,
      RALabPerfValue(cpuPercent, @"%.0f%%"),
      RALabPerfValue(footprint == NSNull.null ? footprint : @([footprint doubleValue] / 1048576.0), @"%.0f MB"),
      row[@"thermal"], s.window.intervals ? [NSString stringWithFormat:@"%llu", (unsigned long long)s.window.late] : @"Unavailable",
      signals.count ? [signals componentsJoinedByString:@", "] : @"none observed",
      RALabPerfValue(row[@"core_work_max_ms"], @"%.1f ms"), RALabPerfValue(row[@"frame_max_ms"], @"%.1f ms"),
      RALabPerfValue(row[@"video_submit_ms_total"], @"%.1f ms"), RALabPerfValue(row[@"audio_write_ms_total"], @"%.1f ms")];
   if (!self.pingPending)
   {
      self.pingPending = YES;
      dispatch_async(dispatch_get_main_queue(), ^{
         os_unfair_lock_lock(&ra_perf_lock); ra_perf.heartbeat = RALabPerfNow(); os_unfair_lock_unlock(&ra_perf_lock);
         [self updateOverlay];
         dispatch_async(self.queue, ^{ self.pingPending = NO; });
      });
   }
   if (self.recording && (now - self.started >= 600000000 || self.bytes >= 1500000))
      [self stopOnQueue:@"recording_limit"];
}
@end

void RALabPerfEvent(NSString *event)
{ if (ra_lab_perf_clock()) [[RALabPerformance shared] event:event]; }
void RALabPerfPS3Surface(UIView *surface)
{ RALabPerformance.shared.ps3Surface = surface; [RALabPerformance.shared updateOverlay]; }

@interface RALabPS3LogStore : NSObject
{
   os_unfair_lock _lock;
   NSMutableArray *_lines;
   NSUInteger _head, _count, _bytes;
   uint64_t _total, _truncated;
}
+ (instancetype)shared;
- (void)append:(NSString *)message level:(int32_t)level;
- (NSDictionary *)snapshot:(NSUInteger)limit;
- (NSString *)exportText;
@end
@implementation RALabPS3LogStore
+ (instancetype)shared
{
   static RALabPS3LogStore *store;
   static dispatch_once_t once;
   dispatch_once(&once, ^{ store = [self new]; });
   return store;
}
- (instancetype)init
{
   if ((self = [super init]))
   {
      _lock = (os_unfair_lock)OS_UNFAIR_LOCK_INIT;
      _lines = [NSMutableArray arrayWithCapacity:10000];
      for (NSUInteger i = 0; i < 10000; i++) [_lines addObject:NSNull.null];
   }
   return self;
}
- (void)append:(NSString *)message level:(int32_t)level
{
   if (!message.length) return;
   BOOL truncated = message.length > 4096;
   if (truncated)
   {
      NSUInteger end = 4096;
      if (CFStringIsSurrogateHighCharacter([message characterAtIndex:end - 1])) end--;
      message = [[message substringToIndex:end] stringByAppendingString:@" [message truncated]"];
   }
   NSArray *parts = [message componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
   os_unfair_lock_lock(&_lock);
   if (truncated) _truncated++;
   for (NSString *part in parts)
   {
      if (!part.length) continue;
      NSString *line = [NSString stringWithFormat:@"[%d] %@", level, part];
      NSUInteger bytes = [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
      while (_count && (_count == 10000 || _bytes + bytes > 4 * 1024 * 1024))
      {
         _bytes -= [_lines[_head] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1;
         _lines[_head] = NSNull.null; _head = (_head + 1) % 10000; _count--;
      }
      _lines[(_head + _count) % 10000] = line; _count++; _bytes += bytes; _total++;
   }
   os_unfair_lock_unlock(&_lock);
}
- (NSDictionary *)snapshot:(NSUInteger)limit
{
   os_unfair_lock_lock(&_lock);
   NSUInteger count = MIN(limit, _count);
   NSMutableArray *lines = [NSMutableArray arrayWithCapacity:count];
   for (NSUInteger i = _count - count; i < _count; i++) [lines addObject:_lines[(_head + i) % 10000]];
   NSDictionary *result = @{@"lines": lines, @"total": @(_total), @"retained": @(_count),
         @"omitted": @(_total - _count), @"truncated": @(_truncated), @"bytes": @(_bytes)};
   os_unfair_lock_unlock(&_lock);
   return result;
}
- (NSString *)exportText
{
   NSDictionary *snapshot = [self snapshot:10000];
   return [NSString stringWithFormat:@"RPCS3 Log\nExported UTC: %@\nBuild: %@\n%@ retained / %@ total lines received\n%@ older lines omitted; %@ oversized messages truncated\nRetention: latest 10,000 lines / 4 MiB, memory only until export.\nOnly messages delivered by the core callback are included. Logs may contain game names and local paths.\n\n%@\n",
         [[NSISO8601DateFormatter new] stringFromDate:NSDate.date],
         [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown",
         snapshot[@"retained"], snapshot[@"total"], snapshot[@"omitted"], snapshot[@"truncated"],
         [snapshot[@"lines"] componentsJoinedByString:@"\n"]];
}
@end
void RALabPerfPS3Log(int32_t level, const char *message)
{
   if (!message) return;
   @autoreleasepool
   {
      size_t length = strnlen(message, 16384);
      NSString *text = [[NSString alloc] initWithBytes:message length:length encoding:NSUTF8StringEncoding];
      if (!text) text = @"[unreadable or oversized UTF-8 log message]";
      [RALabPS3LogStore.shared append:text level:level];
   }
}

@interface RALabPS3LogController : UIViewController
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UILabel *countsLabel;
@property(nonatomic, strong) UIButton *exportButton;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic) uint64_t displayedTotal;
@property(nonatomic) BOOL embedded;
@end
@implementation RALabPS3LogController
- (void)viewDidLoad
{
   [super viewDidLoad]; self.title = @"RPCS3 Log"; self.view.backgroundColor = UIColor.blackColor;
   self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
   UILabel *title = [UILabel new]; title.text = @"RPCS3 Log"; title.textColor = UIColor.whiteColor;
   title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; title.adjustsFontForContentSizeCategory = YES;
   self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
   [self.exportButton setTitle:@"Export" forState:UIControlStateNormal];
   [self.exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
   self.exportButton.tintColor = UIColor.whiteColor; self.exportButton.accessibilityIdentifier = @"Export RPCS3 log";
   self.exportButton.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1]; self.exportButton.layer.cornerRadius = 22;
   [self.exportButton addTarget:self action:@selector(exportLog:) forControlEvents:UIControlEventTouchUpInside];
   [self.exportButton.widthAnchor constraintEqualToConstant:110].active = YES;
   [self.exportButton.heightAnchor constraintEqualToConstant:44].active = YES;
   UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, self.exportButton]];
   header.alignment = UIStackViewAlignmentCenter; header.spacing = 12;
   if (self.embedded)
   {
      UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
      [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
      close.tintColor = UIColor.whiteColor; close.accessibilityLabel = @"Close RPCS3 log";
      [close addTarget:self action:@selector(closeOverlay) forControlEvents:UIControlEventTouchUpInside];
      [close.widthAnchor constraintEqualToConstant:44].active = YES;
      [close.heightAnchor constraintEqualToConstant:44].active = YES;
      [header addArrangedSubview:close];
   }
   self.countsLabel = [UILabel new]; self.countsLabel.textColor = UIColor.lightGrayColor; self.countsLabel.numberOfLines = 0;
   self.countsLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
   self.countsLabel.adjustsFontForContentSizeCategory = YES;
   self.countsLabel.accessibilityIdentifier = @"RPCS3 log counts";
   self.text = [UITextView new]; self.text.editable = NO;
   self.text.backgroundColor = UIColor.blackColor; self.text.textColor = UIColor.whiteColor;
   self.text.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleCaption1]
         scaledFontForFont:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]];
   self.text.adjustsFontForContentSizeCategory = YES; self.text.accessibilityIdentifier = @"RPCS3 log messages";
   UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[header, self.countsLabel, self.text]];
   stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = NO;
   [self.view addSubview:stack];
   [NSLayoutConstraint activateConstraints:@[
      [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
      [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
      [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
      [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12]]];
   self.displayedTotal = UINT64_MAX;
   [self refresh];
}
- (void)viewDidAppear:(BOOL)animated
{
   [super viewDidAppear:animated];
   [RALabPerformance.shared updateOverlay];
   __weak RALabPS3LogController *weakSelf = self;
   self.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
}
- (void)viewWillDisappear:(BOOL)animated
{ [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer = nil; }
- (void)refresh
{
   NSDictionary *snapshot = [RALabPS3LogStore.shared snapshot:300];
   uint64_t total = [snapshot[@"total"] unsignedLongLongValue];
   if (total == self.displayedTotal) return;
   self.displayedTotal = total;
   NSArray *lines = snapshot[@"lines"];
   self.countsLabel.text = [NSString stringWithFormat:@"%lu recent · %@ total\nExport includes %@ retained lines; %@ older lines omitted.",
         (unsigned long)lines.count, snapshot[@"total"], snapshot[@"retained"], snapshot[@"omitted"]];
   BOOL atEnd = self.text.contentOffset.y + self.text.bounds.size.height >= self.text.contentSize.height - 24;
   CGPoint offset = self.text.contentOffset;
   self.text.text = lines.count ? [lines componentsJoinedByString:@"\n"] :
         @"Waiting for RPCS3 messages. Open this screen before starting PS3 to inspect startup logs. Only messages delivered by the core are shown.";
   if (atEnd && lines.count) [self.text scrollRangeToVisible:NSMakeRange(self.text.text.length, 0)];
   else self.text.contentOffset = offset;
}
- (void)closeOverlay
{
   [self.timer invalidate]; self.timer = nil;
   [self willMoveToParentViewController:nil];
   [self beginAppearanceTransition:NO animated:NO];
   [self.view removeFromSuperview]; [self endAppearanceTransition];
   [self removeFromParentViewController];
   [RALabPerformance.shared updateOverlay];
}
- (void)exportLog:(UIButton *)button
{
   button.enabled = NO;
   dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
      NSString *text = [RALabPS3LogStore.shared exportText];
      NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"RPCS3Log-%@.txt", NSUUID.UUID.UUIDString]]];
      NSError *error = nil;
      BOOL saved = [text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error];
      dispatch_async(dispatch_get_main_queue(), ^{
         button.enabled = YES;
         if (!saved)
         {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Log export failed"
                  message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil]; return;
         }
         UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
         share.popoverPresentationController.sourceView = button;
         share.popoverPresentationController.sourceRect = button.bounds;
         share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *failure) {
            [NSFileManager.defaultManager removeItemAtURL:url error:nil];
         };
         if (self.view.window) [self presentViewController:share animated:YES completion:nil];
         else [NSFileManager.defaultManager removeItemAtURL:url error:nil];
      });
   });
}
@end
void RALabPerfLogShow(UIViewController *parent)
{ [parent.navigationController pushViewController:[RALabPS3LogController new] animated:YES]; }
void RALabPerfLogToggle(UIViewController *parent, UIView *surface)
{
   for (UIViewController *child in parent.childViewControllers)
      if ([child isKindOfClass:RALabPS3LogController.class]) { [(RALabPS3LogController *)child closeOverlay]; return; }
   if (surface.bounds.size.height < 240) { RALabPerfLogShow(parent); return; }
   RALabPS3LogController *console = [RALabPS3LogController new]; console.embedded = YES;
   [parent addChildViewController:console];
   [console beginAppearanceTransition:YES animated:NO];
   console.view.translatesAutoresizingMaskIntoConstraints = NO; [surface addSubview:console.view];
   [NSLayoutConstraint activateConstraints:@[
      [console.view.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor],
      [console.view.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor],
      [console.view.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor],
      [console.view.heightAnchor constraintEqualToAnchor:surface.heightAnchor multiplier:surface.bounds.size.height >= 360 ? 0.65 : 1]]];
   [console didMoveToParentViewController:parent]; [console endAppearanceTransition];
}

@interface RALabPerformanceController : UIViewController
@property(nonatomic, strong) UITextView *text;
@property(nonatomic, strong) UIButton *toggle, *markButton;
@property(nonatomic, strong) UISwitch *overlaySwitch;
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation RALabPerformanceController
- (void)viewDidLoad
{
   [super viewDidLoad]; self.title = @"Performance";
   self.view.backgroundColor = UIColor.systemBackgroundColor;
   UILabel *overlayTitle = [UILabel new]; overlayTitle.text = @"Live performance overlay";
   overlayTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; overlayTitle.adjustsFontForContentSizeCategory = YES;
   self.overlaySwitch = [UISwitch new]; self.overlaySwitch.accessibilityIdentifier = @"Live performance overlay";
   self.overlaySwitch.accessibilityLabel = @"Live performance overlay";
   [self.overlaySwitch addTarget:self action:@selector(toggleOverlay) forControlEvents:UIControlEventValueChanged];
   UIStackView *overlay = [[UIStackView alloc] initWithArrangedSubviews:@[overlayTitle, self.overlaySwitch]];
   overlay.alignment = UIStackViewAlignmentCenter; overlay.spacing = 12;
   self.toggle = [UIButton buttonWithType:UIButtonTypeSystem];
   self.toggle.accessibilityIdentifier = @"Performance recording";
   [self.toggle addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
   UIButton *mark = [UIButton buttonWithType:UIButtonTypeSystem];
   self.markButton = mark;
   [mark setTitle:@"Mark slowdown" forState:UIControlStateNormal];
   [mark addTarget:self action:@selector(mark) forControlEvents:UIControlEventTouchUpInside];
   UIButton *share = [UIButton buttonWithType:UIButtonTypeSystem];
   [share setTitle:@"Share a report…" forState:UIControlStateNormal];
   [share addTarget:self action:@selector(share:) forControlEvents:UIControlEventTouchUpInside];
   UIButton *log = [UIButton buttonWithType:UIButtonTypeSystem];
   [log setTitle:@"RPCS3 Log" forState:UIControlStateNormal];
   [log addTarget:self action:@selector(openLog) forControlEvents:UIControlEventTouchUpInside];
   self.text = [[UITextView alloc] init]; self.text.editable = NO;
   self.text.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
   self.text.accessibilityIdentifier = @"Performance summary";
   UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[overlay, self.toggle, mark, share, log, self.text]];
   stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12;
   stack.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:stack];
   [NSLayoutConstraint activateConstraints:@[
      [stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
      [stack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-48],
      [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
      [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16]]];
   for (UIButton *button in @[self.toggle, mark, share, log]) [button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
   [self refresh];
}
- (void)viewDidAppear:(BOOL)animated
{
   [super viewDidAppear:animated];
   [RALabPerformance.shared updateOverlay];
   __weak RALabPerformanceController *weakSelf = self;
   self.timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
}
- (void)viewWillDisappear:(BOOL)animated
{ [super viewWillDisappear:animated]; [self.timer invalidate]; self.timer = nil; }
- (void)refresh
{
   RALabPerformance *recorder = RALabPerformance.shared;
   BOOL active = recorder.recording;
   self.overlaySwitch.on = recorder.overlayEnabled;
   self.markButton.enabled = active;
   [self.toggle setTitle:active ? @"Stop recording" : @"Start recording" forState:UIControlStateNormal];
   self.text.text = [NSString stringWithFormat:@"%@\n\n%@\n\nThe live overlay shows FPS, CPU, estimated GPU and RAM in the top-left. It can run without saving a report. Recording also shows it with a red dot; tap it to mark a slowdown. This session's overlay setting resets when the app closes.\n\nCPU on the gauge is this app's use across all logical cores. RAM is this app's footprint as a percentage of physical device memory, not the iOS memory limit. GPU≈ is the PS3 RSX estimate; other cores show —. Missing values show —.\n\nRecord the same game section for 2–3 minutes, then return here and stop. Reports stay on this device until shared; they include game filenames, not game data. Recording stops after 10 minutes or 1.5 MB. The latest 5 reports are kept in Files > RetroArch Lab > Performance.\n\nFrame cadence counts libretro calls, not unique frames. Audio/video timing includes synchronization waits. Exact GPU timing and PS3 frame/audio internals are unavailable. RPCS3 Log shows callback messages in a separate live console and exports retained text; it may include local paths.",
      recorder.failure ?: (active ? @"RECORDING" : @"Recording off"), recorder.summary];
}
- (void)toggleRecording
{
   if (RALabPerformance.shared.recording) [RALabPerformance.shared stop:@"user_stopped"];
   else [RALabPerformance.shared start];
   [self refresh];
}
- (void)mark { [RALabPerformance.shared mark]; }
- (void)toggleOverlay { [RALabPerformance.shared showOverlay:self.overlaySwitch.on]; [self refresh]; }
- (void)openLog { RALabPerfLogShow(self); }
- (void)share:(UIButton *)button
{
   if (RALabPerformance.shared.recording) [RALabPerformance.shared stop:@"shared_report"];
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
