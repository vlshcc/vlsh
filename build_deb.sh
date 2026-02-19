#!/bin/sh
# build_deb.sh — build a binary .deb package for vlsh
# Requires: v (V compiler), dpkg-deb, dpkg (all present on Ubuntu)
set -e

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found"; }

need v
need dpkg-deb
need dpkg

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
VERSION=$(grep "version:" v.mod | sed "s/.*'\(.*\)'.*/\1/")
ARCH=$(dpkg --print-architecture)
PKG_NAME="vlsh_${VERSION}_${ARCH}"
STAGE="${PKG_NAME}"

echo "==> Building vlsh ${VERSION} for ${ARCH}"

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
# Compile
# ---------------------------------------------------------------------------
echo "==> Compiling"
v .

# ---------------------------------------------------------------------------
# Assemble staging tree
# ---------------------------------------------------------------------------
echo "==> Assembling ${STAGE}/"
rm -rf "$STAGE"
mkdir -p "${STAGE}/DEBIAN"
mkdir -p "${STAGE}/usr/bin"

cp vlsh "${STAGE}/usr/bin/vlsh"
chmod 755 "${STAGE}/usr/bin/vlsh"

INSTALLED_SIZE=$(du -sk "${STAGE}/usr" | cut -f1)

# ---------------------------------------------------------------------------
# Control file
# ---------------------------------------------------------------------------
sed \
    -e "s/VERSION/${VERSION}/g" \
    -e "s/ARCH/${ARCH}/g" \
    -e "s/INSTALLED_SIZE/${INSTALLED_SIZE}/g" \
    pkg/deb/control.in > "${STAGE}/DEBIAN/control"

# ---------------------------------------------------------------------------
# Maintainer scripts
# ---------------------------------------------------------------------------
cp pkg/deb/postinst "${STAGE}/DEBIAN/postinst"
cp pkg/deb/prerm    "${STAGE}/DEBIAN/prerm"
chmod 755 "${STAGE}/DEBIAN/postinst"
chmod 755 "${STAGE}/DEBIAN/prerm"

# ---------------------------------------------------------------------------
# Build .deb
# ---------------------------------------------------------------------------
echo "==> Building ${PKG_NAME}.deb"
dpkg-deb --build --root-owner-group "$STAGE"
rm -rf "$STAGE"

echo ""
echo "Done: ${PKG_NAME}.deb"
echo ""
echo "Install:       sudo dpkg -i ${PKG_NAME}.deb"
echo "Verify:        dpkg -l vlsh"
echo "Set as shell:  chsh -s /usr/bin/vlsh"
echo "Uninstall:     sudo dpkg -r vlsh"
