#!/bin/sh
# pkg/build.sh — build vlsh binary, .deb, and .rpm packages
# Builds whatever package formats the current system supports.
# Requires: v (V compiler)
# Optional: dpkg-deb (for .deb), rpmbuild (for .rpm)
# Cross-compilation: pass --freebsd to cross-compile for FreeBSD (requires clang + lld)
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
        --freebsd) TARGET_OS="freebsd" ;;
        --help|-h)
            echo "Usage: $0 [--freebsd]"
            echo "  --freebsd  Cross-compile for FreeBSD (requires clang + lld)"
            exit 0
            ;;
    esac
done

need v

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
VERSION=$(grep "version:" v.mod | sed "s/.*'\(.*\)'.*/\1/")
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

    FBSD_SYSROOT="$HOME/.vmodules/freebsdroot"

    echo "==> Cross-compiling for FreeBSD"
    echo "    (V will auto-download the FreeBSD sysroot on first run — ~458 MB)"

    # V's thirdparty object compilation doesn't add FreeBSD target flags,
    # so we inject them via CFLAGS to ensure gc.o, mbedtls, etc. are
    # compiled against the FreeBSD sysroot rather than the host's glibc.
    rm -rf "$HOME/.vmodules/.cache"
    CFLAGS="--target=x86_64-unknown-freebsd14.0 --sysroot=${FBSD_SYSROOT} -I${FBSD_SYSROOT}/usr/include" \
        v -os freebsd -prod .

    mkdir -p builds
    cp vlsh "builds/vlsh_${VERSION}_${DEB_ARCH}_freebsd"

    echo ""
    echo "Done. Built artifact:"
    echo "  builds/vlsh_${VERSION}_${DEB_ARCH}_freebsd"
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
Maintainer: David Satime Wallin <david@dwall.in>
Homepage: https://github.com/dvwallin/vlsh
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
URL:            https://github.com/dvwallin/vlsh

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
v -prod .

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
