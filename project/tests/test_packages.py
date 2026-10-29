# AdVanish contributions: Copyright (C) 2026 maxblox2999.
# GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

import importlib.util
import io
from pathlib import Path
import struct
import tarfile
import tempfile
import unittest
from test_ipa import dylib_command, image

spec = importlib.util.spec_from_file_location("package_verifier", Path(__file__).resolve().parents[1] / "scripts/verify-package.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


def archive(files):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as stream:
        for name, data in files.items():
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            stream.addfile(entry, io.BytesIO(data))
    return output.getvalue()


def fat(loads):
    pieces = [image(kind=6, subtype=subtype, extra=tuple(dylib_command(name) for name in loads)) for subtype in (0, 2)]
    header = struct.pack(">II", 0xCAFEBABE, 2)
    offset = 48
    for subtype, piece in zip((0, 2), pieces):
        header += struct.pack(">IIIII", 0x100000C, subtype, offset, len(piece), 0)
        offset += len(piece)
    return header + b"".join(pieces)


def package(architecture, prefix, substrate, root_api):
    loads = [substrate] + ([root_api] if root_api else [])
    files = {
        prefix + "Library/MobileSubstrate/DynamicLibraries/advanish.dylib": fat(loads),
        prefix + "Library/PreferenceBundles/adspeedprefs.bundle/adspeedprefs": fat([root_api] if root_api else []),
    }
    control = f"Package: com.maxblox2999.advanish\nVersion: 0.4.0\nArchitecture: {architecture}\n".encode()
    members = {"debian-binary": b"2.0\n", "control.tar.gz": archive({"control": control}), "data.tar.gz": archive(files)}
    output = b"!<arch>\n"
    for name, data in members.items():
        header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{100644:<8}{len(data):<10}`\n".encode()
        output += header + data + (b"\n" if len(data) % 2 else b"")
    return output


class PackageTests(unittest.TestCase):
    def verify(self, data, variant):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.deb"
            path.write_bytes(data)
            return verifier.verify(path, variant, "com.maxblox2999.advanish", "advanish")

    def test_roothide_relocated_dependencies(self):
        data = package("iphoneos-arm64e", "", "@loader_path/.jbroot/usr/lib/libsubstrate.dylib", "@loader_path/.jbroot/usr/lib/libroothide.dylib")
        self.assertEqual(self.verify(data, "roothide")["variant"], "roothide")

    def test_roothide_rejects_renamed_rootless_package(self):
        data = package("iphoneos-arm64", "var/jb/", "@rpath/libsubstrate.dylib", None)
        with self.assertRaises(ValueError):
            self.verify(data, "roothide")

    def test_roothide_rejects_fixed_root(self):
        data = package("iphoneos-arm64e", "var/jb/", "@loader_path/.jbroot/usr/lib/libsubstrate.dylib", "@loader_path/.jbroot/usr/lib/libroothide.dylib")
        with self.assertRaises(ValueError):
            self.verify(data, "roothide")

    def test_roothide_rejects_fixed_loader(self):
        data = package("iphoneos-arm64e", "", "/usr/lib/libsubstrate.dylib", "@loader_path/.jbroot/usr/lib/libroothide.dylib")
        with self.assertRaises(ValueError):
            self.verify(data, "roothide")

    def test_roothide_requires_path_library(self):
        data = package("iphoneos-arm64e", "", "@loader_path/.jbroot/usr/lib/libsubstrate.dylib", None)
        with self.assertRaises(ValueError):
            self.verify(data, "roothide")

    def test_existing_package_schemes(self):
        for variant, architecture, prefix, loader in [
            ("rootless", "iphoneos-arm64", "var/jb/", "@rpath/libsubstrate.dylib"),
            ("rootful", "iphoneos-arm", "", "/usr/lib/libsubstrate.dylib"),
        ]:
            self.assertEqual(self.verify(package(architecture, prefix, loader, None), variant)["variant"], variant)


if __name__ == "__main__":
    unittest.main()
