#import <XCTest/XCTest.h>
#import <TargetConditionals.h>
@interface LabUITests : XCTestCase
@end
@implementation LabUITests
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
@end
