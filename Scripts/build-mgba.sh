#!/usr/bin/env bash
# Builds libmgba (https://github.com/mgba-emu/mgba) as a static xcframework for
# iOS devices + simulator and lays out headers for the Tinbox Xcode project.
#
#   Scripts/build-mgba.sh            # build everything
#   Scripts/build-mgba.sh --clean    # wipe Vendor/build + Vendor/mgba-dist first
#
# Output:
#   Vendor/mgba-dist/mgba.xcframework        (libmgba + libpng + zlib merged per slice)
#   Vendor/mgba-dist/include/{mgba,mgba-util} (public headers)
#   Vendor/mgba-dist/include/mgba/flags.h     (generated; MUST be included before any
#                                              other mgba header so struct layouts match)
#
# Requirements: macOS, Xcode 15+, CMake >= 3.20 (brew install cmake).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Vendor"
SRC="$VENDOR/mgba"
BUILD="$VENDOR/build"
DIST="$VENDOR/mgba-dist"
MGBA_REPO="https://github.com/mgba-emu/mgba.git"
# Commit the bridge was written against (mgba-emu/mgba master, 2026-08-19).
# Override with MGBA_REF=<branch|tag|sha> to build something else.
MGBA_REF="${MGBA_REF:-cc94070a8910ecb8c1d10c515e913a4599223a31}"
IOS_MIN="${IOS_MIN:-16.0}"

if [[ "${1:-}" == "--clean" ]]; then
  rm -rf "$BUILD" "$DIST"
fi

command -v cmake >/dev/null || { echo "cmake not found (brew install cmake)"; exit 1; }
command -v xcrun  >/dev/null || { echo "xcrun not found (install Xcode)"; exit 1; }

# ---------------------------------------------------------------- sources
if [[ ! -d "$SRC/.git" ]]; then
  echo "==> Cloning mGBA ($MGBA_REF)"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$MGBA_REPO"
  git -C "$SRC" fetch --depth 1 origin "$MGBA_REF"
  git -C "$SRC" checkout -q FETCH_HEAD
fi
echo "==> mGBA revision: $(git -C "$SRC" rev-parse --short HEAD)"

# Guard two Apple-only lines in mGBA's CMakeLists that break iOS cross builds:
#   1. it force-sets CMAKE_OSX_DEPLOYMENT_TARGET to 10.6 (macOS) for any Darwin target
#   2. it force-enables -flto on Apple, which ties the .a to one exact clang version
if git -C "$SRC" apply --check "$ROOT/Scripts/mgba-ios.patch" 2>/dev/null; then
  echo "==> Applying Scripts/mgba-ios.patch"
  git -C "$SRC" apply "$ROOT/Scripts/mgba-ios.patch"
elif git -C "$SRC" apply --check --reverse "$ROOT/Scripts/mgba-ios.patch" 2>/dev/null; then
  echo "==> mgba-ios.patch already applied"
else
  echo "!! Scripts/mgba-ios.patch does not apply to this mGBA revision; inspect CMakeLists.txt manually" >&2
  exit 1
fi

# ---------------------------------------------------------------- cmake
# Feature set: GBA core only, VFS + directories, bundled zlib/minizip (.zip ROMs)
# and bundled libpng (PNG save states with embedded screenshots). Everything
# that needs a desktop dependency (Qt/SDL, ffmpeg, lua, sqlite, libzip, …) is off.
COMMON_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_MIN"
  -DCMAKE_C_FLAGS="-DNDEBUG"
  -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY
  -DBUILD_STATIC=ON -DBUILD_SHARED=OFF
  -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_LIBRETRO=OFF -DBUILD_GL=OFF -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF
  -DBUILD_TEST=OFF -DBUILD_SUITE=OFF -DBUILD_PERF=OFF -DBUILD_HEADLESS=OFF -DBUILD_EXAMPLE=OFF
  -DM_CORE_GBA=ON -DM_CORE_GB=ON      # GBA + Game Boy / Game Boy Color cores
  -DENABLE_DEBUGGERS=OFF -DENABLE_GDB_STUB=OFF -DENABLE_SCRIPTING=OFF
  -DUSE_ZLIB=ON -DUSE_PNG=ON            # zlib comes from the iOS SDK (libz.tbd); libpng is not in the SDK,
  -DUSE_LIBZIP=OFF -DUSE_MINIZIP=OFF    # so mGBA compiles its bundled src/third-party/libpng. .zip ROM support
                                        # comes from the bundled minizip in zlib/contrib (selected when USE_ZLIB
                                        # is on and neither libzip nor external minizip is used).
  -DUSE_LZMA=OFF -DUSE_SQLITE3=OFF -DUSE_ELF=OFF -DUSE_FFMPEG=OFF -DUSE_EPOXY=OFF
  -DUSE_EDITLINE=OFF -DUSE_LUA=OFF -DUSE_JSON_C=OFF -DUSE_FREETYPE=OFF -DUSE_DISCORD_RPC=OFF
  -DPNG_HARDWARE_OPTIMIZATIONS=OFF -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_EXECUTABLES=OFF -DPNG_FRAMEWORK=OFF -DPNG_SHARED=OFF -DPNG_STATIC=ON
  -DSKIP_INSTALL_ALL=ON
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON   # we read the real -D flags back out of compile_commands.json
)
# How mGBA resolves these: WANT_x is copied from USE_x, find_feature() flips USE_x
# back OFF when the library is not found under CMAKE_FIND_ROOT_PATH (the SDK), and
# "WANT_x AND NOT USE_x" then builds the bundled copy. Either way the result is
# self-contained apart from libz.tbd, which the Xcode project links.

export PKG_CONFIG_LIBDIR=/nonexistent   # never pick up Homebrew libs for an iOS build

build_slice() {   # name sysroot archs
  local name="$1" sysroot="$2" archs="$3"
  local dir="$BUILD/$name"
  echo "==> Configuring $name ($archs)"
  cmake -S "$SRC" -B "$dir" -G Ninja "${COMMON_FLAGS[@]}" \
        -DCMAKE_OSX_SYSROOT="$sysroot" -DCMAKE_OSX_ARCHITECTURES="$archs" 2>&1 | tail -n 5
  echo "==> Building $name"
  cmake --build "$dir" --target mgba 2>&1 | tail -n 3

  # Merge libmgba + bundled zlib + libpng into a single archive per slice.
  local libs=()
  libs+=("$(find "$dir" -name 'libmgba*.a' | head -n 1)")
  while IFS= read -r l; do libs+=("$l"); done < <(find "$dir" -name 'libpng*.a' -o -name 'libz*.a' | grep -v mgba || true)
  echo "    merging: ${libs[*]##*/}"
  xcrun libtool -static -o "$dir/libmgba-merged.a" "${libs[@]}"

  # Record the exact preprocessor definitions libmgba was compiled with.
  # mGBA's generated flags.h only reflects CMake *variables*; several
  # definitions (ENABLE_DIRECTORIES, USE_MINIZIP, ENABLE_VFS_FD, …) are added
  # straight to COMPILE_DEFINITIONS and never show up there — yet struct mCore's
  # layout depends on them. The consumer must see the same set.
  python3 - "$dir" <<'PY'
import json, shlex, sys
build = sys.argv[1]
entries = json.load(open(f"{build}/compile_commands.json"))
entry = next(e for e in entries if e["file"].replace("\\", "/").endswith("src/core/core.c"))
args = entry.get("arguments") or shlex.split(entry["command"])
defs = []
skip = {"NDEBUG"}
for a in args:
    if a.startswith("-D"):
        d = a[2:]
        name = d.split("=")[0]
        if name not in skip and d not in defs:
            defs.append(d)
open(f"{build}/mgba-defines.txt", "w").write("\n".join(defs) + "\n")
print("    compile definitions:", " ".join(defs))
PY
}

build_slice ios-arm64          iphoneos        "arm64"
build_slice ios-simulator      iphonesimulator "arm64;x86_64"

# ---------------------------------------------------------------- headers
rm -rf "$DIST"; mkdir -p "$DIST/include"
cp -R "$SRC/include/mgba" "$SRC/include/mgba-util" "$DIST/include/"
cp "$BUILD/ios-arm64/include/mgba/flags.h" "$DIST/include/mgba/flags.h"

# Sanity: both slices must have been compiled with identical definitions,
# otherwise struct mCore has a different layout per slice.
if ! diff -q "$BUILD/ios-arm64/mgba-defines.txt" "$BUILD/ios-simulator/mgba-defines.txt" >/dev/null; then
  echo "!! compile definitions differ between device and simulator builds" >&2
  diff "$BUILD/ios-arm64/mgba-defines.txt" "$BUILD/ios-simulator/mgba-defines.txt" || true
  exit 1
fi

# Append the real definitions to the distributed flags.h so any consumer that
# includes <mgba/flags.h> first sees exactly what the library saw.
{
  echo
  echo "// ---- Added by Scripts/build-mgba.sh: definitions libmgba was actually compiled with."
  echo "// ---- (mGBA's cmakedefine block above misses ones that are only COMPILE_DEFINITIONS.)"
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    name="${d%%=*}"
    if [[ "$d" == *"="* ]]; then value="${d#*=}"; else value=""; fi
    echo "#ifndef $name"
    echo "#define $name $value"
    echo "#endif"
  done < "$BUILD/ios-arm64/mgba-defines.txt"
} >> "$DIST/include/mgba/flags.h"

# ---------------------------------------------------------------- xcframework
xcodebuild -create-xcframework \
  -library "$BUILD/ios-arm64/libmgba-merged.a"     -headers "$DIST/include" \
  -library "$BUILD/ios-simulator/libmgba-merged.a" -headers "$DIST/include" \
  -output "$DIST/mgba.xcframework"

echo
echo "==> Done: $DIST/mgba.xcframework"
echo "    Effective definitions (must match the bridge's view of struct mCore):"
grep -E '^#define ' "$DIST/include/mgba/flags.h" | sort -u | sed 's/^/      /'
