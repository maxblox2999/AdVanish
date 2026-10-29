# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

"""Bounded IPA preparation. Never modifies the supplied archive or decrypts code."""
import hashlib
import plistlib
import stat
import struct
import unicodedata
import zipfile
from pathlib import Path, PurePosixPath

LOAD_PATH = "@executable_path/Frameworks/AdVanish.framework/AdVanish"
MAX_FILE = 2 * 1024 ** 3
MAX_TOTAL = 8 * 1024 ** 3


def safe_name(name):
    path = PurePosixPath(name)
    if (not name or "\\" in name or "\0" in name or ":" in name or
            path.is_absolute() or any(part in ("", ".", "..") for part in name.rstrip("/").split("/"))):
        raise ValueError("Unsafe archive path")
    return path


def extract_ipa(source, target, modes=None):
    seen = set()
    files = set()
    directories = set()
    total = 0
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        if len(entries) > 100000:
            raise ValueError("Too many archive members")
        for entry in entries:
            path = safe_name(entry.orig_filename)
            key = unicodedata.normalize("NFC", str(path)).casefold()
            if key in seen:
                raise ValueError("Duplicate or case-colliding archive path")
            parents = {unicodedata.normalize("NFC", str(parent)).casefold() for parent in path.parents}
            if parents & files:
                raise ValueError("Archive file collides with a parent directory")
            if not entry.is_dir() and key in directories:
                raise ValueError("Archive file collides with a directory")
            seen.add(key)
            directories.update(parents)
            mode = entry.external_attr >> 16
            if stat.S_ISLNK(mode) or (stat.S_IFMT(mode) not in (0, stat.S_IFREG, stat.S_IFDIR)):
                raise ValueError("Archive links and special files are unsupported")
            if entry.flag_bits & 1:
                raise ValueError("Encrypted ZIP archives are unsupported")
            total += entry.file_size
            if entry.file_size > MAX_FILE or total > MAX_TOTAL:
                raise ValueError("Archive exceeds size limits")
            destination = target.joinpath(*path.parts)
            if entry.is_dir():
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            files.add(key)
            permissions = mode & 0o777 if mode & 0o777 else 0o644
            if modes is not None:
                modes[str(path)] = permissions
            with archive.open(entry) as incoming, destination.open("xb") as outgoing:
                copied = 0
                while chunk := incoming.read(1024 * 1024):
                    copied += len(chunk)
                    if copied > entry.file_size or copied > MAX_FILE:
                        raise ValueError("Archive member exceeds declared size")
                    outgoing.write(chunk)
                if copied != entry.file_size:
                    raise ValueError("Truncated archive member")
            destination.chmod(permissions)
    apps = list((target / "Payload").glob("*.app"))
    if len(apps) != 1 or not apps[0].is_dir():
        raise ValueError("Expected exactly one Payload application")
    return apps[0]


def macho_commands(data, filetype=None):
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Only thin little-endian arm64 Mach-O images are supported")
    cpu, subtype, kind, count, size = struct.unpack_from("<IIIII", data, 4)
    if cpu != 0x100000C or subtype & 0xFFFFFF != 0:
        raise ValueError("A plain arm64 image is required")
    if filetype is not None and kind != filetype:
        raise ValueError("Unexpected Mach-O image type")
    if count > 16384 or 32 + size > len(data):
        raise ValueError("Invalid Mach-O load-command bounds")
    cursor = 32
    commands = []
    for _ in range(count):
        if cursor + 8 > 32 + size:
            raise ValueError("Truncated Mach-O command")
        command, length = struct.unpack_from("<II", data, cursor)
        if length < 8 or length % 8 or cursor + length > 32 + size:
            raise ValueError("Invalid Mach-O load command")
        commands.append((command, cursor, length))
        cursor += length
    if cursor != 32 + size:
        raise ValueError("Mach-O load-command size mismatch")
    return commands


def dylib_name(data, offset, length):
    if length < 24:
        raise ValueError("Truncated dylib command")
    start = struct.unpack_from("<I", data, offset + 8)[0]
    if start < 24 or start >= length:
        raise ValueError("Invalid dylib name offset")
    value = data[offset + start:offset + length]
    if b"\0" not in value:
        raise ValueError("Unterminated dylib name")
    return value.split(b"\0", 1)[0].decode("utf-8")


def framework_report(framework):
    info = plistlib.loads((framework / "Info.plist").read_bytes())
    if info.get("CFBundleExecutable") != "AdVanish" or info.get("CFBundlePackageType") != "FMWK":
        raise ValueError("Unexpected framework identity")
    data = (framework / "AdVanish").read_bytes()
    commands = macho_commands(data, 6)
    minimum = None
    identity = None
    dependencies = []
    for command, offset, length in commands:
        if command == 0x32:
            if length < 24 or struct.unpack_from("<I", data, offset + 8)[0] != 2:
                raise ValueError("Framework must target physical iOS")
            minimum = struct.unpack_from("<I", data, offset + 12)[0]
        elif command == 0x25:
            minimum = struct.unpack_from("<I", data, offset + 8)[0]
        elif command == 0xD:
            identity = dylib_name(data, offset, length)
        elif command in (0xC, 0x80000018, 0x8000001F, 0x80000023):
            dependency = dylib_name(data, offset, length)
            dependencies.append(dependency)
            if not dependency.startswith(("/System/Library/Frameworks/", "/usr/lib/")) or "PrivateFrameworks" in dependency:
                raise ValueError("Jailed framework contains a non-system dependency")
    if minimum != 15 << 16 or identity != "@rpath/AdVanish.framework/AdVanish":
        raise ValueError("Unexpected framework deployment target or install name")
    return {"architecture": "arm64", "minimum_ios": "15.0", "dependencies": dependencies,
            "sha256": hashlib.sha256(data).hexdigest(), "device_tested": False}


def patch_executable(data):
    """Add a load command using verified zero padding; remove an old tail signature."""
    commands = macho_commands(data, 2)
    command_end = 32 + struct.unpack_from("<I", data, 20)[0]
    first_content = len(data)
    signature = None
    linkedit = None
    device_platform = False
    kept = []
    for command, offset, length in commands:
        if command == 0x32:
            if length < 24 or struct.unpack_from("<I", data, offset + 8)[0] != 2:
                raise ValueError("Executable must target an iOS device")
            device_platform = True
        elif command == 0x25:
            if length < 16:
                raise ValueError("Truncated iOS deployment command")
            device_platform = True
        if command in (0x21, 0x2C):
            if length < 20 or struct.unpack_from("<I", data, offset + 16)[0]:
                raise ValueError("Encrypted executable: supply an authorized decrypted IPA")
        if command == 0x19:
            if length < 72:
                raise ValueError("Truncated segment command")
            fileoff, filesize = struct.unpack_from("<QQ", data, offset + 40)
            sections = struct.unpack_from("<I", data, offset + 64)[0]
            if 72 + sections * 80 > length or fileoff + filesize > len(data):
                raise ValueError("Invalid segment bounds")
            if fileoff:
                first_content = min(first_content, fileoff)
            for index in range(sections):
                section = offset + 72 + index * 80
                section_size = struct.unpack_from("<Q", data, section + 40)[0]
                section_offset = struct.unpack_from("<I", data, section + 48)[0]
                flags = struct.unpack_from("<I", data, section + 64)[0] & 0xFF
                if section_size and flags not in (1, 0xC, 0x12):
                    if section_offset < command_end or section_offset + section_size > len(data):
                        raise ValueError("Invalid file-backed section bounds")
                    first_content = min(first_content, section_offset)
            if data[offset + 8:offset + 24].rstrip(b"\0") == b"__LINKEDIT":
                linkedit = (offset, fileoff, filesize)
        if command in (0xC, 0x80000018, 0x8000001F, 0x80000023) and dylib_name(data, offset, length) == LOAD_PATH:
            raise ValueError("AdVanish is already injected")
        if command == 0x1D:
            if signature or length != 16:
                raise ValueError("Invalid code-signature command")
            signature = struct.unpack_from("<II", data, offset + 8)
        else:
            kept.append((command, offset, data[offset:offset + length]))
    if not device_platform:
        raise ValueError("Executable must declare an iOS device platform")
    if first_content <= command_end or not any(command == 0x19 for command, _, _ in commands):
        raise ValueError("Executable has no safe header padding")
    payload = LOAD_PATH.encode() + b"\0"
    length = (24 + len(payload) + 7) & ~7
    new_command = struct.pack("<IIIIII", 0xC, length, 24, 0, 0, 0) + payload
    new_command += b"\0" * (length - len(new_command))
    if signature:
        start, size = signature
        if not size or start < first_content or start + size != len(data) or not linkedit:
            raise ValueError("Only a bounded tail code signature can be removed")
        _, fileoff, filesize = linkedit
        if fileoff + filesize != len(data) or start < fileoff:
            raise ValueError("Unexpected signed __LINKEDIT layout")
        updated = []
        for command, offset, raw in kept:
            if offset == linkedit[0]:
                raw = bytearray(raw)
                remaining = start - fileoff
                struct.pack_into("<Q", raw, 48, remaining)
                struct.pack_into("<Q", raw, 32, (remaining + 0x3FFF) & ~0x3FFF)
                raw = bytes(raw)
            updated.append((command, offset, raw))
        kept = updated
        data = data[:start]
    encoded = b"".join(raw for _, _, raw in kept) + new_command
    end = 32 + len(encoded)
    if end > first_content or any(data[command_end:end]):
        raise ValueError("Insufficient zero-filled Mach-O header padding")
    result = bytearray(data)
    result[32:max(command_end, end)] = encoded + b"\0" * (max(command_end, end) - end)
    struct.pack_into("<II", result, 16, len(kept) + 1, len(encoded))
    return bytes(result)


def write_ipa(root, output, modes=None):
    with zipfile.ZipFile(output, "x", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(root.rglob("*")):
            if path.is_symlink():
                raise ValueError("Symbolic links are unsupported")
            if path.is_file():
                name = path.relative_to(root).as_posix()
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                permissions = (modes or {}).get(name, path.stat().st_mode & 0o777)
                entry.external_attr = (stat.S_IFREG | permissions) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                with path.open("rb") as source, archive.open(entry, "w", force_zip64=True) as destination:
                    while chunk := source.read(1024 * 1024):
                        destination.write(chunk)


def original_entitlements(data):
    has_der = False
    for command, offset, _ in macho_commands(data, 2):
        if command != 0x1D:
            continue
        start, size = struct.unpack_from("<II", data, offset + 8)
        if size < 12 or start + size > len(data):
            raise ValueError("Invalid original signature bounds")
        blob = data[start:start + size]
        magic, length, count = struct.unpack_from(">III", blob)
        if magic != 0xFADE0CC0 or length > size or 12 + count * 8 > length:
            raise ValueError("Unsupported original code signature")
        for index in range(count):
            kind, position = struct.unpack_from(">II", blob, 12 + index * 8)
            if position + 8 > length:
                raise ValueError("Invalid signature sub-blob")
            tag, sublength = struct.unpack_from(">II", blob, position)
            if sublength < 8 or position + sublength > length:
                raise ValueError("Invalid signature sub-blob bounds")
            if kind == 5 and tag == 0xFADE7171:
                values = plistlib.loads(blob[position + 8:position + sublength].rstrip(b"\0"))
                if not isinstance(values, dict):
                    raise ValueError("Original entitlements must be a dictionary")
                return values
            if kind == 7:
                # Modern signatures normally carry both XML and DER. A DER-only
                # entitlement set needs a signing tool capable of decoding it.
                has_der = True
        if has_der:
            raise ValueError("DER-only entitlements need an external signing tool")
    return {}


def file_hash(path):
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
        return digest.hexdigest()


def application_executable(app):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or safe_name(executable).name != executable:
        raise ValueError("Invalid application executable")
    path = app / executable
    if not path.is_file():
        raise ValueError("Missing application executable")
    return path, info
