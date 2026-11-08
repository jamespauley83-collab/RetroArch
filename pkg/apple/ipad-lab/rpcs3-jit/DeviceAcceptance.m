#import <XCTest/XCTest.h>
@interface StorageAcceptance : XCTestCase
@end
@implementation StorageAcceptance
- (void)capture:(NSString *)name
{
    XCTAttachment *shot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    shot.name = name;
    shot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:shot];
}
- (void)testRestoreJIT
{
    self.continueAfterFailure = NO;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
    XCUIApplication *stik = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.stik.stikdebug"];
    [app terminate];
    [app launch];
    XCTAssertTrue([app.buttons[@"PS3"] waitForExistenceWithTimeout:20], @"%@", app.debugDescription);
    [app.buttons[@"PS3"] tap];
    XCTAssertTrue([app.buttons[@"Enable PS3 JIT"] waitForExistenceWithTimeout:10], @"%@", app.debugDescription);
    [app.buttons[@"Enable PS3 JIT"] tap];
    XCTAssertTrue([stik.buttons[@"Enable and Run Script"] waitForExistenceWithTimeout:20], @"%@", stik.debugDescription);
    XCTAssertTrue(stik.staticTexts[@"An external link wants to enable JIT and run a script for com.jamespauley.retroarchlab.ps3bridge."].exists);
    [stik.buttons[@"Enable and Run Script"] tap];
    XCTAssertTrue([app waitForState:XCUIApplicationStateRunningForeground timeout:40], @"%@", stik.debugDescription);
    [app activate];
    XCTAssertTrue([app.buttons[@"PS3"] waitForExistenceWithTimeout:20]);
    [app.buttons[@"PS3"] tap];
    XCTAssertTrue([app.buttons[@"Start PS3"] waitForExistenceWithTimeout:10]);
    [app.buttons[@"Start PS3"] tap];
    XCTNSPredicateExpectation *ready = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] object:app.buttons[@"Import"]];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[ready] timeout:60], XCTWaiterResultCompleted, @"%@", app.debugDescription);
    NSString *status = app.staticTexts[@"PS3 status"].label;
    XCTAssertTrue([status containsString:@"Firmware"]);
    XCTAssertFalse([status containsString:@"Interpreter"]);
    NSLog(@"JIT_RESTORED_STATUS %@", status);
    [self capture:@"Development JIT initialized"];
}
- (void)testBootWithJIT
{
    self.continueAfterFailure = NO;
    XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
    [app activate];
    XCTAssertTrue([app.staticTexts[@"PS3 status"] waitForExistenceWithTimeout:10], @"%@", app.debugDescription);
    if (!app.buttons[@"Stop game"].exists) {
        XCTAssertTrue(app.buttons[@"Import"].enabled);
        XCTAssertEqual(app.tables[@"PS3 games"].cells.count, 1u);
        [app.tables[@"PS3 games"].cells.firstMatch tap];
    } else if (app.buttons[@"Resume"].exists) {
        [app.buttons[@"Resume"] tap];
    }
    XCTNSPredicateExpectation *playing = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] object:app.buttons[@"Pause"]];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[playing] timeout:600], XCTWaiterResultCompleted, @"%@", app.debugDescription);
    NSLog(@"JIT_GAME_STATUS %@", app.staticTexts[@"PS3 status"].label);
    [self capture:@"PS3 game running with JIT"];
    [app.buttons[@"Pause"] tap];
    XCTNSPredicateExpectation *paused = [[XCTNSPredicateExpectation alloc]
        initWithPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH %@", @"Paused"] object:app.staticTexts[@"PS3 status"]];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[paused] timeout:15], XCTWaiterResultCompleted);
    NSLog(@"JIT_FINAL_STATUS %@", app.staticTexts[@"PS3 status"].label);
    [self capture:@"PS3 JIT paused"];
}
@end
