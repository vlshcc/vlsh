# vlsh — V project: use the V compiler from PATH (override with `make V=/path/to/v`).
V ?= v
PREFIX ?= /usr/local

.PHONY: all build test check clean install dist dist-build dist-install help

all: build

help:
	@echo "vlsh — Makefile targets"
	@echo ""
	@echo "  make, make build     Compile the shell (v . in the project root)."
	@echo "  make test, make check   Run the test suite (v test .)."
	@echo "  make clean           Remove the vlsh binary from the build tree."
	@echo "  make install         Install vlsh to \$$(DESTDIR)\$$(PREFIX)/bin (default PREFIX=$(PREFIX))."
	@echo "                       Depends on build; use sudo if needed (sudo make install)."
	@echo "  make dist            Same as make dist-build — run pkg/dist.sh to fill builds/"
	@echo "                       (Linux .deb/.rpm, FreeBSD/DragonFly cross-bins; NetBSD/OpenBSD when native)."
	@echo "  make dist-install    Install the newest matching package/binary from builds/ for this OS"
	@echo "                       (pkg/dist.sh install; sudo when not root)."
	@echo ""
	@echo "Variables:  V=/path/to/v   PREFIX=$(PREFIX)   DESTDIR="
	@echo "More detail: README.md (Build and run, Distribution builds)."
	@echo ""

build:
	$(V) .

test: check

check:
	$(V) test .

clean:
	rm -f vlsh

# Install the locally built binary (run with sufficient privileges, e.g. sudo make install).
install: build
	install -m 755 vlsh $(DESTDIR)$(PREFIX)/bin/vlsh

# Build distribution artifacts under builds/ (Linux .deb/.rpm + binaries; BSD cross-builds where tools exist).
dist dist-build:
	sh ./pkg/dist.sh build

# Install the newest matching package/binary from builds/ for this OS (see pkg/dist.sh).
dist-install:
	sh ./pkg/dist.sh install
