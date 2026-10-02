#!/bin/sh
# Builds the CONVOY DATUM Gateway (BLAKE2b / header-v2) as one universal
# (arm64 + x86_64) executable for macOS 13+, with its libraries linked in
# statically, so the app bundle needs nothing installed on the user's Mac.
# Only system libraries (libcurl, libSystem) are linked dynamically.
#
# Every source is pinned to a version and SHA-256 checksum.
# Build requirements: Xcode Command Line Tools, cmake, pkg-config
#   (brew install cmake pkg-config)
#
# Output: build/datum/datum_gateway
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK="$ROOT/build/datum"
SRC="$WORK/src"
OUT="$WORK/datum_gateway"
MACOS_MIN=13.0
JOBS=$(sysctl -n hw.ncpu)

GATEWAY_REPO=https://github.com/CONVOYMining/datum_gateway.git
GATEWAY_COMMIT=ac9b70c8b361f14e90e2c963b429a9bbb414aecb

# name|url|sha256
DEPS="
libsodium|https://download.libsodium.org/libsodium/releases/libsodium-1.0.22.tar.gz|adbdd8f16149e81ac6078a03aca6fc03b592b89ef7b5ed83841c086191be3349
jansson|https://github.com/akheron/jansson/releases/download/v2.15.1/jansson-2.15.1.tar.gz|0c7114dc0b2d22a670724a1f95922029d7077c19dbf79a584cb8084d2f267f2f
libmicrohttpd|https://ftpmirror.gnu.org/libmicrohttpd/libmicrohttpd-1.0.10.tar.gz|04bfe8ef75db7d629a33de767599765cecadc56274a39822d5d081030d577685
argp|https://github.com/argp-standalone/argp-standalone/archive/refs/tags/1.5.0.tar.gz|c29eae929dfebd575c38174f2c8c315766092cec99a8f987569d0cad3c6d64f6
epoll-shim|https://github.com/jiixyj/epoll-shim/archive/refs/tags/v0.0.20240608.tar.gz|8f5125217e4a0eeb96ab01f9dfd56c38f85ac3e8f26ef2578e538e72e87862cb
"

for tool in cmake pkg-config; do
    command -v $tool >/dev/null || { echo "$tool is required (brew install cmake pkg-config)"; exit 1; }
done
mkdir -p "$SRC"

fetch() {  # name url sha
    tarball="$SRC/$1.tar.gz"
    if [ ! -f "$tarball" ] || [ "$(shasum -a 256 "$tarball" | cut -d' ' -f1)" != "$3" ]; then
        echo "-- downloading $1"
        curl -fsSL -o "$tarball" "$2"
    fi
    actual=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
    [ "$actual" = "$3" ] || { echo "checksum mismatch for $1: $actual"; exit 1; }
}

echo "$DEPS" | while IFS='|' read -r name url sha; do
    if [ -n "$name" ]; then fetch "$name" "$url" "$sha"; fi
done

if [ ! -d "$SRC/datum_gateway/.git" ]; then
    git clone -q "$GATEWAY_REPO" "$SRC/datum_gateway"
fi
git -C "$SRC/datum_gateway" fetch -q origin "$GATEWAY_COMMIT" 2>/dev/null || true
git -C "$SRC/datum_gateway" checkout -q "$GATEWAY_COMMIT"

unpack() {  # name dir
    rm -rf "$2"
    mkdir -p "$2"
    tar xzf "$SRC/$1.tar.gz" -C "$2" --strip-components 1
}

build_arch() {
    arch=$1
    host=$( [ "$arch" = arm64 ] && echo aarch64-apple-darwin || echo x86_64-apple-darwin )
    B="$WORK/$arch"
    P="$B/prefix"
    rm -rf "$B"
    mkdir -p "$P/lib/pkgconfig" "$P/include"
    export CC="clang -arch $arch -mmacosx-version-min=$MACOS_MIN"
    export CFLAGS="-O2"
    export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig"
    unset PKG_CONFIG_PATH || true
    autoconf_opts="--host=$host --prefix=$P --disable-shared --enable-static"

    echo "== [$arch] libsodium"
    unpack libsodium "$B/libsodium"
    (cd "$B/libsodium" && ./configure $autoconf_opts >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

    echo "== [$arch] jansson"
    unpack jansson "$B/jansson"
    (cd "$B/jansson" && ./configure $autoconf_opts >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

    echo "== [$arch] libmicrohttpd"
    unpack libmicrohttpd "$B/libmicrohttpd"
    (cd "$B/libmicrohttpd" && ./configure $autoconf_opts --disable-doc --disable-examples --disable-tools \
        --disable-https --without-gnutls --disable-curl >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)

    echo "== [$arch] argp-standalone"
    unpack argp "$B/argp"
    # Generate config.h from argp's own template, as its meson build would on macOS.
    cat > "$B/argp/defines.txt" <<'EOF'
HAVE_CONFIG_H 1
HAVE_UNISTD_H 1
HAVE_ALLOCA_H 1
HAVE_ASPRINTF 1
HAVE_STRCHRNUL 0
HAVE_STRNDUP 1
HAVE_MEMPCPY 0
HAVE_DECL_PROGRAM_INVOCATION_NAME 0
HAVE_DECL_PROGRAM_INVOCATION_SHORT_NAME 0
HAVE_DECL_FWRITE_UNLOCKED 0
HAVE_DECL_CLEARERR_UNLOCKED 1
HAVE_DECL_FEOF_UNLOCKED 1
HAVE_DECL_FERROR_UNLOCKED 1
HAVE_DECL_FFLUSH_UNLOCKED 0
HAVE_DECL_FGETS_UNLOCKED 0
HAVE_DECL_FPUTC_UNLOCKED 0
HAVE_DECL_FPUTS_UNLOCKED 0
HAVE_DECL_FLOCKFILE 1
HAVE_DECL_PUTC_UNLOCKED 1
EOF
    awk 'NR == FNR { def[$1] = $2; next }
         /^#mesondefine / { n = $2; print (n in def) ? "#define " n " " def[n] : "/* #undef " n " */"; next }
         /^#undef HAVE_GCC_ATTRIBUTE/ { print "#define HAVE_GCC_ATTRIBUTE 1"; next }
         { print }' "$B/argp/defines.txt" "$B/argp/meson_config.h.in" > "$B/argp/config.h"
    grep -q "define HAVE_GCC_ATTRIBUTE 1" "$B/argp/config.h" || sed -i '' '1i\
#define HAVE_GCC_ATTRIBUTE 1
' "$B/argp/config.h"
    (cd "$B/argp" && for f in argp-ba argp-eexst argp-fmtstream argp-help argp-parse argp-pv argp-pvh mempcpy strchrnul; do
        $CC $CFLAGS -DHAVE_CONFIG_H=1 -I. -c "$f.c" -o "$f.o" || exit 1
    done && ar rcs "$P/lib/libargp.a" ./*.o && cp argp.h "$P/include/")
    nm "$P/lib/libargp.a" | grep -q " T _argp_parse" || { echo "argp build incomplete"; exit 1; }

    echo "== [$arch] epoll-shim"
    unpack epoll-shim "$B/epoll-shim"
    cmake -S "$B/epoll-shim" -B "$B/epoll-shim/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_TESTING=OFF -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN \
        -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_INSTALL_PKGCONFIGDIR="$P/lib/pkgconfig" >/dev/null
    cmake --build "$B/epoll-shim/build" -j"$JOBS" >/dev/null
    cmake --install "$B/epoll-shim/build" >/dev/null

    # libcurl ships with macOS; describe the SDK copy to pkg-config.
    cat > "$P/lib/pkgconfig/libcurl.pc" <<EOF
Name: libcurl
Description: macOS system libcurl
Version: 8
Libs: -lcurl
Cflags:
EOF

    echo "== [$arch] datum_gateway"
    unset CC CFLAGS
    cmake -S "$SRC/datum_gateway" -B "$B/gateway" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$arch" -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN \
        -DARGP_INCLUDE_DIR="$P/include" -DARGP_LIBRARY="$P/lib/libargp.a" \
        -DCMAKE_IGNORE_PREFIX_PATH="/opt/homebrew;/usr/local" >/dev/null
    cmake --build "$B/gateway" -j"$JOBS" --target datum_gateway >/dev/null
}

build_arch arm64
build_arch x86_64

lipo -create -output "$OUT" "$WORK/arm64/gateway/datum_gateway" "$WORK/x86_64/gateway/datum_gateway"
echo "== Built $OUT ($(lipo -archs "$OUT"))"
echo "Linked libraries:"
otool -L "$OUT" | tail -n +2
if otool -L "$OUT" | grep -qE '/opt/homebrew|/usr/local'; then
    echo "ERROR: links a Homebrew library; the binary would not run on other Macs"
    exit 1
fi
