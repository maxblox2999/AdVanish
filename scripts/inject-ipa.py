#!/usr/bin/env python3
import argparse
import json
import plistlib
import shutil
import tempfile
from pathlib import Path
from ipa_tools import application_executable, extract_ipa, file_hash, framework_report, original_entitlements, patch_executable, write_ipa

CONFIG_KEYS = {"Enabled", "ManualSkip", "SpeedUpVideo", "CompressTimers", "AccelerateClock", "ForceInline",
               "SpeedNativeVideo", "AutoInteract", "AutoDismiss", "BlockRedirects"}


def load_config(path):
    if path.stat().st_size > 65536:
        raise ValueError("Configuration exceeds 64 KiB")
    values = plistlib.loads(path.read_bytes())
    if not isinstance(values, dict) or any(key not in CONFIG_KEYS or type(value) is not bool for key, value in values.items()):
        raise ValueError("Configuration must contain supported boolean settings only")
    return values


def inject(source, framework, output, config=None):
    source = source.resolve()
    output = output.resolve()
    if source == output or output.exists():
        raise ValueError("Output must be a new file; the original IPA is never overwritten")
    settings = load_config(config) if config else None
    if framework.is_symlink():
        raise ValueError("Framework links are unsupported")
    report = framework_report(framework)
    for path in framework.rglob("*"):
        if path.is_symlink() or (not path.is_file() and not path.is_dir()):
            raise ValueError("Framework links and special files are unsupported")
    with tempfile.TemporaryDirectory(prefix="advanish-inject-") as directory:
        root = Path(directory)
        modes = {}
        app = extract_ipa(source, root, modes)
        binary, info = application_executable(app)
        destination = app / "Frameworks/AdVanish.framework"
        if any(path.name.casefold() == "advanish.framework" for path in app.rglob("*")):
            raise ValueError("An AdVanish framework is already present")
        entitlement_file = app / "AdVanish-original-entitlements.plist"
        if any(path.name.casefold() == entitlement_file.name.casefold() for path in app.iterdir()):
            raise ValueError("An AdVanish preparation record is already present")
        config_file = app / "AdVanish.plist"
        if any(path.name.casefold() == config_file.name.casefold() for path in app.iterdir()):
            raise ValueError("An AdVanish configuration file is already present")
        original = binary.read_bytes()
        entitlements = original_entitlements(original)
        modified = patch_executable(original)
        destination.parent.mkdir(exist_ok=True)
        shutil.copytree(framework, destination)
        binary.write_bytes(modified)
        binary.chmod(0o755)
        entitlement_file.write_bytes(plistlib.dumps(entitlements))
        if settings is not None:
            config_file.write_bytes(plistlib.dumps(settings))
        modes[binary.relative_to(root).as_posix()] = 0o755
        modes[(destination / "AdVanish").relative_to(root).as_posix()] = 0o755
        signature = app / "_CodeSignature"
        if signature.is_dir():
            shutil.rmtree(signature)
        output.parent.mkdir(parents=True, exist_ok=True)
        try:
            write_ipa(root, output, modes)
        except BaseException:
            output.unlink(missing_ok=True)
            raise
    return {"input_sha256": file_hash(source),
            "output_sha256": file_hash(output),
            "bundle_id": info.get("CFBundleIdentifier"), "framework": report,
            "signing_required": True, "device_tested": False,
            "note": "Prepared IPA only. Re-sign the app and every embedded code bundle before installation."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Prepare an authorized decrypted arm64 IPA for re-signing")
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--framework", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--config", type=Path, help="Optional plist of boolean AdVanish settings")
    args = parser.parse_args()
    print(json.dumps(inject(args.ipa, args.framework, args.output, args.config), indent=2))
