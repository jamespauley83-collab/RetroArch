#!/usr/bin/env python3
"""Package a development JIT build from preserved Lab resources and a rebuilt core."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
from datetime import datetime

IDENTITY = "com.jamespauley.retroarchlab.ps3bridge"
CORES = ("armsx2", "dolphin", "fceumm", "mednafen.saturn", "opera", "play", "snes9x2010", "yabause")
LLVM = "ca7933e47d3a3451d81e72ac174dcb5aa28b59d1"


def run(*args):
    return subprocess.check_output([str(x) for x in args], stderr=subprocess.STDOUT)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def info(app):
    return plistlib.loads((app / "Info.plist").read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for key in ("resource-app", "development-app", "host-app", "native-core", "output"):
        parser.add_argument("--" + key, type=Path, required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--signing-identity", required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Use a new output directory.")
    for app in (args.resource_app, args.development_app, args.host_app):
        if info(app)["CFBundleIdentifier"] != IDENTITY:
            raise ValueError("Every input must use the established Lab identity.")
    host = args.host_app / info(args.host_app)["CFBundleExecutable"]
    host_bytes = host.read_bytes()
    core_bytes = args.native_core.read_bytes()
    if b"RALabPS3Controller" not in host_bytes or b"Enable PS3 JIT" not in host_bytes:
        raise ValueError("The host must contain the native PS3 JIT controls.")
    if b"PS3 executable-memory self-test returned an invalid result." not in host_bytes:
        raise ValueError("The host must execute the LLVM self-test.")
    if LLVM.encode() not in core_bytes or b'"jit":"sealed-arena"' not in core_bytes:
        raise ValueError("The native core must include the pinned LLVM JIT.")
    if b'"execution_mode":"RPCS3 interpreter-only distribution"' in core_bytes:
        raise ValueError("An interpreter-only native core cannot be used.")
    if run("xcrun", "lipo", "-archs", args.native_core).strip() != b"arm64":
        raise ValueError("Expected an arm64 native core.")
    profile_path = args.development_app / "embedded.mobileprovision"
    profile = plistlib.loads(run("security", "cms", "-D", "-i", profile_path))
    signature = run("codesign", "-d", "--entitlements", ":-", args.development_app)
    entitlements = plistlib.loads(b"<?xml" + signature.split(b"<?xml", 1)[1])
    if profile["ExpirationDate"] <= datetime.utcnow():
        raise ValueError("The development profile has expired.")
    for key in ("get-task-allow", "com.apple.developer.kernel.extended-virtual-addressing",
                "com.apple.developer.kernel.increased-memory-limit"):
        if profile["Entitlements"].get(key) is not True or entitlements.get(key) is not True:
            raise ValueError("The development profile and signature must authorize " + key)
    if not entitlements["application-identifier"].endswith("." + IDENTITY):
        raise ValueError("The development signature has a different app identity.")
    for name in CORES:
        if not (args.development_app / "Frameworks" / (name + ".libretro.framework")).is_dir():
            raise ValueError("Missing development core: " + name)
    target = args.output / "Payload/RetroArch.app"
    shutil.copytree(args.resource_app, target)
    if (target / "PlugIns").exists():
        raise ValueError("This packaging recipe expects the established extension-free resource app.")
    for signature in list(target.rglob("_CodeSignature")):
        shutil.rmtree(signature)
    shutil.copy2(host, target / info(target)["CFBundleExecutable"])
    frameworks = target / "Frameworks"
    shutil.rmtree(frameworks / "RPCS3Core.framework", ignore_errors=True)
    for name in CORES:
        dest = frameworks / (name + ".libretro.framework")
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(args.development_app / "Frameworks" / dest.name, dest)
    core = frameworks / "libRPCS3Core.dylib"
    shutil.copy2(args.native_core, core)
    core_id = run("xcrun", "otool", "-D", core).decode().splitlines()[1].strip()
    if core_id != "@rpath/libRPCS3Core.dylib":
        run("xcrun", "install_name_tool", "-id", "@rpath/libRPCS3Core.dylib", core)
    plist = info(target)
    plist["CFBundleVersion"] = str(args.build)
    plist["CFBundleName"] = plist["CFBundleDisplayName"] = "RetroArch Lab"
    plist["CFBundleURLTypes"] = [{"CFBundleURLName": IDENTITY,
                                "CFBundleURLSchemes": ["retroarchlabps3bridge"]}]
    (target / "Info.plist").write_bytes(plistlib.dumps(plist))
    helper = Path(__file__).resolve().parents[1] / "archive_testflight_interpreter.py"
    spec = importlib.util.spec_from_file_location("storage_privacy", helper)
    privacy = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(privacy)
    privacy.declare_import_storage_usage(target)
    shutil.copy2(profile_path, target / "embedded.mobileprovision")
    entitlement_file = args.output / "Development.entitlements"
    entitlement_file.write_bytes(plistlib.dumps(entitlements))
    record = {
        "build": args.build, "version": plist["CFBundleShortVersionString"],
        "bundle_identifier": IDENTITY, "distribution": "development",
        "host_sha256": digest(host), "unsigned_native_core_sha256": digest(args.native_core),
        "native_commit": "f88bff947b83730c0cf8a3949f59338b992b3ca0",
        "llvm_revision": LLVM, "native_patches": ["interpreter build option disabled",
        "microphone and logger corrections", "important-usage storage capacity"],
        "libretro_cores": list(CORES), "testflight_compatible": False,
    }
    (target / "RPCS3-core.lock.json").write_text(json.dumps(record, indent=2) + "\n")
    for item in sorted(frameworks.iterdir()):
        if item.suffix in (".framework", ".dylib"):
            run("codesign", "--force", "--sign", args.signing_identity, item)
    run("codesign", "--force", "--sign", args.signing_identity,
        "--entitlements", entitlement_file, "--generate-entitlement-der", target)
    run("codesign", "--verify", "--deep", "--strict", target)
    record["signed_native_core_sha256"] = digest(core)
    record["signature_verified"] = True
    (args.output / "manifest.json").write_text(json.dumps(record, indent=2) + "\n")
    print(target)


if __name__ == "__main__":
    main()
