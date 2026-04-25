# vlsh — V project: use the V compiler from PATH (override with `make V=/path/to/v`).
V ?= v
PREFIX ?= /usr/local
# Embed `git rev-parse --short` in the reported version (1.2-<sha>); empty if not a git checkout.
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null)
V_GIT := $(if $(GIT_SHA),-d git_sha=$(GIT_SHA))
# Default for `make fuzz` (override: make fuzz FUZZ_ITER=200000).
FUZZ_ITER ?= 50000

.PHONY: all build test check fuzz clean install dist dist-deb dist-rpm dist-linux dist-freebsd dist-dragonfly dist-install openbsd help

all: build

help:
	@echo "vlsh — Makefile targets"
	@echo ""
	@echo "  make, make build         Compile the shell (embeds git short SHA in version)."
	@echo "  make test, make check   Run the test suite."
	@echo "  make clean           Remove vlsh binary."
	@echo "  make install        Install vlsh to \$$(PREFIX)/bin."
	@echo ""
	@echo "  Distribution builds (use pkg/dist.sh directly or make with DIST_FLAGS):"
	@echo "    make dist                 Build all targets (default)."
	@echo "    make dist-deb             Build only Linux .deb."
	@echo "    make dist-rpm            Build only Linux .rpm."
	@echo "    make dist-linux          Build Linux .deb + .rpm + standalone."
	@echo "    make dist-freebsd        Build FreeBSD cross-compiled binary."
	@echo "    make dist-dragonfly       Build DragonFlyBSD cross-compiled binary."
	@echo "    make dist-install        Install from builds/."
	@echo ""
	@echo "  Examples:"
	@echo "    make dist          # all"
	@echo "    make dist-deb     # just .deb"
	@echo "    make dist-linux   # Linux packages"
	@echo ""
	@echo "Variables:  V=  PREFIX=  DESTDIR=  FUZZ_ITER=  DIST_FLAGS="
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

install: build
	install -m 755 vlsh $(DESTDIR)$(PREFIX)/bin/vlsh

# Distribution builds - delegate to pkg/dist.sh with appropriate flags
dist dist-all:
	sh ./pkg/dist.sh build

dist-deb:
	sh ./pkg/dist.sh build --deb

dist-rpm:
	sh ./pkg/dist.sh build --rpm

dist-linux:
	sh ./pkg/dist.sh build --linux

dist-freebsd:
	sh ./pkg/dist.sh build --freebsd

dist-dragonfly:
	sh ./pkg/dist.sh build --dragonfly

dist-install:
	sh ./pkg/dist.sh install

openbsd:
	sh ./pkg/build.sh --openbsd
