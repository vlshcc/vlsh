FreeBSD Port for vlsh
=====================

The port files are in pkg/freebsd/ and should be copied into the
FreeBSD ports tree at shells/vlsh/.

The port consists of 3 files:

  pkg/freebsd/Makefile    - Port definition (build deps, fetch, build, install)
  pkg/freebsd/distinfo    - SHA256 and size of the GitHub source tarball
  pkg/freebsd/pkg-descr   - Long description of the port

The Makefile declares lang/v as a build dependency, fetches the source
from GitHub via USE_GITHUB, builds with "v -prod .", and installs the
binary to ${PREFIX}/bin/vlsh. The @shell plist keyword automatically
registers/unregisters vlsh in /etc/shells.

To submit to the FreeBSD ports tree
------------------------------------

1. Copy the files into a local checkout of the ports tree:

     cp -r pkg/freebsd/ /usr/ports/shells/vlsh/

2. On a FreeBSD machine, verify and regenerate distinfo:

     cd /usr/ports/shells/vlsh && make makesum

3. Test the build:

     make stage && make check-plist && make package

4. Run the port linter:

     portlint -A

5. Submit via a FreeBSD Bugzilla bug (https://bugs.freebsd.org/) with
   category "ports" and a shar of the port:

     cd /usr/ports/shells && shar vlsh > vlsh.shar

Validation status
-----------------

These are draft port templates. The distinfo entries still contain placeholders;
regenerate them on FreeBSD before using or submitting the port. CI verifies Linux
with V 0.5.2; verify the native lang/v compiler separately. The published GitHub
release tag is v1.2, while package metadata is 1.2.0: choose the intended source
revision explicitly when preparing the port rather than assuming a v1.2.0 tag.
