/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <XCTest/XCTest.h>
#include <stdatomic.h>
#import "../../../../ui/drivers/cocoa/RetroArchLabRPCS3.m"

bool exec_mem_begin_builtin_jit(void) { return true; }
void exec_mem_end_builtin_jit(void) {}
static atomic_int state, attached, boots, stops, pauses, resumes, disconnected, stopFails, bootState, pauseFails;
static dispatch_semaphore_t bootGate;
static const char *mockError(void) { return "test failure"; }
static const char *mockFirmware(void) { return "4.93"; }
static rpcs3_ios_status mockGames(rpcs3_ios_game_callback callback, void *context)
{
   rpcs3_ios_game_info game = {0};
   game.struct_size = sizeof(game); game.title = "Test game"; game.title_id = "TEST00001"; game.bootable = 1;
   callback(context, &game); return 0;
}
static rpcs3_ios_status mockSurface(const rpcs3_ios_display_surface *surface)
{
   if (!surface && atomic_load(&state) != RPCS3_IOS_EMULATION_STATE_STOPPED) return RPCS3_IOS_INVALID_STATE;
   atomic_store(&attached, surface != NULL); return 0;
}
static rpcs3_ios_status mockBoot(const char *title, const char *save)
{
   if (!atomic_load(&attached)) return RPCS3_IOS_BOOT_FAILED;
   atomic_fetch_add(&boots, 1);
   dispatch_semaphore_wait(bootGate, DISPATCH_TIME_FOREVER);
   atomic_store(&state, atomic_load(&bootState)); return 0;
}
static rpcs3_ios_status mockStop(void)
{
   atomic_fetch_add(&stops, 1);
   if (atomic_load(&stopFails)) return RPCS3_IOS_STOP_FAILED;
   atomic_store(&state, RPCS3_IOS_EMULATION_STATE_STOPPED); return 0;
}
static rpcs3_ios_emulation_state mockState(void) { return atomic_load(&state); }
static rpcs3_ios_status mockPause(void)
{
   if (atomic_load(&pauseFails)) return RPCS3_IOS_INVALID_STATE;
   atomic_fetch_add(&pauses, 1); atomic_store(&state, RPCS3_IOS_EMULATION_STATE_PAUSED); return 0;
}
static rpcs3_ios_status mockResume(void)
{ atomic_fetch_add(&resumes, 1); atomic_store(&state, RPCS3_IOS_EMULATION_STATE_RUNNING); return 0; }
static rpcs3_ios_status mockPad(uint32_t index, const rpcs3_ios_pad_state *pad)
{ if (!pad->connected) atomic_fetch_add(&disconnected, 1); return 0; }
static rpcs3_ios_status mockProgress(uint32_t *done, uint32_t *total, char *stage, size_t length)
{ stage[0] = 0; return 0; }

@interface AudioTestController : RALabPS3Controller
@property(nonatomic, strong) NSError *audioError;
@end
@implementation AudioTestController
- (NSError *)configureAudioSession { return self.audioError; }
@end

@interface BridgeTests : XCTestCase
@property(nonatomic, strong) UIWindow *window;
@property(nonatomic, strong) RALabPS3Controller *controller;
@end
@implementation BridgeTests
- (void)until:(BOOL (^)(void))condition
{
   NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
   while (!condition() && deadline.timeIntervalSinceNow > 0)
      [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
   XCTAssertTrue(condition());
}
- (void)setUp
{
   [super setUp];
   atomic_store(&state, RPCS3_IOS_EMULATION_STATE_STOPPED);
   atomic_store(&attached, 0); atomic_store(&boots, 0); atomic_store(&stops, 0);
   atomic_store(&pauses, 0); atomic_store(&resumes, 0); atomic_store(&disconnected, 0); atomic_store(&stopFails, 0);
   atomic_store(&bootState, RPCS3_IOS_EMULATION_STATE_RUNNING); atomic_store(&pauseFails, 0);
   bootGate = dispatch_semaphore_create(0);
   ra_ps3_queue = dispatch_queue_create("ps3.tests", DISPATCH_QUEUE_SERIAL);
   ra_ps3_ready = YES; ra_ps3_failed = NO; ra_ps3_handle = NULL;
   ra_ps3_api = (RALabPS3API){0};
   ra_ps3_api.last_error = mockError; ra_ps3_api.firmware_version = mockFirmware;
   ra_ps3_api.enumerate_games = mockGames; ra_ps3_api.set_display_surface = mockSurface;
   ra_ps3_api.boot_game = mockBoot; ra_ps3_api.stop_emulation = mockStop;
   ra_ps3_api.get_emulation_state = mockState; ra_ps3_api.pause_emulation = mockPause;
   ra_ps3_api.resume_emulation = mockResume; ra_ps3_api.set_pad_state = mockPad;
   ra_ps3_api.get_boot_progress = mockProgress;
   self.controller = [[AudioTestController alloc] init];
   UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
   self.window = [[UIWindow alloc] initWithWindowScene:scene];
   self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:self.controller];
   [self.window makeKeyAndVisible];
   [self.controller loadViewIfNeeded]; [self.controller.view layoutIfNeeded];
   [self until:^BOOL{ return !self.controller.busy; }];
}
- (void)tearDown
{
   dispatch_semaphore_signal(bootGate);
   if (self.controller.playing)
   { atomic_store(&stopFails, 0); [self.controller stopGame]; [self until:^BOOL{ return !self.controller.playing; }]; }
   [self.controller.displayLink invalidate]; self.controller.displayLink = nil;
   self.window.hidden = YES; self.window.rootViewController = nil;
   self.controller = nil; self.window = nil;
   [super tearDown];
}
- (void)boot
{
   [self.controller tableView:self.controller.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
   [self until:^BOOL{ return atomic_load(&boots) == 1; }];
}
- (void)testEnumerationCopiesCallbackStrings
{
   XCTAssertEqual(self.controller.games.count, 1u);
   XCTAssertEqualObjects(self.controller.games[0][@"id"], @"TEST00001");
}
- (void)testStopDuringBootRetainsSurfaceUntilCoreStops
{
   [self boot]; [self.controller stopGame];
   XCTAssertTrue(self.controller.playing); XCTAssertTrue(atomic_load(&attached));
   XCTAssertEqual(atomic_load(&stops), 0);
   dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.playing && !self.controller.busy; }];
   XCTAssertEqual(atomic_load(&stops), 1); XCTAssertFalse(atomic_load(&attached));
   XCTAssertGreaterThanOrEqual(atomic_load(&disconnected), 7);
}
- (void)testBackgroundDuringBootPausesAndDoesNotAutoResume
{
   [self boot]; [self.controller background]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_PAUSED && !self.controller.busy; }];
   [self.controller foreground];
   XCTAssertEqual(atomic_load(&resumes), 0);
   [self.controller togglePause];
   [self until:^BOOL{ return atomic_load(&resumes) == 1 && !self.controller.pausePending; }];
}
- (void)testStopFailureKeepsSurfaceAndAllowsRetry
{
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.busy; }];
   atomic_store(&stopFails, 1); [self.controller stopGame];
   [self until:^BOOL{ return !self.controller.stopping; }];
   XCTAssertTrue(self.controller.playing); XCTAssertTrue(atomic_load(&attached));
   atomic_store(&stopFails, 0); [self.controller stopGame];
   [self until:^BOOL{ return !self.controller.playing; }];
   XCTAssertFalse(atomic_load(&attached));
}
- (void)testMissingUniversalDoesNotLoadCore
{
   ra_ps3_ready = NO; [self.controller startCore];
   [self until:^BOOL{ return !self.controller.busy; }];
   XCTAssertFalse(ra_ps3_handle); XCTAssertFalse(ra_ps3_ready);
   XCTAssertTrue([self.controller.status.text containsString:@"Universal JIT is not attached"]);
}
- (void)testDuplicateBootIsRejected
{
   [self boot];
   [self.controller tableView:self.controller.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
   XCTAssertEqual(atomic_load(&boots), 1);
   dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.busy; }];
}
- (void)testAcceptedBootWaitsForRunningBeforeEnablingPause
{
   atomic_store(&bootState, RPCS3_IOS_EMULATION_STATE_READY);
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_READY; }];
   XCTAssertTrue(self.controller.busy); XCTAssertFalse(self.controller.pauseButton.enabled);
   atomic_store(&state, RPCS3_IOS_EMULATION_STATE_RUNNING);
   [self until:^BOOL{ return !self.controller.busy; }];
   XCTAssertFalse(self.controller.booting); XCTAssertTrue(self.controller.pauseButton.enabled);
}
- (void)testBackgroundDuringAsyncStartupPausesOnceRunning
{
   atomic_store(&bootState, RPCS3_IOS_EMULATION_STATE_STARTING);
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_STARTING; }];
   [self.controller background]; XCTAssertEqual(atomic_load(&pauses), 0);
   atomic_store(&state, RPCS3_IOS_EMULATION_STATE_RUNNING);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_PAUSED; }];
   [self.controller foreground]; XCTAssertEqual(atomic_load(&resumes), 0);
}
- (void)testFailedPauseDoesNotOfferResume
{
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.busy; }];
   atomic_store(&pauseFails, 1); [self.controller togglePause];
   [self until:^BOOL{ return !self.controller.pausePending; }];
   XCTAssertEqualObjects(self.controller.pauseButton.currentTitle, @"Pause");
   XCTAssertTrue([self.controller.status.text containsString:@"test failure"]);
}
- (void)testStoppedStartupKeepsItsFailureMessage
{
   atomic_store(&bootState, RPCS3_IOS_EMULATION_STATE_STOPPED);
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.playing && !self.controller.busy; }];
   XCTAssertFalse(atomic_load(&attached));
   XCTAssertEqualObjects(self.controller.status.text, @"Game stopped before startup completed.");
}
- (void)testAudioActivationNotificationPrecedesBootAndResume
{
   __block NSUInteger activations = 0, suspensions = 0;
   id active = [NSNotificationCenter.defaultCenter addObserverForName:@"RPCS3AudioSessionDidActivate"
         object:nil queue:nil usingBlock:^(NSNotification *note) { activations++; }];
   id suspended = [NSNotificationCenter.defaultCenter addObserverForName:@"RPCS3AudioSessionWillDeactivate"
         object:nil queue:nil usingBlock:^(NSNotification *note) { suspensions++; }];
   [self boot]; XCTAssertEqual(activations, 1u);
   dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !self.controller.busy; }];
   [self.controller background]; XCTAssertEqual(suspensions, 1u);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_PAUSED; }];
   [self.controller foreground]; XCTAssertEqual(activations, 1u);
   [self.controller togglePause];
   [self until:^BOOL{ return atomic_load(&resumes) == 1; }];
   XCTAssertEqual(activations, 2u);
   [NSNotificationCenter.defaultCenter removeObserver:active];
   [NSNotificationCenter.defaultCenter removeObserver:suspended];
}
- (void)testFailedAudioActivationBlocksBootAndResume
{
   AudioTestController *controller = (AudioTestController *)self.controller;
   NSError *error = [NSError errorWithDomain:@"test" code:1 userInfo:nil];
   controller.audioError = error;
   [controller tableView:controller.table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
   XCTAssertEqual(atomic_load(&boots), 0);
   XCTAssertFalse(controller.playing);
   controller.audioError = nil; [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return !controller.busy; }];
   [controller togglePause]; [self until:^BOOL{ return !controller.pausePending; }];
   controller.audioError = error; [controller togglePause];
   XCTAssertEqual(atomic_load(&resumes), 0);
   XCTAssertEqualObjects(controller.pauseButton.currentTitle, @"Resume");
   XCTAssertTrue([controller.status.text containsString:@"Unable to start PS3 audio"]);
}
- (void)testInterruptionDuringBootPausesAndRequiresExplicitResume
{
   atomic_store(&bootState, RPCS3_IOS_EMULATION_STATE_STARTING);
   [self boot]; dispatch_semaphore_signal(bootGate);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_STARTING; }];
   [self.controller audioInterrupted:[NSNotification notificationWithName:AVAudioSessionInterruptionNotification
         object:nil userInfo:@{AVAudioSessionInterruptionTypeKey: @(AVAudioSessionInterruptionTypeBegan)}]];
   atomic_store(&state, RPCS3_IOS_EMULATION_STATE_RUNNING);
   [self until:^BOOL{ return atomic_load(&state) == RPCS3_IOS_EMULATION_STATE_PAUSED; }];
   [self.controller togglePause]; XCTAssertEqual(atomic_load(&resumes), 0);
   [self.controller audioInterrupted:[NSNotification notificationWithName:AVAudioSessionInterruptionNotification
         object:nil userInfo:@{AVAudioSessionInterruptionTypeKey: @(AVAudioSessionInterruptionTypeEnded)}]];
   XCTAssertEqual(atomic_load(&resumes), 0);
   [self.controller togglePause]; [self until:^BOOL{ return atomic_load(&resumes) == 1; }];
}
@end
