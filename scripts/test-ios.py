import argparse
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = "com.maxblox2999.advanish.fixture"


def run(*command, timeout=120):
    return subprocess.check_output(command, text=True, timeout=timeout).strip()


def main(video, output):
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path")
    devices = json.loads(run("xcrun", "simctl", "list", "-j"))
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
            (app / "Info.plist").write_bytes(plistlib.dumps(info))
            shutil.copyfile(video, app / "fixture.mp4")
            command = ["xcrun", "--sdk", "iphonesimulator", "clang++", "-fobjc-arc", "-fblocks", "-std=c++11",
                       "-isysroot", sdk, "-target", platform.machine() + "-apple-ios15.0-simulator", "-I", str(ROOT)]
            command += [str(ROOT / name) for name in ["tests/ios/Fixture.mm", "ASPManualSkip.mm", "ASPAdSurface.mm", "ASPUniversalSkip.mm"]]
            for framework in ["Foundation", "UIKit", "AVFoundation", "CoreMedia", "QuartzCore", "CoreGraphics", "WebKit"]:
                command += ["-framework", framework]
            command += ["-o", str(app / "AdVanishFixture")]
            subprocess.run(command, check=True, timeout=120)
            run("codesign", "--force", "--sign", "-", str(app))
            print(json.dumps({"phase": "boot", "runtime": runtime["version"]}), flush=True)
            run("xcrun", "simctl", "boot", device)
            run("xcrun", "simctl", "bootstatus", device, "-b", timeout=240)
            run("xcrun", "simctl", "install", device, str(app))
            container = Path(run("xcrun", "simctl", "get_app_container", device, BUNDLE, "data"))
            run("xcrun", "simctl", "launch", device, BUNDLE)
            report_path = container / "Documents/result.json"
            deadline = time.monotonic() + 45
            while not report_path.exists() and time.monotonic() < deadline:
                time.sleep(0.25)
            if not report_path.exists():
                raise RuntimeError("Native fixture did not write a result")
            report = json.loads(report_path.read_text())
            report["runtime"] = runtime["version"]
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(report, indent=2) + "\n")
            print(json.dumps(report))
            if not report["passed"]:
                raise RuntimeError(report["failure"])
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", device], check=False, timeout=45)
        subprocess.run(["xcrun", "simctl", "delete", device], check=False, timeout=45)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--video", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "dist/ios-simulator.json")
    args = parser.parse_args()
    main(args.video, args.output)
