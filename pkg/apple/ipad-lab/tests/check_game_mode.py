#!/usr/bin/env python3
"""Compile the real notification dispatch body with isolated display sinks."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[4]
source = (root / "runloop.c").read_text()
start = source.index("void runloop_msg_queue_push(\n")
body = source[start:source.index("\n}\n", start) + 3]
fixture = (Path(__file__).with_name("game_mode_queue.c")).read_text()
with tempfile.TemporaryDirectory(prefix="lab-game-mode-") as directory:
    work = Path(directory)
    c = work / "queue.c"
    c.write_text(fixture.replace("/* QUEUE_FUNCTION */", body))
    for lab in (False, True):
        for widgets in (False, True):
            args = ["xcrun", "clang", "-std=c89", "-Wall", "-Wextra", "-Werror",
                    "-Wno-unused-parameter", "-Wno-unused-function", "-DHAVE_MENU",
                    "-DHAVE_ACCESSIBILITY", "-I" + str(root / "libretro-common/include")]
            if lab:
                args.append("-DHAVE_RETROARCH_LAB_LIBRARY")
            if widgets:
                args.append("-DHAVE_GFX_WIDGETS")
            subprocess.run(args + [str(c), "-o", str(work / "queue")], check=True)
            subprocess.run([str(work / "queue")], check=True)
plist = plistlib.loads((root / "pkg/apple/iOS/Info.plist").read_bytes())
assert plist["LSSupportsGameMode"] is True
assert plist["GCSupportsGameMode"] is True
assert plist["LSApplicationCategoryType"] == "public.app-category.games"
print("Current and legacy Game Mode metadata verified.")
