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
DEFAULT_BUDGET = 300


def note(payload):
    print(json.dumps(payload), file=sys.stderr, flush=True)


def run(*command, timeout=120, attempts=2):
    error = None
    for attempt in range(attempts):
        try:
            return subprocess.check_output(command, text=True, timeout=timeout).strip()
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as failure:
            error = failure
            if attempt + 1 < attempts:
                time.sleep(2)
    raise error


def simctl(*arguments, timeout=90, attempts=2):
    error = None
    for attempt in range(attempts):
        try:
            return subprocess.check_output(["xcrun", "simctl", *arguments], text=True,
                                           stderr=subprocess.STDOUT, timeout=timeout).strip()
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError) as failure:
            error = failure
            if attempt + 1 < attempts:
                time.sleep(2)
    raise RuntimeError("simctl " + arguments[0] + " failed: " + str(error))


def simctl_quiet(*arguments, timeout=90):
    try:
        simctl(*arguments, timeout=timeout, attempts=1)
        return True
    except RuntimeError:
        return False


def simulator_devices(timeout=60):
    """The first simulator query after boot can time out once; a hard failure is final."""
    try:
        return json.loads(run("xcrun", "simctl", "list", "-j", timeout=timeout, attempts=1))
    except subprocess.TimeoutExpired:
        return json.loads(run("xcrun", "simctl", "list", "-j", timeout=timeout, attempts=1))


def device_target():
    devices = simulator_devices()
    runtimes = [item for item in devices["runtimes"]
                if item.get("isAvailable") and item["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    if not runtimes:
        raise RuntimeError("An installed iOS Simulator runtime is required")

    def version(item):
        return tuple(int(part) for part in item["version"].split("."))

    runtime = max([item for item in runtimes if item["version"].startswith("18.")] or runtimes, key=version)
    major, minor = version(runtime)[:2]
    packed = (major << 16) | (minor << 8)
    types = [item for item in devices["devicetypes"]
             if item["name"].startswith("iPhone") and item.get("minRuntimeVersion", 0) <= packed
             and item.get("maxRuntimeVersion", 0xFFFFFFFF) >= packed]
    if not types:
        raise RuntimeError("No compatible iPhone simulator type")
    return types[-1]["identifier"], runtime["identifier"], runtime["version"]


def warm_up(device, timeout=60):
    """SpringBoard can accept a launch before it is ready to host an app."""
    try:
        simctl("launch", device, "com.apple.Preferences", timeout=timeout, attempts=1)
    except RuntimeError:
        note({"phase": "warm up"})
        return False
    simctl_quiet("terminate", device, "com.apple.Preferences", timeout=30)
    return True


def reset(device):
    """A launch that hangs means the device is wedged; reboot it, then the service."""
    for arguments, timeout in ((("terminate", device, BUNDLE), 30),
                               (("shutdown", device), 60),
                               (("boot", device), 90),
                               (("bootstatus", device, "-b"), 240)):
        if not simctl_quiet(*arguments, timeout=timeout):
            note({"phase": "simulator reset", "step": arguments[0]})
    if simctl_quiet("bootstatus", device, "-b", timeout=60):
        return True
    note({"phase": "simulator reset", "step": "service"})
    subprocess.run(["killall", "-9", "com.apple.CoreSimulator.CoreSimulatorService"], check=False)
    time.sleep(5)
    return simctl_quiet("boot", device, timeout=120) and simctl_quiet("bootstatus", device, "-b", timeout=300)


def prepare(name):
    started = time.monotonic()
    device_type, runtime, version = device_target()
    device = simctl("create", name, device_type, runtime, timeout=60)
    simctl("boot", device, timeout=120)
    simctl("bootstatus", device, "-b", timeout=300)
    warm_up(device)
    note({"phase": "ready", "runtime": version, "device": device, "elapsed": round(time.monotonic() - started, 1)})
    return device


def delete(device):
    simctl_quiet("terminate", device, BUNDLE, timeout=30)
    simctl_quiet("shutdown", device, timeout=60)
    simctl_quiet("delete", device, timeout=60)


def launch(device, bundle, report_path=None, timeout=90):
    """Run simctl launch, killing it if it never returns."""
    with tempfile.TemporaryFile(mode="w+t") as launch_log:
        launcher = subprocess.Popen(["xcrun", "simctl", "launch", "--terminate-running-process", device, bundle],
                                    stdout=launch_log, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                if report_path is not None and report_path.exists():
                    break
                if launcher.poll() is not None and (report_path is None or launcher.returncode != 0):
                    break
                time.sleep(0.25)
        finally:
            if launcher.poll() is None:
                launcher.terminate()
                try:
                    launcher.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    launcher.kill()
                    launcher.wait(timeout=10)
        launch_log.seek(0)
        return launcher.returncode, launch_log.read()[-32768:]


def source_commit():
    record = ROOT.parent / "SOURCE_COMMIT"
    if record.is_file():
        return record.read_text().strip()
    try:
        return run("git", "-C", str(ROOT), "rev-parse", "HEAD", timeout=30, attempts=1)
    except (RuntimeError, subprocess.SubprocessError):
        return None


def diagnostics(output, device, failure, container=None):
    record = {"phase": "failure", "error": str(failure), "device": device,
              "source_commit": source_commit()}
    if container is not None:
        progress = container / "Documents/settings-progress.json"
        if progress.is_file():
            record["progress"] = progress.read_text()[:65536]
    try:
        logs = subprocess.run(["xcrun", "simctl", "spawn", device, "log", "show",
            "--last", "3m", "--style", "compact", "--predicate",
            'process == "AdVanishFixture" OR eventMessage CONTAINS "AdVanishFixture"'],
            capture_output=True, text=True, timeout=30)
        record["simulator_log"] = (logs.stdout + logs.stderr)[-180000:]
    except subprocess.TimeoutExpired:
        record["simulator_log"] = "log collection timed out"
    reports = Path.home() / "Library/Logs/DiagnosticReports"
    crashes = sorted(reports.glob("AdVanishFixture*"), key=lambda path: path.stat().st_mtime, reverse=True)
    record["crash_reports"] = [
        {"name": path.name, "content": path.read_text(errors="replace")[:180000]}
        for path in crashes[:3] if path.is_file()]
    output.parent.mkdir(parents=True, exist_ok=True)
    path = output.with_name(output.stem + "-diagnostics.json")
    path.write_text(json.dumps(record, indent=2) + "\n")
    note({"phase": "failure", "error": str(failure), "diagnostics": str(path)})
    return path


def main(video, output, injected=False, manual=False, settings=False, device=None, framework=None,
         budget=DEFAULT_BUDGET):
    output.unlink(missing_ok=True)
    if settings and (injected or manual):
        raise ValueError("Settings verification runs separately from ad injection")
    if manual and not injected:
        raise ValueError("Manual-mode verification requires the injected framework")
    deadline = time.monotonic() + budget
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    owned = device is None
    if owned:
        device = prepare("AdVanish fixture")
    booted = owned
    container = None
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
                    "    objc-ivars: [ PSListController._specifiers ]\n"
                    "...\n")
                command += ["-F", directory, "-framework", "Preferences",
                            "-x", "objective-c++", str(ROOT / "tests/ios/SettingsFixture.m")]
            elif injected:
                frameworks = app / "Frameworks"
                if framework:
                    shutil.copytree(framework, frameworks)
                else:
                    subprocess.run([sys.executable, str(ROOT / "scripts/build-jailed.py"), "--simulator",
                                    "--output", str(frameworks)], check=True, timeout=300)
                command += [str(ROOT / "tests/ios/InjectedFixture.mm"), "-F", str(frameworks), "-framework", "AdVanish",
                            "-Wl,-rpath,@executable_path/Frameworks"]
            else:
                command += [str(ROOT / name) for name in ["tests/ios/Fixture.mm", "ASPManualSkip.mm", "ASPAdSurface.mm", "ASPUniversalSkip.mm", "ASPAdCompletion.mm"]]
            for framework_name in ["Foundation", "UIKit", "AVFoundation", "CoreMedia", "QuartzCore", "CoreGraphics", "WebKit"]:
                command += ["-framework", framework_name]
            command += ["-o", str(app / "AdVanishFixture")]
            subprocess.run(command, check=True, timeout=180)
            run("codesign", "--force", "--sign", "-", str(app))
            simctl_quiet("terminate", device, BUNDLE, timeout=30)
            simctl("install", device, str(app), timeout=120)
            for attempt in range(3):
                try:
                    container = Path(simctl("get_app_container", device, BUNDLE, "data", timeout=60))
                    break
                except RuntimeError:
                    if time.monotonic() >= deadline or attempt == 2:
                        raise
                    note({"phase": "app container", "retry": attempt + 1})
                    reset(device)
            report_path = container / "Documents/result.json"
            report_path.unlink(missing_ok=True)
            launch_started = time.time()
            launch_output = ""
            launch_exit_code = None
            launch_attempts = 0
            for attempt in range(2):
                launch_attempts = attempt + 1
                launch_exit_code, launch_output = launch(device, BUNDLE, report_path)
                if report_path.exists():
                    break
                if attempt == 0 and time.monotonic() < deadline:
                    note({"phase": "relaunch", "attempt": launch_attempts,
                          "launcher_exit_code": launch_exit_code,
                          "launcher_output": launch_output[-4096:]})
                    reset(device)
            if not report_path.exists():
                path = diagnostics(output, device, "Native fixture did not write a result", container)
                raise RuntimeError("Native fixture did not write a result; see " + str(path))
            report = json.loads(report_path.read_text())
            report["runtime"] = device_target()[2]
            report["source_commit"] = source_commit()
            report["injected_framework"] = injected
            report["manual_mode"] = manual
            report["settings_controller"] = settings
            report["launch_attempts"] = launch_attempts
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            note({"phase": "done", "elapsed": round(time.monotonic() - (deadline - budget), 1)})
            print(json.dumps(report))
            if not report["passed"]:
                raise RuntimeError(report["failure"])
    except Exception as failure:
        if container is None:
            diagnostics(output, device, failure)
        raise
    finally:
        if booted:
            delete(device)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/ios-simulator.json")
    parser.add_argument("--injected", action="store_true")
    parser.add_argument("--manual", action="store_true", help="Check manual-only mode in the injected framework")
    parser.add_argument("--settings", action="store_true", help="Open production Settings against real simulator Preferences")
    parser.add_argument("--framework", type=Path, help="Reuse a prebuilt injected framework")
    parser.add_argument("--device", help="Reuse a booted simulator instead of creating one")
    parser.add_argument("--prepare", metavar="NAME", help="Create and boot a simulator, then print its UDID")
    parser.add_argument("--delete", metavar="DEVICE", help="Shut down and delete a simulator")
    parser.add_argument("--budget", type=int, default=DEFAULT_BUDGET, help="Seconds allowed for the run")
    args = parser.parse_args()
    if args.prepare:
        print(prepare(args.prepare))
    elif args.delete:
        delete(args.delete)
    else:
        if args.manual and not args.injected:
            parser.error("--manual requires --injected")
        if not args.video:
            parser.error("--video is required")
        main(args.video, args.output, args.injected, args.manual, args.settings, args.device,
             args.framework, args.budget)
