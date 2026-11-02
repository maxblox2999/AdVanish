# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
"""Archive tracked source with its commit ID on macOS or Linux."""
import gzip
import hashlib
import io
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
output = ROOT / "project/dist/source"
output.mkdir(parents=True, exist_ok=True)
sha = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
source = io.BytesIO(subprocess.check_output(["git", "-C", str(ROOT), "archive", "--format=tar", "--prefix=AdVanish/", "HEAD"]))
with tarfile.open(fileobj=source, mode="a") as archive:
    data = (sha + "\n").encode()
    record = tarfile.TarInfo("AdVanish/SOURCE_COMMIT")
    record.size = len(data)
    archive.addfile(record, io.BytesIO(data))
path = output / "AdVanish-source.tar.gz"
with path.open("wb") as file:
    with gzip.GzipFile(filename="", fileobj=file, mode="wb", mtime=0) as compressed:
        compressed.write(source.getvalue())
shutil.copyfile(ROOT / "project/dist/browser.json", output / "browser.json")
(output / "SHA256SUMS").write_text(hashlib.sha256(path.read_bytes()).hexdigest() + "  " + path.name + "\n")
