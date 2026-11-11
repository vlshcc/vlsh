# Testing and stability

Run `make test` before submitting changes. It runs the V module tests, installation and packaging tests, and then
builds a fresh shell for `tests/test_shell.py`, which uses Python 3's standard
library. The temporary test binary is removed after the integration run.
Use `make test-unit`, `make test-install`, `make test-packaging`, or `make test-integration` to run each layer separately.
Override the compiler with `make test V=/path/to/v` and Python with `PYTHON=python3`.

Integration tests run in temporary directories with a temporary HOME. They cover
quoting and empty arguments, comments, field splitting, positional parameters,
shell-local variables and export, multiline command lists, ordered redirections,
builtin isolation, command lookup exit statuses, alias cycles,
large pipelines, early consumer exit, stderr, exit status, Ctrl+C, and interactive
terminal restoration. Every subprocess has a timeout; a stuck pipeline fails the
test and its process group is killed. Tests do not need network access, plugins, or a reference shell. POSIX cases
assert expected outputs, exit statuses, and file contents directly.

Installation tests use a temporary binary, prefix, and shells registry. They
check registration, repeat installs, missing final newlines, staged installs,
and registration failures without changing the host's `/etc/shells` or requiring V.

Packaging tests copy the scripts into temporary trees and use fake compilers and
packaging tools. They exercise target selection, POSIX shell compatibility, compiler
overrides, preservation of existing artifacts, and staging cleanup on failures.
They require no network or native BSD toolchains. Package contents should also be
checked with a real packaging tool when changing package assembly or metadata.

Run a repeatable parser stress test with:

```sh
make fuzz FUZZ_ITER=50000 FUZZ_SEED=32423425234234
```

The seed is printed for reproduction. This harness stresses parsing and history
expansion; it does not execute the generated commands. Add a small regression
test when a crash or incorrect behavior is found.

GitHub Actions installs the official V 0.5.2 Linux toolchain, runs all test layers, runs a fixed-seed
parser stress test, and builds the shell. BSD packaging and full-screen programs
inside mux still require native/manual validation. The shell implements the
subset recorded in [posix-inventory.md](posix-inventory.md); this suite does not
establish full POSIX conformance.
