/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <XCTest/XCTest.h>
#define HAVE_RETROARCH_LAB_LIBRARY 1
#import "../../../../ui/drivers/cocoa/RetroArchLabPerformance.m"

@interface PerformanceRecorderTests : XCTestCase
@end
@implementation PerformanceRecorderTests
- (void)onMain:(dispatch_block_t)block
{ if (NSThread.isMainThread) block(); else dispatch_sync(dispatch_get_main_queue(), block); }
- (void)start { [self onMain:^{ [RALabPerformance.shared start]; }]; XCTAssertNotEqual(ra_lab_perf_clock(), 0); }
- (NSArray *)rows
{
   NSURL *report = RALabPerformance.shared.reports.firstObject;
   XCTAssertNotNil(report);
   NSString *text = [NSString stringWithContentsOfURL:report encoding:NSUTF8StringEncoding error:nil];
   NSMutableArray *rows = [NSMutableArray array];
   for (NSString *line in [text componentsSeparatedByString:@"\n"])
      if (line.length)
      {
         NSDictionary *row = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
         XCTAssertNotNil(row); if (row) [rows addObject:row];
      }
   return rows;
}
- (NSDictionary *)sample:(NSArray *)rows
{
   for (NSDictionary *row in rows) if ([row[@"type"] isEqual:@"sample"]) return row;
   XCTFail(@"No sample recorded"); return @{};
}
- (void)tearDown
{
   [self onMain:^{
      [RALabPerformance.shared stop:@"test_teardown"];
      [RALabPerformance.shared showOverlay:NO];
      RALabPerfPS3Surface(nil);
   }];
   [super tearDown];
}
- (void)testRecordsFrameAudioVideoAndMark
{
   [self start];
   ra_lab_perf_begin("TestCore", "Synthetic.nes", 60, 0, "test-video", "test-audio", 0);
   uint64_t stamp = ra_lab_perf_clock(); usleep(20000); ra_lab_perf_stage(stamp, 0);
   ra_lab_perf_end(); ra_lab_perf_audio(10, 1);
   [RALabPerformance.shared event:@"USER: slowdown noticed"];
   usleep(20000);
   ra_lab_perf_begin("TestCore", "Synthetic.nes", 60, 0, "test-video", "test-audio", 0);
   stamp = ra_lab_perf_clock(); usleep(2000); ra_lab_perf_stage(stamp, 1); ra_lab_perf_end();
   [self onMain:^{ [RALabPerformance.shared stop:@"test_finished"]; }];
   NSArray *rows = self.rows; NSDictionary *s = [self sample:rows];
   XCTAssertEqual([s[@"core_calls"] intValue], 2);
   XCTAssertGreaterThan([s[@"core_work_max_ms"] doubleValue], 15);
   XCTAssertGreaterThan([s[@"video_submit_ms_total"] doubleValue], 15);
   XCTAssertGreaterThan([s[@"audio_write_ms_total"] doubleValue], 1);
   XCTAssertNotEqualObjects(s[@"libretro_fps"], NSNull.null);
   XCTAssertEqualObjects(s[@"audio_underruns_delta"], NSNull.null);
   XCTAssertEqualObjects(rows.firstObject[@"type"], @"session");
   XCTAssertEqualObjects(rows.lastObject[@"reason"], @"test_finished");
   XCTAssertTrue([[rows valueForKey:@"message"] containsObject:@"USER: slowdown noticed"]);
   XCTAssertEqual(ra_lab_perf_clock(), 0);
}
- (void)testJITHandoffPreservesAndFinishesRecording
{
   [self onMain:^{ [RALabPerformance.shared showOverlay:YES]; }];
   [self start];
   RALabPerfEvent(@"Before JIT handoff");
   NSArray *reports = RALabPerformance.shared.reports;
   [self onMain:^{ RALabPerfPrepareForRelaunch(); }];
   NSArray *rows = self.rows;
   XCTAssertEqualObjects(rows.firstObject[@"type"], @"session");
   XCTAssertTrue([[rows valueForKey:@"message"] containsObject:@"Before JIT handoff"]);
   XCTAssertEqualObjects(rows.lastObject[@"type"], @"end");
   XCTAssertEqualObjects(rows.lastObject[@"reason"], @"jit_relaunch");
   XCTAssertFalse(RALabPerformance.shared.recording);
   XCTAssertEqual(RALabPerformance.shared.descriptor, -1);
   XCTAssertNotEqual(ra_lab_perf_clock(), 0);
   NSData *saved = [NSData dataWithContentsOfURL:reports.firstObject];
   [self onMain:^{ RALabPerfPrepareForRelaunch(); }];
   XCTAssertEqualObjects(saved, [NSData dataWithContentsOfURL:reports.firstObject]);
   XCTAssertEqualObjects(reports, RALabPerformance.shared.reports);
   [self onMain:^{
      [RALabPerformance.shared showOverlay:NO];
      RALabPerfPrepareForRelaunch();
   }];
   XCTAssertEqual(ra_lab_perf_clock(), 0);
   XCTAssertEqualObjects(saved, [NSData dataWithContentsOfURL:reports.firstObject]);
   XCTAssertEqualObjects(reports, RALabPerformance.shared.reports);
}
- (void)testUnavailablePS3MetricsAndPauseAreNotZeroOrStalls
{
   [self start];
   ra_lab_perf_begin("TestCore", "test", 60, 0, "v", "a", 0); ra_lab_perf_end();
   ra_lab_perf_idle(); usleep(30000);
   ra_lab_perf_begin("TestCore", "test", 60, 0, "v", "a", 0); ra_lab_perf_end();
   RALabPerfPS3(@"PS3 paused", 0, NAN, NAN);
   [self onMain:^{ [RALabPerformance.shared stop:@"test_finished"]; }];
   NSDictionary *s = [self sample:self.rows];
   XCTAssertEqualObjects(s[@"ps3_fps"], NSNull.null);
   XCTAssertEqualObjects(s[@"ps3_rsx_estimate_percent"], NSNull.null);
   XCTAssertEqualObjects(s[@"libretro_fps"], NSNull.null);
   XCTAssertEqualObjects(s[@"slow_frames"], NSNull.null);
}
- (void)testReportsRetainedWithinLimitAndRecordingResets
{
   for (unsigned i = 0; i < 7; i++)
   {
      [self start];
      [self onMain:^{ [RALabPerformance.shared stop:@"retention_test"]; }];
   }
   XCTAssertEqual(RALabPerformance.shared.reports.count, 5);
   NSDictionary *s = [self sample:self.rows];
   XCTAssertEqual([s[@"core_calls"] intValue], 0);
   XCTAssertEqualObjects(s[@"libretro_fps"], NSNull.null);
}
- (void)testAudioDeltaAndReset
{
   [self start];
   ra_lab_perf_audio(5, 1);
   dispatch_sync(RALabPerformance.shared.queue, ^{ [RALabPerformance.shared sample]; });
   ra_lab_perf_audio(8, 1); usleep(1000);
   dispatch_sync(RALabPerformance.shared.queue, ^{ [RALabPerformance.shared sample]; });
   ra_lab_perf_audio(1, 1); usleep(1000);
   [self onMain:^{ [RALabPerformance.shared stop:@"audio_test"]; }];
   NSMutableArray *samples = [NSMutableArray array];
   for (NSDictionary *row in self.rows) if ([row[@"type"] isEqual:@"sample"]) [samples addObject:row];
   XCTAssertEqualObjects(samples[0][@"audio_underruns_delta"], NSNull.null);
   XCTAssertEqual([samples[1][@"audio_underruns_delta"] intValue], 3);
   XCTAssertEqualObjects(samples[2][@"audio_underruns_delta"], NSNull.null);
}
- (void)testPS3OnlySummaryDoesNotInventFrameOrAudioMeasurements
{
   [self start];
   RALabPerfPS3(@"PS3 running", 5, 29.5, 40);
   [self onMain:^{ [RALabPerformance.shared stop:@"ps3_test"]; }];
   NSDictionary *s = [self sample:self.rows];
   XCTAssertEqualObjects(s[@"ps3_fps"], @29.5);
   XCTAssertEqualObjects(s[@"ps3_rsx_estimate_percent"], @40);
   for (NSString *key in @[@"frame_max_ms", @"frame_p95_ms", @"slow_frames", @"core_work_max_ms",
         @"video_submit_ms_total", @"audio_write_ms_total", @"audio_underruns_delta"])
      XCTAssertEqualObjects(s[key], NSNull.null, @"%@ must remain unavailable", key);
   XCTAssertTrue([RALabPerformance.shared.summary containsString:@"Core work max: Unavailable"]);
   XCTAssertTrue([RALabPerformance.shared.summary containsString:@"Frame max: Unavailable"]);
   XCTAssertTrue([RALabPerformance.shared.summary containsString:@"Audio writes: Unavailable"]);
   XCTAssertTrue([RALabPerformance.shared.summary containsString:@"Slow frames this window: Unavailable"]);
}
- (void)testLiveOverlayCollectsWithoutCreatingOrPruningReports
{
   NSArray *before = RALabPerformance.shared.reports;
   [self onMain:^{ [RALabPerformance.shared showOverlay:YES]; }];
   XCTAssertNotEqual(ra_lab_perf_clock(), 0);
   XCTAssertFalse(RALabPerformance.shared.recording);
   RALabPerfPS3(@"PS3 playing", 5, 43.4, 100);
   dispatch_sync(RALabPerformance.shared.queue, ^{ [RALabPerformance.shared sample]; });
   NSDictionary *s = RALabPerformance.shared.latestSample;
   XCTAssertEqualObjects(s[@"ps3_fps"], @43.4);
   XCTAssertNotEqualObjects(s[@"process_cpu_percent_device"], NSNull.null);
   XCTAssertNotEqualObjects(s[@"memory_footprint_percent_physical"], NSNull.null);
   XCTAssertEqualObjects(before, RALabPerformance.shared.reports);
   [self onMain:^{ [RALabPerformance.shared showOverlay:NO]; }];
   XCTAssertEqual(ra_lab_perf_clock(), 0);
   XCTAssertNil(RALabPerformance.shared.timer);
}
- (void)testRecordingStopsButRequestedLiveOverlayContinues
{
   [self onMain:^{ [RALabPerformance.shared showOverlay:YES]; }];
   [self start];
   [self onMain:^{ [RALabPerformance.shared stop:@"user_stopped"]; }];
   NSArray *rows = self.rows;
   XCTAssertEqualObjects(rows.lastObject[@"reason"], @"user_stopped");
   XCTAssertFalse(RALabPerformance.shared.recording);
   XCTAssertNotEqual(ra_lab_perf_clock(), 0);
   RALabPerfPS3(@"PS3 playing", 1, 25, 0);
   dispatch_sync(RALabPerformance.shared.queue, ^{ [RALabPerformance.shared sample]; });
   XCTAssertEqualObjects(RALabPerformance.shared.latestSample[@"ps3_fps"], @25);
   XCTAssertEqualObjects(rows, self.rows);
}
- (void)testHUDShowsSourceAndEstimateAndClearsUnavailableValues
{
   [self onMain:^{
      RALabPerformanceHUD *hud = [[RALabPerformanceHUD alloc] initWithFrame:CGRectMake(12, 8, 232, 64)];
      NSDictionary *sample = @{@"ps3_fps": @43.4, @"process_cpu_percent_device": @13,
            @"ps3_rsx_estimate_percent": @100, @"memory_footprint_percent_physical": @50};
      [hud update:sample recording:YES]; [hud layoutIfNeeded];
      XCTAssertEqualObjects(hud.fps.text, @"43.4");
      XCTAssertEqualObjects(hud.cpu.value.text, @"13%");
      XCTAssertEqualObjects(hud.gpu.value.text, @"100%");
      XCTAssertTrue([hud.accessibilityValue containsString:@"PS3"]);
      XCTAssertTrue([hud.accessibilityValue containsString:@"estimated GPU"]);
      XCTAssertFalse(hud.recordingDot.hidden);
      UIView *canvas = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 400, 100)];
      canvas.backgroundColor = UIColor.blackColor; [canvas addSubview:hud];
      UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:canvas.bounds];
      UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
         [canvas.layer renderInContext:context.CGContext];
      }];
      XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
      attachment.name = @"Performance-HUD-reference-values"; attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
      [self addAttachment:attachment];
      [hud update:@{@"libretro_fps": @30} recording:NO];
      XCTAssertEqualObjects(hud.fps.text, @"30.0");
      XCTAssertEqualObjects(hud.gpu.value.text, @"—");
      XCTAssertEqual(hud.gpu.fill.strokeEnd, 0);
      XCTAssertTrue([hud.accessibilityValue containsString:@"Libretro cadence"]);
      XCTAssertTrue(hud.recordingDot.hidden);
      XCTAssertFalse(hud.userInteractionEnabled);
   }];
}
- (void)testLogRetainsVerboseLinesInOrderAndExportsBeyondRecentWindow
{
   RALabPS3LogStore *store = [RALabPS3LogStore new];
   for (NSUInteger i = 0; i < 10020; i++)
      [store append:[NSString stringWithFormat:@"SPRX Worker 2: import %lu", (unsigned long)i] level:6];
   NSDictionary *snapshot = [store snapshot:300];
   XCTAssertEqual([snapshot[@"total"] unsignedLongLongValue], 10020);
   XCTAssertEqual([snapshot[@"retained"] unsignedLongLongValue], 10000);
   XCTAssertEqual([snapshot[@"omitted"] unsignedLongLongValue], 20);
   XCTAssertEqual([snapshot[@"lines"] count], 300);
   XCTAssertEqualObjects([snapshot[@"lines"] firstObject], @"[6] SPRX Worker 2: import 9720");
   XCTAssertEqualObjects([snapshot[@"lines"] lastObject], @"[6] SPRX Worker 2: import 10019");
   NSString *text = store.exportText;
   XCTAssertTrue([text containsString:@"[6] SPRX Worker 2: import 20\n"]);
   XCTAssertTrue([text containsString:@"20 older lines omitted"]);
   XCTAssertFalse([text containsString:@"[6] SPRX Worker 2: import 0\n"]);
}
- (void)testConcurrentLogCallbacksAndByteLimitAreBounded
{
   RALabPS3LogStore *store = [RALabPS3LogStore new];
   NSString *message = [@"iOS LLVM compilation " stringByPaddingToLength:5000 withString:@"x" startingAtIndex:0];
   dispatch_apply(1200, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t i) {
      @autoreleasepool { [store append:message level:5]; }
   });
   NSDictionary *snapshot = [store snapshot:10000];
   XCTAssertEqual([snapshot[@"total"] unsignedLongLongValue], 1200);
   XCTAssertEqual([snapshot[@"truncated"] unsignedLongLongValue], 1200);
   XCTAssertLessThanOrEqual([snapshot[@"bytes"] unsignedLongLongValue], 4 * 1024 * 1024);
   XCTAssertGreaterThan([snapshot[@"omitted"] unsignedLongLongValue], 0);
   XCTAssertTrue([store.exportText containsString:@"[message truncated]"]);
}
- (void)testCoreCallbackFeedsTheLiveConsole
{
   RALabPerfPS3Log(6, "SPRX Worker 2: sys_fs import\nPPUW: LLVM compiled");
   [self onMain:^{
      RALabPS3LogController *console = [RALabPS3LogController new];
      [console loadViewIfNeeded];
      XCTAssertTrue([console.text.text containsString:@"[6] SPRX Worker 2: sys_fs import"]);
      XCTAssertTrue([console.text.text containsString:@"[6] PPUW: LLVM compiled"]);
      XCTAssertTrue([console.countsLabel.text containsString:@"total"]);
      XCTAssertEqualObjects(console.exportButton.currentTitle, @"Export");
      console.view.frame = CGRectMake(0, 0, 800, 500);
      [console.view layoutIfNeeded];
      XCTAssertFalse(console.text.hasAmbiguousLayout);
      UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:console.view.bounds];
      UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
         [console.view.layer renderInContext:context.CGContext];
      }];
      XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
      attachment.name = @"RPCS3-console-callback-fixture"; attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
      [self addAttachment:attachment];
   }];
}
- (void)testHUDAnchorsToGameSurfaceAndFollowsNavigation
{
   [self onMain:^{
      UIWindow *window = nil;
      for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
         if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows)
               if (candidate.isKeyWindow) window = candidate;
      XCTAssertNotNil(window);
      UIViewController *original = window.rootViewController;
      UIViewController *game = [UIViewController new];
      UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:game];
      window.rootViewController = navigation; [window layoutIfNeeded];
      UIView *surface = [[UIView alloc] initWithFrame:CGRectMake(0, 160, game.view.bounds.size.width, 300)];
      surface.backgroundColor = UIColor.blackColor; [game.view addSubview:surface];
      RALabPerfPS3Surface(surface);
      [RALabPerformance.shared showOverlay:YES];
      [game.view layoutIfNeeded];
      RALabPerformanceHUD *hud = RALabPerformance.shared.badge;
      XCTAssertEqual(hud.superview, surface);
      XCTAssertFalse(hud.hasAmbiguousLayout);
      XCTAssertTrue(CGRectContainsRect(surface.bounds, hud.frame));
      XCTAssertGreaterThanOrEqual(hud.frame.origin.x, 12);
      XCTAssertGreaterThanOrEqual(hud.frame.origin.y, 8);
      RALabPerfLogToggle(game, surface); [game.view layoutIfNeeded];
      XCTAssertTrue([game.childViewControllers.lastObject isKindOfClass:RALabPS3LogController.class]);
      XCTAssertNil(hud.superview);
      RALabPerfLogToggle(game, surface); [game.view layoutIfNeeded];
      XCTAssertEqual(game.childViewControllers.count, 0);
      XCTAssertEqual(hud.superview, surface);
      RALabPerformanceController *settings = [RALabPerformanceController new];
      [navigation pushViewController:settings animated:NO]; [window layoutIfNeeded];
      [RALabPerformance.shared updateOverlay];
      XCTAssertNil(hud.superview);
      XCTAssertEqualObjects(settings.toggle.currentTitle, @"Start recording");
      [navigation popViewControllerAnimated:NO];
      [window layoutIfNeeded];
      [RALabPerformance.shared updateOverlay]; [game.view layoutIfNeeded];
      XCTAssertEqual(hud.superview, surface);
      RALabPerfPS3Surface(nil);
      [RALabPerformance.shared showOverlay:NO];
      window.rootViewController = original;
   }];
}
@end
