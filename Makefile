# vlsh — V project: use the V compiler from PATH (override with `make V=/path/to/v`).
V ?= v
PREFIX ?= /usr/local
# Embed `git rev-parse --short` in the reported version (1.2-<sha>); empty if not a git checkout.
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null)
V_GIT := $(if $(GIT_SHA),-d git_sha=$(GIT_SHA))
# Default for `make fuzz` (override: make fuzz FUZZ_ITER=200000).
FUZZ_ITER ?= 50000

.PHONY: all build test check fuzz clean install dist dist-build dist-install openbsd help

all: build

help:
	@echo "vlsh — Makefile targets"
	@echo ""
	@echo "  make, make build     Compile the shell; embeds git short SHA in the version (1.2-<sha>)."
	@echo "  make test, make check   Run the test suite (v test .)."
	@echo "  make fuzz               Run tools/fuzz_shell.v (random input stress; FUZZ_ITER=$(FUZZ_ITER))."
	@echo "  make clean           Remove the vlsh binary from the build tree."
	@echo "  make install         Install vlsh to \$$(DESTDIR)\$$(PREFIX)/bin (default PREFIX=$(PREFIX))."
	@echo "                       Depends on build; use sudo if needed (sudo make install)."
	@echo "  make dist            Same as make dist-build — run pkg/dist.sh to fill builds/"
	@echo "                       (Linux .deb/.rpm, FreeBSD/DragonFly cross-bins; NetBSD/OpenBSD when native)."
	@echo "  make dist-install    Install the newest matching package/binary from builds/ for this OS"
	@echo "                       (pkg/dist.sh install; sudo when not root)."
	@echo "  make openbsd         Native OpenBSD build artifact (pkg/build.sh --openbsd; on OpenBSD only)."
	@echo ""
	@echo "Variables:  V=/path/to/v   PREFIX=$(PREFIX)   DESTDIR=   FUZZ_ITER=$(FUZZ_ITER)   FUZZ_SEED="
	@echo "More detail: README.md (Build and run, Distribution builds)."
	@echo ""

build:
	$(V) $(V_GIT) .

test: check

check:
	$(V) test .

fuzz:
	FUZZ_ITER=$(FUZZ_ITER) FUZZ_SEED=$(FUZZ_SEED) $(V) run tools/fuzz_shell.v

clean:
	rm -f vlsh tools/fuzz_shell

# Install the locally built binary (run with sufficient privileges, e.g. sudo make install).
install: build
	install -m 755 vlsh $(DESTDIR)$(PREFIX)/bin/vlsh

# Build distribution artifacts under builds/ (Linux .deb/.rpm + binaries; BSD cross-builds where tools exist).
dist dist-build:
	sh ./pkg/dist.sh build

# Install the newest matching package/binary from builds/ for this OS (see pkg/dist.sh).
dist-install:
	sh ./pkg/dist.sh install

# Native OpenBSD binary under builds/ (no-op on other hosts — see pkg/build.sh --openbsd).
openbsd:
	sh ./pkg/build.sh --openbsd
