#import <XCTest/XCTest.h>
@interface LabUITests : XCTestCase
@end
@implementation LabUITests
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
