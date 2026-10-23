/* RetroArch Lab native library. SPDX-License-Identifier: GPL-3.0-or-later */
#import <UIKit/UIKit.h>
#include <math.h>
#import "apple_platform.h"
#import "RetroArchLabLibrary.h"
#ifdef HAVE_RETROARCH_LAB_STIKJIT
#import "RetroArchLabJIT.h"
#endif
#import "RetroArchLabLibrarySupport.h"
#import "RetroArchPlaylistManager.h"
#import "cocoa_common.h"
#include "../../../configuration.h"
#include "../../../core_info.h"
#include "../../../runloop.h"
#include "../../../tasks/task_content.h"
#include "../../../menu/menu_driver.h"
#include "../../../menu/menu_defines.h"
#include "../../../pkg/apple/JITSupport.h"
#include <file/file_path.h>
#include <queues/task_queue.h>

#if !__has_feature(objc_arc)
#error The Lab library must be compiled with ARC.
#endif

static BOOL ra_lab_library_visible;
bool cocoa_lab_library_visible(void) { return ra_lab_library_visible; }

@interface RALabGameCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *art;
@property(nonatomic, strong) UILabel *nameLabel;
@property(nonatomic, strong) UILabel *systemLabel;
@property(nonatomic, copy) NSString *artPath;
@end

@implementation RALabGameCell
- (instancetype)initWithFrame:(CGRect)frame
{
   if ((self = [super initWithFrame:frame]))
   {
      self.contentView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
      self.contentView.layer.cornerRadius = 14;
      self.contentView.clipsToBounds = YES;
      self.art = [[UIImageView alloc] init];
      self.art.contentMode = UIViewContentModeScaleAspectFit;
      self.art.tintColor = UIColor.tertiaryLabelColor;
      self.art.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
      self.nameLabel = [[UILabel alloc] init];
      self.nameLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
      self.nameLabel.adjustsFontForContentSizeCategory = YES;
      self.nameLabel.numberOfLines = 2;
      self.systemLabel = [[UILabel alloc] init];
      self.systemLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
      self.systemLabel.adjustsFontForContentSizeCategory = YES;
      self.systemLabel.textColor = UIColor.secondaryLabelColor;
      self.systemLabel.numberOfLines = 2;
      for (UIView *v in @[self.art, self.nameLabel, self.systemLabel])
      {
         v.translatesAutoresizingMaskIntoConstraints = NO;
         [self.contentView addSubview:v];
      }
      [NSLayoutConstraint activateConstraints:@[
         [self.art.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
         [self.art.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
         [self.art.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
         [self.art.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor multiplier:0.60],
         [self.nameLabel.topAnchor constraintEqualToAnchor:self.art.bottomAnchor constant:10],
         [self.nameLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
         [self.nameLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
         [self.systemLabel.topAnchor constraintEqualToAnchor:self.nameLabel.bottomAnchor constant:5],
         [self.systemLabel.leadingAnchor constraintEqualToAnchor:self.nameLabel.leadingAnchor],
         [self.systemLabel.trailingAnchor constraintEqualToAnchor:self.nameLabel.trailingAnchor],
         [self.systemLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-10]
      ]];
      self.isAccessibilityElement = YES;
      self.accessibilityTraits = UIAccessibilityTraitButton;
   }
   return self;
}
- (void)prepareForReuse
{
   [super prepareForReuse];
   self.artPath = nil;
   self.art.image = nil;
}
- (void)setHighlighted:(BOOL)highlighted
{
   [super setHighlighted:highlighted];
   self.contentView.alpha = highlighted ? 0.65 : 1.0;
}
@end

@interface RALabLibraryController : UIViewController <UICollectionViewDataSource,
      UICollectionViewDelegateFlowLayout, UISearchBarDelegate>
@property(nonatomic, strong) UICollectionView *grid;
@property(nonatomic, strong) UISearchBar *search;
@property(nonatomic, strong) UISegmentedControl *section;
@property(nonatomic, strong) UIButton *systemButton;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UILabel *emptyLabel;
@property(nonatomic, copy) NSArray<RetroArchPlaylistGame *> *library;
@property(nonatomic, copy) NSArray<RetroArchPlaylistGame *> *recent;
@property(nonatomic, copy) NSArray<RetroArchPlaylistGame *> *favorites;
@property(nonatomic, copy) NSArray<RetroArchPlaylistGame *> *filtered;
@property(nonatomic, copy) NSString *selectedSystem;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *images;
@property(nonatomic, strong) NSOperationQueue *artQueue;
@property(nonatomic, assign) BOOL leaving;
@end

@implementation RALabLibraryController
- (void)viewDidLoad
{
   [super viewDidLoad];
   self.title = @"RetroArch Lab";
   self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
   self.images = [[NSCache alloc] init];
   self.images.totalCostLimit = 32 * 1024 * 1024;
   self.artQueue = [[NSOperationQueue alloc] init];
   self.artQueue.maxConcurrentOperationCount = 2;
   self.artQueue.qualityOfService = NSQualityOfServiceUtility;
   self.library = self.recent = self.favorites = self.filtered = @[];
   UIBarButtonItem *advanced = [[UIBarButtonItem alloc] initWithTitle:@"Advanced"
         style:UIBarButtonItemStylePlain target:self action:@selector(openAdvanced)];
   UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:
         UIBarButtonSystemItemRefresh target:self action:@selector(reloadLibrary)];
   refresh.accessibilityLabel = @"Refresh game library";
   self.navigationItem.rightBarButtonItems = @[advanced, refresh];
#ifdef HAVE_RETROARCH_LAB_STIKJIT
   UIBarButtonItem *jit = [[UIBarButtonItem alloc] initWithTitle:@"JIT Setup"
         style:UIBarButtonItemStylePlain target:self action:@selector(openJITSetup)];
   self.navigationItem.rightBarButtonItems = @[advanced, jit, refresh];
#endif
   if (!retroarch_ctl(RARCH_CTL_IS_DUMMY_CORE, NULL))
      self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Resume"
            style:UIBarButtonItemStylePlain target:self action:@selector(resumeGame)];
   self.search = [[UISearchBar alloc] init];
   self.search.placeholder = @"Search games or systems";
   self.search.delegate = self;
   self.search.searchBarStyle = UISearchBarStyleMinimal;
   self.section = [[UISegmentedControl alloc] initWithItems:@[@"All games", @"Recent", @"Favorites"]];
   self.section.selectedSegmentIndex = 0;
   [self.section addTarget:self action:@selector(filterLibrary) forControlEvents:UIControlEventValueChanged];
   self.systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
   [self.systemButton setTitle:@"All systems" forState:UIControlStateNormal];
   self.systemButton.showsMenuAsPrimaryAction = YES;
   self.systemButton.accessibilityLabel = @"Filter by system";
   self.statusLabel = [[UILabel alloc] init];
   self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
   self.statusLabel.textColor = UIColor.secondaryLabelColor;
   self.statusLabel.text = @"Reading your existing playlists...";
   self.statusLabel.numberOfLines = 0;
   UIStackView *filters = [[UIStackView alloc] initWithArrangedSubviews:
         @[self.search, self.section, self.systemButton, self.statusLabel]];
   filters.axis = UILayoutConstraintAxisVertical;
   filters.spacing = 10;
   UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
   layout.minimumInteritemSpacing = 12;
   layout.minimumLineSpacing = 16;
   layout.sectionInset = UIEdgeInsetsMake(12, 0, 24, 0);
   self.grid = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
   self.grid.backgroundColor = UIColor.clearColor;
   self.grid.dataSource = self;
   self.grid.delegate = self;
   self.grid.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
   [self.grid registerClass:RALabGameCell.class forCellWithReuseIdentifier:@"game"];
   self.emptyLabel = [[UILabel alloc] init];
   self.emptyLabel.numberOfLines = 0;
   self.emptyLabel.textAlignment = NSTextAlignmentCenter;
   self.emptyLabel.textColor = UIColor.secondaryLabelColor;
   self.emptyLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
   self.grid.backgroundView = self.emptyLabel;
   for (UIView *v in @[filters, self.grid])
   {
      v.translatesAutoresizingMaskIntoConstraints = NO;
      [self.view addSubview:v];
   }
   UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
   [NSLayoutConstraint activateConstraints:@[
      [filters.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
      [filters.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
      [filters.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-16],
      [self.grid.topAnchor constraintEqualToAnchor:filters.bottomAnchor constant:8],
      [self.grid.leadingAnchor constraintEqualToAnchor:filters.leadingAnchor],
      [self.grid.trailingAnchor constraintEqualToAnchor:filters.trailingAnchor],
      [self.grid.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor]
   ]];
}
- (void)viewDidAppear:(BOOL)animated
{
   [super viewDidAppear:animated];
   command_event(CMD_EVENT_AUDIO_STOP, NULL);
   dispatch_async(dispatch_get_main_queue(), ^{ [self reloadLibrary]; });
}
- (void)viewDidDisappear:(BOOL)animated
{
   [super viewDidDisappear:animated];
   /* Alerts do not dismiss the full-screen navigation controller. */
   if (!self.navigationController.presentingViewController)
   {
      ra_lab_library_visible = NO;
      [self.artQueue cancelAllOperations];
      if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
         command_event(CMD_EVENT_AUDIO_START, NULL);
   }
}
- (void)viewWillTransitionToSize:(CGSize)size
      withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
   [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
   [self.grid.collectionViewLayout invalidateLayout];
}
- (void)reloadLibrary
{
   NSArray *playlists = [RetroArchPlaylistManager getAllGames];
   self.recent = [RetroArchPlaylistManager getHistoryGames];
   self.favorites = [RetroArchPlaylistManager getAllFavoriteGames];
   NSMutableArray *all = [NSMutableArray array];
   NSMutableSet *seen = [NSMutableSet set];
   NSMutableDictionary *systems = [NSMutableDictionary dictionary];
   for (RetroArchPlaylistGame *game in playlists)
      if (game.system.length)
         systems[RALabEntryKey(game.fullPath, game.corePath)] = game.system;
   for (NSArray *source in @[playlists, self.recent, self.favorites])
      for (RetroArchPlaylistGame *game in source)
      {
         NSArray *key = RALabEntryKey(game.fullPath, game.corePath);
         if (!game.system.length)
            game.system = systems[key] ?: @"Other / recent";
         if (![seen containsObject:key])
         {
            [all addObject:game];
            [seen addObject:key];
         }
      }
   self.library = [all sortedArrayUsingComparator:^NSComparisonResult(
         RetroArchPlaylistGame *a, RetroArchPlaylistGame *b) {
      return [a.title localizedStandardCompare:b.title];
   }];
   NSMutableSet *names = [NSMutableSet set];
   for (RetroArchPlaylistGame *game in self.library)
      if (game.system.length) [names addObject:game.system];
   if (self.selectedSystem && ![names containsObject:self.selectedSystem])
      self.selectedSystem = nil;
   NSMutableArray *actions = [NSMutableArray array];
   __weak RALabLibraryController *weakSelf = self;
   [actions addObject:[UIAction actionWithTitle:@"All systems" image:nil identifier:nil
         handler:^(UIAction *action) { weakSelf.selectedSystem = nil; [weakSelf filterLibrary]; }]];
   for (NSString *name in [[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)])
      [actions addObject:[UIAction actionWithTitle:name image:nil identifier:nil
            handler:^(UIAction *action) { weakSelf.selectedSystem = name; [weakSelf filterLibrary]; }]];
   self.systemButton.menu = [UIMenu menuWithTitle:@"Choose a system" children:actions];
   [self filterLibrary];
}
- (void)filterLibrary
{
   NSArray *source = self.section.selectedSegmentIndex == 1 ? self.recent :
         (self.section.selectedSegmentIndex == 2 ? self.favorites : self.library);
   NSMutableArray *result = [NSMutableArray array];
   for (RetroArchPlaylistGame *game in source)
      if (RALabMatches(game.title ?: game.filename, game.system ?: @"",
            self.search.text ?: @"", self.selectedSystem))
         [result addObject:game];
   self.filtered = result;
   [self.systemButton setTitle:self.selectedSystem ?: @"All systems" forState:UIControlStateNormal];
   self.statusLabel.text = [NSString stringWithFormat:@"%lu games%@",
         (unsigned long)result.count, self.section.selectedSegmentIndex == 1 ? @" (latest 10)" : @""];
   self.emptyLabel.text = self.library.count ? @"No games match this view.\nTry another filter or search." :
         @"Your library starts here.\n\nUse Advanced > Import Content to scan your games.\nRecently played games also appear here.\n\nNo game files are moved or renamed.";
   self.emptyLabel.hidden = result.count != 0;
   [self.artQueue cancelAllOperations];
   [self.grid reloadData];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText
{ [self filterLibrary]; }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{ return self.filtered.count; }
- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout
      sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
   CGFloat width = collectionView.bounds.size.width;
   BOOL largeText = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
   NSInteger columns = MAX(1, (NSInteger)floor((width + 12) / (largeText ? 310 : 170)));
   CGFloat itemWidth = floor((width - 12 * (columns - 1)) / columns);
   return CGSizeMake(itemWidth, MAX(largeText ? 420 : 260, itemWidth * 1.35));
}
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
   RALabGameCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"game" forIndexPath:indexPath];
   RetroArchPlaylistGame *game = self.filtered[indexPath.item];
   cell.nameLabel.text = game.title.length ? game.title : game.filename;
   cell.systemLabel.text = game.system;
   cell.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", cell.nameLabel.text, game.system ?: @""];
   cell.accessibilityHint = @"Launch using this game's assigned core";
   cell.art.image = [UIImage systemImageNamed:@"gamecontroller"];
   cell.artPath = nil;
   settings_t *settings = config_get_ptr();
   if (settings && game.title.length)
   {
      char directory[PATH_MAX_LENGTH];
      fill_pathname_expand_special(directory, settings->paths.directory_thumbnails, sizeof(directory));
      NSString *path = RALabArtworkPath([NSString stringWithUTF8String:directory],
            game.databaseName, game.system, game.title);
      if (!path) return cell;
      cell.artPath = path;
      UIImage *cached = [self.images objectForKey:path];
      if (cached) cell.art.image = cached;
      else
      {
         __weak RALabGameCell *weakCell = cell;
         NSCache *cache = self.images;
         [self.artQueue addOperationWithBlock:^{
            UIImage *image = [UIImage imageWithContentsOfFile:path];
            if (!image) return;
            [cache setObject:image forKey:path cost:(NSUInteger)(image.size.width * image.size.height * image.scale * image.scale * 4)];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
               RALabGameCell *target = weakCell;
               if ([target.artPath isEqualToString:path]) target.art.image = image;
            }];
         }];
      }
   }
   return cell;
}
- (void)showProblem:(NSString *)message
{
   UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Before you play"
         message:message preferredStyle:UIAlertControllerStyleAlert];
   [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
   [self presentViewController:alert animated:YES completion:nil];
}
- (void)dismissLibrary:(void (^)(void))completion
{
   UIViewController *presenter = self.navigationController.presentingViewController;
   if (!presenter || self.leaving) return;
   self.leaving = YES;
   [self.view endEditing:YES];
   [presenter dismissViewControllerAnimated:YES completion:^{
      ra_lab_library_visible = NO;
      if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive)
         command_event(CMD_EVENT_AUDIO_START, NULL);
      if (completion) completion();
   }];
}
- (void)openAdvanced
{
   [self dismissLibrary:^{
      if (!(menu_state_get_ptr()->flags & MENU_ST_FLAG_ALIVE))
         command_event(CMD_EVENT_MENU_TOGGLE, NULL);
   }];
}
- (void)resumeGame
{
   [self dismissLibrary:^{
      if (menu_state_get_ptr()->flags & MENU_ST_FLAG_ALIVE)
         command_event(CMD_EVENT_MENU_TOGGLE, NULL);
   }];
}
#ifdef HAVE_RETROARCH_LAB_STIKJIT
- (void)openJITSetup { [[RALabJIT shared] showSettingsFrom:self]; }
#endif
- (void)launchPath:(NSString *)path core:(NSString *)core
{
#ifdef HAVE_RETROARCH_LAB_STIKJIT
   NSString *identifier = RALabCoreIdentifier(core);
   if ([@[@"armsx2", @"dolphin", @"play"] containsObject:identifier])
   {
      [[RALabJIT shared] enableFrom:self completion:^(BOOL ready) {
         if (ready && self.view.window && !self.leaving) [self queuePath:path core:core];
      }];
      return;
   }
#endif
   [self queuePath:path core:core];
}
- (void)queuePath:(NSString *)path core:(NSString *)core
{
   [self dismissLibrary:^{
      content_ctx_info_t info = {0};
      bool queued = task_push_load_content_with_new_core_from_companion_ui(
            core.UTF8String, path.UTF8String, NULL, NULL, NULL, &info, NULL, NULL);
      if (!queued)
      {
         UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Game could not be queued"
               message:@"Open the library again or use Advanced to inspect this game's configuration."
               preferredStyle:UIAlertControllerStyleAlert];
         [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
         [[CocoaView get] presentViewController:alert animated:YES completion:nil];
      }
   }];
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
   RetroArchPlaylistGame *game = self.filtered[indexPath.item];
   if (!game.fullPath.length || [game.fullPath lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= PATH_MAX_LENGTH)
   { [self showProblem:@"This playlist entry has no usable game path. Check it in Advanced."]; return; }
   char expanded[PATH_MAX_LENGTH];
   fill_pathname_expand_special(expanded, game.fullPath.UTF8String, sizeof(expanded));
   NSString *path = [NSString stringWithUTF8String:expanded];
   NSFileManager *files = NSFileManager.defaultManager;
   NSString *container = [path componentsSeparatedByString:@"#"].firstObject;
   if (![files isReadableFileAtPath:path] && ![files isReadableFileAtPath:container])
   { [self showProblem:@"The game file is missing or unavailable. Check its location in Advanced; files are not moved automatically."]; return; }
   NSMutableArray *installed = [NSMutableArray array];
   core_info_list_t *cores = NULL;
   core_info_get_list(&cores);
   if (cores)
      for (size_t i = 0; i < cores->count; i++)
         if (cores->list[i].path)
         {
            NSString *corePath = [NSString stringWithUTF8String:cores->list[i].path];
            if ([files isReadableFileAtPath:corePath]) [installed addObject:corePath];
         }
   NSString *assigned = game.corePath;
   if (assigned.length && [assigned lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < PATH_MAX_LENGTH)
   {
      fill_pathname_expand_special(expanded, assigned.UTF8String, sizeof(expanded));
      assigned = [NSString stringWithUTF8String:expanded];
   }
   NSString *core = RALabResolveCore(assigned, installed);
   if (!core)
   { [self showProblem:@"Assign an installed core to this game or playlist in Advanced. The library will not guess a console from .iso or .chd."]; return; }
   NSString *identifier = RALabCoreIdentifier(core);
#ifndef HAVE_RETROARCH_LAB_STIKJIT
   /* ARMSX2 checks and allocates its required arena in retro_load_game. */
   if (([identifier isEqualToString:@"dolphin"] || [identifier isEqualToString:@"play"]) && !jit_available())
   {
      NSBundle *bundle = NSBundle.mainBundle;
      NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: @"this app";
      [self showProblem:[NSString stringWithFormat:@"This core needs JIT. Enable JIT for %@ (%@) with StikDebug, then try again.",
            name, bundle.bundleIdentifier ?: @"unknown app ID"]];
      return;
   }
#endif
   if (!retroarch_ctl(RARCH_CTL_IS_DUMMY_CORE, NULL))
   {
      UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Switch games?"
            message:@"This closes the current game. Save your progress in the game before switching."
            preferredStyle:UIAlertControllerStyleAlert];
      [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
      [alert addAction:[UIAlertAction actionWithTitle:@"Launch" style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *action) { [self launchPath:path core:core]; }]];
      [self presentViewController:alert animated:YES completion:nil];
   }
   else [self launchPath:path core:core];
}
@end

void cocoa_lab_show_library(void)
{
   dispatch_async(dispatch_get_main_queue(), ^{
      CocoaView *root = [CocoaView get];
      if (!runloop_is_inited() || ra_lab_library_visible || root.presentedViewController || !root.view.window)
         return;
      RALabLibraryController *library = [[RALabLibraryController alloc] init];
      UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:library];
      navigation.modalPresentationStyle = UIModalPresentationFullScreen;
      ra_lab_library_visible = YES;
      rarch_stop_draw_observer();
      [root presentViewController:navigation animated:YES completion:nil];
   });
}
