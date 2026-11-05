/* SPDX-License-Identifier: GPL-3.0-or-later */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <queues/message_queue.h>

#define RUNLOOP_FLAG_CORE_RUNNING 1
#define RUNLOOP_FLAG_PAUSED 2
#define RUNLOOP_FLAG_IDLE 4
#define MENU_ST_FLAG_ALIVE 1
#define CORE_TYPE_DUMMY 0
typedef struct { unsigned flags; int current_core_type; msg_queue_t msg_queue; size_t msg_queue_size; } runloop_state_t;
typedef struct { unsigned flags; } menu_state_t;
typedef struct { bool active; } dispgfx_widget_t;
typedef struct { struct { bool accessibility_enable; } bools; struct { unsigned accessibility_narrator_speech_speed; } uints; } settings_t;
typedef struct { bool enabled; } access_state_t;
static runloop_state_t runloop_state;
static menu_state_t menu;
static dispgfx_widget_t widgets;
static settings_t settings;
static access_state_t access_state;
static int quiet, library, drawn, companion, spoken, cleared, checked;
static bool ra_lab_game_mode_quiet_enabled(void) { return quiet != 0; }
static bool cocoa_lab_library_visible(void) { return library != 0; }
static menu_state_t *menu_state_get_ptr(void) { return &menu; }
static dispgfx_widget_t *dispwidget_get_ptr(void) { return &widgets; }
static settings_t *config_get_ptr(void) { return &settings; }
static access_state_t *access_state_get_ptr(void) { return &access_state; }
static bool is_accessibility_enabled(bool setting, bool enabled) { return setting || enabled; }
static void accessibility_speak_priority(bool enable, unsigned speed, char *message, int priority) { spoken++; }
static void gfx_widgets_msg_queue_push(void *context, const char *msg, size_t len, float duration, char *title, enum message_queue_icon icon, enum message_queue_category category, unsigned prio, bool flush, bool menu_open) { drawn++; }
void msg_queue_push(msg_queue_t *queue, const char *msg, unsigned prio, unsigned duration, char *title, enum message_queue_icon icon, enum message_queue_category category) { drawn++; }
void msg_queue_clear(msg_queue_t *queue) { cleared++; }
size_t msg_queue_size(msg_queue_t *queue) { return drawn; }
static void ui_companion_driver_msg_queue_push(const char *message, unsigned priority, unsigned duration, bool flush) { companion++; }

/* QUEUE_FUNCTION */

static void send_message(enum message_queue_category category, unsigned priority, int expected)
{
   drawn = companion = spoken = cleared = 0;
#ifndef HAVE_RETROARCH_LAB_LIBRARY
   expected = 1;
#endif
   runloop_msg_queue_push("test", 4, priority, 60, true, NULL, MESSAGE_QUEUE_ICON_DEFAULT, category);
   assert(drawn == expected);
   assert(companion == expected);
   assert(spoken == 1);
   if (!expected) assert(!cleared);
   checked++;
}
int main(void)
{
   int pass;
   settings.bools.accessibility_enable = true;
   for (pass = 0; pass < 2; pass++)
   {
      widgets.active = pass != 0;
      quiet = 1; library = 0; menu.flags = 0;
      runloop_state.flags = RUNLOOP_FLAG_CORE_RUNNING;
      runloop_state.current_core_type = 1;
      send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 0);
      send_message(MESSAGE_QUEUE_CATEGORY_SUCCESS, 1, 0);
      send_message(MESSAGE_QUEUE_CATEGORY_WARNING, 0, 1);
      send_message(MESSAGE_QUEUE_CATEGORY_ERROR, 0, 1);
      send_message(MESSAGE_QUEUE_CATEGORY_INFO, 2, 1);
      quiet = 0; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1); quiet = 1;
      library = 1; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1); library = 0;
      menu.flags = MENU_ST_FLAG_ALIVE; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1); menu.flags = 0;
      runloop_state.flags |= RUNLOOP_FLAG_PAUSED; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1);
      runloop_state.flags = RUNLOOP_FLAG_CORE_RUNNING | RUNLOOP_FLAG_IDLE; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1);
      runloop_state.flags = 0; send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1);
      runloop_state.flags = RUNLOOP_FLAG_CORE_RUNNING; runloop_state.current_core_type = CORE_TYPE_DUMMY;
      send_message(MESSAGE_QUEUE_CATEGORY_INFO, 1, 1);
   }
   printf("%d actual notification-dispatch cases passed.\n", checked);
   return 0;
}
