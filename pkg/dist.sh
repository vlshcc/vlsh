#!/bin/sh
# pkg/dist.sh — run pkg/build.sh for selected targets (default: all); preserve
# matching builds/ artifacts by renaming them with a timestamp.
set -e

cd "$(dirname "$0")/.."

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not found"; }

VERSION=$(grep "version:" v.mod | sed "s/.*'\(.*\)'.*/\1/")

# Preserve canonical artifacts only; previous archives are never renamed again.
uniquify_file() {
	[ -f "$1" ] || return 0
	f="$1"
	ts=$(date +%Y%m%d_%H%M%S)
	case "$f" in
		*.deb) stem=${f%.deb}; ext=.deb ;;
		*.rpm) stem=${f%.rpm}; ext=.rpm ;;
		*) stem=$f; ext= ;;
	esac
	archive="${stem}_${ts}${ext}"
	counter=1
	while [ -e "$archive" ]; do
		archive="${stem}_${ts}_${counter}${ext}"
		counter=$((counter + 1))
	done
	mv "$f" "$archive"
	echo "  preserved $f as $archive" >&2
}

uniquify_existing_builds() {
	[ -d builds ] || return 0
	arch=$(map_uname_to_deb_arch "$(uname -m)")
	if [ "$do_deb" -eq 1 ]; then
		uniquify_file "builds/vlsh_${VERSION}_${arch}.deb"
	fi
	if [ "$do_rpm" -eq 1 ]; then
		for rpm_file in builds/vlsh-${VERSION}-*."$(uname -m)".rpm; do
			uniquify_file "$rpm_file"
		done
	fi
	for target in linux freebsd dragonfly netbsd openbsd; do
		case "$target" in
			linux) selected=$do_standalone ;;
			freebsd) selected=$do_freebsd ;;
			dragonfly) selected=$do_dragonfly ;;
			netbsd) selected=$do_netbsd ;;
			openbsd) selected=$do_openbsd ;;
		esac
		if [ "$selected" -eq 1 ]; then
			uniquify_file "builds/vlsh_${VERSION}_${arch}_${target}"
		fi
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
		armv7l) echo armhf ;;
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

run_build() {
	step=$((step + 1))
	echo ""
	echo "==> [$step/$total] pkg/build.sh $*"
	sh pkg/build.sh "$@"
}

cmd_build() {
	do_deb=0
	do_rpm=0
	do_standalone=0
	do_freebsd=0
	do_dragonfly=0
	do_netbsd=0
	do_openbsd=0
	linux_all=0
	if [ "$#" -eq 0 ]; then set -- --all; fi
	for arg in "$@"; do
		case "$arg" in
			--all)
				do_deb=1; do_rpm=1; do_standalone=1; linux_all=1
				do_freebsd=1; do_dragonfly=1; do_netbsd=1; do_openbsd=1
				;;
			--linux) do_deb=1; do_rpm=1; do_standalone=1; linux_all=1 ;;
			--deb) do_deb=1 ;;
			--rpm) do_rpm=1 ;;
			--standalone) do_standalone=1 ;;
			--freebsd) do_freebsd=1 ;;
			--dragonfly) do_dragonfly=1 ;;
			--netbsd) do_netbsd=1 ;;
			--openbsd) do_openbsd=1 ;;
			*) die "unknown build option: $arg" ;;
		esac
	done
	V=${V:-v}
	export V
	need "$V"
	total=$((do_freebsd + do_dragonfly + do_netbsd + do_openbsd))
	if [ "$do_deb" -eq 1 ] || [ "$do_rpm" -eq 1 ] || [ "$do_standalone" -eq 1 ]; then
		total=$((total + 1))
	fi
	step=0
	mkdir -p builds
	echo "==> vlsh dist build for version ${VERSION}"
	uniquify_existing_builds

	if [ "$linux_all" -eq 1 ]; then
		run_build --linux
	elif [ "$do_deb" -eq 1 ] || [ "$do_rpm" -eq 1 ] || [ "$do_standalone" -eq 1 ]; then
		set --
		if [ "$do_deb" -eq 1 ]; then set -- "$@" --deb; fi
		if [ "$do_rpm" -eq 1 ]; then set -- "$@" --rpm; fi
		if [ "$do_standalone" -eq 1 ]; then set -- "$@" --standalone; fi
		run_build "$@"
	fi
	if [ "$do_freebsd" -eq 1 ]; then run_build --freebsd; fi
	if [ "$do_dragonfly" -eq 1 ]; then run_build --dragonfly; fi
	if [ "$do_netbsd" -eq 1 ]; then run_build --netbsd; fi
	if [ "$do_openbsd" -eq 1 ]; then run_build --openbsd; fi

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

command=${1:-build}
if [ "$#" -gt 0 ]; then shift; fi
case "$command" in
	build)
		cmd_build "$@"
		;;
	install)
		[ "$#" -eq 0 ] || die "install takes no options"
		cmd_install
		;;
	-h|--help|help)
		echo "Usage: ${0##*/} build [--all|--linux|--deb|--rpm|--standalone|--freebsd|--dragonfly|--netbsd|--openbsd]"
		echo "       ${0##*/} install"
		echo "  build   — build selected targets (default: all); preserve matching existing artifacts"
		echo "  install — install newest matching package/binary from builds/ for this OS"
		;;
	*)
		die "unknown command: $command (try: build, install, --help)"
		;;
esac
