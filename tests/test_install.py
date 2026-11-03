#!/usr/bin/env python3
"""Exercise make install without writing to the host's shell registry."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

MAKEFILE = Path(__file__).resolve().parents[1] / 'Makefile'


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vlsh-install-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.prefix = self.root / 'prefix'
        self.registry = self.root / 'shells'
        self.shell_path = str(self.prefix / 'bin' / 'vlsh')
        self.binary = self.root / 'vlsh'
        self.binary.write_text('#!/bin/sh\nexit 0\n')
        self.binary.chmod(0o755)
        self.registry.write_text('# valid shells\n/bin/sh\n')

    def install(self, *variables):
        env = os.environ.copy()
        env['PATH'] = '/usr/bin:/bin'
        # Do not inherit make overrides that could redirect test installation.
        for name in ('MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES', 'DESTDIR',
                     'PREFIX', 'SHELLS_FILE', 'REGISTER_SHELL'):
            env.pop(name, None)
        return subprocess.run(
            ['make', '-f', str(MAKEFILE), 'install', f'PREFIX={self.prefix}',
             f'SHELLS_FILE={self.registry}', 'REGISTER_SHELL=1', 'DESTDIR=',
             'V=/missing-v-compiler', *variables],
            cwd=self.root, env=env, capture_output=True, text=True, timeout=10,
        )

    def assert_installed(self, result):
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        installed = self.prefix / 'bin' / 'vlsh'
        self.assertEqual(installed.read_bytes(), self.binary.read_bytes())
        self.assertEqual(installed.stat().st_mode & 0o777, 0o755)

    def test_registers_exact_installed_path_once(self):
        original = self.registry.read_text()
        self.assert_installed(self.install())
        first = self.registry.read_text()
        self.assertTrue(first.startswith(original))
        self.assertEqual(first.splitlines().count(self.shell_path), 1)
        self.assert_installed(self.install())
        self.assertEqual(self.registry.read_text(), first)

    def test_creates_missing_registry(self):
        self.registry.unlink()
        self.assert_installed(self.install())
        self.assertEqual(self.registry.read_text().split(), [self.shell_path])

    def test_preserves_existing_line_without_final_newline(self):
        self.registry.write_text('/bin/sh')
        self.assert_installed(self.install())
        self.assertEqual(self.registry.read_text().splitlines(), ['/bin/sh', self.shell_path])

    def test_does_not_append_when_path_already_exists(self):
        content = f'# valid shells\n/bin/sh\n{self.shell_path}'
        self.registry.write_text(content)
        self.assert_installed(self.install())
        self.assertEqual(self.registry.read_text(), content)

    def test_staging_leaves_registry_unchanged(self):
        content = self.registry.read_text()
        staging = self.root / 'staging root'
        result = self.install(f'DESTDIR={staging}')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        staged_binary = staging / str(self.prefix).lstrip('/') / 'bin' / 'vlsh'
        self.assertEqual(staged_binary.read_bytes(), self.binary.read_bytes())
        self.assertEqual(self.registry.read_text(), content)

    def test_registration_can_be_disabled(self):
        content = self.registry.read_text()
        self.assert_installed(self.install('REGISTER_SHELL=0'))
        self.assertEqual(self.registry.read_text(), content)

    def test_registration_failure_is_reported(self):
        self.registry.unlink()
        self.registry.mkdir()
        result = self.install()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_binary_requires_build_without_invoking_compiler(self):
        self.binary.unlink()
        content = self.registry.read_text()
        result = self.install()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('make build', result.stderr)
        self.assertFalse((self.prefix / 'bin' / 'vlsh').exists())
        self.assertEqual(self.registry.read_text(), content)


if __name__ == '__main__':
    unittest.main(verbosity=2)
