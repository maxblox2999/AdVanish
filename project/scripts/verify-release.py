# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.
"""Check public release downloads before removing superseded releases."""
import hashlib
import json
import os
from pathlib import Path
import urllib.request

repo = os.environ["GITHUB_REPOSITORY"]
sha = os.environ["GITHUB_SHA"]
base = "https://api.github.com/repos/" + repo
headers = {"User-Agent": "AdVanish-release-verification"}
def read(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        return response.read(32 * 1024 * 1024)
release = json.loads(read(base + "/releases/tags/v0.5.2"))
assert not release["draft"] and release["prerelease"]
assert release["target_commitish"] == sha
assert len(release["assets"]) == 8
for asset in release["assets"]:
    local = Path("release") / asset["name"]
    assert local.parent == Path("release") and local.is_file()
    assert asset["browser_download_url"].startswith("https://github.com/" + repo + "/releases/download/v0.5.2/")
    expected = hashlib.sha256(local.read_bytes()).hexdigest()
    downloaded = hashlib.sha256(read(asset["browser_download_url"])).hexdigest()
    assert downloaded == expected and asset["digest"] == "sha256:" + expected
print(json.dumps({"public_downloads_verified": 8, "release": release["html_url"]}))
