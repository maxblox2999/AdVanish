#!/usr/bin/env python3
# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

import argparse
import hashlib
import io
import json
import struct
import tarfile
from pathlib import Path, PurePosixPath


def ar_members(data):
    if not data.startswith(b"!<arch>\n"):
        raise ValueError("Not a Debian ar archive")
    result = {}
    cursor = 8
    while cursor < len(data):
        header = data[cursor:cursor + 60]
        if len(header) != 60 or header[58:] != b"`\n":
            raise ValueError("Truncated ar header")
        name = header[:16].decode("ascii").strip().removesuffix("/")
        size = int(header[48:58])
        cursor += 60
        if size < 0 or cursor + size > len(data) or name in result:
            raise ValueError("Invalid ar member bounds or duplicate member")
        result[name] = data[cursor:cursor + size]
        cursor += size + size % 2
    return result


def tar_files(data):
    result = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:*") as archive:
        total = 0
        for member in archive:
            path = PurePosixPath(member.name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe package member path")
            if not member.isfile():
                continue
            total += member.size
            if member.size > 8 * 1024 * 1024 or total > 32 * 1024 * 1024:
                raise ValueError("Package exceeds inspection size limits")
            name = str(path)
            if name in result:
                raise ValueError("Duplicate package file")
            result[name] = archive.extractfile(member).read()
    return result


def macho_slices(data):
    pieces = []
    if data[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
        wide = data[:4] == b"\xca\xfe\xba\xbf"
        count = struct.unpack_from(">I", data, 4)[0]
        if not 1 <= count <= 8:
            raise ValueError("Invalid fat architecture count")
        for index in range(count):
            record = 8 + index * (32 if wide else 20)
            start, size = struct.unpack_from(">QQ" if wide else ">II", data, record + 8)
            if start + size > len(data):
                raise ValueError("Fat slice exceeds file")
            pieces.append(data[start:start + size])
    else:
        pieces.append(data)
    results = []
    for piece in pieces:
        if piece[:4] != b"\xcf\xfa\xed\xfe" or len(piece) < 32:
            raise ValueError("Expected a little-endian 64-bit Mach-O")
        cpu, subtype, filetype, count, command_size = struct.unpack_from("<IIIII", piece, 4)
        if cpu != 0x100000C or 32 + command_size > len(piece):
            raise ValueError("Unexpected CPU or command bounds")
        architecture = "arm64e" if subtype & 0xFFFFFF == 2 else "arm64"
        cursor = 32
        minimum = None
        signature = False
        dylibs = []
        for _ in range(count):
            command, size = struct.unpack_from("<II", piece, cursor)
            if size < 8 or cursor + size > 32 + command_size:
                raise ValueError("Invalid Mach-O load command")
            if command == 0x32:
                minimum = struct.unpack_from("<I", piece, cursor + 12)[0]
            elif command == 0x25:
                minimum = struct.unpack_from("<I", piece, cursor + 8)[0]
            elif command == 0x1D:
                offset, length = struct.unpack_from("<II", piece, cursor + 8)
                signature = length > 0 and offset + length <= len(piece)
            elif command in (0xC, 0x80000018, 0x8000001F, 0x80000023):
                offset = struct.unpack_from("<I", piece, cursor + 8)[0]
                if offset >= size:
                    raise ValueError("Invalid dylib name offset")
                name = piece[cursor + offset:cursor + size].split(b"\0", 1)[0].decode("utf-8")
                dylibs.append(name)
            cursor += size
        if cursor != 32 + command_size or minimum != 15 << 16 or not signature:
            raise ValueError("Expected iOS 15 deployment minimum and a code-signature command")
        results.append({"architecture": architecture, "filetype": filetype,
                        "minimum_ios": "15.0", "code_signature_command": signature, "dylibs": dylibs})
    if sorted(item["architecture"] for item in results) != ["arm64", "arm64e"]:
        raise ValueError("Both arm64 and arm64e slices are required")
    return results


def verify(path, variant, package_id, library):
    if path.stat().st_size > 32 * 1024 * 1024:
        raise ValueError("Unexpectedly large tweak package")
    data = path.read_bytes()
    members = ar_members(data)
    if members.get("debian-binary") != b"2.0\n":
        raise ValueError("Unsupported Debian package version")
    control_name = [name for name in members if name.startswith("control.tar")]
    data_name = [name for name in members if name.startswith("data.tar")]
    if len(control_name) != 1 or len(data_name) != 1:
        raise ValueError("Expected one control and one data archive")
    control = tar_files(members[control_name[0]])["control"].decode("utf-8")
    fields = dict(line.split(": ", 1) for line in control.splitlines() if ": " in line)
    expected_arch = {"rootless": "iphoneos-arm64", "rootful": "iphoneos-arm", "roothide": "iphoneos-arm64e"}[variant]
    if fields.get("Package") != package_id or fields.get("Architecture") != expected_arch:
        raise ValueError("Wrong package identity or Debian architecture")
    files = tar_files(members[data_name[0]])
    prefix = "var/jb/" if variant == "rootless" else ""
    if variant == "rootless" and any(not name.startswith(prefix) for name in files):
        raise ValueError("Rootless package has files outside /var/jb")
    if variant in ("rootful", "roothide") and any(name.startswith("var/jb/") for name in files):
        raise ValueError("Package contains a fixed rootless installation path")
    binaries = {}
    for name in [prefix + "Library/MobileSubstrate/DynamicLibraries/" + library + ".dylib",
                 prefix + "Library/PreferenceBundles/adspeedprefs.bundle/adspeedprefs"]:
        binaries[name] = macho_slices(files[name])
    library_path = prefix + "Library/MobileSubstrate/DynamicLibraries/" + library + ".dylib"
    for image in binaries[library_path]:
        if not any("/UIKit.framework/" in name for name in image["dylibs"]):
            raise ValueError("Missing UIKit runtime dependency")
        loads = [name for name in image["dylibs"] if "substrate" in name.lower()]
        if variant == "rootless" and any(not name.startswith("@rpath/") for name in loads):
            raise ValueError("Unexpected tweak-loader linkage")
        if variant == "roothide" and any(not name.startswith("@loader_path/.jbroot/") for name in loads):
            raise ValueError("RootHide requires relocated tweak-loader linkage")
    if variant == "roothide":
        for images in binaries.values():
            for image in images:
                if "@loader_path/.jbroot/usr/lib/libroothide.dylib" not in image["dylibs"]:
                    raise ValueError("RootHide path support is missing")
                if any(name.startswith("/var/jb/") for name in image["dylibs"]):
                    raise ValueError("RootHide links to a fixed rootless path")
    return {"package": path.name, "sha256": hashlib.sha256(data).hexdigest(),
            "variant": variant, "control": fields, "file_count": len(files), "binaries": binaries,
            "limits": "Static package checks only; signature command presence is not cryptographic or device validation."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("variant", choices=["rootless", "rootful", "roothide"])
    parser.add_argument("--package-id", default="com.maxblox2999.advanish")
    parser.add_argument("--library", default="advanish")
    args = parser.parse_args()
    print(json.dumps(verify(args.package, args.variant, args.package_id, args.library), indent=2))
