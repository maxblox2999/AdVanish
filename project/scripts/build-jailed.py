#!/usr/bin/env python3
# AdVanish contributions: Copyright (C) 2026 maxblox2999.
# GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

import argparse
import hashlib
import json
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from ipa_tools import framework_report

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = ROOT.parent
NATIVE = ["ASPUniversalSkip.mm", "ASPManualSkip.mm", "ASPAdSurface.mm", "ASPAdCompletion.mm"]
FRAMEWORKS = ["Foundation", "UIKit", "QuartzCore", "CoreGraphics", "AVFoundation", "CoreMedia", "WebKit"]


def build(output, simulator=False):
    theos = Path(os.environ["THEOS"])
    logos = theos / "bin/logos.pl"
    if not logos.is_file():
        raise RuntimeError("THEOS must contain the pinned Logos preprocessor")
    sdkname = "iphonesimulator" if simulator else "iphoneos"
    sdk = subprocess.check_output(["xcrun", "--sdk", sdkname, "--show-sdk-path"], text=True).strip()
    architecture = platform.machine() if simulator else "arm64"
    target = architecture + "-apple-ios15.0" + ("-simulator" if simulator else "")
    output.mkdir(parents=True, exist_ok=True)
    framework = output / "AdVanish.framework"
    if framework.exists():
        shutil.rmtree(framework)
    framework.mkdir()
    version = next(line.split(":", 1)[1].strip() for line in (ROOT / "control").read_text().splitlines()
                   if line.startswith("Version:"))
    info = {"CFBundleIdentifier": "com.maxblox2999.advanish.framework", "CFBundleExecutable": "AdVanish",
            "CFBundleName": "AdVanish", "CFBundlePackageType": "FMWK", "CFBundleVersion": version,
            "CFBundleShortVersionString": version, "MinimumOSVersion": "15.0",
            "CFBundleSupportedPlatforms": ["iPhoneSimulator" if simulator else "iPhoneOS"]}
    (framework / "Info.plist").write_bytes(plistlib.dumps(info))
    with tempfile.TemporaryDirectory(prefix="advanish-logos-") as directory:
        generated = Path(directory) / "Tweak.mm"
        with generated.open("w") as stream:
            subprocess.run(["perl", str(logos), "-c", "generator=internal", str(ROOT / "Tweak.xm")],
                           stdout=stream, check=True, timeout=60)
        command = ["xcrun", "--sdk", sdkname, "clang++", "-dynamiclib", "-fobjc-arc", "-fblocks",
                   "-std=c++11", "-fno-rtti", "-fno-exceptions", "-DNDEBUG", "-DADSPEED_JAILED=1",
                   "-isysroot", sdk, "-target", target, "-I", str(ROOT), "-I", str(theos / "include"),
                   "-install_name", "@rpath/AdVanish.framework/AdVanish", "-Wl,-headerpad_max_install_names",
                   str(generated)]
        command += [str(ROOT / name) for name in NATIVE]
        for name in FRAMEWORKS:
            command += ["-framework", name]
        command += ["-o", str(framework / "AdVanish")]
        subprocess.run(command, check=True, timeout=180)
    subprocess.run(["codesign", "--force", "--sign", "-", str(framework)], check=True, timeout=60)
    subprocess.run(["codesign", "--verify", "--strict", str(framework)], check=True, timeout=60)
    if not simulator:
        report = framework_report(framework)
        report["signature"] = "ad-hoc; re-sign with the app before installation"
        (output / "framework-check.json").write_text(json.dumps(report, indent=2) + "\n")
        commit_file = REPOSITORY / "SOURCE_COMMIT"
        commit = commit_file.read_text().strip() if commit_file.is_file() else subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
        toolchain = {
            "commit": commit,
            "variant": "jailed",
            "target": target,
            "sdk": sdk,
            "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "clang": subprocess.check_output(["xcrun", "--sdk", sdkname, "clang++", "--version"], text=True).strip(),
            "python": platform.python_version(),
            "theos_revision": subprocess.check_output(["git", "-C", str(theos), "rev-parse", "HEAD"], text=True).strip(),
        }
        (output / "build-info.json").write_text(json.dumps(toolchain, indent=2) + "\n")
        shutil.copy2(ROOT / "scripts/inject-ipa.py", output)
        shutil.copy2(ROOT / "scripts/sign-ipa.py", output)
        shutil.copy2(ROOT / "scripts/ipa_tools.py", output)
        with tempfile.TemporaryDirectory(prefix="advanish-release-") as directory:
            staging = Path(directory)
            shutil.copytree(framework, staging / framework.name)
            for name in ["framework-check.json", "build-info.json", "inject-ipa.py", "sign-ipa.py", "ipa_tools.py"]:
                shutil.copy2(output / name, staging / name)
            for name in ["LICENSE", "NOTICE.md"]:
                shutil.copy2(REPOSITORY / name, staging / name)
            shutil.copy2(ROOT / "licenses/GPL-3.0.txt", staging / "GPL-3.0.txt")
            archive = shutil.make_archive(str((output / "AdVanish-jailed").resolve()), "zip", staging)
        files = [Path(archive), output / "framework-check.json", output / "build-info.json", output / "inject-ipa.py", output / "sign-ipa.py", output / "ipa_tools.py"]
        (output / "SHA256SUMS").write_text("".join(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n" for path in files))
    return framework


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "dist/jailed")
    parser.add_argument("--simulator", action="store_true")
    args = parser.parse_args()
    print(build(args.output, args.simulator))
