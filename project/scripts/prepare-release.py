# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
"""Validate Actions artifacts and stage a test release."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "project"
SHA = os.environ["GITHUB_SHA"]
RUN = os.environ["GITHUB_RUN_ID"]
INCOMING = ROOT / "incoming"
OUTPUT = ROOT / "release"
VERSION = "0.5.2"
OUTPUT.mkdir(exist_ok=True)
reports = {}
native = {}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

for variant in ["rootless", "rootful", "roothide", "jailed"]:
    folder = INCOMING / ("advanish-" + variant + "-" + SHA)
    assert folder.is_dir(), variant
    for line in (folder / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split(None, 1)
        path = folder / name.strip().removeprefix("./")
        assert path.resolve().is_relative_to(folder.resolve())
        assert digest(path) == expected
    if variant == "jailed":
        payload = folder / "AdVanish-jailed.zip"
        reports[variant] = json.loads((folder / "framework-check.json").read_text())
        with zipfile.ZipFile(payload) as archive:
            assert archive.testzip() is None
            assert archive.read("LICENSE") == (ROOT / "LICENSE").read_bytes()
            assert archive.read("NOTICE.md") == (ROOT / "NOTICE.md").read_bytes()
            info = json.loads(archive.read("build-info.json"))
            assert info["commit"] == SHA and info["hook_engine"] == "Objective-C runtime"
        shutil.copyfile(payload, OUTPUT / ("AdVanish-" + VERSION + "-jailed.zip"))
        for key, name, count in [
            ("injected", "ios-injected.json", 18),
            ("manual", "ios-injected-manual.json", 23),
        ]:
            report = json.loads((folder / name).read_text())
            assert report["passed"] and report["source_commit"] == SHA
            assert report["injected_framework"] and len(report["checks"]) >= count
            assert report["manual_mode"] == (key == "manual")
            native[key] = report
    else:
        packages = list(folder.glob("*.deb"))
        assert len(packages) == 1
        report = json.loads(subprocess.check_output([
            sys.executable, str(PROJECT / "scripts/verify-package.py"),
            str(packages[0]), variant
        ], text=True))
        assert report["control"]["Version"] == VERSION
        reports[variant] = report
        info = (folder / "build-info.txt").read_text()
        assert ("commit=" + SHA + "\n") in info
        shutil.copyfile(packages[0], OUTPUT / ("AdVanish-" + VERSION + "-" + variant + ".deb"))
        if variant == "rootless":
            report = json.loads((folder / "ios-simulator.json").read_text())
            assert report["passed"] and report["source_commit"] == SHA
            assert len(report["checks"]) >= 71
            native["helpers"] = report
            settings_report = json.loads((folder / "ios-settings.json").read_text())
            assert settings_report["passed"] and settings_report["source_commit"] == SHA
            assert settings_report["settings_controller"] and len(settings_report["checks"]) >= 15
            native["settings"] = settings_report

source_folder = INCOMING / ("advanish-source-" + SHA)
source = source_folder / "AdVanish-source.tar.gz"
expected = (source_folder / "SHA256SUMS").read_text().split()[0]
assert digest(source) == expected
with tarfile.open(source, "r:gz") as archive:
    files = {m.name: archive.extractfile(m).read() for m in archive if m.isfile()}
assert files["AdVanish/SOURCE_COMMIT"].decode().strip() == SHA
tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
for name in filter(None, tracked):
    assert files["AdVanish/" + name] == (ROOT / name).read_bytes(), name
shutil.copyfile(source, OUTPUT / ("AdVanish-" + VERSION + "-source.tar.gz"))
with zipfile.ZipFile(OUTPUT / ("AdVanish-" + VERSION + "-source.zip"), "w", zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(files.items()):
        archive.writestr(name, data)

browser = json.loads((source_folder / "browser.json").read_text())
assert browser["passed"] >= 34
assert browser["sourceSha256"] == hashlib.sha256((PROJECT / "web/adspeed.js").read_bytes()).hexdigest()
validation = {
    "node_tests": 124, "ipa_tool_tests": 39, "browser": browser,
    "version": VERSION, "commit": SHA,
    "workflow": "https://github.com/maxblox2999/AdVanish/actions/runs/" + RUN,
    "packages": reports, "ios_simulator": native,
    "complete_source_matches_repository": True,
    "physical_iphone_tested": False, "real_sdk_rewards_verified": False,
    "signed_device_injection_verified": False, "physical_roothide_tested": False,
    "cyanide_quickloader_supported": False,
    "limits": "Simulator SDK events are mocked. Real games, rewards and physical device loaders remain unverified."
}
(OUTPUT / ("AdVanish-" + VERSION + "-validation.json")).write_text(json.dumps(validation, indent=2) + "\n")
assets = sorted(OUTPUT.iterdir())
assert len(assets) == 7
(OUTPUT / "SHA256SUMS").write_text("".join(digest(p) + "  " + p.name + "\n" for p in assets))
print(json.dumps({"commit": SHA, "assets": 8, "native_checks": {k: len(v["checks"]) for k,v in native.items()}}))
