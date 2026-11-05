/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <XCTest/XCTest.h>
#define HAVE_RETROARCH_LAB_LIBRARY 1
#import "../../../../ui/drivers/cocoa/RetroArchLabPerformance.m"
#import "../../../../ui/drivers/cocoa/RetroArchLabGameMode.m"

@interface PerformanceRecorderTests : XCTestCase
@end

@interface GameModeTests : XCTestCase
@property(nonatomic, strong) id savedQuietPreference;
@end
@implementation GameModeTests
- (void)setUp
{
   [super setUp];
   self.savedQuietPreference = [NSUserDefaults.standardUserDefaults objectForKey:RALabQuietGameplayKey];
}
- (void)tearDown
{
   if (self.savedQuietPreference)
      [NSUserDefaults.standardUserDefaults setObject:self.savedQuietPreference forKey:RALabQuietGameplayKey];
   else
      [NSUserDefaults.standardUserDefaults removeObjectForKey:RALabQuietGameplayKey];
   __atomic_store_n(&ra_lab_quiet_gameplay, RALabGameModeReadPreference(), __ATOMIC_RELAXED);
   [super tearDown];
}
- (void)testDefaultAndStoredChoices
{
   [NSUserDefaults.standardUserDefaults removeObjectForKey:RALabQuietGameplayKey];
   XCTAssertTrue(RALabGameModeReadPreference());
   [NSUserDefaults.standardUserDefaults setBool:NO forKey:RALabQuietGameplayKey];
   XCTAssertFalse(RALabGameModeReadPreference());
   [NSUserDefaults.standardUserDefaults setBool:YES forKey:RALabQuietGameplayKey];
   XCTAssertTrue(RALabGameModeReadPreference());
}
- (void)testSwitchPersistsAndDoesNotStartRecorder
{
   void (^check)(void) = ^{
      XCTAssertEqual(ra_lab_perf_clock(), 0);
      RALabGameModeController *page = [[RALabGameModeController alloc] initWithStyle:UITableViewStyleInsetGrouped];
      [page loadViewIfNeeded];
      UITableViewCell *cell = [page tableView:page.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
      UISwitch *toggle = (UISwitch *)cell.accessoryView;
      XCTAssertEqualObjects(toggle.accessibilityIdentifier, @"Lab quiet gameplay");
      toggle.on = NO;
      [toggle sendActionsForControlEvents:UIControlEventValueChanged];
      XCTAssertFalse(ra_lab_game_mode_quiet_enabled());
      XCTAssertFalse(RALabGameModeReadPreference());
      toggle.on = YES;
      [toggle sendActionsForControlEvents:UIControlEventValueChanged];
      XCTAssertTrue(ra_lab_game_mode_quiet_enabled());
      XCTAssertTrue(RALabGameModeReadPreference());
      XCTAssertEqual(ra_lab_perf_clock(), 0);
   };
   if (NSThread.isMainThread) check(); else dispatch_sync(dispatch_get_main_queue(), check);
}
- (void)testGuidanceDoesNotClaimSystemFocusControl
{
   void (^check)(void) = ^{
      RALabGameModeController *page = [[RALabGameModeController alloc] initWithStyle:UITableViewStyleInsetGrouped];
      [page loadViewIfNeeded];
      XCTAssertEqual([page numberOfSectionsInTableView:page.tableView], 3);
      XCTAssertEqual([page tableView:page.tableView numberOfRowsInSection:2], 3);
      XCTAssertTrue([[page tableView:page.tableView titleForFooterInSection:2] containsString:@"cannot turn it on"]);
      XCTAssertTrue([[page tableView:page.tableView titleForFooterInSection:1] containsString:@"cannot force it on"]);
   };
   if (NSThread.isMainThread) check(); else dispatch_sync(dispatch_get_main_queue(), check);
}
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
{ [self onMain:^{ [RALabPerformance.shared stop:@"test_teardown"]; }]; [super tearDown]; }
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
   XCTAssertEqual([s[@"slow_frames"] intValue], 0);
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
@end
