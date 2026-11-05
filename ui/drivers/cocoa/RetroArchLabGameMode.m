/* SPDX-License-Identifier: GPL-3.0-or-later */
#import "RetroArchLabGameMode.h"
#import "RetroArchLabPerformance.h"

static NSString *const RALabQuietGameplayKey = @"RALabQuietGameplay";
static int ra_lab_quiet_gameplay;

static BOOL RALabGameModeReadPreference(void)
{
   id value = [NSUserDefaults.standardUserDefaults objectForKey:RALabQuietGameplayKey];
   return value ? [value boolValue] : YES;
}

bool ra_lab_game_mode_quiet_enabled(void)
{
   static dispatch_once_t once;
   dispatch_once(&once, ^{
      __atomic_store_n(&ra_lab_quiet_gameplay, RALabGameModeReadPreference(), __ATOMIC_RELAXED);
   });
   return __atomic_load_n(&ra_lab_quiet_gameplay, __ATOMIC_RELAXED) != 0;
}

@interface RALabGameModeController : UITableViewController
@end

@implementation RALabGameModeController
- (void)viewDidLoad
{
   [super viewDidLoad];
   self.title = @"Game Mode";
   self.tableView.rowHeight = UITableViewAutomaticDimension;
   self.tableView.estimatedRowHeight = 80;
   self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
         initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}
- (void)done { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{ return section == 2 ? 3 : 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{ return @[@"Quiet gameplay", @"Apple Game Mode", @"Silence system notifications"][section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section
{
   if (section == 0)
      return @"Hides routine RetroArch popups while a game is running. Warnings, errors, higher-priority messages and accessibility announcements stay available. Menus and the performance recorder are unchanged.";
   if (section == 1)
      return @"iOS/iPadOS controls system resource priority. This app supports Game Mode, but cannot force it on or confirm its current state. Keep the game full screen.";
   return @"Gaming Focus handles banners from other apps. RetroArch cannot turn it on for you or stop other apps from receiving notifications. Allowed people, time-sensitive notifications and emergency exceptions can still interrupt. PS3 also uses Apple Game Mode and Gaming Focus.";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path
{
   UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
   cell.selectionStyle = UITableViewCellSelectionStyleNone;
   cell.textLabel.numberOfLines = 0;
   cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
   cell.textLabel.adjustsFontForContentSizeCategory = YES;
   if (path.section == 0)
   {
      cell.textLabel.text = @"Hide routine popups";
      UISwitch *toggle = [[UISwitch alloc] init];
      toggle.accessibilityLabel = @"Hide routine gameplay popups";
      toggle.accessibilityIdentifier = @"Lab quiet gameplay";
      toggle.on = ra_lab_game_mode_quiet_enabled();
      [toggle addTarget:self action:@selector(quietChanged:) forControlEvents:UIControlEventValueChanged];
      cell.accessoryView = toggle;
   }
   else if (path.section == 1)
      cell.textLabel.text = @"While playing, open Control Center, tap this app's Game Overlay, then Controls > Game Mode. On older systems, tap the app name or Game Mode control.";
   else
   {
      NSString *name = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"RetroArch Lab";
      cell.textLabel.text = @[
         @"1. Open Settings > Focus. Add Gaming, or select your existing Gaming Focus. Choose which people and apps may interrupt you.",
         [NSString stringWithFormat:@"2. Under Set a Schedule, tap Add Schedule > App and select %@. Gaming Focus can then turn on automatically while you use this app.", name],
         @"3. Before playing, check Control Center > Focus > Gaming. For fewer interruptions, review Time Sensitive Notifications, repeated calls and Intelligent Breakthrough & Silencing in your Focus settings."
      ][path.row];
   }
   return cell;
}
- (void)quietChanged:(UISwitch *)sender
{
   (void)ra_lab_game_mode_quiet_enabled();
   [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:RALabQuietGameplayKey];
   __atomic_store_n(&ra_lab_quiet_gameplay, sender.on, __ATOMIC_RELAXED);
   RALabPerfEvent(sender.on ? @"Quiet gameplay enabled" : @"Quiet gameplay disabled");
}
@end

void RALabGameModeShow(UIViewController *parent)
{
   RALabGameModeController *page = [[RALabGameModeController alloc] initWithStyle:UITableViewStyleInsetGrouped];
   UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:page];
   navigation.modalPresentationStyle = UIModalPresentationFormSheet;
   [parent presentViewController:navigation animated:YES completion:nil];
}
