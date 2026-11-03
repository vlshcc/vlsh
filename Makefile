# vlsh — V project: use the V compiler from PATH (override with `make V=/path/to/v`).
V ?= v
PREFIX ?= /usr/local
PYTHON ?= python3
SHELLS_FILE ?= /etc/shells
REGISTER_SHELL ?= 1
# Embed `git rev-parse --short` in the reported version (1.2-<sha>); empty if not a git checkout.
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null)
V_GIT := $(if $(GIT_SHA),-d git_sha=$(GIT_SHA))
# Default for `make fuzz` (override: make fuzz FUZZ_ITER=200000).
FUZZ_ITER ?= 50000

.PHONY: all build test check test-unit test-install test-packaging test-integration fuzz clean install dist dist-all dist-build dist-deb dist-rpm dist-linux dist-freebsd dist-dragonfly dist-install openbsd help

all: build

help:
	@echo "vlsh — Makefile targets"
	@echo ""
	@echo "  make, make build         Compile the shell (embeds git short SHA in version)."
	@echo "  make test, make check   Run unit, installation, packaging, and shell integration tests."
	@echo "  make clean           Remove vlsh binary."
	@echo "  make install        Install the built vlsh and register it in /etc/shells."
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
	@echo "Variables:  V=  PREFIX=  DESTDIR=  REGISTER_SHELL=  SHELLS_FILE=  FUZZ_ITER=  DIST_FLAGS="
	@echo ""

build:
	$(V) $(V_GIT) .

test: check

check: test-unit test-install test-packaging test-integration

test-unit:
	$(V) test .

test-install:
	$(PYTHON) tests/test_install.py

test-packaging:
	$(PYTHON) tests/test_packaging.py

test-integration:
	$(V) -o .vlsh-test .
	@trap 'rm -f .vlsh-test' EXIT HUP INT TERM; $(PYTHON) tests/test_shell.py ./.vlsh-test

fuzz:
	FUZZ_ITER=$(FUZZ_ITER) FUZZ_SEED=$(FUZZ_SEED) $(V) run tools/fuzz_shell.v

clean:
	rm -f vlsh .vlsh-test tools/fuzz_shell

install:
	@test -x ./vlsh || { echo "Run 'make build' as your regular user before installing." >&2; exit 1; }
	install -d "$(DESTDIR)$(PREFIX)/bin"
	install -m 755 vlsh "$(DESTDIR)$(PREFIX)/bin/vlsh"
	@if [ -z "$(DESTDIR)" ] && [ "$(REGISTER_SHELL)" != "0" ]; then \
		shell_path="$(PREFIX)/bin/vlsh"; \
		if ! grep -qxF -- "$$shell_path" "$(SHELLS_FILE)" 2>/dev/null; then \
			printf '\n%s\n' "$$shell_path" >> "$(SHELLS_FILE)"; \
		fi; \
	fi

# Distribution builds - delegate to pkg/dist.sh with appropriate flags
dist dist-all dist-build:
	V="$(V)" sh ./pkg/dist.sh build $(DIST_FLAGS)

dist-deb:
	V="$(V)" sh ./pkg/dist.sh build --deb $(DIST_FLAGS)

dist-rpm:
	V="$(V)" sh ./pkg/dist.sh build --rpm $(DIST_FLAGS)

dist-linux:
	V="$(V)" sh ./pkg/dist.sh build --linux $(DIST_FLAGS)

dist-freebsd:
	V="$(V)" sh ./pkg/dist.sh build --freebsd $(DIST_FLAGS)

dist-dragonfly:
	V="$(V)" sh ./pkg/dist.sh build --dragonfly $(DIST_FLAGS)

dist-install:
	sh ./pkg/dist.sh install

openbsd:
	sh ./pkg/build.sh --openbsd
