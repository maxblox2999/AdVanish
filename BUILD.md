# Build

## GitHub Actions

Fork this repository, enable Actions, then run **Build → Run workflow** on `main`.

Download the rootless, rootful and source artifacts from the completed run. No signing secrets or game IPAs are needed. Source archives include `SOURCE_COMMIT`.

## macOS

Requires Xcode, its command-line tools, Node.js 18+ and Python 3.9+. Complete Xcode's setup before building.

```sh
brew install make ldid dpkg node python
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
bash scripts/setup-theos.sh
export THEOS="$PWD/.theos-tools/theos"
bash scripts/build.sh rootless
bash scripts/build.sh rootful
```

Packages and checksums are written to `dist/rootless/` and `dist/rootful/`.

```sh
cd dist/rootless
shasum -a 256 -c SHA256SUMS
```

Both variants contain arm64/arm64e builds with an iOS 15 minimum. Choose the package matching your jailbreak layout. Existing AdSpeed preferences are retained.

Dependencies are pinned in [build/dependencies.env](build/dependencies.env). Each artifact records its toolchain in `build-info.txt`; different toolchains can produce different binary hashes.

Test runners and their limits: [docs/VALIDATION.md](docs/VALIDATION.md).
