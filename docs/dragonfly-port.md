How to Create a DragonFlyBSD Port for the DPorts Repository

DragonFlyBSD uses DPorts, a fork of FreeBSD's ports collection.
The repository is at github.com/DragonFlyBSD/DPorts.

1. Structure
------------
Your port goes under a category directory. For vlsh:

  shells/vlsh/
  ├── Makefile
  ├── distinfo
  └── pkg-descr

These files already exist in pkg/dragonfly/.

2. Test your port on DragonFlyBSD
---------------------------------
Before submitting, test the port on an actual DragonFlyBSD system:

  # Copy your port into the local DPorts tree
  sudo mkdir -p /usr/dports/shells/vlsh
  sudo cp pkg/dragonfly/* /usr/dports/shells/vlsh/

  # Build and test
  cd /usr/dports/shells/vlsh
  sudo make install
  sudo make package
  sudo make deinstall

3. Generate a correct distinfo
------------------------------
On the DragonFlyBSD system, run:

  cd /usr/dports/shells/vlsh
  sudo make makesum

This regenerates distinfo with the correct SHA256 and SIZE
(replacing the PLACEHOLDERs currently in yours).

4. Submit
---------
DPorts contributions go through their bug tracker:

  1. Go to bugs.dragonflybsd.org
  2. Create a new bug with category "dports"
  3. Set the summary to something like:
     New port: shells/vlsh — Interactive shell written in V
  4. Attach a .tar.gz or .diff of your port directory
  5. Include a brief description of what the port does

Alternatively, you can open a pull request on
github.com/DragonFlyBSD/DPorts, though the bug tracker
is the traditional route.

5. Prerequisites
----------------
Your port's Makefile has BUILD_DEPENDS= v:lang/v, meaning the
V compiler must already exist as a port (lang/v). If lang/v
doesn't exist in DPorts yet, you'd need to submit that port
first (or adjust the port to bundle/bootstrap the V compiler).

Check whether lang/v exists by browsing:
github.com/DragonFlyBSD/DPorts/tree/master/lang

Validation status
-----------------

The port files are drafts; native build and package checks remain required.
CI uses V 0.5.2 on Linux. The published release tag is v1.2, while package
metadata is 1.2.0: update the port to use the intended source revision explicitly.
