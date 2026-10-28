# AdVanish contributions: Copyright (C) 2026 maxblox2999.
# GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

import importlib.util
import plistlib
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import ipa_tools

spec = importlib.util.spec_from_file_location("inject_ipa", ROOT / "scripts/inject-ipa.py")
inject_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inject_module)
sign_spec = importlib.util.spec_from_file_location("sign_ipa", ROOT / "scripts/sign-ipa.py")
sign_module = importlib.util.module_from_spec(sign_spec)
sign_spec.loader.exec_module(sign_module)
runner_spec = importlib.util.spec_from_file_location("ios_runner", ROOT / "scripts/test-ios.py")
runner_module = importlib.util.module_from_spec(runner_spec)
runner_spec.loader.exec_module(runner_module)


def dylib_command(name, command=0xC):
    encoded = name.encode() + b"\0"
    length = (24 + len(encoded) + 7) & ~7
    return struct.pack("<IIIIII", command, length, 24, 0, 0, 0) + encoded + bytes(length - 24 - len(encoded))


def image(*, kind=2, encrypted=False, signature=True, padding=True, subtype=0, extra=()):
    text = struct.pack("<II16sQQQQIIII", 0x19, 152, b"__TEXT", 0x100000000, 0x4000, 0, 1024, 5, 5, 1, 0)
    text += struct.pack("<16s16sQQIIIIIIII", b"__text", b"__TEXT", 0x100000200, 16, 512, 2, 0, 0, 0, 0, 0, 0)
    linkedit = struct.pack("<II16sQQQQIIII", 0x19, 72, b"__LINKEDIT", 0x100004000, 0x4000, 1024, 128, 1, 1, 0, 0)
    commands = [text, linkedit]
    commands += [struct.pack("<IIIIII", 0x32, 24, 2, 15 << 16, 18 << 16, 0)]
    if encrypted:
        commands += [struct.pack("<IIIIII", 0x2C, 24, 512, 16, 1, 0)]
    commands += list(extra)
    if signature:
        commands += [struct.pack("<IIII", 0x1D, 16, 1088, 64)]
    raw = b"".join(commands)
    header = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x100000C, subtype, kind, len(commands), len(raw), 0, 0)
    result = bytearray(header + raw + bytes(1152 - 32 - len(raw)))
    result[512:528] = b"actual code here"
    result[1088:] = struct.pack(">III", 0xFADE0CC0, 12, 0) + bytes(52)
    if not padding:
        result[32 + len(raw):512] = b"X" * (512 - 32 - len(raw))
    return bytes(result)


def framework(root):
    path = root / "AdVanish.framework"
    path.mkdir()
    (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "AdVanish", "CFBundlePackageType": "FMWK"}))
    data = image(kind=6, signature=False, extra=[dylib_command("@rpath/AdVanish.framework/AdVanish", 0xD),
                                               dylib_command("/usr/lib/libobjc.A.dylib")])
    (path / "AdVanish").write_bytes(data)
    return path


def ipa(path, data=None, entries=None):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Game.app/Info.plist", plistlib.dumps({"CFBundleExecutable": "Game", "CFBundleIdentifier": "com.example.game"}))
        archive.writestr("Payload/Game.app/Game", data or image())
        archive.writestr("Payload/Game.app/_CodeSignature/CodeResources", b"old signature")
        archive.writestr("Payload/Game.app/assets/file.dat", b"preserved asset")
        for name, value in entries or []:
            if isinstance(name, str):
                entry = zipfile.ZipInfo()
                entry.filename = name
                name = entry
            archive.writestr(name, value)


class MachOTests(unittest.TestCase):
    def test_preserves_code_removes_tail_signature_and_adds_load(self):
        before = image()
        after = ipa_tools.patch_executable(before)
        commands = ipa_tools.macho_commands(after, 2)
        self.assertEqual(after[512:1088], before[512:1088])
        self.assertEqual(len(after), 1088)
        self.assertNotIn(0x1D, [command for command, _, _ in commands])
        loads = [ipa_tools.dylib_name(after, offset, length) for command, offset, length in commands if command == 0xC]
        self.assertEqual(loads, [ipa_tools.LOAD_PATH])
        link = next(offset for command, offset, _ in commands if command == 0x19 and after[offset + 8:offset + 24].rstrip(b"\0") == b"__LINKEDIT")
        self.assertEqual(struct.unpack_from("<Q", after, link + 48)[0], 64)

    def test_unsigned_image(self):
        after = ipa_tools.patch_executable(image(signature=False))
        self.assertTrue(any(command == 0xC for command, _, _ in ipa_tools.macho_commands(after)))

    def test_rejects_encryption(self):
        with self.assertRaisesRegex(ValueError, "Encrypted executable"):
            ipa_tools.patch_executable(image(encrypted=True))

    def test_rejects_architecture(self):
        with self.assertRaisesRegex(ValueError, "plain arm64"):
            ipa_tools.patch_executable(image(subtype=2))
        with self.assertRaisesRegex(ValueError, "thin"):
            ipa_tools.patch_executable(b"\xca\xfe\xba\xbe" + bytes(200))

    def test_rejects_non_ios_device_platform(self):
        for platform in (1, 3, 6, 7):
            with self.subTest(platform=platform):
                data = bytearray(image())
                offset = next(offset for command, offset, _ in ipa_tools.macho_commands(data) if command == 0x32)
                struct.pack_into("<I", data, offset + 8, platform)
                with self.assertRaisesRegex(ValueError, "iOS device"):
                    ipa_tools.patch_executable(data)

    def test_rejects_nonzero_header_padding(self):
        with self.assertRaisesRegex(ValueError, "padding"):
            ipa_tools.patch_executable(image(padding=False))

    def test_rejects_duplicate_injection(self):
        with self.assertRaisesRegex(ValueError, "already injected"):
            ipa_tools.patch_executable(image(extra=[dylib_command(ipa_tools.LOAD_PATH)]))

    def test_rejects_out_of_bounds_signature(self):
        data = bytearray(image())
        offset = next(offset for command, offset, _ in ipa_tools.macho_commands(data) if command == 0x1D)
        struct.pack_into("<I", data, offset + 8, 5000)
        with self.assertRaisesRegex(ValueError, "tail code signature"):
            ipa_tools.patch_executable(data)

    def test_rejects_truncated_commands(self):
        for length in (0, 8, 32, 80, 200):
            with self.subTest(length=length), self.assertRaises(ValueError):
                ipa_tools.patch_executable(image()[:length])


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "game.ipa"
        self.output = self.root / "prepared.ipa"
        self.framework = framework(self.root)

    def tearDown(self):
        self.temporary.cleanup()

    def test_complete_injection_preserves_original_and_assets(self):
        ipa(self.source)
        original = self.source.read_bytes()
        report = inject_module.inject(self.source, self.framework, self.output)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertTrue(report["signing_required"])
        self.assertFalse(report["device_tested"])
        with zipfile.ZipFile(self.output) as result:
            self.assertEqual(result.read("Payload/Game.app/assets/file.dat"), b"preserved asset")
            self.assertIn("Payload/Game.app/Frameworks/AdVanish.framework/AdVanish", result.namelist())
            self.assertNotIn("Payload/Game.app/_CodeSignature/CodeResources", result.namelist())
            for name in ("Payload/Game.app/Game", "Payload/Game.app/Frameworks/AdVanish.framework/AdVanish"):
                self.assertEqual(result.getinfo(name).external_attr >> 16 & 0o777, 0o755)
                self.assertEqual(result.getinfo(name).create_system, 3)

    def test_rejects_overwriting_source_or_output(self):
        ipa(self.source)
        with self.assertRaisesRegex(ValueError, "new file"):
            inject_module.inject(self.source, self.framework, self.source)
        self.output.write_bytes(b"keep me")
        with self.assertRaises(ValueError):
            inject_module.inject(self.source, self.framework, self.output)
        self.assertEqual(self.output.read_bytes(), b"keep me")

    def test_rejects_unsafe_paths(self):
        for name in ("../outside", "/outside", "Payload/../outside", "C:/outside", "Payload\\outside", "Payload//outside"):
            with self.subTest(name=name):
                ipa(self.source, entries=[(name, b"bad")])
                with self.assertRaisesRegex(ValueError, "Unsafe archive path"):
                    inject_module.inject(self.source, self.framework, self.output)
                self.assertFalse(self.output.exists())

    def test_rejects_case_collisions(self):
        ipa(self.source, entries=[("Payload/Game.app/game", b"collision")])
        with self.assertRaisesRegex(ValueError, "colliding"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_rejects_symlinks(self):
        link = zipfile.ZipInfo("Payload/Game.app/link")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        ipa(self.source, entries=[(link, "../../outside")])
        with self.assertRaisesRegex(ValueError, "links"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_rejects_existing_framework(self):
        ipa(self.source, entries=[("Payload/Game.app/Frameworks/advanish.framework/existing", b"keep")])
        with self.assertRaisesRegex(ValueError, "already present"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_rejects_reserved_record_collision(self):
        ipa(self.source, entries=[("Payload/Game.app/advanish-original-entitlements.plist", b"existing asset")])
        with self.assertRaisesRegex(ValueError, "record is already present"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_embeds_validated_jailed_configuration(self):
        ipa(self.source)
        config = self.root / "settings.plist"
        values = {"AutomaticAds": False, "ManualSkip": True, "AutoInteract": True, "SpeedUpVideo": True}
        config.write_bytes(plistlib.dumps(values))
        inject_module.inject(self.source, self.framework, self.output, config)
        with zipfile.ZipFile(self.output) as result:
            self.assertEqual(plistlib.loads(result.read("Payload/Game.app/AdVanish.plist")), values)

    def test_rejects_invalid_configuration_without_output(self):
        ipa(self.source)
        config = self.root / "settings.plist"
        for values in ({"Unknown": True}, {"Enabled": 1}, {"AutomaticAds": 0}, [True]):
            config.write_bytes(plistlib.dumps(values))
            with self.assertRaisesRegex(ValueError, "supported boolean"):
                inject_module.inject(self.source, self.framework, self.output, config)
            self.assertFalse(self.output.exists())

    def test_rejects_configuration_asset_collision(self):
        ipa(self.source, entries=[("Payload/Game.app/advanish.plist", b"existing asset")])
        with self.assertRaisesRegex(ValueError, "configuration file is already present"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_rejects_file_parent_collisions(self):
        for entries in ([('Payload/Game.app/foo', b'file'), ('Payload/Game.app/foo/bar', b'child')],
                        [('Payload/Game.app/foo/bar', b'child'), ('Payload/Game.app/foo', b'file')]):
            ipa(self.source, entries=entries)
            with self.assertRaisesRegex(ValueError, "collides"):
                inject_module.inject(self.source, self.framework, self.output)

    def test_bounded_extraction(self):
        ipa(self.source)
        with patch.object(ipa_tools, "MAX_TOTAL", 100), self.assertRaisesRegex(ValueError, "size limits"):
            inject_module.inject(self.source, self.framework, self.output)

    def test_rejects_jailbreak_dependency(self):
        (self.framework / "AdVanish").write_bytes(image(kind=6, signature=False,
            extra=[dylib_command("@rpath/AdVanish.framework/AdVanish", 0xD), dylib_command("@rpath/libsubstrate.dylib")]))
        with self.assertRaisesRegex(ValueError, "non-system dependency"):
            ipa_tools.framework_report(self.framework)


class SigningPolicyTests(unittest.TestCase):
    def setUp(self):
        self.provision = {"TeamIdentifier": ["NEWTEAM"], "Entitlements": {
            "application-identifier": "NEWTEAM.com.example.game", "com.apple.developer.team-identifier": "NEWTEAM",
            "get-task-allow": True, "aps-environment": "development", "keychain-access-groups": ["NEWTEAM.*"]}}

    def test_preserves_authorized_capabilities(self):
        result, team = sign_module.signing_entitlements({"aps-environment": "development"}, self.provision, "com.example.game")
        self.assertEqual(result["aps-environment"], "development")
        self.assertEqual(result["application-identifier"], "NEWTEAM.com.example.game")
        self.assertEqual(team, "NEWTEAM")
        self.assertFalse(result["get-task-allow"])

    def test_rejects_missing_capability(self):
        with self.assertRaisesRegex(ValueError, "cannot preserve"):
            sign_module.signing_entitlements({"com.apple.developer.icloud-container-identifiers": ["iCloud.example"]}, self.provision, "com.example.game")

    def test_rejects_old_team_keychain_groups(self):
        with self.assertRaisesRegex(ValueError, "keychain-access-groups"):
            sign_module.signing_entitlements({"keychain-access-groups": ["OLDTEAM.com.example.game"]}, self.provision, "com.example.game")

    def test_accepts_authorized_group_wildcard(self):
        result, _ = sign_module.signing_entitlements({"keychain-access-groups": ["NEWTEAM.com.example.game"]}, self.provision, "com.example.game")
        self.assertEqual(result["keychain-access-groups"], ["NEWTEAM.com.example.game"])

    def test_rejects_profile_for_another_bundle(self):
        with self.assertRaisesRegex(ValueError, "exact bundle"):
            sign_module.signing_entitlements({}, self.provision, "com.someone.other")

    def test_rejects_wildcard_main_profile(self):
        self.provision["Entitlements"]["application-identifier"] = "NEWTEAM.*"
        with self.assertRaisesRegex(ValueError, "exact bundle"):
            sign_module.signing_entitlements({}, self.provision, "com.example.game")


class SimulatorRunnerTests(unittest.TestCase):
    def test_retries_initial_simulator_timeout_once(self):
        error = subprocess.TimeoutExpired(["xcrun", "simctl", "list", "-j"], 120)
        with patch.object(runner_module, "run", side_effect=[error, '{"runtimes": []}']) as command:
            self.assertEqual(runner_module.simulator_devices(), {"runtimes": []})
            self.assertEqual(command.call_count, 2)

    def test_second_startup_timeout_remains_a_failure(self):
        error = subprocess.TimeoutExpired(["xcrun", "simctl", "list", "-j"], 120)
        with patch.object(runner_module, "run", side_effect=error) as command:
            with self.assertRaises(subprocess.TimeoutExpired):
                runner_module.simulator_devices()
            self.assertEqual(command.call_count, 2)

    def test_does_not_retry_command_failures(self):
        error = subprocess.CalledProcessError(1, ["xcrun", "simctl", "list", "-j"])
        with patch.object(runner_module, "run", side_effect=error) as command:
            with self.assertRaises(subprocess.CalledProcessError):
                runner_module.simulator_devices()
            command.assert_called_once()

    def test_failed_startup_cannot_leave_a_passing_report(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "result.json"
            output.write_text('{"passed": true}')
            error = subprocess.CalledProcessError(1, ["xcrun"])
            with patch.object(runner_module, "run", side_effect=error), self.assertRaises(subprocess.CalledProcessError):
                runner_module.main(Path(directory) / "fixture.mp4", output, True)
            self.assertFalse(output.exists())

    def test_source_archive_revision_is_read_from_repository_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "project"
            project.mkdir()
            revision = "b" * 40
            (root / "SOURCE_COMMIT").write_text(revision + "\n")
            with patch.object(runner_module, "ROOT", project), patch.object(runner_module, "run") as command:
                self.assertEqual(runner_module.source_commit(), revision)
                command.assert_not_called()


if __name__ == "__main__":
    unittest.main()
