#!/bin/sh
# pkg/build.sh — build vlsh binary, .deb, and .rpm packages
# Builds whatever package formats the current system supports.
# Requires: v (V compiler)
# Optional: dpkg-deb (for .deb), rpmbuild (for .rpm)
# Cross-compilation: --freebsd / --dragonfly (requires clang + lld)
# Native only: --netbsd / --openbsd (must run on NetBSD / OpenBSD; skipped elsewhere)
set -e

cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found"; }
has()  { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_OS="linux"
for arg in "$@"; do
    case "$arg" in
        --freebsd)    TARGET_OS="freebsd" ;;
        --dragonfly)  TARGET_OS="dragonfly" ;;
        --netbsd)     TARGET_OS="netbsd" ;;
        --openbsd)    TARGET_OS="openbsd" ;;
        --help|-h)
            echo "Usage: $0 [--freebsd] [--dragonfly] [--netbsd] [--openbsd]"
            echo "  --freebsd    Cross-compile for FreeBSD (requires clang + lld)"
            echo "  --dragonfly  Cross-compile for DragonFlyBSD (requires clang + lld)"
            echo "  --netbsd     Native build on NetBSD only (skipped on other hosts)"
            echo "  --openbsd    Native build on OpenBSD only (skipped on other hosts)"
            exit 0
            ;;
    esac
done

need v

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
VERSION=$(grep "version:" v.mod | sed "s/.*'\(.*\)'.*/\1/")
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || true)
if [ -n "$GIT_SHA" ]; then
	V_GIT_SHA_FLAG="-d git_sha=${GIT_SHA}"
else
	V_GIT_SHA_FLAG=""
fi
MACHINE_ARCH=$(uname -m)

# Map uname -m to Debian architecture names
case "$MACHINE_ARCH" in
    x86_64)  DEB_ARCH="amd64" ;;
    aarch64) DEB_ARCH="arm64" ;;
    armv7l)  DEB_ARCH="armhf" ;;
    i686)    DEB_ARCH="i386"  ;;
    *)       DEB_ARCH="$MACHINE_ARCH" ;;
esac

RPM_ARCH="$MACHINE_ARCH"
PKG_NAME="vlsh_${VERSION}_${DEB_ARCH}"

echo "==> Building vlsh ${VERSION} for ${MACHINE_ARCH} (target: ${TARGET_OS})"

# ---------------------------------------------------------------------------
# FreeBSD cross-compilation
# ---------------------------------------------------------------------------
if [ "$TARGET_OS" = "freebsd" ]; then
    need clang
    has ld.lld || die "'ld.lld' is required for FreeBSD cross-compilation (install the 'lld' package)"
    need git

    FBSD_SYSROOT="$HOME/.vmodules/freebsdroot"
    FBSD_SYSROOT_REPO="https://github.com/spytheman/freebsd_base13.2"

    echo "==> Cross-compiling for FreeBSD"
    echo "    (sysroot ~458 MB — same tree V uses for linking)"

    # V's cc_freebsd_cross() runs build_thirdparty_obj_files() *before*
    # ensure_freebsdroot_exists(), so headers must already be on disk when gc.c
    # is compiled. Pre-clone the sysroot; otherwise pthread.h etc. are missing.
    if [ ! -f "$FBSD_SYSROOT/usr/include/pthread.h" ]; then
        echo "==> Fetching FreeBSD sysroot (needed before thirdparty .o build)"
        if [ -d "$FBSD_SYSROOT" ]; then
            echo "    removing incomplete sysroot at $FBSD_SYSROOT"
            rm -rf "$FBSD_SYSROOT"
        fi
        mkdir -p "$(dirname "$FBSD_SYSROOT")"
        git clone --depth 1 "$FBSD_SYSROOT_REPO" "$FBSD_SYSROOT" \
            || die "failed to clone FreeBSD sysroot (need git + network)"
    fi

    # V's thirdparty object compilation doesn't add FreeBSD target flags,
    # so we inject them via CFLAGS to ensure gc.o, mbedtls, etc. are
    # compiled against the FreeBSD sysroot rather than the host's glibc.
    # Include paths match cc_freebsd_cross() in V's cc.v (include + usr/include).
    rm -rf "$HOME/.vmodules/.cache"
    CFLAGS="--target=x86_64-unknown-freebsd14.0 --sysroot=${FBSD_SYSROOT} -I${FBSD_SYSROOT}/include -I${FBSD_SYSROOT}/usr/include" \
        v -os freebsd -prod $V_GIT_SHA_FLAG .

    mkdir -p builds
    cp vlsh "builds/vlsh_${VERSION}_${DEB_ARCH}_freebsd"

    echo ""
    echo "Done. Built artifact:"
    echo "  builds/vlsh_${VERSION}_${DEB_ARCH}_freebsd"
    exit 0
fi

# ---------------------------------------------------------------------------
# DragonFlyBSD cross-compilation
# ---------------------------------------------------------------------------
if [ "$TARGET_OS" = "dragonfly" ]; then
    need clang
    has ld.lld || die "'ld.lld' is required for DragonFlyBSD cross-compilation (install the 'lld' package)"

    DFBSD_SYSROOT="$HOME/.vmodules/dragonflybsdroot"

    echo "==> Cross-compiling for DragonFlyBSD"

    if [ ! -d "$DFBSD_SYSROOT/usr/include" ]; then
        has curl    || die "'curl' is required to download the DragonFlyBSD ISO"
        has bunzip2 || die "'bunzip2' is required to decompress the DragonFlyBSD ISO (install 'bzip2')"

        # ISO9660 extraction: libarchive bsdtar is preferred; GNU tar (common on Linux) usually works too.
        if command -v bsdtar >/dev/null 2>&1; then
            DFBSD_TAR="bsdtar"
        elif command -v tar >/dev/null 2>&1; then
            DFBSD_TAR="tar"
        else
            die "need bsdtar (e.g. apt install libarchive-tools) or tar to extract the DragonFly ISO"
        fi

        DFBSD_ISO_URL="https://avalon.dragonflybsd.org/iso-images/dfly-x86_64-6.4.2_REL.iso.bz2"
        DFBSD_ISO=$(mktemp /tmp/dragonfly-XXXXXX.iso)
        trap "rm -f '$DFBSD_ISO'" EXIT

        echo "    Downloading and decompressing DragonFlyBSD 6.4.2 ISO (~260 MB download) ..."
        curl -fSL "$DFBSD_ISO_URL" | bunzip2 > "$DFBSD_ISO" \
            || die "failed to download ${DFBSD_ISO_URL}"

        echo "    Extracting sysroot (usr/include, usr/lib, lib) using ${DFBSD_TAR} ..."
        mkdir -p "$DFBSD_SYSROOT"
        "$DFBSD_TAR" -xf "$DFBSD_ISO" -C "$DFBSD_SYSROOT" usr/include usr/lib lib \
            || die "${DFBSD_TAR} failed — install bsdtar (libarchive-tools) or GNU tar, or copy usr/include, usr/lib, lib from DragonFlyBSD to ${DFBSD_SYSROOT}/"

        rm -f "$DFBSD_ISO"
        trap - EXIT

        echo "    Sysroot ready at ${DFBSD_SYSROOT}"
    fi

    # V's thirdparty object compilation hardcodes 'cc', so we prepend a
    # wrapper directory where 'cc' is a symlink to clang.
    CCWRAP=$(mktemp -d)
    ln -sf "$(command -v clang)" "$CCWRAP/cc"
    trap "rm -rf '$CCWRAP'" EXIT

    V_ROOT=$(dirname "$(readlink -f "$(command -v v)")")
    V_GC_INC="${V_ROOT}/thirdparty/libgc/include"

    # V links -lgc against the system library, but DragonFlyBSD's base
    # system doesn't include Boehm GC.  Build it from V's bundled sources.
    if [ ! -f "${DFBSD_SYSROOT}/usr/lib/libgc.a" ]; then
        echo "    Building libgc.a for DragonFlyBSD target ..."
        GC_OBJ=$(mktemp /tmp/gc-XXXXXX.o)
        clang --target=x86_64-unknown-dragonfly \
              "--sysroot=${DFBSD_SYSROOT}" \
              -I"${DFBSD_SYSROOT}/usr/include" \
              -I"${V_GC_INC}" \
              -DGC_THREADS -DGC_BUILTIN_ATOMIC -DNDEBUG -O2 \
              -c -o "$GC_OBJ" "${V_ROOT}/thirdparty/libgc/gc.c" \
            || die "failed to compile libgc for DragonFlyBSD"
        ar rcs "${DFBSD_SYSROOT}/usr/lib/libgc.a" "$GC_OBJ"
        rm -f "$GC_OBJ"
    fi

    rm -rf "$HOME/.vmodules/.cache"
    PATH="$CCWRAP:$PATH" \
    VCROSS_COMPILER_NAME="clang" \
    # V's -prod enables -flto which clang can't use for the dragonfly
    # target linker.  Instead we pass equivalent optimization flags manually.
    CFLAGS="--target=x86_64-unknown-dragonfly --sysroot=${DFBSD_SYSROOT} -I${DFBSD_SYSROOT}/usr/include -I${V_GC_INC} -fuse-ld=lld -O2 -DNDEBUG" \
    LDFLAGS="--target=x86_64-unknown-dragonfly --sysroot=${DFBSD_SYSROOT} -fuse-ld=lld" \
        v -cc clang -os dragonfly $V_GIT_SHA_FLAG .

    mkdir -p builds
    cp vlsh "builds/vlsh_${VERSION}_${DEB_ARCH}_dragonfly"

    echo ""
    echo "Done. Built artifact:"
    echo "  builds/vlsh_${VERSION}_${DEB_ARCH}_dragonfly"
    exit 0
fi

# ---------------------------------------------------------------------------
# NetBSD (native build only — V has no Linux→NetBSD cross sysroot like FreeBSD)
# ---------------------------------------------------------------------------
if [ "$TARGET_OS" = "netbsd" ]; then
    if [ "$(uname -s)" != "NetBSD" ]; then
        echo "==> Skipping NetBSD artifact: run pkg/build.sh --netbsd on a NetBSD system (no cross-sysroot in V yet)."
        exit 0
    fi
    echo "==> Native NetBSD build"
    v -prod $V_GIT_SHA_FLAG .
    mkdir -p builds
    cp vlsh "builds/vlsh_${VERSION}_${DEB_ARCH}_netbsd"
    echo ""
    echo "Done. Built artifact:"
    echo "  builds/vlsh_${VERSION}_${DEB_ARCH}_netbsd"
    exit 0
fi

# ---------------------------------------------------------------------------
# OpenBSD (native build only)
# ---------------------------------------------------------------------------
if [ "$TARGET_OS" = "openbsd" ]; then
    if [ "$(uname -s)" != "OpenBSD" ]; then
        echo "==> Skipping OpenBSD artifact: run pkg/build.sh --openbsd on an OpenBSD system (no cross-sysroot in V yet)."
        exit 0
    fi
    echo "==> Native OpenBSD build"
    v -prod $V_GIT_SHA_FLAG .
    mkdir -p builds
    cp vlsh "builds/vlsh_${VERSION}_${DEB_ARCH}_openbsd"
    echo ""
    echo "Done. Built artifact:"
    echo "  builds/vlsh_${VERSION}_${DEB_ARCH}_openbsd"
    exit 0
fi

# ---------------------------------------------------------------------------
# Ensure pkg/deb template files exist (recreate if missing)
# ---------------------------------------------------------------------------
if [ ! -f pkg/deb/control.in ] || [ ! -f pkg/deb/postinst ] || [ ! -f pkg/deb/prerm ]; then
    echo "==> Recreating missing pkg/deb files"
    mkdir -p pkg/deb

    cat > pkg/deb/control.in << 'EOF'
Package: vlsh
Version: VERSION
Architecture: ARCH
Maintainer: David Satime Wallin <sarmonsiill@tilde.guru>
Homepage: https://github.com/vlshcc/vlsh
Section: shells
Priority: optional
Installed-Size: INSTALLED_SIZE
Depends: libc6
Description: V Lang SHell — a shell written in V
 vlsh is an interactive shell written in the V programming language.
 .
 Features:
  - Pipes (cmd1 | cmd2 | cmd3)
  - Output redirection (> and >>)
  - AND-chain execution (cmd1 && cmd2)
  - Tilde expansion (~ and ~/path)
  - Per-command environment variable prefix (VAR=val cmd)
  - Session environment variables (venv add/rm/list)
  - Shared command history across sessions (last 5000 entries)
  - Tab completion for files and directories
  - Aliases (defined in ~/.vlshrc or managed at runtime)
  - Plugin system (~/.vlsh/plugins/)
  - Built-in terminal multiplexer (mux) with split panes
  - Native .vsh script execution via v run
EOF

    cat > pkg/deb/postinst << 'EOF'
#!/bin/sh
set -e

SHELL_PATH=/usr/bin/vlsh

case "$1" in
    configure)
        if ! grep -qxF "$SHELL_PATH" /etc/shells 2>/dev/null; then
            echo "$SHELL_PATH" >> /etc/shells
        fi
        ;;
esac
EOF

    cat > pkg/deb/prerm << 'EOF'
#!/bin/sh
set -e

SHELL_PATH=/usr/bin/vlsh

case "$1" in
    remove|purge)
        if [ -f /etc/shells ]; then
            tmp=$(mktemp)
            grep -vxF "$SHELL_PATH" /etc/shells > "$tmp" || true
            mv "$tmp" /etc/shells
        fi
        ;;
esac
EOF
fi

# ---------------------------------------------------------------------------
# Ensure pkg/rpm template files exist (recreate if missing)
# ---------------------------------------------------------------------------
if [ ! -f pkg/rpm/vlsh.spec.in ]; then
    echo "==> Recreating missing pkg/rpm files"
    mkdir -p pkg/rpm

    cat > pkg/rpm/vlsh.spec.in << 'EOF'
Name:           vlsh
Version:        VERSION
Release:        1%{?dist}
Summary:        V Lang SHell — a shell written in V
License:        MIT
URL:            https://github.com/vlshcc/vlsh

%description
vlsh is an interactive shell written in the V programming language.

Features:
- Pipes (cmd1 | cmd2 | cmd3)
- Output redirection (> and >>)
- AND-chain execution (cmd1 && cmd2)
- Tilde expansion (~ and ~/path)
- Per-command environment variable prefix (VAR=val cmd)
- Session environment variables (venv add/rm/list)
- Shared command history across sessions (last 5000 entries)
- Tab completion for files and directories
- Aliases (defined in ~/.vlshrc or managed at runtime)
- Plugin system (~/.vlsh/plugins/)
- Built-in terminal multiplexer (mux) with split panes
- Native .vsh script execution via v run

%install
mkdir -p %{buildroot}%{_bindir}
install -m 755 %{_sourcedir}/vlsh %{buildroot}%{_bindir}/vlsh

%post
if ! grep -qxF "/usr/bin/vlsh" /etc/shells 2>/dev/null; then
    echo "/usr/bin/vlsh" >> /etc/shells
fi

%preun
if [ "$1" = "0" ] && [ -f /etc/shells ]; then
    tmp=$(mktemp)
    grep -vxF "/usr/bin/vlsh" /etc/shells > "$tmp" || true
    mv "$tmp" /etc/shells
fi

%files
%{_bindir}/vlsh
EOF
fi

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
echo "==> Compiling"
v -prod $V_GIT_SHA_FLAG .

# ---------------------------------------------------------------------------
# Build .deb (if tools available)
# ---------------------------------------------------------------------------
if has dpkg-deb; then
    echo "==> Assembling .deb staging tree"
    STAGE="${PKG_NAME}"
    rm -rf "$STAGE"
    mkdir -p "${STAGE}/DEBIAN"
    mkdir -p "${STAGE}/usr/bin"

    cp vlsh "${STAGE}/usr/bin/vlsh"
    chmod 755 "${STAGE}/usr/bin/vlsh"

    INSTALLED_SIZE=$(du -sk "${STAGE}/usr" | cut -f1)

    sed \
        -e "s/VERSION/${VERSION}/g" \
        -e "s/ARCH/${DEB_ARCH}/g" \
        -e "s/INSTALLED_SIZE/${INSTALLED_SIZE}/g" \
        pkg/deb/control.in > "${STAGE}/DEBIAN/control"

    cp pkg/deb/postinst "${STAGE}/DEBIAN/postinst"
    cp pkg/deb/prerm    "${STAGE}/DEBIAN/prerm"
    chmod 755 "${STAGE}/DEBIAN/postinst"
    chmod 755 "${STAGE}/DEBIAN/prerm"

    echo "==> Building ${PKG_NAME}.deb"
    dpkg-deb --build --root-owner-group "$STAGE"
    rm -rf "$STAGE"

    mkdir -p builds
    mv "${PKG_NAME}.deb" builds/
    BUILT_DEB=1
else
    BUILT_DEB=0
    echo "==> Skipping .deb (dpkg-deb not found — install the 'dpkg' package to enable)"
fi

# ---------------------------------------------------------------------------
# Build .rpm (if tools available)
# ---------------------------------------------------------------------------
if has rpmbuild; then
    echo "==> Building .rpm"
    RPMTOP=$(mktemp -d)
    mkdir -p "$RPMTOP"/{SPECS,SOURCES,BUILD,RPMS,SRPMS}

    cp vlsh "$RPMTOP/SOURCES/"

    sed -e "s/VERSION/${VERSION}/g" \
        pkg/rpm/vlsh.spec.in > "$RPMTOP/SPECS/vlsh.spec"

    rpmbuild --define "_topdir $RPMTOP" -bb "$RPMTOP/SPECS/vlsh.spec"

    mkdir -p builds
    RPM_FILE=$(find "$RPMTOP/RPMS" -name "vlsh-*.rpm" -type f | head -1)
    if [ -n "$RPM_FILE" ]; then
        RPM_BASENAME=$(basename "$RPM_FILE")
        cp "$RPM_FILE" builds/
        echo "==> Built builds/${RPM_BASENAME}"
    fi

    rm -rf "$RPMTOP"
    BUILT_RPM=1
else
    BUILT_RPM=0
    echo "==> Skipping .rpm (rpmbuild not found — install the 'rpm-build' package to enable)"
fi

# ---------------------------------------------------------------------------
# Standalone binary
# ---------------------------------------------------------------------------
mkdir -p builds
cp vlsh "builds/${PKG_NAME}_linux"

echo ""
echo "Done. Built artifacts in builds/:"
ls -1 builds/${PKG_NAME}* 2>/dev/null | sed 's/^/  /'
if [ "$BUILT_RPM" = "1" ]; then
    RPM_FILE=$(ls builds/vlsh-${VERSION}-1.*.rpm 2>/dev/null | head -1)
    if [ -n "$RPM_FILE" ]; then
        echo "  ${RPM_FILE}"
    fi
fi
echo ""
if [ "$BUILT_DEB" = "1" ]; then
    echo "Install .deb:   sudo dpkg -i builds/${PKG_NAME}.deb"
    echo "Verify .deb:    dpkg -l vlsh"
    echo "Uninstall .deb: sudo dpkg -r vlsh"
fi
if [ "$BUILT_RPM" = "1" ] && [ -n "$RPM_FILE" ]; then
    echo "Install .rpm:   sudo rpm -U ${RPM_FILE}"
    echo "Verify .rpm:    rpm -q vlsh"
    echo "Uninstall .rpm: sudo rpm -e vlsh"
fi
echo "Set as shell:   chsh -s /usr/bin/vlsh"
