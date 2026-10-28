#!/usr/bin/env bash
# AdVanish contributions: Copyright (C) 2026 maxblox2999.
# GPL-3.0-only with origin terms; see LICENSE and NOTICE.md.

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
source build/dependencies.env
variant="${1:-rootless}"
case "$variant" in
    rootless) scheme=rootless; architecture=iphoneos-arm64 ;;
    rootful) scheme=; architecture=iphoneos-arm ;;
    jailed)
        node scripts/embed-web.cjs
        exec python3 scripts/build-jailed.py
        ;;
    *) printf 'Usage: bash scripts/build.sh rootless|rootful|jailed\n' >&2; exit 2 ;;
esac
: "${THEOS:?Set THEOS to the directory printed by scripts/setup-theos.sh}"
make_command="${MAKE:-make}"
node scripts/embed-web.cjs
node --test tests/web.test.cjs
"$make_command" clean
"$make_command" package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME="$scheme" \
    ARCHS="arm64 arm64e" TARGET="iphone:clang:$IOS_SDK:$IOS_MINIMUM" \
    THEOS_PLATFORM_DEB_COMPRESSION_TYPE=gzip

output_dir="dist/$variant"
mkdir -p "$output_dir"
package_id="$(awk '/^Package:/ {print $2}' control)"
version="$(awk '/^Version:/ {print $2}' control)"
package="packages/${package_id}_${version}_${architecture}.deb"
test -f "$package"
python3 scripts/verify-package.py "$package" "$variant" > "$output_dir/package-check.json"
cp "$package" "$output_dir/"
{
    if [ -f ../SOURCE_COMMIT ]; then
        printf 'commit=%s\n' "$(cat ../SOURCE_COMMIT)"
    else
        printf 'commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    fi
    printf 'variant=%s\n' "$variant"
    printf 'theos=%s\nsdks=%s\n' "$THEOS_REVISION" "$SDK_REVISION"
    printf 'sdk=%s\nminimum_ios=%s\n' "$IOS_SDK" "$IOS_MINIMUM"
    xcodebuild -version
    xcrun clang --version
    node --version
    python3 --version
    brew list --versions ldid make dpkg
} > "$output_dir/build-info.txt"
(
    cd "$output_dir"
    shasum -a 256 ./*.deb package-check.json build-info.txt > SHA256SUMS
)
