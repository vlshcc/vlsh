DragonFlyBSD Support — Summary of Changes

1. mux/pty_helpers.h — PTY header include
DragonFlyBSD uses <libutil.h> for openpty()/forkpty(), same as FreeBSD. Added
__DragonFly__ to the existing FreeBSD preprocessor guard:

  #elif defined(__FreeBSD__) || defined(__DragonFly__)
  #include <libutil.h>

2. pkg/build.sh — Cross-compilation support (--dragonfly)
Added --dragonfly flag for cross-compiling from Linux. The script automatically:
  - Downloads the DragonFlyBSD 6.4.2 ISO (~260 MB) from avalon.dragonflybsd.org
  - Extracts usr/include, usr/lib, and lib into ~/.vmodules/dragonflybsdroot
  - Compiles V's bundled Boehm GC (libgc.a) for the DragonFlyBSD target
  - Wraps 'cc' to point at clang (V hardcodes 'cc' for thirdparty objects)
  - Cross-compiles with clang + lld using -O2 (LTO is skipped because
    clang cannot pass LLVM bitcode to the DragonFlyBSD target linker)
  - The sysroot is cached for subsequent builds

Requires: clang, lld, bsdtar (from libarchive) or a compatible tar, curl, bunzip2

3. pkg/dragonfly/ — DPorts package files
Created Makefile, pkg-descr, and distinfo for DragonFlyBSD's DPorts system
(which uses the same format as FreeBSD ports). These allow building a native
package directly on DragonFlyBSD with the V compiler installed.

Note: The #flag dragonfly -lcompiler_rt linker flag was NOT added (unlike
FreeBSD) because DragonFlyBSD's base system does not include libcompiler_rt.
Clang handles compiler builtins automatically for the DragonFlyBSD target.

The execution path now also uses exec/process_helpers.h for POSIX pipes,
fork/exec, file descriptors, and signal handling. These paths have Linux
regression coverage; native DragonFlyBSD validation is still required.
