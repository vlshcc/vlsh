module exec

import os

// ---------------------------------------------------------------------------
// norm_pipe
// ---------------------------------------------------------------------------

fn test_norm_pipe_no_pipe() {
	assert norm_pipe('ls -la') == 'ls -la'
}

fn test_norm_pipe_single_pipe() {
	assert norm_pipe('ls | wc') == 'ls|wc'
}

fn test_norm_pipe_trims_whitespace_around_pipe() {
	assert norm_pipe('  ls  |  wc  ') == 'ls|wc'
}

fn test_norm_pipe_multiple_pipes() {
	assert norm_pipe('cat f | grep x | wc') == 'cat f|grep x|wc'
}

fn test_norm_pipe_empty_segments_are_dropped() {
	// double pipe produces an empty segment that must be discarded
	assert norm_pipe('ls || wc') == 'ls|wc'
}

fn test_norm_pipe_leading_pipe_ignored() {
	assert norm_pipe('| ls') == 'ls'
}

fn test_norm_pipe_trailing_pipe_ignored() {
	assert norm_pipe('ls |') == 'ls'
}

fn test_norm_pipe_only_whitespace() {
	assert norm_pipe('   ') == ''
}

fn test_norm_pipe_empty_string() {
	assert norm_pipe('') == ''
}

// ---------------------------------------------------------------------------
// requote_args
// ---------------------------------------------------------------------------

fn test_requote_args_no_args() {
	assert requote_args([]) == ''
}

fn test_requote_args_single_no_space() {
	assert requote_args(['-la']) == '-la'
}

fn test_requote_args_multiple_no_spaces() {
	assert requote_args(['-l', '-a']) == '-l -a'
}

fn test_requote_args_arg_with_space_gets_quoted() {
	assert requote_args(['hello world']) == '"hello world"'
}

fn test_requote_args_mixed() {
	assert requote_args(['--flag', 'some value', 'plain']) == '--flag "some value" plain'
}

fn test_requote_args_all_with_spaces() {
	assert requote_args(['a b', 'c d']) == '"a b" "c d"'
}

// ---------------------------------------------------------------------------
// alias_key_exists
// ---------------------------------------------------------------------------

fn test_alias_key_exists_found() {
	aliases := {'gs': 'git status', 'gps': 'git push'}
	assert alias_key_exists('gs', aliases) == true
}

fn test_alias_key_exists_not_found() {
	aliases := {'gs': 'git status'}
	assert alias_key_exists('ll', aliases) == false
}

fn test_alias_key_exists_empty_map() {
	aliases := map[string]string{}
	assert alias_key_exists('gs', aliases) == false
}

fn test_alias_key_exists_exact_match_only() {
	aliases := {'gstat': 'git status'}
	// 'gs' is a prefix of 'gstat' but must NOT match
	assert alias_key_exists('gs', aliases) == false
}

fn test_alias_key_exists_empty_key() {
	aliases := {'': 'something'}
	assert alias_key_exists('', aliases) == true
}

// ---------------------------------------------------------------------------
// expand_tilde
// ---------------------------------------------------------------------------

fn test_expand_tilde_plain_string_unchanged() {
	assert expand_tilde('/usr/bin') == '/usr/bin'
}

fn test_expand_tilde_tilde_alone() {
	result := expand_tilde('~')
	assert result == os.home_dir()
}

fn test_expand_tilde_tilde_slash() {
	result := expand_tilde('~/foo/bar')
	assert result == os.home_dir() + '/foo/bar'
}

fn test_expand_tilde_embedded_tilde_unchanged() {
	assert expand_tilde('/foo/~/bar') == '/foo/~/bar'
}

fn test_expand_tilde_empty_string() {
	assert expand_tilde('') == ''
}

// ---------------------------------------------------------------------------
// parse_redirect — stdout (> and >>)
// ---------------------------------------------------------------------------

fn test_parse_redirect_no_redirect() {
	args, file, app, stdin_file := parse_redirect(['-l', '-a'])
	assert args       == ['-l', '-a']
	assert file       == ''
	assert app        == false
	assert stdin_file == ''
}

fn test_parse_redirect_truncate() {
	args, file, app, stdin_file := parse_redirect(['echo', 'hello', '>', '/tmp/out.txt'])
	assert args       == ['echo', 'hello']
	assert file       == '/tmp/out.txt'
	assert app        == false
	assert stdin_file == ''
}

fn test_parse_redirect_append() {
	args, file, app, stdin_file := parse_redirect(['echo', 'hello', '>>', '/tmp/out.txt'])
	assert args       == ['echo', 'hello']
	assert file       == '/tmp/out.txt'
	assert app        == true
	assert stdin_file == ''
}

fn test_parse_redirect_strips_only_redirect_tokens() {
	args, file, _, _ := parse_redirect(['ls', '-la', '>', '/tmp/ls.txt'])
	assert args == ['ls', '-la']
	assert file == '/tmp/ls.txt'
}

fn test_parse_redirect_empty_args() {
	args, file, app, stdin_file := parse_redirect([])
	assert args       == []string{}
	assert file       == ''
	assert app        == false
	assert stdin_file == ''
}

fn test_parse_redirect_tilde_in_output_target() {
	_, file, _, _ := parse_redirect(['echo', 'x', '>', '~/out.txt'])
	assert file == os.home_dir() + '/out.txt'
}

// ---------------------------------------------------------------------------
// parse_redirect — stdin (<)
// ---------------------------------------------------------------------------

fn test_parse_redirect_stdin_file() {
	args, file, app, stdin_file := parse_redirect(['cat', '<', '/tmp/in.txt'])
	assert args       == ['cat']
	assert file       == ''
	assert app        == false
	assert stdin_file == '/tmp/in.txt'
}

fn test_parse_redirect_stdin_tilde_expanded() {
	_, _, _, stdin_file := parse_redirect(['cat', '<', '~/input.txt'])
	assert stdin_file == os.home_dir() + '/input.txt'
}

fn test_parse_redirect_stdin_and_stdout_together() {
	args, file, app, stdin_file := parse_redirect(['cmd', '<', '/tmp/in.txt', '>', '/tmp/out.txt'])
	assert args       == ['cmd']
	assert file       == '/tmp/out.txt'
	assert app        == false
	assert stdin_file == '/tmp/in.txt'
}

fn test_parse_redirect_stdin_and_append_together() {
	args, file, app, stdin_file := parse_redirect(['cmd', '<', '/tmp/in.txt', '>>', '/tmp/out.txt'])
	assert args       == ['cmd']
	assert file       == '/tmp/out.txt'
	assert app        == true
	assert stdin_file == '/tmp/in.txt'
}

fn test_parse_redirect_no_stdin_file_when_absent() {
	_, _, _, stdin_file := parse_redirect(['-l', '-a'])
	assert stdin_file == ''
}

fn test_parse_redirect_stdin_strips_both_tokens() {
	args, _, _, stdin_file := parse_redirect(['wc', '-l', '<', '/tmp/data.txt'])
	assert args       == ['wc', '-l']
	assert stdin_file == '/tmp/data.txt'
}

// ---------------------------------------------------------------------------
// find_v_exe
// ---------------------------------------------------------------------------

fn test_find_v_exe_finds_v_binary() {
	result := find_v_exe()
	assert result != '', 'v binary not found in PATH'
	assert result.ends_with('/v')
}

// ---------------------------------------------------------------------------
// use_v_run (via find_exe on a real .vsh file)
// ---------------------------------------------------------------------------

fn test_use_v_run_sets_fullcmd_to_v() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_test_script_${pid}.vsh'
	os.write_file(tmp, '#!/usr/bin/env -S v\nprintln("hello")\n') or { assert false, err.msg(); return }
	defer { os.rm(tmp) or {} }

	mut c := Cmd_object{
		cmd:  tmp,
		args: [],
	}
	c.find_exe() or { assert false, err.msg(); return }
	assert c.fullcmd.ends_with('/v'), 'fullcmd should be the v binary, got: ${c.fullcmd}'
	assert c.args.len >= 2
	assert c.args[0] == 'run'
	assert c.args[1] == tmp
}

fn test_use_v_run_preserves_script_args() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_test_args_${pid}.vsh'
	os.write_file(tmp, '#!/usr/bin/env -S v\nprintln("ok")\n') or { assert false, err.msg(); return }
	defer { os.rm(tmp) or {} }

	mut c := Cmd_object{
		cmd:  tmp,
		args: ['--flag', 'value'],
	}
	c.find_exe() or { assert false, err.msg(); return }
	assert c.args[0] == 'run'
	assert c.args[1] == tmp
	assert c.args[2] == '--flag'
	assert c.args[3] == 'value'
}

// ---------------------------------------------------------------------------
// find_exe — relative path handling
// ---------------------------------------------------------------------------

fn test_find_exe_absolute_path_resolved() {
	pid := os.getpid()
	tmp_exe := '/tmp/vlsh_test_exe_${pid}'
	os.write_file(tmp_exe, '#!/bin/sh\necho hi\n') or { assert false, err.msg(); return }
	os.chmod(tmp_exe, 0o755) or {}
	defer { os.rm(tmp_exe) or {} }

	mut c := Cmd_object{
		cmd:  tmp_exe,
		args: [],
	}
	c.find_exe() or { assert false, err.msg(); return }
	assert c.fullcmd == tmp_exe
}

// ---------------------------------------------------------------------------
// get_search_paths
// ---------------------------------------------------------------------------

fn test_get_search_paths_returns_path_entries() {
	paths := get_search_paths()
	assert paths.len > 0
}

fn test_get_search_paths_falls_back_when_empty() {
	old := os.getenv('PATH')
	os.setenv('PATH', '', true)
	defer { os.setenv('PATH', old, true) }
	paths := get_search_paths()
	assert '/usr/bin' in paths
	assert '/bin' in paths
}

// ---------------------------------------------------------------------------
// internal_cmd_modifiers
// ---------------------------------------------------------------------------

fn test_internal_cmd_modifiers_adds_color_to_ls() {
	mut c := Cmd_object{
		cmd:  'ls',
		args: ['-la'],
	}
	c.internal_cmd_modifiers()
	assert '--color=always' in c.args
}

fn test_internal_cmd_modifiers_does_not_duplicate_color() {
	mut c := Cmd_object{
		cmd:  'ls',
		args: ['--color=auto'],
	}
	c.internal_cmd_modifiers()
	color_count := c.args.filter(it.contains('--color')).len
	assert color_count == 1
}

fn test_internal_cmd_modifiers_noop_for_other_commands() {
	mut c := Cmd_object{
		cmd:  'cat',
		args: ['file.txt'],
	}
	c.internal_cmd_modifiers()
	assert c.args == ['file.txt']
}
