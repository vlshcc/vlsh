#!/usr/bin/env python3
"""Packaging regressions using isolated trees and fake build tools."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vlsh-pkg-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        shutil.copytree(REPO / 'pkg', self.root / 'pkg')
        for name in ('v.mod', 'Makefile'):
            shutil.copy2(REPO / name, self.root / name)
        self.bin = self.root / 'tools'
        self.bin.mkdir()
        self.work = self.root / 'temp space'
        self.work.mkdir()
        self.log = self.root / 'calls'
        self.env = os.environ.copy()
        self.env.update(PATH=f'{self.bin}:/usr/bin:/bin', LOG=str(self.log),
                        TMPDIR=str(self.work), V='v', LC_ALL='C')
        for name in ('MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'DIST_FLAGS'):
            self.env.pop(name, None)
        self.tool('uname', 'case "$1" in -m) echo x86_64 ;; -s) echo Linux ;; *) exit 1 ;; esac')
        self.tool('v', 'echo v >> "$LOG"\nprintf "#!/bin/sh\\nexit 0\\n" > vlsh\nchmod 755 vlsh')
        self.tool('dpkg-deb', '''echo dpkg-deb >> "$LOG"
[ "${FAIL_DEB:-0}" -eq 0 ] || exit 9
[ -x "$3/usr/bin/vlsh" ] && [ -f "$3/DEBIAN/control" ]
bad_modes=$(find "$3" -type d ! -perm 755 -print)
[ -z "$bad_modes" ]
printf deb > "$4"''')
        self.tool('rpmbuild', '''echo rpmbuild >> "$LOG"
[ "${FAIL_RPM:-0}" -eq 0 ] || exit 9
top=${2#_topdir }
for dir in SPECS SOURCES BUILD RPMS SRPMS BUILDROOT; do
    [ -d "$top/$dir" ] || exit 8
done
[ -f "$top/SOURCES/vlsh" ] && [ -f "$top/SPECS/vlsh.spec" ]
mkdir -p "$top/RPMS/x86_64"
printf rpm > "$top/RPMS/x86_64/vlsh-1.2.0-1.x86_64.rpm"''')

    def tool(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\nset -e\n' + body + '\n')
        path.chmod(0o755)
        return path

    def run_command(self, *args):
        return subprocess.run(args, cwd=self.root, env=self.env, text=True,
                              capture_output=True, timeout=15)

    def success(self, *args):
        result = self.run_command(*args)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def calls(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def artifacts(self):
        return {path.name for path in (self.root / 'builds').iterdir()}

    def stub_build_dispatch(self):
        (self.root / 'pkg/build.sh').write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$LOG"\n')

    def test_make_dist_deb_builds_only_deb(self):
        self.success('make', 'dist-deb')
        self.assertEqual(self.calls(), ['v', 'dpkg-deb'])
        self.assertEqual(self.artifacts(), {'vlsh_1.2.0_amd64.deb'})
        self.assertEqual(list(self.work.iterdir()), [])

    def test_make_dist_rpm_works_under_posix_sh(self):
        self.success('make', 'dist-rpm')
        self.assertEqual(self.calls(), ['v', 'rpmbuild'])
        self.assertEqual(self.artifacts(), {'vlsh-1.2.0-1.x86_64.rpm'})
        self.assertEqual(list(self.work.iterdir()), [])

    def test_linux_builds_available_packages_and_standalone(self):
        self.success('make', 'dist-linux')
        self.assertEqual(self.calls(), ['v', 'dpkg-deb', 'rpmbuild'])
        self.assertEqual(self.artifacts(), {'vlsh_1.2.0_amd64.deb',
                                           'vlsh-1.2.0-1.x86_64.rpm',
                                           'vlsh_1.2.0_amd64_linux'})

    def test_direct_build_script_honors_deb_and_rpm(self):
        self.success('sh', 'pkg/build.sh', '--deb', '--rpm')
        self.assertEqual(self.calls(), ['v', 'dpkg-deb', 'rpmbuild'])
        self.assertNotIn('vlsh_1.2.0_amd64_linux', self.artifacts())

    def test_standalone_does_not_invoke_packagers(self):
        self.success('sh', 'pkg/dist.sh', 'build', '--standalone')
        self.assertEqual(self.calls(), ['v'])
        self.assertEqual(self.artifacts(), {'vlsh_1.2.0_amd64_linux'})

    def test_default_dist_dispatches_all_targets(self):
        self.stub_build_dispatch()
        self.success('sh', 'pkg/dist.sh', 'build')
        self.assertEqual(self.calls(), ['--linux', '--freebsd', '--dragonfly', '--netbsd', '--openbsd'])

    def test_explicit_bsd_targets_dispatch_only_selected_target(self):
        self.stub_build_dispatch()
        for target in ('freebsd', 'dragonfly', 'netbsd', 'openbsd'):
            with self.subTest(target=target):
                self.log.unlink(missing_ok=True)
                self.success('sh', 'pkg/dist.sh', 'build', f'--{target}')
                self.assertEqual(self.calls(), [f'--{target}'])

    def test_dist_flags_are_forwarded(self):
        self.stub_build_dispatch()
        self.success('make', 'dist', 'DIST_FLAGS=--deb --netbsd')
        self.assertEqual(self.calls(), ['--deb', '--netbsd'])

    def test_make_honors_compiler_override(self):
        compiler = self.tool('custom compiler', 'echo custom-v >> "$LOG"\nprintf binary > vlsh')
        self.success('make', 'dist-deb', f'V={compiler}')
        self.assertEqual(self.calls(), ['custom-v', 'dpkg-deb'])

    def test_unknown_option_fails_before_compilation_or_artifact_rename(self):
        builds = self.root / 'builds'
        builds.mkdir()
        package = builds / 'vlsh_1.2.0_amd64.deb'
        package.write_text('existing')
        for script, args in (('pkg/dist.sh', ('build', '--typo')),
                             ('pkg/build.sh', ('--typo',))):
            result = self.run_command('sh', script, *args)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('unknown build option', result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(package.read_text(), 'existing')

    def test_explicit_package_requires_its_tool_before_compilation(self):
        for fmt, tool in (('deb', 'dpkg-deb'), ('rpm', 'rpmbuild')):
            with self.subTest(fmt=fmt):
                (self.bin / tool).unlink()
                self.env['PATH'] = str(self.bin)
                result = self.run_command('/bin/sh', 'pkg/build.sh', f'--{fmt}')
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"'{tool}' is required", result.stderr)
                self.assertEqual(self.calls(), [])

    def test_conflicting_os_and_format_options_are_rejected(self):
        for flags in (('--deb', '--freebsd'), ('--freebsd', '--openbsd')):
            result = self.run_command('sh', 'pkg/build.sh', *flags)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_preserves_only_selected_artifact_and_never_rearchives_history(self):
        builds = self.root / 'builds'
        builds.mkdir()
        existing = {'vlsh_1.2.0_amd64.deb': 'old deb',
                    'vlsh-1.2.0-1.x86_64.rpm': 'old rpm',
                    'vlsh_1.2.0_amd64_freebsd': 'old bsd',
                    'vlsh_1.2.0_arm64.deb': 'other architecture',
                    'vlsh_1.2.0_amd64_20260101_000000.deb': 'archive'}
        for name, content in existing.items():
            (builds / name).write_text(content)
        self.tool('date', 'echo 20261103_120000')
        self.success('make', 'dist-deb')
        archive = builds / 'vlsh_1.2.0_amd64_20261103_120000.deb'
        self.assertEqual(archive.read_text(), 'old deb')
        self.success('make', 'dist-deb')
        self.assertEqual(archive.read_text(), 'old deb')
        self.assertEqual((builds / 'vlsh_1.2.0_amd64_20261103_120000_1.deb').read_text(), 'deb')
        for name, content in existing.items():
            if name != 'vlsh_1.2.0_amd64.deb':
                self.assertEqual((builds / name).read_text(), content)

    def test_failed_package_builds_clean_up_staging(self):
        for fmt in ('deb', 'rpm'):
            with self.subTest(fmt=fmt):
                self.env[f'FAIL_{fmt.upper()}'] = '1'
                result = self.run_command('sh', 'pkg/build.sh', f'--{fmt}')
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(list(self.work.iterdir()), [])
                del self.env[f'FAIL_{fmt.upper()}']


if __name__ == '__main__':
    unittest.main(verbosity=2)
