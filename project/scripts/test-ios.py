# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

import argparse
import json
import os
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.maxblox2999.advanish.fixture"


def run(*command, timeout=120):
    return subprocess.check_output(command, text=True, timeout=timeout).strip()


def simulator_devices():
    try:
        return json.loads(run("xcrun", "simctl", "list", "-j"))
    except subprocess.TimeoutExpired:
        print(json.dumps({"phase": "simulator startup", "retry": 1}), flush=True)
        return json.loads(run("xcrun", "simctl", "list", "-j"))


def source_commit():
    record = ROOT.parent / "SOURCE_COMMIT"
    if record.is_file():
        return record.read_text().strip()
    try:
        return run("git", "-C", str(ROOT), "rev-parse", "HEAD")
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None


def main(video, output, injected=False, manual=False, settings=False):
    output.unlink(missing_ok=True)
    if settings and (injected or manual):
        raise ValueError("Settings verification runs separately from ad injection")
    if manual and not injected:
        raise ValueError("Manual-mode verification requires the injected framework")
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    devices = simulator_devices()
    runtimes = [item for item in devices["runtimes"]
                if item.get("isAvailable") and item["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    if not runtimes:
        raise RuntimeError("An installed iOS Simulator runtime is required")
    matching = [item for item in runtimes if item["version"].startswith("18.")]
    runtime = max(matching or runtimes, key=lambda item: tuple(map(int, item["version"].split("."))))
    runtime_version = tuple(map(int, runtime["version"].split(".")))
    packed_version = (runtime_version[0] << 16) | (runtime_version[1] << 8)
    types = [item for item in devices["devicetypes"]
             if item["name"].startswith("iPhone") and item.get("minRuntimeVersion", 0) <= packed_version
             and item.get("maxRuntimeVersion", 0xFFFFFFFF) >= packed_version]
    if not types:
        raise RuntimeError("No compatible iPhone simulator type")
    device = run("xcrun", "simctl", "create", "AdVanish fixture", types[-1]["identifier"], runtime["identifier"])
    booted = False
    try:
        with tempfile.TemporaryDirectory(prefix="advanish-ios-") as directory:
            app = Path(directory) / "AdVanishFixture.app"
            app.mkdir()
            info = {
                "CFBundleIdentifier": BUNDLE,
                "CFBundleExecutable": "AdVanishFixture",
                "CFBundleName": "AdVanishFixture",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
                "MinimumOSVersion": "15.0",
                "LSRequiresIPhoneOS": True,
                "UIDeviceFamily": [1],
                "UILaunchScreen": {},
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
            }
            if manual:
                info["AdVanishManualFixture"] = True
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            if injected:
                (app / "AdVanish.plist").write_bytes(plistlib.dumps({"AutomaticAds": not manual, "ManualSkip": True}))
            shutil.copyfile(video, app / "fixture.mp4")
            command = ["xcrun", "--sdk", "iphonesimulator", "clang++", "-fobjc-arc", "-fblocks", "-std=c++11",
                       "-isysroot", sdk, "-target", platform.machine() + "-apple-ios15.0-simulator", "-I", str(ROOT)]
            if settings:
                theos = Path(os.environ["THEOS"])
                include_paths = [theos / "include", theos / "vendor/include"]
                if not any((path / "Preferences/PSListController.h").is_file() for path in include_paths):
                    raise RuntimeError("Pinned Theos Preferences headers are missing")
                command += [argument for path in include_paths for argument in ("-I", str(path))]
                stub = Path(directory) / "Preferences.framework"
                stub.mkdir()
                target_name = platform.machine() + "-ios-simulator"
                (stub / "Preferences.tbd").write_text(
                    "--- !tapi-tbd\n"
                    "tbd-version: 4\n"
                    "targets: [ " + target_name + " ]\n"
                    "install-name: '/System/Library/PrivateFrameworks/Preferences.framework/Preferences'\n"
                    "exports:\n"
                    "  - targets: [ " + target_name + " ]\n"
                    "    objc-classes: [ PSListController, PSSpecifier ]\n"
                    "...\n")
                command += ["-F", directory, "-framework", "Preferences",
                            "-x", "objective-c++", str(ROOT / "tests/ios/SettingsFixture.m")]
            elif injected:
                frameworks = app / "Frameworks"
                subprocess.run([sys.executable, str(ROOT / "scripts/build-jailed.py"), "--simulator", "--output", str(frameworks)], check=True, timeout=300)
                command += [str(ROOT / "tests/ios/InjectedFixture.mm"), "-F", str(frameworks), "-framework", "AdVanish",
                            "-Wl,-rpath,@executable_path/Frameworks"]
            else:
                command += [str(ROOT / name) for name in ["tests/ios/Fixture.mm", "ASPManualSkip.mm", "ASPAdSurface.mm", "ASPUniversalSkip.mm", "ASPAdCompletion.mm"]]
            for framework in ["Foundation", "UIKit", "AVFoundation", "CoreMedia", "QuartzCore", "CoreGraphics", "WebKit"]:
                command += ["-framework", framework]
            command += ["-o", str(app / "AdVanishFixture")]
            subprocess.run(command, check=True, timeout=120)
            run("codesign", "--force", "--sign", "-", str(app))
            print(json.dumps({"phase": "boot", "runtime": runtime["version"]}), flush=True)
            run("xcrun", "simctl", "boot", device)
            booted = True
            run("xcrun", "simctl", "bootstatus", device, "-b", timeout=240)
            run("xcrun", "simctl", "install", device, str(app))
            container = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE, "data"))
            report_path = container / "Documents/result.json"
            with tempfile.TemporaryFile(mode="w+t") as launch_log:
                launcher = subprocess.Popen(["xcrun", "simctl", "launch", device, BUNDLE], stdout=launch_log, stderr=subprocess.STDOUT, text=True)
                try:
                    deadline = time.monotonic() + 90
                    while not report_path.exists() and time.monotonic() < deadline:
                        if launcher.poll() not in (None, 0):
                            launch_log.seek(0)
                            raise RuntimeError("Simulator launch failed: " + launch_log.read())
                        time.sleep(0.25)
                finally:
                    if launcher.poll() is None:
                        launcher.terminate()
                        try:
                            launcher.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            launcher.kill()
                            launcher.wait(timeout=10)
            if not report_path.exists():
                raise RuntimeError("Native fixture did not write a result")
            report = json.loads(report_path.read_text())
            report["runtime"] = runtime["version"]
            report["injected_framework"] = injected
            report["source_commit"] = source_commit()
            report["manual_mode"] = manual
            report["settings_controller"] = settings
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report))
            if not report["passed"]:
                raise RuntimeError(report["failure"])
    finally:
        try:
            if booted:
                subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=45)
        finally:
            subprocess.run(["xcrun", "simctl", "delete", device], check=False, timeout=45)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/ios-simulator.json")
    parser.add_argument("--injected", action="store_true")
    parser.add_argument("--manual", action="store_true", help="Check manual-only mode in the injected framework")
    parser.add_argument("--settings", action="store_true", help="Open production Settings against real simulator Preferences")
    args = parser.parse_args()
    if args.manual and not args.injected:
        parser.error("--manual requires --injected")
    main(args.video, args.output, args.injected, args.manual, args.settings)
