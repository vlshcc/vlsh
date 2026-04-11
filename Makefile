# vlsh — V project: use the V compiler from PATH (override with `make V=/path/to/v`).
V ?= v
PREFIX ?= /usr/local
# Default for `make fuzz` (override: make fuzz FUZZ_ITER=200000).
FUZZ_ITER ?= 50000

.PHONY: all build test check fuzz clean install dist dist-build dist-install help

all: build

help:
	@echo "vlsh — Makefile targets"
	@echo ""
	@echo "  make, make build     Compile the shell (v . in the project root)."
	@echo "  make test, make check   Run the test suite (v test .)."
	@echo "  make fuzz               Run tools/fuzz_shell.v (random input stress; FUZZ_ITER=$(FUZZ_ITER))."
	@echo "  make clean           Remove the vlsh binary from the build tree."
	@echo "  make install         Install vlsh to \$$(DESTDIR)\$$(PREFIX)/bin (default PREFIX=$(PREFIX))."
	@echo "                       Depends on build; use sudo if needed (sudo make install)."
	@echo "  make dist            Same as make dist-build — run pkg/dist.sh to fill builds/"
	@echo "                       (Linux .deb/.rpm, FreeBSD/DragonFly cross-bins; NetBSD/OpenBSD when native)."
	@echo "  make dist-install    Install the newest matching package/binary from builds/ for this OS"
	@echo "                       (pkg/dist.sh install; sudo when not root)."
	@echo ""
	@echo "Variables:  V=/path/to/v   PREFIX=$(PREFIX)   DESTDIR=   FUZZ_ITER=$(FUZZ_ITER)   FUZZ_SEED="
	@echo "More detail: README.md (Build and run, Distribution builds)."
	@echo ""

build:
	$(V) .

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
