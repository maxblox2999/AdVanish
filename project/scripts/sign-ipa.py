#!/usr/bin/env python3
# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

"""Optional local macOS signing for a single app and its embedded frameworks."""
import argparse
import datetime
import json
import platform
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path
from ipa_tools import application_executable, extract_ipa, write_ipa


def permits(requested, allowed):
    if isinstance(requested, str) and isinstance(allowed, str):
        return requested == allowed or (allowed.endswith("*") and requested.startswith(allowed[:-1]))
    if isinstance(requested, list) and isinstance(allowed, list):
        return all(any(permits(item, candidate) for candidate in allowed) for item in requested)
    if isinstance(requested, dict) and isinstance(allowed, dict):
        return all(key in allowed and permits(value, allowed[key]) for key, value in requested.items())
    return type(requested) is type(allowed) and requested == allowed


def signing_entitlements(original, provision, bundle_id):
    allowed = provision.get("Entitlements", {})
    teams = provision.get("TeamIdentifier", [])
    app_id = allowed.get("application-identifier", "")
    if len(teams) != 1 or not bundle_id or app_id != teams[0] + "." + bundle_id:
        raise ValueError("Use a provisioning profile for this exact bundle identifier")
    result = original.copy()
    identity_keys = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow"}
    for key, value in original.items():
        if key not in identity_keys and (key not in allowed or not permits(value, allowed[key])):
            raise ValueError("The profile cannot preserve the app capability: " + key)
    result["application-identifier"] = app_id
    result["com.apple.developer.team-identifier"] = teams[0]
    result["get-task-allow"] = False
    return result, teams[0]


def verify_team(path, team):
    details = subprocess.run(["codesign", "-dvv", str(path)], check=True, capture_output=True, text=True, timeout=30)
    values = dict(line.split("=", 1) for line in details.stderr.splitlines() if "=" in line)
    if values.get("TeamIdentifier") != team:
        raise ValueError("Signed component TeamIdentifier does not match the profile")


def sign(source, output, identity, profile):
    if platform.system() != "Darwin":
        raise RuntimeError("Signing requires macOS and an identity in your login keychain")
    if identity == "-" or not identity.strip():
        raise ValueError("A real Apple signing identity is required")
    if source.resolve() == output.resolve() or output.exists():
        raise ValueError("Output must be a new file")
    decoded = subprocess.check_output(["security", "cms", "-D", "-i", str(profile)], timeout=30)
    provision = plistlib.loads(decoded)
    expiration = provision.get("ExpirationDate")
    if not expiration or expiration <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("Provisioning profile is expired")
    with tempfile.TemporaryDirectory(prefix="advanish-sign-") as directory:
        root = Path(directory)
        modes = {}
        app = extract_ipa(source, root, modes)
        _, info = application_executable(app)
        if any(path.is_dir() and path.suffix in (".appex", ".app") for path in app.rglob("*")):
            raise ValueError("Extensions and nested apps need their own profiles; use your signing tool")
        bundle_id = info.get("CFBundleIdentifier", "")
        record = app / "AdVanish-original-entitlements.plist"
        if not record.is_file():
            raise ValueError("Prepare this IPA with inject-ipa.py first")
        entitlements, team = signing_entitlements(plistlib.loads(record.read_bytes()), provision, bundle_id)
        entitlements_file = root / "entitlements.plist"
        entitlements_file.write_bytes(plistlib.dumps(entitlements))
        shutil.copyfile(profile, app / "embedded.mobileprovision")
        for library in app.rglob("*.dylib"):
            subprocess.run(["codesign", "--force", "--sign", identity, "--timestamp=none", str(library)], check=True, timeout=60)
            verify_team(library, team)
        frameworks = sorted(app.rglob("*.framework"), key=lambda path: len(path.parts), reverse=True)
        for framework in frameworks:
            subprocess.run(["codesign", "--force", "--sign", identity, "--timestamp=none", str(framework)], check=True, timeout=60)
            verify_team(framework, team)
        subprocess.run(["codesign", "--force", "--sign", identity, "--timestamp=none", "--entitlements", str(entitlements_file), str(app)], check=True, timeout=120)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, timeout=60)
        verify_team(app, team)
        certificate_prefix = root / "signing-certificate-"
        subprocess.run(["codesign", "-d", "--extract-certificates", str(certificate_prefix), str(app)], check=True, timeout=30)
        leaf = Path(str(certificate_prefix) + "0")
        if not leaf.is_file() or leaf.read_bytes() not in provision.get("DeveloperCertificates", []):
            raise ValueError("The signing certificate is not included in this provisioning profile")
        for certificate in root.glob("signing-certificate-*"):
            certificate.unlink()
        entitlements_file.unlink()
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            write_ipa(root, output, modes)
        except BaseException:
            output.unlink(missing_ok=True)
            raise
    return {"output": str(output), "signature_verified_locally": True,
            "provisioning_team_and_certificate_checked": True,
            "device_installation_tested": False, "bundle_id": bundle_id}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--identity", required=True)
    parser.add_argument("--profile", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(sign(args.ipa, args.output, args.identity, args.profile), indent=2))
