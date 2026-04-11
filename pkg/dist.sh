#!/bin/sh
# pkg/dist.sh — run pkg/build.sh for all supported targets; preserve existing
# builds/ artifacts by renaming them with a timestamp before each full dist run.
set -e

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found"; }

VERSION=$(grep "version:" v.mod | sed "s/.*'\(.*\)'.*/\1/")

# Rename existing file to stem_YYYYMMDD_HHMMSS.ext (or stem_YYYYMMDD_HHMMSS if no ext)
uniquify_file() {
	[ -f "$1" ] || return 0
	f="$1"
	dir=$(dirname "$f")
	base=$(basename "$f")
	ts=$(date +%Y%m%d_%H%M%S)
	case "$base" in
		*.deb)
			mv "$f" "${dir}/${base%.deb}_${ts}.deb"
			;;
		*.rpm)
			mv "$f" "${dir}/${base%.rpm}_${ts}.rpm"
			;;
		*)
			mv "$f" "${dir}/${base}_${ts}"
			;;
	esac
	echo "  preserved existing build as ${base} -> timestamped name" >&2
}

# Move aside any prior artifacts for this version so build.sh can reuse canonical names.
uniquify_existing_builds() {
	[ -d builds ] || return 0
	find builds -maxdepth 1 -type f \( \
		-name "vlsh_${VERSION}_*.deb" -o \
		-name "vlsh-${VERSION}-*.rpm" -o \
		-name "vlsh_${VERSION}_*_linux" -o \
		-name "vlsh_${VERSION}_*_freebsd" -o \
		-name "vlsh_${VERSION}_*_dragonfly" -o \
		-name "vlsh_${VERSION}_*_netbsd" -o \
		-name "vlsh_${VERSION}_*_openbsd" \
		\) 2>/dev/null | while IFS= read -r f; do
		uniquify_file "$f"
	done
}

map_uname_to_deb_arch() {
	m="$1"
	case "$m" in
		x86_64)  echo amd64 ;;
		aarch64) echo arm64 ;;
		amd64)   echo amd64 ;;
		arm64)   echo arm64 ;;
		i386|i686) echo i386 ;;
		*)       echo "$m" ;;
	esac
}

sudo_cmd() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	else
		need sudo
		sudo "$@"
	fi
}

cmd_build() {
	need v
	mkdir -p builds
	echo "==> vlsh dist build for version ${VERSION}"
	uniquify_existing_builds

	echo ""
	echo "==> [1/5] Linux (.deb / .rpm / standalone) — pkg/build.sh"
	sh pkg/build.sh

	echo ""
	echo "==> [2/5] FreeBSD (cross) — pkg/build.sh --freebsd"
	sh pkg/build.sh --freebsd

	echo ""
	echo "==> [3/5] DragonFlyBSD (cross) — pkg/build.sh --dragonfly"
	sh pkg/build.sh --dragonfly

	echo ""
	echo "==> [4/5] NetBSD — pkg/build.sh --netbsd (native only; skipped off NetBSD)"
	sh pkg/build.sh --netbsd

	echo ""
	echo "==> [5/5] OpenBSD — pkg/build.sh --openbsd (native only; skipped off OpenBSD)"
	sh pkg/build.sh --openbsd

	echo ""
	echo "==> dist build finished"
	echo "Artifacts under builds/:"
	ls -la builds 2>/dev/null | sed 's/^/  /' || true
}

cmd_install() {
	[ -d builds ] || die "no builds/ directory — run: ${0##*/} build"

	uname_s=$(uname -s)
	mach=$(uname -m)
	deb_arch=$(map_uname_to_deb_arch "$mach")

	case "$uname_s" in
	Linux)
		deb=$(ls -t builds/vlsh_${VERSION}_${deb_arch}*.deb 2>/dev/null | head -1)
		rpm=$(ls -t builds/vlsh-${VERSION}-*.rpm 2>/dev/null | head -1)
		if [ -n "$deb" ] && [ -f "$deb" ]; then
			echo "==> Installing .deb: $deb"
			sudo_cmd dpkg -i "$deb" || sudo_cmd apt-get install -f -y
			exit 0
		fi
		if [ -n "$rpm" ] && [ -f "$rpm" ]; then
			echo "==> Installing .rpm: $rpm"
			sudo_cmd rpm -U "$rpm"
			exit 0
		fi
		bin=$(ls -t builds/vlsh_${VERSION}_${deb_arch}_linux* 2>/dev/null | head -1)
		[ -n "$bin" ] && [ -f "$bin" ] || die "no suitable Linux package or binary in builds/ for ${deb_arch} — run: ${0##*/} build"
		echo "==> Installing standalone binary: $bin → /usr/local/bin/vlsh"
		sudo_cmd install -m 755 "$bin" /usr/local/bin/vlsh
		;;
	FreeBSD)
		bin=$(ls -t builds/vlsh_${VERSION}_${deb_arch}_freebsd* 2>/dev/null | head -1)
		[ -n "$bin" ] && [ -f "$bin" ] || die "no FreeBSD build in builds/ — run dist build on a host with cross-tools, or copy a binary manually"
		echo "==> Installing: $bin → /usr/local/bin/vlsh"
		sudo_cmd install -m 755 "$bin" /usr/local/bin/vlsh
		;;
	DragonFly)
		bin=$(ls -t builds/vlsh_${VERSION}_${deb_arch}_dragonfly* 2>/dev/null | head -1)
		[ -n "$bin" ] && [ -f "$bin" ] || die "no DragonFly build in builds/"
		echo "==> Installing: $bin → /usr/local/bin/vlsh"
		sudo_cmd install -m 755 "$bin" /usr/local/bin/vlsh
		;;
	NetBSD)
		bin=$(ls -t builds/vlsh_${VERSION}_${deb_arch}_netbsd* 2>/dev/null | head -1)
		[ -n "$bin" ] && [ -f "$bin" ] || die "no NetBSD build in builds/ — run ${0##*/} build on NetBSD to produce one"
		echo "==> Installing: $bin → /usr/pkg/bin/vlsh (or /usr/local/bin)"
		if [ -d /usr/pkg/bin ]; then
			sudo_cmd install -m 755 "$bin" /usr/pkg/bin/vlsh
		else
			sudo_cmd install -m 755 "$bin" /usr/local/bin/vlsh
		fi
		;;
	OpenBSD)
		bin=$(ls -t builds/vlsh_${VERSION}_${deb_arch}_openbsd* 2>/dev/null | head -1)
		[ -n "$bin" ] && [ -f "$bin" ] || die "no OpenBSD build in builds/ — run ${0##*/} build on OpenBSD to produce one"
		echo "==> Installing: $bin → /usr/local/bin/vlsh"
		sudo_cmd install -m 755 "$bin" /usr/local/bin/vlsh
		;;
	*)
		die "unsupported OS for dist install: $uname_s"
		;;
	esac
}

case "${1:-}" in
	build|'')
		cmd_build
		;;
	install)
		cmd_install
		;;
	-h|--help|help)
		echo "Usage: ${0##*/} [build|install]"
		echo "  build   — preserve existing builds/* then run pkg/build.sh for Linux, FreeBSD, DragonFly, NetBSD, OpenBSD"
		echo "  install — install newest matching package/binary from builds/ for this OS"
		;;
	*)
		die "unknown command: $1 (try: build, install, --help)"
		;;
esac
