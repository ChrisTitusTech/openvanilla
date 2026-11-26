#!/usr/bin/env bash
# Configure and build MacroQuest (Live x64) on Linux with clang-cl + xwin (tools/linux/README.md).
# Usage: tools/linux/build.sh [extra cmake configure args...]
#   BUILD_DIR   build directory (default: build/linux-x64)
#   XWIN_ROOT   xwin splat (default: ~/.local/share/xwin)
#   TARGETS     space-separated ninja targets (default: all)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
linux="$repo/tools/linux"
build_dir="${BUILD_DIR:-$repo/build/linux-x64}"
export XWIN_ROOT="${XWIN_ROOT:-$HOME/.local/share/xwin}"
export VCPKG_ROOT="$repo/contrib/vcpkg"
export PATH="$linux/bin:$PATH"

for tool in iconv clang-cl lld-link llvm-rc llvm-lib llvm-mt nasm ninja cmake pwsh; do
    command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 1; }
done
[[ -d "$XWIN_ROOT/winsdk" ]] || { echo "xwin splat not found (see tools/linux/README.md): $XWIN_ROOT" >&2; exit 1; }
[[ -x "$VCPKG_ROOT/vcpkg" ]] || "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics

# The fork can't commit to the eqlib submodule; carry its clang fixes as patches (idempotent).
for patch in "$linux"/patches/eqlib/*.patch; do
    if git -C "$repo/src/eqlib" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    echo "applying $(basename "$patch") to src/eqlib"
    git -C "$repo/src/eqlib" apply "$patch"
done

# External plugin sources are pinned submodules. Keep Linux compatibility
# changes in this repository, just as for eqlib.
for patch in "$linux"/patches/plugins/*/*.patch; do
    [[ -f "$patch" ]] || continue
    plugin_dir="$repo/plugins/$(basename "$(dirname "$patch")")"
    [[ -e "$plugin_dir/.git" ]] || continue
    if git -C "$plugin_dir" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    echo "applying $(basename "$patch") to $(basename "$plugin_dir")"
    git -C "$plugin_dir" apply "$patch"
done

cmake -S "$repo" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DMQ_PLATFORM=x64 \
    -DMQ_BUILD_LAUNCHER=ON \
    -DMQ_BUILD_CUSTOM_PLUGINS=OFF \
    -DMQ_FORCE_VCXPROJ_CONVERSION=OFF \
    -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE="$linux/cmake/clang-cl-xwin.cmake" \
    -DVCPKG_TARGET_TRIPLET=x64-windows-static \
    -DVCPKG_HOST_TRIPLET=x64-linux \
    -DVCPKG_OVERLAY_TRIPLETS="$linux/vcpkg/triplets" \
    -DVCPKG_OVERLAY_PORTS="$linux/vcpkg/ports" \
    -DCMAKE_PROJECT_INCLUDE="$linux/cmake/mq-linux.cmake" \
    "$@"

# shellcheck disable=SC2086
cmake --build "$build_dir" ${TARGETS:+--target $TARGETS}

# The converted Visual Studio projects don't stage plugin resource trees with
# Ninja. Install the bundled defaults without replacing user-edited resources.
for plugin in MQ2AdvPath MQ2EasyFind MQItemColor; do
    source_resources="$repo/plugins/$plugin/resources"
    release_dir="$build_dir/bin/release"
    if [[ -f "$release_dir/plugins/$plugin.dll" && -d "$source_resources" ]]; then
        mkdir -p "$release_dir/resources"
        cp -an "$source_resources/." "$release_dir/resources/"
    fi
done
