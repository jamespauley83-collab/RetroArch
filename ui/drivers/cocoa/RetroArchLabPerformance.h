/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef RETROARCH_LAB_PERFORMANCE_H
#define RETROARCH_LAB_PERFORMANCE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#ifdef HAVE_RETROARCH_LAB_LIBRARY
uint64_t ra_lab_perf_clock(void);
void ra_lab_perf_begin(const char *core, const char *game, double hz,
      int mode, const char *video, const char *audio, int threaded_video);
void ra_lab_perf_end(void);
void ra_lab_perf_idle(void);
void ra_lab_perf_stage(uint64_t start, int audio);
void ra_lab_perf_audio(uint64_t underruns, int valid);
#endif
#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <UIKit/UIKit.h>
#ifdef HAVE_RETROARCH_LAB_LIBRARY
void RALabPerfShow(UIViewController *parent);
void RALabPerfLogShow(UIViewController *parent);
void RALabPerfLogToggle(UIViewController *parent, UIView *surface);
void RALabPerfPS3Surface(UIView *surface);
void RALabPerfPS3Log(int32_t level, const char *message);
void RALabPerfEvent(NSString *event);
void RALabPerfPrepareForRelaunch(void);
void RALabPerfPS3(NSString *state, unsigned valid, double fps, double rsx);
#else
static inline void RALabPerfPS3Surface(UIView *surface) { (void)surface; }
static inline void RALabPerfPS3Log(int32_t level, const char *message) { (void)level; (void)message; }
static inline void RALabPerfEvent(NSString *event) { (void)event; }
static inline void RALabPerfPrepareForRelaunch(void) {}
static inline void RALabPerfPS3(NSString *state, unsigned valid, double fps, double rsx)
{ (void)state; (void)valid; (void)fps; (void)rsx; }
#endif
#endif
#endif
