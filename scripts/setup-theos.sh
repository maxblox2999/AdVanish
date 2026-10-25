#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_dir/build/dependencies.env"
tools_dir="${1:-$project_dir/.theos-tools}"
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
    git -C "$path" fetch --quiet --depth=1 origin "$revision"
    git -C "$path" checkout --quiet --detach "$revision"
    test "$(git -C "$path" rev-parse HEAD)" = "$revision"
}

checkout_revision https://github.com/theos/theos.git "$tools_dir/theos" "$THEOS_REVISION"
git -C "$tools_dir/theos" submodule update --init --recursive --depth=1
checkout_revision https://github.com/theos/sdks.git "$tools_dir/sdks" "$SDK_REVISION"
test -d "$tools_dir/sdks/iPhoneOS$IOS_SDK.sdk"
mkdir -p "$tools_dir/theos/sdks"
sdk_link="$tools_dir/theos/sdks/iPhoneOS$IOS_SDK.sdk"
if [ ! -e "$sdk_link" ]; then
    ln -s "$tools_dir/sdks/iPhoneOS$IOS_SDK.sdk" "$sdk_link"
fi
printf 'THEOS=%s\n' "$tools_dir/theos"
