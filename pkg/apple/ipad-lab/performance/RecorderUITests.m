/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <XCTest/XCTest.h>
@interface PerformanceRecorderUITests : XCTestCase
@end
@implementation PerformanceRecorderUITests
- (void)testInstalledAppRecordsAndOffersReport
{
   XCUIApplication *app = [[XCUIApplication alloc] initWithBundleIdentifier:@"com.jamespauley.retroarchlab.ps3bridge"];
   [app launch];
   XCUIElement *performance = app.buttons[@"Performance"].firstMatch;
   XCTAssertTrue([performance waitForExistenceWithTimeout:20]);
   [performance tap];
   XCUIElement *recording = app.buttons[@"Performance recording"];
   XCTAssertTrue([recording waitForExistenceWithTimeout:5]);
   if ([recording.label isEqualToString:@"Stop recording"]) [recording tap];
   [recording tap];
   NSPredicate *sampled = [NSPredicate predicateWithFormat:@"value CONTAINS 'seconds' AND value CONTAINS 'CPU'"];
   [self expectationForPredicate:sampled evaluatedWithObject:app.textViews[@"Performance summary"] handler:nil];
   [self waitForExpectationsWithTimeout:8 handler:nil];
   [app.buttons[@"Mark slowdown"] tap];
   [recording tap];
   XCTAssertEqualObjects(recording.label, @"Start recording");
   [app.buttons[@"Share a report…"] tap];
   XCUIElement *report = [app.buttons matchingPredicate:[NSPredicate predicateWithFormat:@"label BEGINSWITH 'LabPerf-'"]].firstMatch;
   XCTAssertTrue([report waitForExistenceWithTimeout:5]);
   /* iPad action-sheet popovers omit the cancel row. */
   [[app coordinateWithNormalizedOffset:CGVectorMake(0.05, 0.8)] tap];
}
@end
