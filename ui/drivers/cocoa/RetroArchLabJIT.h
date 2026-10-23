/* SPDX-License-Identifier: GPL-3.0-or-later */
#import <UIKit/UIKit.h>

@interface RALabJIT : NSObject
+ (instancetype)shared;
- (void)showSettingsFrom:(UIViewController *)presenter;
- (void)enableFrom:(UIViewController *)presenter completion:(void (^)(BOOL))completion;
@end
