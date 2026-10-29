#import <XCTest/XCTest.h>
#import <TargetConditionals.h>
@interface LabUITests : XCTestCase
@end
@implementation LabUITests
- (void)waitForEnabled:(XCUIElement *)element timeout:(NSTimeInterval)timeout
{
   NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id value, NSDictionary *bindings) {
      XCUIElement *candidate = value;
      return candidate.exists && candidate.enabled;
   }];
   XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc] initWithPredicate:predicate object:element];
   XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:timeout], XCTWaiterResultCompleted);
}
- (void)captureGame:(NSString *)name
{
   XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
   shot.name = name; shot.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:shot];
}
- (void)waitForStatus:(XCUIApplication *)app prefix:(NSString *)prefix
{
   XCTNSPredicateExpectation *status = [[XCTNSPredicateExpectation alloc]
         initWithPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@", prefix]
         object:app.staticTexts[@"PS3 status"]];
   XCTAssertEqual([XCTWaiter waitForExpectations:@[status] timeout:15], XCTWaiterResultCompleted);
}
- (void)testDeviceJITHandoffInitializesCore
{
#if TARGET_OS_SIMULATOR
   XCTSkip(@"Requires the signed device core and configured StikDebug Universal.");
#else
   self.continueAfterFailure = NO;
   XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
   XCUIApplication *stik = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.stik.stikdebug"];
   [app launch];
   XCTAssertTrue([app.buttons[@"PS3"] waitForExistenceWithTimeout:20]);
   [app.buttons[@"PS3"] tap];
   XCTAssertTrue([app.buttons[@"Enable PS3 JIT"] waitForExistenceWithTimeout:10]);
   [app.buttons[@"Enable PS3 JIT"] tap];
   XCTAssertTrue([stik.buttons[@"Enable and Run Script"] waitForExistenceWithTimeout:20]);
   XCTAssertTrue(stik.staticTexts[@"An external link wants to enable JIT and run a script for com.jamespauley.retroarchlab.ps3bridge."].exists);
   [stik.buttons[@"Enable and Run Script"] tap];
   XCTAssertTrue([app waitForState:XCUIApplicationStateRunningForeground timeout:30]);
   [app activate];
   XCTAssertTrue([app.buttons[@"PS3"] waitForExistenceWithTimeout:20]);
   [app.buttons[@"PS3"] tap];
   XCTAssertTrue([app.buttons[@"Start PS3"] waitForExistenceWithTimeout:10]);
   [app.buttons[@"Start PS3"] tap];
   XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc]
         initWithPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"]
         object:app.buttons[@"Import"]];
   XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:45], XCTWaiterResultCompleted);
   XCTAssertTrue([app.staticTexts[@"PS3 status"].label containsString:@"Firmware"]);
#endif
}
- (void)testNativeLibraryOpensPS3AndRejectsMissingJIT
{
   XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
   [app launch];
   XCUIElement *ps3 = app.buttons[@"PS3"];
   XCTAssertTrue([ps3 waitForExistenceWithTimeout:20]);
   [ps3 tap];
   XCTAssertTrue([app.buttons[@"Start PS3"] waitForExistenceWithTimeout:5]);
   [app.buttons[@"Start PS3"] tap];
   NSPredicate *failure = [NSPredicate predicateWithFormat:@"label CONTAINS %@", @"Universal JIT is not attached"];
   XCTAssertTrue([[app.staticTexts matchingPredicate:failure].firstMatch waitForExistenceWithTimeout:5]);
   [app terminate];
}
- (void)testDeviceReadyGameLifecycle
{
#if TARGET_OS_SIMULATOR
   XCTSkip(@"Requires an initialized device core and an imported game.");
#else
   self.continueAfterFailure = NO;
   XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
   [app activate];
   XCTSkipUnless(app.staticTexts[@"PS3 status"].exists && app.buttons[@"Import"].enabled &&
         app.tables[@"PS3 games"].cells.count > 0, @"Initialize PS3 and import firmware and a game first.");
   [app.tables[@"PS3 games"].cells.firstMatch tap];
   if (!app.buttons[@"Pause"].enabled)
      XCTAssertFalse([app.staticTexts[@"PS3 status"].label hasPrefix:@"Game running"]);
   [self waitForEnabled:app.buttons[@"Pause"] timeout:1200];
   [self waitForStatus:app prefix:@"Game running"];
   [self captureGame:@"Running"];
   [app.buttons[@"Pause"] tap]; [self waitForStatus:app prefix:@"Paused"];
   [app.buttons[@"Resume"] tap]; [self waitForStatus:app prefix:@"Game running"];
   [XCUIDevice.sharedDevice pressButton:XCUIDeviceButtonHome]; [app activate];
   [self waitForStatus:app prefix:@"Paused"];
   XCTAssertTrue(app.buttons[@"Resume"].exists);
   [app.buttons[@"Resume"] tap]; [self waitForStatus:app prefix:@"Game running"];
   UIDeviceOrientation orientation = XCUIDevice.sharedDevice.orientation;
   if (orientation < UIDeviceOrientationPortrait || orientation > UIDeviceOrientationLandscapeRight)
      orientation = UIDeviceOrientationPortrait;
   [self addTeardownBlock:^{ XCUIDevice.sharedDevice.orientation = orientation; }];
   XCUIDevice.sharedDevice.orientation = UIDeviceOrientationLandscapeLeft;
   [self captureGame:@"Landscape"];
   XCUIDevice.sharedDevice.orientation = orientation;
   [app.buttons[@"Stop game"] tap];
   [self waitForEnabled:app.buttons[@"Import"] timeout:60];
   XCTAssertGreaterThan(app.tables[@"PS3 games"].cells.count, 0u);
   [app.tables[@"PS3 games"].cells.firstMatch tap];
   [self waitForEnabled:app.buttons[@"Pause"] timeout:180];
   [self waitForStatus:app prefix:@"Game running"];
   [self captureGame:@"Rebooted"];
   [app.buttons[@"Pause"] tap]; [self waitForStatus:app prefix:@"Paused"];
#endif
}
@end
