/* SPDX-License-Identifier: GPL-3.0-or-later */
#import "RetroArchLabJIT.h"
#import "RetroArchLabLibrary.h"
#import "cocoa_common.h"
#import <Security/Security.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <dlfcn.h>
#include <unistd.h>
#include "../../../pkg/apple/JITSupport.h"

/* Private extension API, used only in the sideloaded Lab build. */
@interface NSObject (RALabExtension)
+ (id)extensionWithIdentifier:(NSString *)identifier error:(NSError **)error;
- (void)beginExtensionRequestWithInputItems:(NSArray *)items completion:(void (^)(NSUUID *))completion;
- (void)setRequestCompletionBlock:(void (^)(NSUUID *, NSArray *))block;
- (void)setRequestCancellationBlock:(void (^)(NSUUID *, NSError *))block;
- (void)setRequestInterruptionBlock:(void (^)(NSUUID *))block;
@end

void cocoa_lab_show_jit_settings(void)
{
   dispatch_async(dispatch_get_main_queue(), ^{
      UIViewController *presenter = nil;
      for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
      {
         if (scene.activationState != UISceneActivationStateForegroundActive
               || ![scene isKindOfClass:UIWindowScene.class]) continue;
         for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) presenter = window.rootViewController;
      }
      if (!presenter) presenter = [CocoaView get].view.window.rootViewController;
      while (presenter.presentedViewController
            && !presenter.presentedViewController.isBeingDismissed)
         presenter = presenter.presentedViewController;
      if (presenter.view.window)
         [[RALabJIT shared] showSettingsFrom:presenter];
   });
}

extern CFTypeRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(CFTypeRef task, CFStringRef entitlement, CFErrorRef *error);

@interface RALabJIT () <UIDocumentPickerDelegate>
@property(nonatomic, weak) UIViewController *presenter;
@property(nonatomic, strong) id helper;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) UIAlertController *progress;
@property(nonatomic, copy) void (^completion)(BOOL);
@property(nonatomic, strong) NSDate *deadline;
@property(nonatomic, assign) NSUInteger generation;
@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL enabling;
@property(nonatomic, assign) BOOL abandoned;
@property(nonatomic, assign) BOOL poolReady;
@property(nonatomic, copy) NSString *lastStatus;
@end

@implementation RALabJIT
+ (instancetype)shared
{
   static RALabJIT *instance;
   static dispatch_once_t once;
   dispatch_once(&once, ^{ instance = [[self alloc] init]; });
   return instance;
}
- (NSMutableDictionary *)keyQuery
{
   return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
         (__bridge id)kSecAttrService: @"RetroArchLab.StikJIT",
         (__bridge id)kSecAttrAccount: @"pairing"} mutableCopy];
}
- (NSData *)pairing
{
   NSMutableDictionary *query = [self keyQuery];
   query[(__bridge id)kSecReturnData] = @YES;
   CFTypeRef result = NULL;
   if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess)
      return nil;
   return CFBridgingRelease(result);
}
- (BOOL)debuggable
{
   CFTypeRef task = SecTaskCreateFromSelf(NULL);
   if (!task) return NO;
   CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
   BOOL allowed = value && CFEqual(value, kCFBooleanTrue);
   if (value) CFRelease(value);
   CFRelease(task);
   return allowed;
}
- (NSString *)helperIdentifier
{
   NSURL *url = [NSBundle.mainBundle.builtInPlugInsURL URLByAppendingPathComponent:@"RALabJITHelper.appex"];
   return url ? [NSBundle bundleWithURL:url].bundleIdentifier : nil;
}
- (NSString *)method
{
   return [NSUserDefaults.standardUserDefaults stringForKey:@"RALabJITMethod"] ?: @"builtin";
}
- (NSString *)preflight:(BOOL)builtin
{
#if TARGET_OS_SIMULATOR
   return @"JIT activation requires a physical device.";
#endif
   if (@available(iOS 26.0, *)) {} else return @"Built-in JIT requires iOS 26 or later.";
   if (![self debuggable]) return @"This installation is not signed for debugging. Re-sign with get-task-allow enabled.";
   if (builtin)
   {
      if (getenv("LC_HOME_PATH")) return @"Built-in JIT is unavailable in LiveContainer. Select StikDebug.";
      if (![self helperIdentifier]) return @"The JIT helper is missing. Reinstall this test build and keep app extensions, or select StikDebug.";
      if (![self pairing]) return @"Open JIT Setup and import this device's pairing file first. Enable Developer Mode and connect LocalDevVPN.";
   }
   return nil;
}
- (void)message:(NSString *)message from:(UIViewController *)presenter
{
   self.lastStatus = message;
   UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"JIT"
         message:message preferredStyle:UIAlertControllerStyleAlert];
   [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
   if (presenter.view.window && !presenter.presentedViewController)
      [presenter presentViewController:alert animated:YES completion:nil];
}
- (void)showSettingsFrom:(UIViewController *)presenter
{
   if (self.busy)
   { [self message:@"JIT activation is still running. Wait for it to finish; if it does not respond, close and reopen this test app." from:presenter]; return; }
   self.presenter = presenter;
   NSString *method = [self method];
   NSString *status = [NSString stringWithFormat:@"Method: %@\nPairing file: %@\n\nEnable Developer Mode and connect LocalDevVPN. Built-in activation runs when you launch a JIT game.\n\n%@",
         [method isEqualToString:@"builtin"] ? @"Built-in StikJIT" : ([method isEqualToString:@"stikdebug"] ? @"StikDebug" : @"Wait for debugger"),
         [self pairing] ? @"Imported (private to this device)" : @"Not imported", self.lastStatus ?: @""];
   UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"JIT Setup" message:status
         preferredStyle:UIAlertControllerStyleActionSheet];
   for (NSArray *choice in @[@[@"Built-in StikJIT", @"builtin"], @[@"StikDebug", @"stikdebug"], @[@"Wait for debugger", @"external"]])
      [menu addAction:[UIAlertAction actionWithTitle:choice[0] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
         [NSUserDefaults.standardUserDefaults setObject:choice[1] forKey:@"RALabJITMethod"];
         self.lastStatus = @"Method selected.";
      }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Import pairing file" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeData] asCopy:NO];
      picker.delegate = self;
      [presenter presentViewController:picker animated:YES completion:nil];
   }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Check setup" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      [self beginOperation:@"prepare" from:presenter completion:nil];
   }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Enable JIT now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      [self enableFrom:presenter completion:nil];
   }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Reset Developer Disk Image" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
      [self beginOperation:@"reset" from:presenter completion:nil];
   }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Forget pairing file" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
      SecItemDelete((__bridge CFDictionaryRef)[self keyQuery]);
      self.lastStatus = @"Pairing file removed.";
   }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
   menu.popoverPresentationController.sourceView = presenter.view;
   menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), 60, 1, 1);
   [presenter presentViewController:menu animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
   NSURL *url = urls.firstObject;
   BOOL scoped = [url startAccessingSecurityScopedResource];
   NSError *error = nil;
   NSNumber *size = nil;
   [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
   NSData *data = size && size.unsignedLongLongValue <= 1024 * 1024 ? [NSData dataWithContentsOfURL:url options:0 error:&error] : nil;
   if (scoped) [url stopAccessingSecurityScopedResource];
   id plist = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error] : nil;
   if (![plist isKindOfClass:NSDictionary.class] || ![(NSDictionary *)plist count])
   { [self message:@"Choose a valid device pairing plist smaller than 1 MB." from:self.presenter]; return; }
   NSDictionary *attributes = @{(__bridge id)kSecValueData: data,
         (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
   NSMutableDictionary *query = [self keyQuery];
   OSStatus result = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
   if (result == errSecItemNotFound)
   {
      [query addEntriesFromDictionary:attributes];
      result = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
   }
   if (result == errSecSuccess)
   {
      [NSUserDefaults.standardUserDefaults setObject:@"builtin" forKey:@"RALabJITMethod"];
      [self message:@"Pairing file imported. Connect LocalDevVPN, then launch your game or use Check setup." from:self.presenter];
   }
   else [self message:@"The pairing file could not be stored. Unlock the device and try again." from:self.presenter];
}
- (void)enableFrom:(UIViewController *)presenter completion:(void (^)(BOOL))completion
{
   [self beginOperation:@"enable" from:presenter completion:completion];
}
- (void)finish:(BOOL)success message:(NSString *)message generation:(NSUInteger)generation
{
   if (!self.busy || generation != self.generation) return;
   exec_mem_end_builtin_jit();
   [self.timer invalidate]; self.timer = nil;
   self.busy = NO;
   [self.helper setRequestCompletionBlock:nil];
   [self.helper setRequestCancellationBlock:nil];
   [self.helper setRequestInterruptionBlock:nil];
   self.helper = nil;
   void (^completion)(BOOL) = self.completion;
   self.completion = nil;
   BOOL deliver = !self.abandoned && UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
   self.lastStatus = message;
   UIAlertController *progress = self.progress;
   self.progress = nil;
   void (^done)(void) = ^{
      if (deliver && completion) completion(success);
      if (deliver && (!success || !completion)) [self message:message from:self.presenter];
   };
   if (progress.presentingViewController) [progress dismissViewControllerAnimated:YES completion:done];
   else done();
}
- (void)poll:(NSUInteger)generation
{
   if (!self.busy || generation != self.generation) return;
   /* The script must prepare the pool before any core can run. */
   if (self.enabling && !self.poolReady)
      self.poolReady = exec_mem_pool_init();
   if (!self.helper && self.poolReady)
   { [self finish:YES message:@"JIT is ready." generation:generation]; return; }
   if ([self.deadline timeIntervalSinceNow] <= 0 && !self.abandoned)
   {
      self.abandoned = YES;
      self.completion = nil;
      self.progress.message = @"Activation has taken too long. No game will start automatically. Close and reopen this test app before retrying.";
      if (!self.helper) [self finish:NO message:self.progress.message generation:generation];
   }
}
- (void)beginOperation:(NSString *)operation from:(UIViewController *)presenter completion:(void (^)(BOOL))completion
{
   if (self.busy) { if (completion) completion(NO); return; }
   BOOL enabling = [operation isEqualToString:@"enable"];
   BOOL builtin = !enabling || [[self method] isEqualToString:@"builtin"];
   if (builtin && !exec_mem_begin_builtin_jit())
   {
      if (completion) completion(NO);
      [self message:@"A network JIT activation is still finishing or its result is unknown. Wait, then retry. If it stays blocked, close and reopen this test app." from:presenter];
      return;
   }
   if (enabling && exec_mem_pool_init())
   { if (builtin) exec_mem_end_builtin_jit(); if (completion) completion(YES); return; }
   NSString *problem = [self preflight:builtin];
   if (problem)
   { if (builtin) exec_mem_end_builtin_jit(); if (completion) completion(NO); [self message:problem from:presenter]; return; }
   self.presenter = presenter;
   self.busy = YES; self.enabling = enabling; self.abandoned = NO; self.poolReady = NO;
   self.completion = completion;
   NSUInteger generation = ++self.generation;
   self.deadline = [NSDate dateWithTimeIntervalSinceNow:180];
   self.progress = [UIAlertController alertControllerWithTitle:enabling ? @"Enabling JIT" : @"Preparing JIT"
         message:@"Keep Lab open and LocalDevVPN connected. The first preparation may download developer support files."
         preferredStyle:UIAlertControllerStyleAlert];
   [self.progress addAction:[UIAlertAction actionWithTitle:@"Stop waiting" style:UIAlertActionStyleCancel handler:^(UIAlertAction *a) {
      self.abandoned = YES;
      self.completion = nil;
      self.lastStatus = @"Automatic launch cancelled. The helper may still be finishing; reopen Lab if it stalls.";
      if (!self.helper) [self finish:NO message:self.lastStatus generation:generation];
   }]];
   [presenter presentViewController:self.progress animated:YES completion:nil];
   self.timer = [NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) { [self poll:generation]; }];
   if (!builtin)
   {
      if ([[self method] isEqualToString:@"external"])
      { self.progress.message = @"Enable JIT for this app with your debugger, then return to Lab."; return; }
      NSURLComponents *url = [[NSURLComponents alloc] init];
      url.scheme = @"stikdebug"; url.host = @"enable-jit";
      url.queryItems = @[[NSURLQueryItem queryItemWithName:@"bundle-id" value:NSBundle.mainBundle.bundleIdentifier],
            [NSURLQueryItem queryItemWithName:@"pid" value:[NSString stringWithFormat:@"%d", getpid()]],
            [NSURLQueryItem queryItemWithName:@"script-name" value:@"universal.js"]];
      [UIApplication.sharedApplication openURL:url.URL options:@{} completionHandler:^(BOOL opened) {
         if (!opened) [self finish:NO message:@"StikDebug could not open. Install it or select Built-in StikJIT." generation:generation];
      }];
      return;
   }
   if (!NSClassFromString(@"NSExtension"))
      dlopen("/System/Library/Frameworks/ExtensionFoundation.framework/ExtensionFoundation", RTLD_NOW);
   Class type = NSClassFromString(@"NSExtension");
   NSError *error = nil;
   if ([type respondsToSelector:@selector(extensionWithIdentifier:error:)])
      self.helper = [type extensionWithIdentifier:[self helperIdentifier] error:&error];
   if (!self.helper)
   { [self finish:NO message:error.localizedDescription ?: @"iOS could not start the embedded JIT helper. Keep extensions when signing, or select StikDebug." generation:generation]; return; }
   __weak RALabJIT *weakSelf = self;
   [self.helper setRequestCompletionBlock:^(NSUUID *request, NSArray *items) {
      NSDictionary *response = [items.firstObject isKindOfClass:NSExtensionItem.class] ? ((NSExtensionItem *)items.firstObject).userInfo : nil;
      dispatch_async(dispatch_get_main_queue(), ^{
         RALabJIT *owner = weakSelf;
         if (enabling && [response[@"success"] boolValue] && !owner.poolReady)
            owner.poolReady = exec_mem_pool_init();
         BOOL ready = [response[@"success"] boolValue] && (!enabling || owner.poolReady);
         NSString *message = response[@"message"] ?: @"The helper returned no result.";
         if (enabling && [response[@"success"] boolValue] && !owner.poolReady) message = @"The debugger finished but executable memory is not ready. No game was started.";
         [owner finish:ready message:message generation:generation];
      });
   }];
   [self.helper setRequestCancellationBlock:^(NSUUID *request, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finish:NO message:error.localizedDescription ?: @"JIT helper cancelled." generation:generation]; });
   }];
   [self.helper setRequestInterruptionBlock:^(NSUUID *request) {
      dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finish:NO message:@"JIT helper interrupted. Try again with Lab open and LocalDevVPN connected." generation:generation]; });
   }];
   NSExtensionItem *item = [[NSExtensionItem alloc] init];
   item.userInfo = @{@"operation": operation, @"pid": @(getpid()), @"pairing": [self pairing] ?: NSData.data};
   [self.helper beginExtensionRequestWithInputItems:@[item] completion:^(NSUUID *request) {
      if (!request) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf finish:NO message:@"The JIT helper did not start. Reinstall keeping app extensions." generation:generation]; });
   }];
}
@end
