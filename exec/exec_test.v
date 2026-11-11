module exec

import os
import utils

// alias_key_exists
// ---------------------------------------------------------------------------

fn test_alias_key_exists_found() {
	aliases := {
		'gs':  'git status'
		'gps': 'git push'
	}
	assert alias_key_exists('gs', aliases) == true
}

fn test_alias_key_exists_not_found() {
	aliases := {
		'gs': 'git status'
	}
	assert alias_key_exists('ll', aliases) == false
}

fn test_alias_key_exists_empty_map() {
	aliases := map[string]string{}
	assert alias_key_exists('gs', aliases) == false
}

fn test_alias_key_exists_exact_match_only() {
	aliases := {
		'gstat': 'git status'
	}
	// 'gs' is a prefix of 'gstat' but must NOT match
	assert alias_key_exists('gs', aliases) == false
}

fn test_alias_key_exists_empty_key() {
	aliases := {
		'': 'something'
	}
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
	os.write_file(tmp, '#!/usr/bin/env -S v\nprintln("hello")\n') or {
		assert false, err.msg()
		return
	}
	defer { os.rm(tmp) or {} }

	mut c := Cmd_object{
		cmd:  tmp
		args: []
	}
	c.find_exe() or {
		assert false, err.msg()
		return
	}
	assert c.fullcmd.ends_with('/v'), 'fullcmd should be the v binary, got: ${c.fullcmd}'
	assert c.args.len >= 2
	assert c.args[0] == 'run'
	assert c.args[1] == tmp
}

fn test_use_v_run_preserves_script_args() {
	pid := os.getpid()
	tmp := '/tmp/vlsh_test_args_${pid}.vsh'
	os.write_file(tmp, '#!/usr/bin/env -S v\nprintln("ok")\n') or {
		assert false, err.msg()
		return
	}
	defer { os.rm(tmp) or {} }

	mut c := Cmd_object{
		cmd:  tmp
		args: ['--flag', 'value']
	}
	c.find_exe() or {
		assert false, err.msg()
		return
	}
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
	os.write_file(tmp_exe, '#!/bin/sh\necho hi\n') or {
		assert false, err.msg()
		return
	}
	os.chmod(tmp_exe, 0o755) or {}
	defer { os.rm(tmp_exe) or {} }

	mut c := Cmd_object{
		cmd:  tmp_exe
		args: []
	}
	c.find_exe() or {
		assert false, err.msg()
		return
	}
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

fn test_path_command_completions_finds_prefix_in_path() {
	dir := os.join_path(os.temp_dir(), 'vlsh_pct_${os.getpid()}')
	os.mkdir_all(dir) or { assert false }
	defer { os.rmdir_all(dir) or {} }
	exe := os.join_path(dir, 'vfoo')
	os.write_file(exe, '') or { assert false }
	os.chmod(exe, 0o755) or { assert false }
	old := os.getenv('PATH')
	os.setenv('PATH', '${dir}:${old}', true)
	defer { os.setenv('PATH', old, true) }
	names := path_command_completions('vf')
	assert 'vfoo' in names
}

fn test_path_command_completions_skips_slash_prefix() {
	assert path_command_completions('bin/ls').len == 0
}

fn test_path_command_completions_dedupes_same_name_in_multiple_path_dirs() {
	dir1 := os.join_path(os.temp_dir(), 'vlsh_pd1_${os.getpid()}')
	dir2 := os.join_path(os.temp_dir(), 'vlsh_pd2_${os.getpid()}')
	os.mkdir_all(dir1) or { assert false }
	os.mkdir_all(dir2) or { assert false }
	defer { os.rmdir_all(dir1) or {} }
	defer { os.rmdir_all(dir2) or {} }
	os.write_file(os.join_path(dir1, 'samecmd'), '') or { assert false }
	os.write_file(os.join_path(dir2, 'samecmd'), '') or { assert false }
	os.chmod(os.join_path(dir1, 'samecmd'), 0o755) or { assert false }
	os.chmod(os.join_path(dir2, 'samecmd'), 0o755) or { assert false }
	old := os.getenv('PATH')
	os.setenv('PATH', '${dir1}:${dir2}', true)
	defer { os.setenv('PATH', old, true) }
	names := path_command_completions('same')
	assert names.filter(it == 'samecmd').len == 1
}

// ---------------------------------------------------------------------------
// internal_cmd_modifiers
// ---------------------------------------------------------------------------

fn test_internal_cmd_modifiers_adds_color_to_ls() {
	mut c := Cmd_object{
		cmd:  'ls'
		args: ['-la']
	}
	c.internal_cmd_modifiers()
	assert '--color=always' in c.args
}

fn test_internal_cmd_modifiers_does_not_duplicate_color() {
	mut c := Cmd_object{
		cmd:  'ls'
		args: ['--color=auto']
	}
	c.internal_cmd_modifiers()
	color_count := c.args.filter(it.contains('--color')).len
	assert color_count == 1
}

fn test_internal_cmd_modifiers_noop_for_other_commands() {
	mut c := Cmd_object{
		cmd:  'cat'
		args: ['file.txt']
	}
	c.internal_cmd_modifiers()
	assert c.args == ['file.txt']
}

fn test_parse_pipeline_preserves_literal_operators_and_empty_arguments() {
	mut task := Task{ tokens: utils.parse_tokens("printf '%s' '' '|' '>' | cat") }
	task.parse_pipe()!
	assert task.cmd.args == ['%s', '', '|', '>']
	assert task.pipe_cmds.len == 1
	assert task.pipe_cmds[0].cmd == 'cat'
}

fn test_parse_pipeline_extracts_redirections() {
	mut task := Task{ tokens: utils.parse_tokens('cat < input | cat >> output 2>&1') }
	task.parse_pipe()!
	assert task.cmd.redirects == [Redirect{ fd: 0, path: 'input', op: .input }]
	assert task.pipe_cmds[0].redirects == [
		Redirect{ fd: 1, path: 'output', op: .append },
		Redirect{ fd: 2, op: .duplicate, target: 1 },
	]
}

fn test_parse_pipeline_rejects_missing_stage_and_redirection_target() {
	for input in ['cat |', '| cat', 'cat >', 'cat > | cat'] {
		mut task := Task{ tokens: utils.parse_tokens(input) }
		task.parse_pipe() or { continue }
		assert false, 'expected syntax error for ${input}'
	}
}

fn test_path_completions_exclude_non_executables_and_directories() {
	dir := os.join_path(os.temp_dir(), 'vlsh_nonexec_${os.getpid()}')
	os.mkdir_all(os.join_path(dir, 'vdir'))!
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'vfile'), '')!
	old := os.getenv('PATH')
	os.setenv('PATH', dir, true)
	defer { os.setenv('PATH', old, true) }
	assert path_command_completions('v') == []string{}
}
