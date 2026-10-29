#!/usr/bin/env bash
# Copyright (C) 2026 maxblox2999. See LICENSE and NOTICE.md.

set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/build/dependencies.env"
tools_dir="${1:-$project_dir/.theos-tools}"
variant="${2:-rootless}"
theos_url=https://github.com/theos/theos.git
theos_revision="$THEOS_REVISION"
if [ "$variant" = roothide ]; then
    theos_url=https://github.com/roothide/theos.git
    theos_revision="$ROOTHIDE_THEOS_REVISION"
fi
mkdir -p "$tools_dir"
tools_dir="$(cd "$tools_dir" && pwd)"

checkout_revision() {
    local url="$1"
    local path="$2"
    local revision="$3"
    if [ ! -d "$path/.git" ]; then
        git init --quiet "$path"
        git -C "$path" remote add origin "$url"
    fi
    test "$(git -C "$path" remote get-url origin)" = "$url"
    git -C "$path" fetch --quiet --depth=1 origin "$revision"
    git -C "$path" checkout --quiet --detach "$revision"
    test "$(git -C "$path" rev-parse HEAD)" = "$revision"
}

checkout_revision "$theos_url" "$tools_dir/theos" "$theos_revision"
git -C "$tools_dir/theos" submodule update --init --recursive --depth=1
checkout_revision https://github.com/theos/sdks.git "$tools_dir/sdks" "$SDK_REVISION"
test -d "$tools_dir/sdks/iPhoneOS$IOS_SDK.sdk"
mkdir -p "$tools_dir/theos/sdks"
sdk_link="$tools_dir/theos/sdks/iPhoneOS$IOS_SDK.sdk"
if [ ! -e "$sdk_link" ]; then
    ln -s "$tools_dir/sdks/iPhoneOS$IOS_SDK.sdk" "$sdk_link"
fi
printf 'THEOS=%s\n' "$tools_dir/theos"
