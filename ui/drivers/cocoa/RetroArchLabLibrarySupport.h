/* RetroArch Lab library helpers. SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RETROARCH_LAB_LIBRARY_SUPPORT_H
#define RETROARCH_LAB_LIBRARY_SUPPORT_H

#import <Foundation/Foundation.h>

static inline NSString *RALabCoreIdentifier(NSString *path)
{
   if (!path.length || [path isEqualToString:@"DETECT"])
      return nil;
   NSString *name = path.lastPathComponent;
   for (NSString *suffix in @[@"_libretro_ios.dylib", @"_libretro.dylib",
         @"_libretro.so", @".libretro.framework", @".libretro"])
      if ([name hasSuffix:suffix])
         return [name substringToIndex:name.length - suffix.length];
   return name;
}

/* Resolve an explicitly assigned core, never a content-file extension. */
static inline NSString *RALabResolveCore(NSString *assigned, NSArray<NSString *> *installed)
{
   NSString *identifier = RALabCoreIdentifier(assigned);
   if (!identifier.length)
      return nil;
   if ([installed containsObject:assigned])
      return assigned;
   NSString *match = nil;
   for (NSString *path in installed)
      if ([RALabCoreIdentifier(path) isEqualToString:identifier])
      {
         if (match)
            return nil;
         match = path;
      }
   return match;
}

static inline NSArray<NSString *> *RALabEntryKey(NSString *path, NSString *core)
{
   return @[[path stringByStandardizingPath] ?: @"", RALabCoreIdentifier(core) ?: @""];
}

static inline BOOL RALabMatches(NSString *title, NSString *system,
      NSString *query, NSString *selectedSystem)
{
   if (selectedSystem.length && ![selectedSystem isEqualToString:system])
      return NO;
   NSString *needle = [query stringByTrimmingCharactersInSet:
         NSCharacterSet.whitespaceAndNewlineCharacterSet];
   if (!needle.length)
      return YES;
   NSStringCompareOptions options = NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch;
   return [(title ?: @"") rangeOfString:needle options:options].location != NSNotFound
      || [(system ?: @"") rangeOfString:needle options:options].location != NSNotFound;
}

static inline NSString *RALabArtworkFilename(NSString *title)
{
   NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"&*/:`<>?\\|\""];
   NSString *name = [[title componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"_"];
   return [name stringByAppendingPathExtension:@"png"];
}

#endif
