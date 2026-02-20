module shellops

import os

// ---------------------------------------------------------------------------
// split_commands — && (and)
// ---------------------------------------------------------------------------

fn test_split_commands_single_command() {
	result := split_commands('ls -la')
	assert result == [ChainPart{ cmd: 'ls -la', pre_op: '' }]
}

fn test_split_commands_and_two_commands() {
	result := split_commands('touch /tmp/x && echo ok')
	assert result == [
		ChainPart{ cmd: 'touch /tmp/x', pre_op: '' },
		ChainPart{ cmd: 'echo ok',      pre_op: '&&' },
	]
}

fn test_split_commands_and_three_commands() {
	result := split_commands('a && b && c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '&&' },
		ChainPart{ cmd: 'c', pre_op: '&&' },
	]
}

fn test_split_commands_no_operator() {
	result := split_commands('echo hello')
	assert result == [ChainPart{ cmd: 'echo hello', pre_op: '' }]
}

fn test_split_commands_empty_string() {
	assert split_commands('') == []ChainPart{}
}

fn test_split_commands_trims_whitespace_around_operator() {
	result := split_commands('  a  &&  b  ')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '&&' },
	]
}

fn test_split_commands_single_quoted_and_not_split() {
	result := split_commands("echo 'foo && bar'")
	assert result == [ChainPart{ cmd: "echo 'foo && bar'", pre_op: '' }]
}

fn test_split_commands_double_quoted_and_not_split() {
	result := split_commands('echo "foo && bar"')
	assert result == [ChainPart{ cmd: 'echo "foo && bar"', pre_op: '' }]
}

// ---------------------------------------------------------------------------
// split_commands — || (or)
// ---------------------------------------------------------------------------

fn test_split_commands_or_two_commands() {
	result := split_commands('false || echo ok')
	assert result == [
		ChainPart{ cmd: 'false',   pre_op: '' },
		ChainPart{ cmd: 'echo ok', pre_op: '||' },
	]
}

fn test_split_commands_or_three_commands() {
	result := split_commands('a || b || c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '||' },
		ChainPart{ cmd: 'c', pre_op: '||' },
	]
}

fn test_split_commands_single_quoted_or_not_split() {
	result := split_commands("echo 'foo || bar'")
	assert result == [ChainPart{ cmd: "echo 'foo || bar'", pre_op: '' }]
}

fn test_split_commands_double_quoted_or_not_split() {
	result := split_commands('echo "foo || bar"')
	assert result == [ChainPart{ cmd: 'echo "foo || bar"', pre_op: '' }]
}

// ---------------------------------------------------------------------------
// split_commands — ; (semicolon)
// ---------------------------------------------------------------------------

fn test_split_commands_semicolon_two_commands() {
	result := split_commands('echo hello ; echo world')
	assert result == [
		ChainPart{ cmd: 'echo hello', pre_op: '' },
		ChainPart{ cmd: 'echo world', pre_op: ';' },
	]
}

fn test_split_commands_semicolon_three_commands() {
	result := split_commands('a ; b ; c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: ';' },
		ChainPart{ cmd: 'c', pre_op: ';' },
	]
}

fn test_split_commands_semicolon_no_spaces() {
	result := split_commands('a;b')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: ';' },
	]
}

fn test_split_commands_single_quoted_semicolon_not_split() {
	result := split_commands("echo 'foo ; bar'")
	assert result == [ChainPart{ cmd: "echo 'foo ; bar'", pre_op: '' }]
}

fn test_split_commands_double_quoted_semicolon_not_split() {
	result := split_commands('echo "foo ; bar"')
	assert result == [ChainPart{ cmd: 'echo "foo ; bar"', pre_op: '' }]
}

// ---------------------------------------------------------------------------
// split_commands — mixed operators
// ---------------------------------------------------------------------------

fn test_split_commands_and_then_or() {
	result := split_commands('a && b || c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '&&' },
		ChainPart{ cmd: 'c', pre_op: '||' },
	]
}

fn test_split_commands_or_then_and() {
	result := split_commands('a || b && c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '||' },
		ChainPart{ cmd: 'c', pre_op: '&&' },
	]
}

fn test_split_commands_semicolon_then_and() {
	result := split_commands('a ; b && c')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: ';' },
		ChainPart{ cmd: 'c', pre_op: '&&' },
	]
}

fn test_split_commands_all_three_operators() {
	result := split_commands('a && b || c ; d')
	assert result == [
		ChainPart{ cmd: 'a', pre_op: '' },
		ChainPart{ cmd: 'b', pre_op: '&&' },
		ChainPart{ cmd: 'c', pre_op: '||' },
		ChainPart{ cmd: 'd', pre_op: ';' },
	]
}

// ---------------------------------------------------------------------------
// split_commands — pipe | stays in buffer (not a chain separator)
// ---------------------------------------------------------------------------

fn test_split_commands_lone_pipe_not_split() {
	result := split_commands('cat file | wc')
	assert result == [ChainPart{ cmd: 'cat file | wc', pre_op: '' }]
}

fn test_split_commands_pipe_combined_with_and_operator() {
	result := split_commands('cat file | wc && echo done')
	assert result == [
		ChainPart{ cmd: 'cat file | wc', pre_op: '' },
		ChainPart{ cmd: 'echo done',     pre_op: '&&' },
	]
}

fn test_split_commands_pipe_combined_with_or_operator() {
	result := split_commands('cat file | grep x || echo missing')
	assert result == [
		ChainPart{ cmd: 'cat file | grep x', pre_op: '' },
		ChainPart{ cmd: 'echo missing',      pre_op: '||' },
	]
}

// ---------------------------------------------------------------------------
// builtin_redirect
// ---------------------------------------------------------------------------

fn test_builtin_redirect_no_redirect() {
	args, file, app := builtin_redirect(['echo', 'hello'])
	assert args == ['echo', 'hello']
	assert file == ''
	assert app  == false
}

fn test_builtin_redirect_truncate() {
	args, file, app := builtin_redirect(['hello', '>', '/tmp/out.txt'])
	assert args == ['hello']
	assert file == '/tmp/out.txt'
	assert app  == false
}

fn test_builtin_redirect_append() {
	args, file, app := builtin_redirect(['hello', '>>', '/tmp/out.txt'])
	assert args == ['hello']
	assert file == '/tmp/out.txt'
	assert app  == true
}

fn test_builtin_redirect_tilde_slash_in_target() {
	_, file, _ := builtin_redirect(['hello', '>', '~/out.txt'])
	assert file == os.home_dir() + '/out.txt'
}

fn test_builtin_redirect_tilde_alone_in_target() {
	_, file, _ := builtin_redirect(['hello', '>', '~'])
	assert file == os.home_dir()
}

fn test_builtin_redirect_empty_args() {
	args, file, app := builtin_redirect([])
	assert args == []string{}
	assert file == ''
	assert app  == false
}

fn test_builtin_redirect_only_redirect_tokens() {
	args, file, _ := builtin_redirect(['>', '/tmp/out.txt'])
	assert args == []string{}
	assert file == '/tmp/out.txt'
}

fn test_builtin_redirect_strips_only_redirect_tokens() {
	args, file, _ := builtin_redirect(['ls', '-la', '>', '/tmp/ls.txt'])
	assert args == ['ls', '-la']
	assert file == '/tmp/ls.txt'
}

// ---------------------------------------------------------------------------
// write_redirect
// ---------------------------------------------------------------------------

fn test_write_redirect_creates_file() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_wr_create_${pid}.txt'
	defer { os.rm(tmp) or {} }

	write_redirect(tmp, 'hello\n', false) or { assert false, err.msg(); return }
	content := os.read_file(tmp) or { assert false, err.msg(); return }
	assert content == 'hello\n'
}

fn test_write_redirect_truncates_existing_content() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_wr_trunc_${pid}.txt'
	defer { os.rm(tmp) or {} }

	os.write_file(tmp, 'old content that should disappear\n') or { assert false, err.msg(); return }
	write_redirect(tmp, 'new\n', false) or { assert false, err.msg(); return }
	content := os.read_file(tmp) or { assert false, err.msg(); return }
	assert content == 'new\n'
}

fn test_write_redirect_appends_to_existing() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_wr_append_${pid}.txt'
	defer { os.rm(tmp) or {} }

	write_redirect(tmp, 'line1\n', false) or { assert false, err.msg(); return }
	write_redirect(tmp, 'line2\n', true)  or { assert false, err.msg(); return }
	content := os.read_file(tmp) or { assert false, err.msg(); return }
	assert content == 'line1\nline2\n'
}

fn test_write_redirect_creates_file_in_append_mode() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_wr_newappend_${pid}.txt'
	defer { os.rm(tmp) or {} }

	write_redirect(tmp, 'only line\n', true) or { assert false, err.msg(); return }
	content := os.read_file(tmp) or { assert false, err.msg(); return }
	assert content == 'only line\n'
}

// ---------------------------------------------------------------------------
// venv helpers (venv_tracked / venv_track / venv_untrack)
// ---------------------------------------------------------------------------

fn test_venv_tracked_empty_when_no_registry() {
	os.unsetenv(venv_registry)
	assert venv_tracked() == []string{}
}

fn test_venv_track_adds_key() {
	os.unsetenv(venv_registry)
	venv_track('TEST_VENV_KEY')
	keys := venv_tracked()
	assert 'TEST_VENV_KEY' in keys
	os.unsetenv(venv_registry)
}

fn test_venv_track_no_duplicates() {
	os.unsetenv(venv_registry)
	venv_track('DUP_KEY')
	venv_track('DUP_KEY')
	keys := venv_tracked()
	assert keys.filter(it == 'DUP_KEY').len == 1
	os.unsetenv(venv_registry)
}

fn test_venv_untrack_removes_key() {
	os.unsetenv(venv_registry)
	venv_track('RM_KEY')
	venv_untrack('RM_KEY')
	keys := venv_tracked()
	assert 'RM_KEY' !in keys
}

fn test_venv_untrack_clears_registry_when_last_key() {
	os.unsetenv(venv_registry)
	venv_track('ONLY_KEY')
	venv_untrack('ONLY_KEY')
	assert os.getenv(venv_registry) == ''
}

fn test_venv_untrack_nonexistent_key_is_noop() {
	os.unsetenv(venv_registry)
	venv_track('A')
	venv_untrack('B') // B was never tracked
	assert 'A' in venv_tracked()
	os.unsetenv(venv_registry)
}
