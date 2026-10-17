/* SPDX-License-Identifier: GPL-3.0-or-later */
#import "ui/drivers/cocoa/RetroArchLabLibrarySupport.h"
#include <stdio.h>
#include <stdlib.h>

static unsigned checks;
#define CHECK(condition) do { checks++; if (!(condition)) { \
   fprintf(stderr, "Library check failed at line %d\n", __LINE__); exit(1); } } while (0)

int main(void)
{
   @autoreleasepool
   {
      NSArray *cores = @[@"/app/dolphin.libretro.framework/dolphin.libretro",
            @"/app/play.libretro.framework/play.libretro",
            @"/app/mednafen.saturn.libretro.framework/mednafen.saturn.libretro",
            @"/app/fceumm.libretro.framework/fceumm.libretro",
            @"/app/snes9x2010.libretro.framework/snes9x2010.libretro",
            @"/app/opera.libretro.framework/opera.libretro"];
      CHECK([RALabCoreIdentifier(@"/old/dolphin_libretro_ios.dylib") isEqualToString:@"dolphin"]);
      CHECK([RALabCoreIdentifier(@"/old/mednafen_saturn_libretro.so") isEqualToString:@"mednafen_saturn"]);
      CHECK([RALabCoreIdentifier(cores[2]) isEqualToString:@"mednafen_saturn"]);
      CHECK([RALabCoreIdentifier(@"/app/mednafen.saturn.libretro.framework")
            isEqualToString:@"mednafen_saturn"]);
      CHECK(RALabCoreIdentifier(nil) == nil);
      CHECK(RALabResolveCore(@"DETECT", cores) == nil);
      CHECK(RALabResolveCore(nil, cores) == nil);
      CHECK([RALabResolveCore(@"/old/dolphin_libretro_ios.dylib", cores) isEqualToString:cores[0]]);
      CHECK([RALabResolveCore(cores[1], cores) isEqualToString:cores[1]]);
      CHECK([RALabResolveCore(@"/old/mednafen_saturn_libretro_ios.dylib", cores)
            isEqualToString:cores[2]]);
      CHECK([RALabResolveCore(@"/old/mednafen_saturn_libretro.so", cores)
            isEqualToString:cores[2]]);
      CHECK(RALabResolveCore(@"/old/mednafen_psx_libretro.so", cores) == nil);
      CHECK(RALabResolveCore(@"/old/yabause_libretro.so", cores) == nil);
      CHECK(RALabResolveCore(@"/old/pcsx2_libretro.so", cores) == nil);
      NSArray *ambiguous = @[cores[2], @"/other/mednafen_saturn_libretro_ios.dylib"];
      CHECK(RALabResolveCore(@"/old/mednafen_saturn_libretro_ios.dylib", ambiguous) == nil);
      CHECK(RALabResolveCore(@"/old/mednafen.saturn.libretro", ambiguous) == nil);
      CHECK([RALabResolveCore(cores[2], ambiguous) isEqualToString:cores[2]]);
      CHECK(RALabResolveCore(@"/old/mednafen_saturn_libretro_ios.dylib", @[]) == nil);
      CHECK(RALabResolveCore(@"/old/mednafen_saturn_libretro_ios.dylib",
            @[cores[0], cores[1]]) == nil);
      NSArray *withPS2 = [cores arrayByAddingObject:
            @"/app/armsx2.libretro.framework/armsx2.libretro"];
      CHECK([RALabResolveCore(@"/old/armsx2_libretro_ios.dylib", withPS2)
            isEqualToString:withPS2.lastObject]);
      CHECK([RALabResolveCore(@"/old/play_libretro_ios.dylib", withPS2)
            isEqualToString:cores[1]]);
      CHECK(RALabResolveCore(@"/old/armsx2_libretro_ios.dylib", cores) == nil);
      CHECK(RALabResolveCore(@"game.iso", withPS2) == nil);
      NSArray *withSaturn = [withPS2 arrayByAddingObject:
            @"/app/yabause.libretro.framework/yabause.libretro"];
      CHECK([RALabResolveCore(@"/old/yabause_libretro_ios.dylib", withSaturn)
            isEqualToString:withSaturn.lastObject]);
      CHECK([RALabResolveCore(@"/old/mednafen_saturn_libretro.so", withSaturn)
            isEqualToString:cores[2]]);
      CHECK(RALabResolveCore(@"/old/yabasanshiro_libretro_ios.dylib", withSaturn) == nil);
      CHECK(![RALabEntryKey(@"/Games/Saturn.chd", cores[2])
            isEqual:RALabEntryKey(@"/Games/Saturn.chd", withSaturn.lastObject)]);
      CHECK(RALabResolveCore(@"game.iso", cores) == nil);
      CHECK(RALabResolveCore(@"game.chd", cores) == nil);
      CHECK(RALabResolveCore(@"/old/dolphin_libretro.so",
            @[@"/one/dolphin.libretro", @"/two/dolphin.libretro"]) == nil);
      CHECK(![RALabEntryKey(@"/GameCube/Burnout.iso", cores[0])
            isEqual:RALabEntryKey(@"/PS2/Burnout.iso", cores[1])]);
      CHECK(![RALabEntryKey(@"/Games/disc.iso", cores[0])
            isEqual:RALabEntryKey(@"/Games/disc.iso", cores[1])]);
      CHECK([RALabEntryKey(@"/Games/./disc.iso", @"/old/dolphin_libretro_ios.dylib")
            isEqual:RALabEntryKey(@"/Games/disc.iso", cores[0])]);
      CHECK([RALabEntryKey(@"/Games/Saturn.chd", @"/old/mednafen_saturn_libretro_ios.dylib")
            isEqual:RALabEntryKey(@"/Games/Saturn.chd", cores[2])]);
      CHECK(RALabMatches(@"Pokemon", @"Nintendo", @"  poke  ", nil));
      CHECK(RALabMatches(@"Pokémon", @"Nintendo", @"pokemon", nil));
      CHECK(RALabMatches(@"Burnout 2", @"GameCube", @"GAMECUBE", @"GameCube"));
      CHECK(!RALabMatches(@"Burnout 2", @"GameCube", @"Burnout", @"PS2"));
      CHECK(!RALabMatches(nil, nil, @"missing", nil));
      CHECK(RALabMatches(@"Burnout", nil, @"", nil));
      CHECK([RALabArtworkFilename(@"A/B: C & D?") isEqualToString:@"A_B_ C _ D_.png"]);
      CHECK([RALabArtworkFilename(@"../escape") rangeOfString:@"/"].location == NSNotFound);
      NSString *thumbnailRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
            NSUUID.UUID.UUIDString];
      NSFileManager *files = NSFileManager.defaultManager;
      NSArray *entries = @[
         @{@"source": @"history", @"db_name": @"Sega - Saturn.lpl",
            @"label": @"NiGHTS into Dreams...", @"folder": @"Sega - Saturn"},
         @{@"source": @"favorites", @"db_name": @"Sony - PlayStation 2.lpl",
            @"label": @"Burnout 2", @"folder": @"Sony - PlayStation 2"}
      ];
      NSData *image = [[NSData alloc] initWithBase64EncodedString:
            @"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXioAAAAASUVORK5CYII="
            options:0];
      for (NSDictionary *entry in entries)
      {
         NSString *expected = [[[thumbnailRoot stringByAppendingPathComponent:entry[@"folder"]]
               stringByAppendingPathComponent:@"Named_Boxarts"]
               stringByAppendingPathComponent:RALabArtworkFilename(entry[@"label"])];
         CHECK([files createDirectoryAtPath:expected.stringByDeletingLastPathComponent
               withIntermediateDirectories:YES attributes:nil error:NULL]);
         CHECK([image writeToFile:expected atomically:YES]);
         NSString *path = RALabArtworkPath(thumbnailRoot, entry[@"db_name"],
               @"Other / recent", entry[@"label"]);
         CHECK([path isEqualToString:expected]);
         CHECK([[NSData dataWithContentsOfFile:path] isEqualToData:image]);
         CHECK([RALabArtworkPath(thumbnailRoot, entry[@"db_name"], nil, entry[@"label"])
               isEqualToString:expected]);
         CHECK([RALabArtworkPath(thumbnailRoot, entry[@"db_name"], @"Custom collection",
               entry[@"label"]) isEqualToString:expected]);
      }
      CHECK([RALabArtworkPath(thumbnailRoot, @"Sega - Saturn", nil, @"Game")
            isEqualToString:[thumbnailRoot stringByAppendingPathComponent:
               @"Sega - Saturn/Named_Boxarts/Game.png"]]);
      CHECK([RALabArtworkPath(thumbnailRoot, nil, @"Nintendo - GameCube", @"A/B: C & D?")
            isEqualToString:[thumbnailRoot stringByAppendingPathComponent:
               @"Nintendo - GameCube/Named_Boxarts/A_B_ C _ D_.png"]]);
      CHECK([RALabArtworkPath(thumbnailRoot, @"", @"Sega - Saturn", @"Game")
            isEqualToString:RALabArtworkPath(thumbnailRoot, @"Sega - Saturn.lpl", nil, @"Game")]);
      CHECK([RALabArtworkPath(thumbnailRoot, @"MAME 2003-Plus.lpl", nil, @"Game")
            isEqualToString:RALabArtworkPath(thumbnailRoot, @"MAME", nil, @"Game")]);
      CHECK([RALabArtworkPath(thumbnailRoot, @"Sega - Saturn.lpl|Other.lpl", nil, @"Game")
            isEqualToString:RALabArtworkPath(thumbnailRoot, @"Sega - Saturn.lpl", nil, @"Game")]);
      CHECK(![files fileExistsAtPath:RALabArtworkPath(thumbnailRoot,
            @"Sega - Saturn.lpl", nil, @"Missing art")]);
      CHECK(RALabArtworkPath(thumbnailRoot, nil, nil, @"Game") == nil);
      CHECK(RALabArtworkPath(thumbnailRoot, @"..", nil, @"Game") == nil);
      CHECK(RALabArtworkPath(thumbnailRoot, @"Sega - Saturn.lpl", nil, @"") == nil);
      CHECK(RALabArtworkPath(nil, @"Sega - Saturn.lpl", nil, @"Game") == nil);
      CHECK([files removeItemAtPath:thumbnailRoot error:NULL]);
      printf("%u native library checks passed\n", checks);
   }
   return 0;
}
