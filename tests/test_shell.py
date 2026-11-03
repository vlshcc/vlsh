#!/usr/bin/env python3
"""Black-box shell regressions. No third-party test dependencies required."""
import os
import pty
import select
import termios
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest

SHELL = str(Path(sys.argv.pop(1) if len(sys.argv) > 1 else './vlsh').resolve())


class ShellTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='vlsh-test-')
        self.addCleanup(self.tmp.cleanup)
        self.cwd = Path(self.tmp.name)
        self.env = os.environ.copy()
        self.env.update(HOME=self.tmp.name, LC_ALL='C', TERM='dumb')
        self.env.pop('IFS', None)

    def run_shell(self, command=None, *, stdin=None, args=None):
        argv = [SHELL] + (args if args is not None else ['-c', command])
        # A group lets timeouts clean up pipeline children as well as the shell.
        proc = subprocess.Popen(argv, cwd=self.cwd, env=self.env, text=True,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, start_new_session=True)
        try:
            out, err = proc.communicate(stdin, timeout=8)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.communicate()
            self.fail(f'shell hung: {argv!r}')
        return proc.returncode, out, err

    def assert_shell(self, command, output='', code=0):
        result = self.run_shell(command)
        self.assertEqual(result[:2], (code, output), result)
        return result

    def test_batch_does_not_create_config_or_history(self):
        self.assert_shell('echo hello', 'hello\n')
        self.assertEqual(list(self.cwd.iterdir()), [])

    def test_version_and_missing_command(self):
        self.assertEqual(self.run_shell(args=['--version'])[0], 0)
        self.assertEqual(self.run_shell(args=['-c'])[0], 2)

    def test_script_and_stdin_return_last_status(self):
        script = '# comment\necho hello\nfalse\n'
        (self.cwd / 'script').write_text(script)
        for kwargs in ({'args': ['script']}, {'args': [], 'stdin': script}):
            self.assertEqual(self.run_shell(**kwargs)[:2], (1, 'hello\n'))

    def test_chains_and_last_status(self):
        self.assert_shell('false && echo skipped || echo $?; true || echo skipped; echo $?', '1\n0\n')

    def test_trailing_semicolon_is_a_separator(self):
        self.assert_shell('echo hello;', 'hello\n')

    def test_unquoted_tilde_and_literal_redirect_target(self):
        self.assert_shell('printf "%s\\n" ~/file', f'{self.cwd}/file\n')
        self.assert_shell("printf hello > '~'; cat < '~'", 'hello')

    def test_alias_in_pipeline_tail(self):
        (self.cwd / '.vlshrc').write_text("alias count=wc -c\n")
        self.assert_shell('printf hello | count', '5\n')

    def test_assignment_only_persists(self):
        self.assert_shell('VLSH_X=hello; echo "$VLSH_X"', 'hello\n')

    def test_prefix_restores_existing_and_empty_values(self):
        self.env.update(VLSH_X='original', VLSH_EMPTY='')
        self.assert_shell('VLSH_X=one VLSH_X=two VLSH_EMPTY=value echo ok; echo "$VLSH_X"; echo "${VLSH_EMPTY:-empty}"', 'ok\noriginal\nempty\n')

    def test_prefix_is_removed_after_external_failure(self):
        self.assert_shell('VLSH_NEW=value missing_vlsh_command; echo "${VLSH_NEW:-unset}"', 'unset\n')

    def test_prefix_reaches_external_child(self):
        self.assert_shell("VLSH_X=value sh -c 'printf %s \"$VLSH_X\"'", 'value')

    def test_quotes_empty_arguments_and_single_expansion(self):
        self.env['VLSH_VALUE'] = '$HOME'
        self.assert_shell('printf "<%s>\\n" \'$HOME\' "$VLSH_VALUE" "" \'a"b\' "a\'b"', '<$HOME>\n<$HOME>\n<>\n<a"b>\n<a\'b>\n')

    def test_literal_operators_are_arguments(self):
        self.assert_shell("printf '%s\\n' '|' '>' '<' '>>' '2>&1'", '|\n>\n<\n>>\n2>&1\n')
        self.assert_shell("echo '|' '>'", '| >\n')

    def test_expanded_operators_are_arguments(self):
        self.env['VLSH_VALUE'] = '|'
        self.assert_shell('printf "%s\\n" "$VLSH_VALUE"', '|\n')

    def test_escaped_operators_and_spaces(self):
        self.assert_shell(r'printf "%s\n" a\ b \; \| \&\&', 'a b\n;\n|\n&&\n')

    def test_sed_pipe_delimiter(self):
        self.assert_shell("printf 'a\\n' | sed 's|a|b|g'", 'b\n')

    def test_large_streaming_pipeline(self):
        self.assert_shell('seq 1 100000 | cat | wc -l', '100000\n')

    def test_consumer_can_exit_early(self):
        self.assert_shell('yes | head -n 1', 'y\n')

    def test_empty_pipe_and_empty_input_file(self):
        (self.cwd / 'empty').write_text('')
        self.assert_shell('true | wc -c', '0\n')
        self.assert_shell('wc -c < empty', '0\n')

    def test_redirect_and_append_with_spaces(self):
        self.assert_shell("printf first > 'a b'; printf second >> 'a b'; cat < 'a b'", 'firstsecond')
        self.assert_shell("echo third > 'a b'; echo fourth >> 'a b'; cat 'a b'", 'third\nfourth\n')

    def test_redirect_failure_is_nonzero(self):
        for command in ('cat < missing', 'printf x > missing/out', 'echo x > missing/out', 'ocp', 'ocp x'):
            with self.subTest(command=command):
                self.assertNotEqual(self.run_shell(command)[0], 0)

    def test_stderr_is_preserved_and_merge_is_ordered(self):
        result = self.assert_shell("sh -c 'printf out; printf err >&2' | cat", 'out')
        self.assertEqual(result[2], 'err')
        self.assert_shell("sh -c 'printf out; printf err >&2; printf end' 2>&1 | cat", 'outerrend')

    def test_large_stderr_does_not_deadlock(self):
        result = self.assert_shell("sh -c 'seq 1 100000 >&2; printf done' | cat", 'done')
        self.assertEqual(len(result[2].splitlines()), 100000)

    def test_pipeline_exit_status_comes_from_tail(self):
        self.assert_shell('false | true', code=0)
        self.assert_shell('true | false', code=1)
        self.assert_shell("printf x | sh -c 'cat; exit 7'", 'x', code=7)

    def test_relative_path_with_slash(self):
        (self.cwd / 'bin').mkdir()
        command = self.cwd / 'bin' / 'hello'
        command.write_text('#!/bin/sh\nprintf hello')
        command.chmod(0o755)
        self.assert_shell('bin/hello', 'hello')

    def test_lookup_skips_non_executable_and_directory(self):
        for name in ('first', 'second'):
            (self.cwd / name).mkdir()
        (self.cwd / 'first' / 'hello').write_text('not executable')
        command = self.cwd / 'second' / 'hello'
        command.write_text('#!/bin/sh\nprintf hello')
        command.chmod(0o755)
        self.env['PATH'] = f'{self.cwd}/first:{self.cwd}/second:/usr/bin:/bin'
        self.assert_shell('hello', 'hello')
        (self.cwd / 'first' / 'hello').unlink()
        (self.cwd / 'first' / 'hello').mkdir()
        self.assert_shell('hello', 'hello')

    def test_alias_cycle_does_not_crash(self):
        (self.cwd / '.vlshrc').write_text('alias a=b\nalias b=a\n')
        result = self.run_shell('a')
        self.assertEqual(result[0], 1, result)
        self.assertIn('alias', result[2])

    def test_alias_preserves_quoted_arguments(self):
        (self.cwd / '.vlshrc').write_text('alias p=printf "<%s>\\n" "a b"\n')
        self.assert_shell('p "c d"', '<a b>\n<c d>\n')

    def test_malformed_input_does_not_execute_prefix(self):
        for command in ('echo bad |', 'echo bad &&', 'echo bad ||', '| echo bad', 'echo bad; ; echo bad', "echo 'bad", 'echo "bad', 'echo ${bad'):
            with self.subTest(command=command):
                result = self.run_shell(command)
                self.assertEqual(result[:2], (2, ''), result)

    def test_interactive_cancel_and_terminal_restore(self):
        pid, master = pty.fork()
        if pid == 0:
            os.chdir(self.cwd)
            os.execve(SHELL, [SHELL], self.env)
        reaped = False

        def read_until(expected):
            output = b''
            deadline = time.monotonic() + 5
            while expected not in output:
                if time.monotonic() >= deadline:
                    self.fail(f'interactive shell stalled: {output!r}')
                if select.select([master], [], [], 0.1)[0]:
                    output += os.read(master, 8192)
            return output

        try:
            read_until(b'- ')
            os.write(master, b'echo cancelled')
            # Wait until readline has consumed the pending input before Ctrl+C.
            read_until(b'cancelled')
            os.write(master, b'\x03')
            read_until(b'- ')
            os.write(master, b'echo interactive\r')
            output = read_until(b'\r\ninteractive\r\n')
            self.assertIn(b'\r\ninteractive\r\n', output)
            os.write(master, b'exit\r')
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                result, status = os.waitpid(pid, os.WNOHANG)
                if result:
                    reaped = True
                    self.assertEqual(os.waitstatus_to_exitcode(status), 0)
                    break
                time.sleep(0.02)
            self.assertTrue(reaped, 'interactive shell did not exit')
            attrs = termios.tcgetattr(master)
            self.assertTrue(attrs[3] & termios.ICANON)
            self.assertTrue(attrs[3] & termios.ECHO)
        finally:
            if not reaped:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
            os.close(master)

    def test_sigint_kills_child_and_shell_can_continue(self):
        # Send to the foreground group, as a terminal does on Ctrl+C.
        proc = subprocess.Popen([SHELL, '-c', 'sleep 30; echo survived'], cwd=self.cwd,
                                env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, start_new_session=True)
        try:
            time.sleep(0.3)
            os.killpg(proc.pid, signal.SIGINT)
            out, err = proc.communicate(timeout=5)
            self.assertEqual((proc.returncode, out), (0, 'survived\n'), err)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.communicate()


if __name__ == '__main__':
    unittest.main(verbosity=2)
