# XITRIX RPCS3 native bridge

RPCS3IOS.h is the unmodified ABI 30 header from XITRIX/rpcs3 at
f88bff947b83730c0cf8a3949f59338b992b3ca0. RPCS3 is predominantly GPL-2.0-only; this bridge is GPL-3.0-or-later.
See RPCS3-LICENSE and RetroArch COPYING. This is a private local prototype.
The combined binary is not published; license compatibility must be resolved
before redistributing a combined application.

The local test package reuses the user's verified XITRIX Preview 0.12 ARMv8.4-A
core, SHA-256 64c942bc435d82627f7ad223ed091be76e1e2ba112c7f95d3596e68c31188237.
It is not rebuilt from the header revision. ABI 30 is checked before initialization.
The release core reports upstream fdcfded8dfd3060af66bda0a3ac4635458980038.
The header's newer optional exports are not used. No firmware, games, saves,
telemetry frameworks, credentials, or private pairing files are included.

This is a native frontend integration, not a libretro core. RPCS3 owns rendering,
audio, timing, and PS3 saves. RetroArch shaders, rewind, cheats, achievements and
save-state UI are not applied. A controller supplies analog sticks; touch buttons
provide a digital fallback. Rumble and native RPCS3 savestate management are not
exposed in this initial bridge.

Source: https://github.com/XITRIX/rpcs3/tree/ios-port
Release: https://github.com/XITRIX/RPCS3-iOS-Releases/releases/tag/v0.12
