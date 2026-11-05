/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RETROARCH_LAB_GAME_MODE_H
#define RETROARCH_LAB_GAME_MODE_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
bool ra_lab_game_mode_quiet_enabled(void);
#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <UIKit/UIKit.h>
void RALabGameModeShow(UIViewController *parent);
#endif
#endif
