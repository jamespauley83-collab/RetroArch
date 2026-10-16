# ARMSX2 iOS core prototype

This is an isolated **build probe**, not a playable PS2 core or installable IPA.
The core deliberately rejects game loading with an explanation. It is not
added to Lab's core lock, normal packaging, or game assignments.

## Reproduce

Open the `ARMSX2 iOS core prototype` PR workflow. It checks out ARMSX2 revision
`e58489d349cdcd635fc6264546087e347c84bf8c`, applies only this directory's patch,
builds the upstream checksum-verified static iOS dependencies, and compiles the
root `pcsx2-libretro` target for ARM64/iPhoneOS 17.4. No Apple credentials or
provisioning profiles are used. A fresh source checkout is required per run.

On a Mac with Xcode, check out the same pinned upstream revision at
`.armsx2-prototype/source` under the Lab repository and run:

```sh
bash pkg/apple/ipad-lab/experiments/armsx2/build.sh
```

The artifact validator rejects simulator/macOS binaries, missing libretro
exports, non-libretro exports, non-system dynamic dependencies, or a missing
prototype load gate. A successful run provides a dylib, source archive,
dependency source archives/checksums, patch, GPL license, inspection report
and manifest. Apply the included patch to the pinned source archive to
reconstruct the modified source. Read the manifest's stage and validation
fields; compilation does not establish runtime compatibility.

## Concrete integration gaps

The upstream `.gitlab-ci.yml` includes an experimental Apple embedded core
recipe, in addition to the standalone iOS app. This prototype follows that
core recipe, not the standalone SwiftUI app's build.

1. **Graphics:** the embedded recipe disables Vulkan and OpenGL. The libretro
   adapter in `pcsx2-libretro/Main.cpp` negotiates only those two APIs; its
   software renderer also requires one for presentation. Without a context it
   sets Null GS. The standalone Metal renderer does not provide a libretro
   frame handoff. A successful compile would otherwise conceal a blank screen.
2. **JIT:** the upstream Darwin code uses its own `csops`/mapping detection and
   code-memory management. It does not use Lab's frontend executable-memory
   callbacks. Audit and adapt allocation, executable/writable alias translation,
   patching, protection and teardown before permitting a VM to start on iOS 26.
3. **Isolation:** before runtime tests, package under a separate test app ID,
   distinct save/config paths, and no shared production iCloud container.
   Do not overwrite Play! memory cards or assume cross-core save compatibility.
4. **Device results:** only after graphics and JIT work, test gameplay, input,
   sound, normal shutdown, in-game save, app restart and reload. Compare against
   Play! at 1x resolution in the same gameplay scene. No speed claim yet.

The load gate runs before pixel-format setup, configuration, memory reservation
or VM startup. It is intentionally enabled by the build script. Removing it
is not the next step; implementing and validating graphics/JIT integration is.

Source: https://github.com/ARMSX2/ARMSX2/tree/e58489d349cdcd635fc6264546087e347c84bf8c
