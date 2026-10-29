/* SPDX-License-Identifier: GPL-3.0-or-later */
#import "RetroArchLabRPCS3.h"
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <AVFoundation/AVFoundation.h>
#include <dlfcn.h>
#include <math.h>
#include "../../../pkg/apple/JITSupport.h"
#include "../../../pkg/apple/ipad-lab/rpcs3/RPCS3BridgeAPI.h"
#include "../../../pkg/apple/ipad-lab/rpcs3/RPCS3JITProbe.h"

static RALabPS3API ra_ps3_api;
static void *ra_ps3_handle;
static BOOL ra_ps3_ready;
static BOOL ra_ps3_failed;
static dispatch_queue_t ra_ps3_queue;
BOOL RALabRPCS3Loaded(void) { return ra_ps3_handle != NULL; }

static NSString *RALabPS3String(const char *text)
{ return text ? [NSString stringWithUTF8String:text] ?: @"" : @""; }
static NSString *RALabPS3Error(int status)
{
   return [NSString stringWithFormat:@"RPCS3 error %d: %@", status,
         RALabPS3String(ra_ps3_api.last_error())];
}
static BOOL RALabPS3ProfileReady(void)
{
   NSString *path = [NSBundle.mainBundle pathForResource:@"embedded" ofType:@"mobileprovision"];
   NSData *data = path ? [NSData dataWithContentsOfFile:path] : nil;
   NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] : nil;
   if (!text) return NO;
   NSRange start = [text rangeOfString:@"<plist"], end = [text rangeOfString:@"</plist>"];
   if (start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) return NO;
   NSData *xml = [[text substringWithRange:NSMakeRange(start.location, NSMaxRange(end) - start.location)] dataUsingEncoding:NSISOLatin1StringEncoding];
   NSDictionary *profile = [NSPropertyListSerialization propertyListWithData:xml options:0 format:nil error:nil];
   NSDictionary *entitlements = [profile isKindOfClass:NSDictionary.class] ? profile[@"Entitlements"] : nil;
   return [entitlements[@"get-task-allow"] boolValue] &&
         [entitlements[@"com.apple.developer.kernel.extended-virtual-addressing"] boolValue] &&
         [entitlements[@"com.apple.developer.kernel.increased-memory-limit"] boolValue];
}
static void RALabPS3Main(void *context, rpcs3_ios_main_thread_task task, void *payload)
{
   (void)context;
   dispatch_async(dispatch_get_main_queue(), ^{ task(payload); });
}
static void RALabPS3Log(void *context, int32_t level, const char *message)
{
   (void)context;
   if (level <= 4) NSLog(@"[Lab PS3] %@", RALabPS3String(message));
}

@interface RALabPS3Surface : UIView
@end
@implementation RALabPS3Surface
+ (Class)layerClass { return CAMetalLayer.class; }
@end

@interface RALabPS3Controller : UIViewController <UITableViewDataSource,
      UITableViewDelegate, UIDocumentPickerDelegate>
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) RALabPS3Surface *surface;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) UIStackView *controls;
@property(nonatomic, strong) UIButton *startButton;
@property(nonatomic, strong) UIButton *jitButton;
@property(nonatomic, strong) UIButton *importButton;
@property(nonatomic, strong) UIButton *pauseButton;
@property(nonatomic, strong) UIButton *stopButton;
@property(nonatomic, copy) NSArray *games;
@property(nonatomic, copy) NSString *importKind;
@property(nonatomic, assign) BOOL busy;
@property(nonatomic, assign) BOOL booting;
@property(nonatomic, assign) NSUInteger bootGeneration;
@property(nonatomic, copy) NSString *bootError;
@property(nonatomic, assign) BOOL playing;
@property(nonatomic, assign) BOOL stopping;
@property(nonatomic, assign) BOOL backgrounded;
@property(nonatomic, assign) BOOL pausePending;
@property(nonatomic, assign) BOOL audioInterruption;
@property(nonatomic, assign) uint64_t touchButtons;
@property(nonatomic, strong) NSArray<GCController *> *controllers;
@end

static void RALabPS3Game(void *context, const rpcs3_ios_game_info *game)
{
   NSMutableArray *games = (__bridge NSMutableArray *)context;
   if (!game || game->struct_size < offsetof(rpcs3_ios_game_info, bootable) + sizeof(game->bootable) || !game->bootable)
      return;
   [games addObject:@{@"id": RALabPS3String(game->title_id), @"title": RALabPS3String(game->title)}];
}
static void RALabPS3Progress(void *context, uint32_t done, uint32_t total, const char *stage)
{
   RALabPS3Controller *owner = (__bridge RALabPS3Controller *)context;
   NSString *message = total ? [NSString stringWithFormat:@"%@: %u / %u",
         RALabPS3String(stage), done, total] : RALabPS3String(stage);
   dispatch_async(dispatch_get_main_queue(), ^{ owner.status.text = message; });
}

@implementation RALabPS3Controller
- (UIButton *)button:(NSString *)title action:(SEL)action
{
   UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
   [button setTitle:title forState:UIControlStateNormal];
   [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
   button.accessibilityIdentifier = title;
   return button;
}
- (void)viewDidLoad
{
   [super viewDidLoad];
   self.title = @"PlayStation 3";
   self.view.backgroundColor = UIColor.systemBackgroundColor;
   self.games = @[];
   self.controllers = @[];
   self.status = [[UILabel alloc] init];
   self.status.numberOfLines = 0;
   self.status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
   self.status.accessibilityIdentifier = @"PS3 status";
   self.status.text = @"XITRIX 0.12 bridge. Enable PS3 JIT to relaunch this test app through StikDebug. Then open PS3 and tap Start PS3. Import firmware and games into this app's separate library.";
   self.jitButton = [self button:@"Enable PS3 JIT" action:@selector(enableJIT)];
   self.startButton = [self button:@"Start PS3" action:@selector(startCore)];
   self.importButton = [self button:@"Import" action:@selector(importMenu)];
   self.pauseButton = [self button:@"Pause" action:@selector(togglePause)];
   self.stopButton = [self button:@"Stop game" action:@selector(stopGame)];
   UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:
         @[self.jitButton, self.startButton, self.importButton, self.pauseButton, self.stopButton]];
   actions.distribution = UIStackViewDistributionEqualSpacing;
   actions.spacing = 8;
   self.surface = [[RALabPS3Surface alloc] init];
   self.surface.backgroundColor = UIColor.blackColor;
   CAMetalLayer *layer = (CAMetalLayer *)self.surface.layer;
   layer.device = MTLCreateSystemDefaultDevice();
   layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
   layer.framebufferOnly = NO;
   self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
   self.table.dataSource = self; self.table.delegate = self;
   self.table.accessibilityIdentifier = @"PS3 games";
   self.controls = [[UIStackView alloc] init];
   self.controls.axis = UILayoutConstraintAxisVertical;
   NSArray *titles = @[@[@"↑", @"↓", @"←", @"→", @"L1", @"R1", @"L2", @"R2"],
         @[@"✕", @"○", @"□", @"△", @"Select", @"Start", @"L3", @"R3"]];
   const unsigned bits[16] = {0,1,2,3,8,9,10,11,4,5,6,7,15,14,12,13};
   NSUInteger index = 0;
   for (NSArray *row in titles)
   {
      UIStackView *stack = [[UIStackView alloc] init];
      stack.distribution = UIStackViewDistributionFillEqually;
      for (NSString *title in row)
      {
         UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
         [button setTitle:title forState:UIControlStateNormal];
         button.tag = bits[index++];
         button.multipleTouchEnabled = YES;
         [button addTarget:self action:@selector(touchDown:) forControlEvents:UIControlEventTouchDown];
         [button addTarget:self action:@selector(touchUp:) forControlEvents:
               UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
         [stack addArrangedSubview:button];
      }
      [self.controls addArrangedSubview:stack];
   }
   UIStackView *layout = [[UIStackView alloc] initWithArrangedSubviews:
         @[self.status, actions, self.surface, self.controls, self.table]];
   layout.axis = UILayoutConstraintAxisVertical; layout.spacing = 10;
   layout.translatesAutoresizingMaskIntoConstraints = NO;
   [self.view addSubview:layout];
   UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
   [NSLayoutConstraint activateConstraints:@[
         [layout.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
         [layout.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
         [layout.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
         [layout.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
         [self.controls.heightAnchor constraintEqualToConstant:88]]];
   NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
   [center addObserver:self selector:@selector(background) name:UIApplicationWillResignActiveNotification object:nil];
   [center addObserver:self selector:@selector(foreground) name:UIApplicationDidBecomeActiveNotification object:nil];
   [center addObserver:self selector:@selector(controllerChanged) name:GCControllerDidConnectNotification object:nil];
   [center addObserver:self selector:@selector(controllerChanged) name:GCControllerDidDisconnectNotification object:nil];
   [center addObserver:self selector:@selector(audioInterrupted:) name:AVAudioSessionInterruptionNotification object:nil];
   [self controllerChanged];
   [self updateControls];
   if (ra_ps3_ready) [self reloadGames];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)updateControls
{
   self.startButton.hidden = ra_ps3_ready;
   self.jitButton.hidden = ra_ps3_ready;
   self.startButton.enabled = !self.busy && !ra_ps3_failed;
   self.jitButton.enabled = !self.busy && !ra_ps3_failed;
   self.importButton.enabled = ra_ps3_ready && !self.busy && !self.playing;
   self.pauseButton.hidden = self.stopButton.hidden = !self.playing;
   self.pauseButton.enabled = !self.busy && !self.pausePending && !self.stopping;
   self.stopButton.enabled = !self.stopping;
   self.table.hidden = self.playing;
   self.surface.hidden = self.controls.hidden = !self.playing;
   self.table.userInteractionEnabled = ra_ps3_ready && !self.busy;
   self.navigationItem.hidesBackButton = self.busy || self.playing;
   self.navigationController.modalInPresentation = self.busy || self.playing;
}
- (void)enableJIT
{
   NSURLComponents *url = [[NSURLComponents alloc] init];
   url.scheme = @"stikdebug"; url.host = @"enable-jit";
   /* StikDebug must launch the process before attaching on this device. */
   url.queryItems = @[[NSURLQueryItem queryItemWithName:@"bundle-id" value:NSBundle.mainBundle.bundleIdentifier],
         [NSURLQueryItem queryItemWithName:@"script-name" value:@"universal.js"]];
   [UIApplication.sharedApplication openURL:url.URL options:@{} completionHandler:^(BOOL opened) {
      self.status.text = opened ? @"Let StikDebug relaunch this test app with Universal, then open PS3 and tap Start PS3."
            : @"Open StikDebug, assign universal.js to this PS3 test app, and launch it there.";
   }];
}
- (void)startCore
{
   if (self.busy || ra_ps3_ready || ra_ps3_failed) return;
#if !TARGET_OS_SIMULATOR
   if (!RALabPS3ProfileReady())
   { self.status.text = @"Sign this test app with Extended Virtual Addressing, Increased Memory Limit and development debugging enabled before starting PS3."; return; }
#endif
   if (!exec_mem_begin_builtin_jit())
   { self.status.text = @"Another JIT request is active. Restart this test app before preparing PS3."; return; }
   self.busy = YES; self.status.text = @"Checking PS3 JIT and loading XITRIX 0.12…";
   [self updateControls];
   dispatch_async(ra_ps3_queue, ^{
      NSString *failure = nil;
      BOOL ready = NO;
      if (!RALabPS3JITAttached())
         failure = @"Universal JIT is not attached. Use Enable PS3 JIT, return here, and try again. Lab's PS2 JIT pool does not prepare the PS3 core.";
      else
      {
         NSString *path = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"libRPCS3Core.dylib"];
         ra_ps3_handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
         if (!ra_ps3_handle) failure = RALabPS3String(dlerror());
         else
         {
            const char *missing = NULL;
            if (!RALabPS3Resolve(&ra_ps3_api, ra_ps3_handle, dlsym, &missing))
               failure = [@"Unsupported PS3 core: " stringByAppendingString:RALabPS3String(missing)];
            else
            {
               NSFileManager *files = NSFileManager.defaultManager;
               NSURL *documents = [files URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
               NSURL *root = [documents URLByAppendingPathComponent:@"PS3/Data" isDirectory:YES];
               NSURL *cache = [documents URLByAppendingPathComponent:@"PS3/Cache" isDirectory:YES];
               NSError *error = nil;
               if (![files createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error] ||
                     ![files createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:&error])
                  failure = error.localizedDescription;
               else
               {
                  [cache setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
                  rpcs3_ios_config config = {0};
                  config.abi_version = RPCS3_IOS_ABI_VERSION; config.struct_size = sizeof(config);
                  NSString *rootPath = [root.path stringByAppendingString:@"/"];
                  NSString *cachePath = [cache.path stringByAppendingString:@"/"];
                  config.application_support_path = rootPath.fileSystemRepresentation;
                  config.cache_path = cachePath.fileSystemRepresentation;
                  config.main_thread_callback = RALabPS3Main; config.log_callback = RALabPS3Log;
                  int status = ra_ps3_api.initialize(&config);
                  uint64_t result = 0;
                  if (!status) status = ra_ps3_api.run_llvm_self_test(5, &result);
                  if (status) failure = RALabPS3Error(status);
                  else if (result != 22) failure = @"PS3 executable-memory self-test returned an invalid result.";
                  else ready = YES;
               }
            }
         }
      }
      exec_mem_end_builtin_jit();
      dispatch_async(dispatch_get_main_queue(), ^{
         ra_ps3_ready = ready;
         ra_ps3_failed = !ready && ra_ps3_handle != NULL;
         self.busy = NO;
         self.status.text = failure ? [failure stringByAppendingString:ra_ps3_failed ? @" Restart this test app before trying again." : @""] : @"PS3 core ready.";
         [self updateControls];
         if (ready) [self reloadGames];
      });
   });
}
- (void)reloadGames
{
   if (self.busy || self.playing || !ra_ps3_ready) return;
   self.busy = YES; [self updateControls];
   dispatch_async(ra_ps3_queue, ^{
      NSMutableArray *games = [NSMutableArray array];
      int status = ra_ps3_api.enumerate_games(RALabPS3Game, (__bridge void *)games);
      NSString *message = status ? RALabPS3Error(status) : [NSString stringWithFormat:
            @"Firmware %@ · %lu games · Connect a controller for analog sticks.",
            RALabPS3String(ra_ps3_api.firmware_version()), (unsigned long)games.count];
      dispatch_async(dispatch_get_main_queue(), ^{
         self.games = games; self.status.text = self.bootError ?: message; self.bootError = nil; self.busy = NO;
         [self.table reloadData]; [self updateControls];
      });
   });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section
{ return self.games.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path
{
   UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
   cell.textLabel.text = self.games[path.row][@"title"];
   cell.detailTextLabel.text = self.games[path.row][@"id"];
   cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
   return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path
{
   [table deselectRowAtIndexPath:path animated:YES];
   if (self.busy || self.playing || !ra_ps3_ready || self.backgrounded) return;
   if (self.audioInterruption || ![self activateAudio]) return;
   NSString *titleID = self.games[path.row][@"id"];
   self.playing = YES; self.busy = YES; self.booting = YES;
   NSUInteger generation = ++self.bootGeneration;
   self.status.text = @"Preparing game…";
   [self updateControls]; [self.view layoutIfNeeded];
   [self resizeSurface];
   self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
   [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
   dispatch_async(ra_ps3_queue, ^{
      int status = ra_ps3_api.boot_game(titleID.UTF8String, NULL);
      NSString *message = status ? RALabPS3Error(status) : @"Starting game. First-time shader compilation may take a few minutes…";
      dispatch_async(dispatch_get_main_queue(), ^{
         if (generation != self.bootGeneration || self.stopping) return;
         self.status.text = message;
         if (status) { self.bootError = message; [self stopGame]; }
         else [self pollBoot:generation];
      });
   });
}
- (void)pollBoot:(NSUInteger)generation
{
   if (generation != self.bootGeneration || !self.playing || !self.booting || self.stopping) return;
   dispatch_async(ra_ps3_queue, ^{
      rpcs3_ios_emulation_state state = ra_ps3_api.get_emulation_state();
      dispatch_async(dispatch_get_main_queue(), ^{
         if (generation != self.bootGeneration || !self.playing || self.stopping) return;
         if (state == RPCS3_IOS_EMULATION_STATE_RUNNING || state == RPCS3_IOS_EMULATION_STATE_PAUSED)
         {
            self.booting = NO; self.busy = NO;
            BOOL paused = state == RPCS3_IOS_EMULATION_STATE_PAUSED;
            self.status.text = paused ? @"Paused." : @"Game running. Save in the game before stopping.";
            [self.pauseButton setTitle:paused ? @"Resume" : @"Pause" forState:UIControlStateNormal];
            [self updateControls];
            if ((self.backgrounded || self.audioInterruption) && !paused) [self pauseForBackground];
         }
         else if (state == RPCS3_IOS_EMULATION_STATE_STOPPED)
         {
            self.bootError = @"Game stopped before startup completed.";
            [self stopGame];
         }
         else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 4), dispatch_get_main_queue(), ^{
            [self pollBoot:generation];
         });
      });
   });
}
- (void)viewDidLayoutSubviews
{
   [super viewDidLayoutSubviews];
   if (self.playing) [self resizeSurface];
}
- (void)resizeSurface
{
   CAMetalLayer *layer = (CAMetalLayer *)self.surface.layer;
   CGFloat scale = self.traitCollection.displayScale;
   CGSize size = self.surface.bounds.size;
   if (size.width <= 0 || size.height <= 0) return;
   layer.contentsScale = scale;
   layer.drawableSize = CGSizeMake(round(size.width * scale), round(size.height * scale));
   rpcs3_ios_display_surface surface = {0};
   surface.struct_size = sizeof(surface); surface.width = layer.drawableSize.width;
   surface.height = layer.drawableSize.height; surface.refresh_rate = 60;
   surface.metal_layer = (__bridge void *)layer;
   int status = ra_ps3_api.set_display_surface(&surface);
   if (status) self.status.text = RALabPS3Error(status);
}
- (void)touchDown:(UIButton *)button { self.touchButtons |= UINT64_C(1) << button.tag; }
- (void)touchUp:(UIButton *)button { self.touchButtons &= ~(UINT64_C(1) << button.tag); }
- (void)controllerChanged
{
   NSMutableArray *controllers = [NSMutableArray array];
   for (GCController *controller in GCController.controllers)
      if (controller.extendedGamepad && controllers.count < 7) [controllers addObject:controller];
   self.controllers = controllers;
   self.touchButtons = 0;
}
- (void)releaseInput
{
   self.touchButtons = 0;
   if (!ra_ps3_ready) return;
   rpcs3_ios_pad_state pad = {0}; pad.struct_size = sizeof(pad);
   for (unsigned index = 0; index < 7; index++) ra_ps3_api.set_pad_state(index, &pad);
}
- (void)tick
{
   if (!self.playing || self.backgrounded || self.stopping) return;
   for (unsigned index = 0; index < 7; index++)
   {
      rpcs3_ios_pad_state pad = {0}; pad.struct_size = sizeof(pad);
      GCExtendedGamepad *gamepad = index < self.controllers.count ? self.controllers[index].extendedGamepad : nil;
      pad.connected = gamepad || index == 0;
      if (index == 0) pad.buttons = self.touchButtons;
      if (gamepad)
      {
         NSArray *buttons = @[gamepad.dpad.up, gamepad.dpad.down, gamepad.dpad.left, gamepad.dpad.right,
               gamepad.buttonA, gamepad.buttonB, gamepad.buttonX, gamepad.buttonY,
               gamepad.leftShoulder, gamepad.rightShoulder, gamepad.leftTrigger, gamepad.rightTrigger];
         for (unsigned bit = 0; bit < buttons.count; bit++)
            if (((GCControllerButtonInput *)buttons[bit]).pressed) pad.buttons |= UINT64_C(1) << bit;
         if (gamepad.leftThumbstickButton.pressed) pad.buttons |= RPCS3_IOS_PAD_BUTTON_L3;
         if (gamepad.rightThumbstickButton.pressed) pad.buttons |= RPCS3_IOS_PAD_BUTTON_R3;
         if (gamepad.buttonMenu.pressed) pad.buttons |= RPCS3_IOS_PAD_BUTTON_START;
         if (gamepad.buttonOptions.pressed) pad.buttons |= RPCS3_IOS_PAD_BUTTON_SELECT;
         pad.left_stick_x = gamepad.leftThumbstick.xAxis.value; pad.left_stick_y = gamepad.leftThumbstick.yAxis.value;
         pad.right_stick_x = gamepad.rightThumbstick.xAxis.value; pad.right_stick_y = gamepad.rightThumbstick.yAxis.value;
         pad.left_trigger = gamepad.leftTrigger.value; pad.right_trigger = gamepad.rightTrigger.value;
      }
      if (index == 0 && (self.touchButtons & RPCS3_IOS_PAD_BUTTON_L2)) pad.left_trigger = fmaxf(pad.left_trigger, 1);
      if (index == 0 && (self.touchButtons & RPCS3_IOS_PAD_BUTTON_R2)) pad.right_trigger = fmaxf(pad.right_trigger, 1);
      ra_ps3_api.set_pad_state(index, &pad);
   }
   if (self.busy)
   {
      uint32_t done = 0, total = 0; char stage[512] = {0};
      if (!ra_ps3_api.get_boot_progress(&done, &total, stage, sizeof(stage)) && stage[0])
         self.status.text = RALabPS3String(stage);
   }
}
/* XITRIX 0.12 keeps RemoteIO suspended until these wrapper notifications.
 * Post only after initialize has installed its observer, and after AVAudioSession
 * activation succeeds. UIKit/session work stays on the main thread. */
- (NSError *)configureAudioSession
{
   AVAudioSession *session = AVAudioSession.sharedInstance;
   NSError *error = nil;
   if (![session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:&error] ||
         ![session setActive:YES error:&error])
      return error ?: [NSError errorWithDomain:@"LabPS3Audio" code:1 userInfo:
            @{NSLocalizedDescriptionKey: @"Audio session activation failed."}];
   return nil;
}
- (BOOL)activateAudio
{
   NSError *error = [self configureAudioSession];
   if (error)
   {
      self.status.text = [@"Unable to start PS3 audio: " stringByAppendingString:error.localizedDescription];
      return NO;
   }
   [NSNotificationCenter.defaultCenter postNotificationName:@"RPCS3AudioSessionDidActivate" object:nil];
   AVAudioSession *session = AVAudioSession.sharedInstance;
   NSLog(@"[Lab PS3] Audio activated: category=%@ route=%@ volume=%.2f sampleRate=%.0f",
         session.category, session.currentRoute.outputs, session.outputVolume, session.sampleRate);
   return YES;
}
- (void)suspendAudio
{
   if (ra_ps3_ready)
      [NSNotificationCenter.defaultCenter postNotificationName:@"RPCS3AudioSessionWillDeactivate" object:nil];
}
- (void)togglePause
{
   if (self.busy || self.pausePending || !self.playing || self.stopping || self.backgrounded || self.audioInterruption) return;
   if ([self.pauseButton.currentTitle isEqualToString:@"Resume"] && ![self activateAudio]) return;
   self.pausePending = YES; [self releaseInput]; [self updateControls];
   dispatch_async(ra_ps3_queue, ^{
      BOOL resume = ra_ps3_api.get_emulation_state() == RPCS3_IOS_EMULATION_STATE_PAUSED;
      int status = resume ? ra_ps3_api.resume_emulation() : ra_ps3_api.pause_emulation();
      NSString *error = status ? RALabPS3Error(status) : nil;
      dispatch_async(dispatch_get_main_queue(), ^{
         self.pausePending = NO;
         self.status.text = error ?: (resume ? @"Game running." : @"Paused.");
         if (!status) [self.pauseButton setTitle:resume ? @"Pause" : @"Resume" forState:UIControlStateNormal];
         [self updateControls];
         if (self.backgrounded && resume) [self pauseForBackground];
      });
   });
}
- (void)pauseForBackground
{
   if (!self.playing || self.stopping) return;
   [self releaseInput];
   if (self.booting) return;
   dispatch_async(ra_ps3_queue, ^{
      rpcs3_ios_emulation_state state = ra_ps3_api.get_emulation_state();
      int status = state == RPCS3_IOS_EMULATION_STATE_RUNNING ? ra_ps3_api.pause_emulation() : 0;
      BOOL paused = !status && (state == RPCS3_IOS_EMULATION_STATE_RUNNING || state == RPCS3_IOS_EMULATION_STATE_PAUSED);
      NSString *error = status ? RALabPS3Error(status) : nil;
      dispatch_async(dispatch_get_main_queue(), ^{
         if (paused) [self.pauseButton setTitle:@"Resume" forState:UIControlStateNormal];
         if (!self.stopping && (paused || error)) self.status.text = error ?: @"Paused. Tap Resume when ready.";
      });
   });
}
- (void)background { self.backgrounded = YES; [self suspendAudio]; [self pauseForBackground]; }
- (void)foreground { self.backgrounded = NO; }
- (void)audioInterrupted:(NSNotification *)notification
{
   self.audioInterruption = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue] == AVAudioSessionInterruptionTypeBegan;
   if (self.audioInterruption)
   { [self suspendAudio]; [self pauseForBackground]; }
   /* Ended does not auto-resume. The user's Resume action activates the session. */
}
- (void)stopGame
{
   if (!self.playing || self.stopping) return;
   ++self.bootGeneration;
   self.stopping = YES; self.busy = YES;
   self.status.text = @"Stopping PS3. Keep this app open…";
   [self releaseInput]; [self.displayLink invalidate]; self.displayLink = nil;
   [self updateControls];
   dispatch_async(ra_ps3_queue, ^{
      int status = ra_ps3_api.stop_emulation();
      if (!status) status = ra_ps3_api.set_display_surface(NULL);
      NSString *error = status ? RALabPS3Error(status) : nil;
      dispatch_async(dispatch_get_main_queue(), ^{
         self.busy = NO; self.stopping = NO;
         if (status)
         {
            self.busy = self.booting; self.status.text = error; [self updateControls];
            if (self.booting) [self pollBoot:self.bootGeneration];
            return;
         }
         self.playing = NO; self.booting = NO; [self.pauseButton setTitle:@"Pause" forState:UIControlStateNormal];
         [self updateControls]; [self reloadGames];
      });
   });
}
- (void)importMenu
{
   if (self.busy || self.playing || !ra_ps3_ready) return;
   UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Import into PS3 test library"
         message:@"The selected source is kept. Installed firmware, games and saves stay in this test app."
         preferredStyle:UIAlertControllerStyleActionSheet];
   for (NSString *kind in @[@"Firmware (.PUP)", @"Game (.ISO)", @"Package (.PKG)", @"License (.RAP)", @"Game folder"])
      [menu addAction:[UIAlertAction actionWithTitle:kind style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
         self.importKind = kind;
         UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
               initForOpeningContentTypes:@[[kind isEqualToString:@"Game folder"] ? UTTypeFolder : UTTypeData] asCopy:NO];
         picker.delegate = self; picker.allowsMultipleSelection = NO;
         [self presentViewController:picker animated:YES completion:nil];
      }]];
   [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
   menu.popoverPresentationController.sourceView = self.importButton;
   menu.popoverPresentationController.sourceRect = self.importButton.bounds;
   [self presentViewController:menu animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
   NSURL *url = urls.firstObject;
   if (!url || self.busy || self.playing) return;
   NSString *kind = self.importKind;
   BOOL scoped = [url startAccessingSecurityScopedResource];
   self.busy = YES; self.status.text = @"Importing into the separate PS3 library…"; [self updateControls];
   dispatch_async(ra_ps3_queue, ^{
      NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
      NSError *coordinationError = nil;
      __block int status = RPCS3_IOS_INVALID_ARGUMENT;
      __block NSString *failure = nil;
      [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
         const char *path = readURL.fileSystemRepresentation;
         void *context = (__bridge void *)self;
         if ([kind hasPrefix:@"Firmware"]) status = ra_ps3_api.install_firmware(path, RALabPS3Progress, context);
         else if ([kind hasPrefix:@"Game (.ISO)"]) status = ra_ps3_api.install_iso(path, NULL, RALabPS3Progress, context);
         else if ([kind hasPrefix:@"Package"]) status = ra_ps3_api.install_package(path, RALabPS3Progress, context);
         else if ([kind hasPrefix:@"License"]) status = ra_ps3_api.install_rap(path);
         else if ([kind isEqualToString:@"Game folder"]) status = ra_ps3_api.install_folder(path, RALabPS3Progress, context);
         if (status) failure = RALabPS3Error(status);
      }];
      if (scoped) [url stopAccessingSecurityScopedResource];
      dispatch_async(dispatch_get_main_queue(), ^{
         self.busy = NO; [self updateControls];
         if (coordinationError || status) self.status.text = coordinationError.localizedDescription ?: failure;
         else [self reloadGames];
      });
   });
}
@end

void RALabShowRPCS3(UIViewController *presenter)
{
   static dispatch_once_t once;
   dispatch_once(&once, ^{ ra_ps3_queue = dispatch_queue_create("retroarch.lab.ps3", DISPATCH_QUEUE_SERIAL); });
   [presenter.navigationController pushViewController:[[RALabPS3Controller alloc] init] animated:YES];
}
