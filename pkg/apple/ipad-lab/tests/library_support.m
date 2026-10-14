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
            @"/app/mednafen_saturn.libretro.framework/mednafen_saturn.libretro"];
      CHECK([RALabCoreIdentifier(@"/old/dolphin_libretro_ios.dylib") isEqualToString:@"dolphin"]);
      CHECK([RALabCoreIdentifier(@"/old/mednafen_saturn_libretro.so") isEqualToString:@"mednafen_saturn"]);
      CHECK(RALabCoreIdentifier(nil) == nil);
      CHECK(RALabResolveCore(@"DETECT", cores) == nil);
      CHECK(RALabResolveCore(nil, cores) == nil);
      CHECK([RALabResolveCore(@"/old/dolphin_libretro_ios.dylib", cores) isEqualToString:cores[0]]);
      CHECK([RALabResolveCore(cores[1], cores) isEqualToString:cores[1]]);
      CHECK(RALabResolveCore(@"/old/pcsx2_libretro.so", cores) == nil);
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
      CHECK(RALabMatches(@"Pokemon", @"Nintendo", @"  poke  ", nil));
      CHECK(RALabMatches(@"Pokémon", @"Nintendo", @"pokemon", nil));
      CHECK(RALabMatches(@"Burnout 2", @"GameCube", @"GAMECUBE", @"GameCube"));
      CHECK(!RALabMatches(@"Burnout 2", @"GameCube", @"Burnout", @"PS2"));
      CHECK(!RALabMatches(nil, nil, @"missing", nil));
      CHECK(RALabMatches(@"Burnout", nil, @"", nil));
      CHECK([RALabArtworkFilename(@"A/B: C & D?") isEqualToString:@"A_B_ C _ D_.png"]);
      CHECK([RALabArtworkFilename(@"../escape") rangeOfString:@"/"].location == NSNotFound);
      printf("%u native library checks passed\n", checks);
   }
   return 0;
}
