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
