#!/usr/bin/env python3
"""Build Shift using only Apple's installed SDKs; no package downloads."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = Path(os.environ.get("SHIFT_BUILD_DIR", str(ROOT / "build")))
BUILD.mkdir(parents=True, exist_ok=True)
SDK = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
# iCloud may update file metadata while the compiler is reading it. Compile an
# immutable local snapshot, so both architecture slices use identical sources.
snapshot_context = tempfile.TemporaryDirectory(prefix="shift-source-")
SNAPSHOT = Path(snapshot_context.name)
for folder in ["Sources", "Tests", "scripts"]:
    (SNAPSHOT / folder).mkdir()
    for file in (ROOT / folder).glob("*.swift"):
        shutil.copyfile(file, SNAPSHOT / folder / file.name)
SOURCES = sorted(str(p) for p in (SNAPSHOT / "Sources").glob("*.swift"))

def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)

for name, files in [
    ("click-tests", ["Sources/Wire.swift", "Sources/ClickProtocol.swift", "Tests/ClickTests.swift"]),
    ("wire-tests", ["Sources/Wire.swift", "Tests/WireTests.swift"]),
    ("bridge-tests", ["Sources/Wire.swift", "Sources/Bridge.swift", "Tests/BridgeTests.swift"]),
]:
    run("xcrun", "swiftc", "-swift-version", "5", *(SNAPSHOT / file for file in files), "-o", BUILD / name)
    run(BUILD / name)

for arch in ["arm64", "x86_64"]:
    run("xcrun", "swiftc", "-swift-version", "5", "-O", "-target", f"{arch}-apple-macos13.0",
        "-sdk", SDK, *SOURCES, "-o", BUILD / f"Shift-{arch}")

APP = BUILD / "Shift.app"
if APP.exists():
    shutil.rmtree(APP)
(APP / "Contents/MacOS").mkdir(parents=True)
(APP / "Contents/Resources").mkdir()
run("xcrun", "swift", SNAPSHOT / "scripts/Icon.swift", BUILD / "Icon.png")
iconset = BUILD / "Shift.iconset"
iconset.mkdir(exist_ok=True)
for size in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = "@2x" if scale == 2 else ""
        run("/usr/bin/sips", "-z", size * scale, size * scale, BUILD / "Icon.png", "--out", iconset / f"icon_{size}x{size}{suffix}.png")
run("/usr/bin/iconutil", "-c", "icns", iconset, "-o", APP / "Contents/Resources/Shift.icns")
run("xcrun", "lipo", "-create", BUILD / "Shift-arm64", BUILD / "Shift-x86_64", "-output", APP / "Contents/MacOS/Shift")
(APP / "Contents/Info.plist").write_bytes(plistlib.dumps({
    "CFBundleName": "Shift", "CFBundleDisplayName": "Shift", "CFBundleExecutable": "Shift",
    "CFBundleIdentifier": "com.joshuaforster.shift", "CFBundlePackageType": "APPL",
    "CFBundleIconFile": "Shift.icns",
    "CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "2", "LSMinimumSystemVersion": "13.0",
    "LSApplicationCategoryType": "public.app-category.healthcare-fitness", "NSHighResolutionCapable": True,
    "NSLocalNetworkUsageDescription": "Shift verbindet deinen Controller im lokalen Netzwerk mit MyWhoosh.",
    "NSBonjourServices": ["_openbikecontrol._tcp"],
    "NSBluetoothAlwaysUsageDescription": "Shift verbindet Zwift Click V2 direkt per Bluetooth zum Schalten in MyWhoosh.",
    "CFBundleURLTypes": [{"CFBundleURLName": "Shift", "CFBundleURLSchemes": ["shift"]}],
    "NSHumanReadableCopyright": "© 2026 Joshua Forster. OpenBikeControl protocol: MIT license.",
}))
for name in ["LICENSE", "THIRD_PARTY_NOTICES.md"]:
    shutil.copy2(ROOT / name, APP / "Contents/Resources" / name)
run("/usr/bin/xattr", "-cr", APP)
identity = os.environ.get("SHIFT_SIGN_IDENTITY", "-")
run("/usr/bin/codesign", "--force", "--sign", identity, "--options", "runtime", "--timestamp=none", APP)
run("/usr/bin/codesign", "--verify", "--strict", "--verbose=2", APP)
run("xcrun", "lipo", "-archs", APP / "Contents/MacOS/Shift")
run("/usr/bin/ditto", "-c", "-k", "--keepParent", APP, BUILD / "Shift-1.1.0-mac.zip")
print("Ready:", BUILD / "Shift-1.1.0-mac.zip")
