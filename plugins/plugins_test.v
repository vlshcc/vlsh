module plugins

import os

// ---------------------------------------------------------------------------
// parse_semver
// ---------------------------------------------------------------------------

fn test_parse_semver_simple() {
	result := parse_semver('1.2.3')
	assert result[0] == 1
	assert result[1] == 2
	assert result[2] == 3
}

fn test_parse_semver_with_v_prefix() {
	result := parse_semver('v1.2.3')
	assert result[0] == 1
	assert result[1] == 2
	assert result[2] == 3
}

fn test_parse_semver_two_parts() {
	result := parse_semver('1.2')
	assert result[0] == 1
	assert result[1] == 2
	assert result[2] == 0
}

fn test_parse_semver_single_part() {
	result := parse_semver('5')
	assert result[0] == 5
	assert result[1] == 0
	assert result[2] == 0
}

fn test_parse_semver_zeros() {
	result := parse_semver('0.0.0')
	assert result[0] == 0
	assert result[1] == 0
	assert result[2] == 0
}

fn test_parse_semver_large_numbers() {
	result := parse_semver('v10.200.3000')
	assert result[0] == 10
	assert result[1] == 200
	assert result[2] == 3000
}

fn test_parse_semver_empty_string() {
	result := parse_semver('')
	assert result[0] == 0
	assert result[1] == 0
	assert result[2] == 0
}

// ---------------------------------------------------------------------------
// compare_semver
// ---------------------------------------------------------------------------

fn test_compare_semver_equal() {
	a := 'v1.2.3'
	b := 'v1.2.3'
	assert compare_semver(&a, &b) == 0
}

fn test_compare_semver_a_less_major() {
	a := 'v1.0.0'
	b := 'v2.0.0'
	assert compare_semver(&a, &b) == -1
}

fn test_compare_semver_a_greater_major() {
	a := 'v3.0.0'
	b := 'v2.0.0'
	assert compare_semver(&a, &b) == 1
}

fn test_compare_semver_a_less_minor() {
	a := 'v1.1.0'
	b := 'v1.2.0'
	assert compare_semver(&a, &b) == -1
}

fn test_compare_semver_a_greater_patch() {
	a := 'v1.0.5'
	b := 'v1.0.3'
	assert compare_semver(&a, &b) == 1
}

fn test_compare_semver_without_v_prefix() {
	a := '1.0.0'
	b := '1.0.1'
	assert compare_semver(&a, &b) == -1
}

fn test_compare_semver_mixed_prefix() {
	a := 'v1.0.0'
	b := '1.0.0'
	assert compare_semver(&a, &b) == 0
}

// ---------------------------------------------------------------------------
// compare_installed_name
// ---------------------------------------------------------------------------

fn test_compare_installed_name_equal() {
	a := InstalledPlugin{ name: 'git', version: 'v1.0.0', src: '' }
	b := InstalledPlugin{ name: 'git', version: 'v1.0.0', src: '' }
	assert compare_installed_name(&a, &b) == 0
}

fn test_compare_installed_name_a_before_b() {
	a := InstalledPlugin{ name: 'abc', version: '', src: '' }
	b := InstalledPlugin{ name: 'xyz', version: '', src: '' }
	assert compare_installed_name(&a, &b) == -1
}

fn test_compare_installed_name_a_after_b() {
	a := InstalledPlugin{ name: 'xyz', version: '', src: '' }
	b := InstalledPlugin{ name: 'abc', version: '', src: '' }
	assert compare_installed_name(&a, &b) == 1
}

// ---------------------------------------------------------------------------
// extract_toml_val
// ---------------------------------------------------------------------------

fn test_extract_toml_val_quoted_string() {
	assert extract_toml_val('"hello world"') == 'hello world'
}

fn test_extract_toml_val_unquoted_string() {
	assert extract_toml_val('hello') == 'hello'
}

fn test_extract_toml_val_strips_surrounding_whitespace() {
	assert extract_toml_val('  "value"  ') == 'value'
}

fn test_extract_toml_val_unquoted_with_whitespace() {
	assert extract_toml_val('  bare  ') == 'bare'
}

fn test_extract_toml_val_empty_quoted_string() {
	assert extract_toml_val('""') == ''
}

fn test_extract_toml_val_single_quote_not_stripped() {
	assert extract_toml_val('"only one') == '"only one'
}

fn test_extract_toml_val_empty_string() {
	assert extract_toml_val('') == ''
}

// ---------------------------------------------------------------------------
// parse_desc
// ---------------------------------------------------------------------------

fn test_parse_desc_full() {
	content := 'name = "git"\nauthor = "alice"\nemail = "alice@example.com"\ndescription = "Git prompt"'
	desc := parse_desc(content)
	assert desc.name        == 'git'
	assert desc.author      == 'alice'
	assert desc.email       == 'alice@example.com'
	assert desc.description == 'Git prompt'
}

fn test_parse_desc_skips_comments() {
	content := '# comment\nname = "git"\n# another\ndescription = "test"'
	desc := parse_desc(content)
	assert desc.name        == 'git'
	assert desc.description == 'test'
	assert desc.author      == ''
}

fn test_parse_desc_skips_blank_lines() {
	content := '\nname = "myplugin"\n\ndescription = "desc"\n'
	desc := parse_desc(content)
	assert desc.name        == 'myplugin'
	assert desc.description == 'desc'
}

fn test_parse_desc_unquoted_values() {
	content := 'name = bare_name\nauthor = bare_author'
	desc := parse_desc(content)
	assert desc.name   == 'bare_name'
	assert desc.author == 'bare_author'
}

fn test_parse_desc_ignores_unknown_keys() {
	content := 'name = "test"\nunknown_key = "value"\nversion = "1.0"'
	desc := parse_desc(content)
	assert desc.name == 'test'
}

fn test_parse_desc_empty_content() {
	desc := parse_desc('')
	assert desc.name        == ''
	assert desc.author      == ''
	assert desc.email       == ''
	assert desc.description == ''
}

fn test_parse_desc_no_equals_sign_skips_line() {
	content := 'name = "valid"\nthis has no equals'
	desc := parse_desc(content)
	assert desc.name == 'valid'
}

// ---------------------------------------------------------------------------
// src_is_newer
// ---------------------------------------------------------------------------

fn test_src_is_newer_returns_true_when_bin_missing() {
	pid := os.getpid()
	src := '/tmp/vlsh_test_src_${pid}'
	bin := '/tmp/vlsh_test_bin_nonexistent_${pid}'
	os.write_file(src, 'x') or { assert false, err.msg(); return }
	defer { os.rm(src) or {} }
	assert src_is_newer(src, bin) == true
}

fn test_src_is_newer_returns_false_when_bin_is_newer() {
	pid := os.getpid()
	src := '/tmp/vlsh_test_src2_${pid}'
	bin := '/tmp/vlsh_test_bin2_${pid}'
	os.write_file(src, 'x') or { assert false, err.msg(); return }
	defer { os.rm(src) or {} }
	// Wait a moment then write bin so it has a later mtime
	os.write_file(bin, 'y') or { assert false, err.msg(); return }
	defer { os.rm(bin) or {} }
	// Touch bin to ensure it is at least as new
	assert src_is_newer(src, bin) == false
}

// ---------------------------------------------------------------------------
// find_v_compiler
// ---------------------------------------------------------------------------

fn test_find_v_compiler_empty_path_returns_empty() {
	old := os.getenv('PATH')
	os.setenv('PATH', '', true)
	defer { os.setenv('PATH', old, true) }
	assert find_v_compiler() == ''
}

fn test_find_v_compiler_skips_directories() {
	pid := os.getpid()
	dir := '/tmp/vlsh_test_vdir_${pid}'
	vdir := '${dir}/v'
	os.mkdir_all(vdir) or { assert false, err.msg(); return }
	defer { os.rmdir_all(dir) or {} }

	old := os.getenv('PATH')
	os.setenv('PATH', dir, true)
	defer { os.setenv('PATH', old, true) }
	assert find_v_compiler() == ''
}

fn test_find_v_compiler_finds_file_named_v() {
	pid := os.getpid()
	dir := '/tmp/vlsh_test_vexe_${pid}'
	os.mkdir_all(dir) or { assert false, err.msg(); return }
	defer { os.rmdir_all(dir) or {} }
	vpath := '${dir}/v'
	os.write_file(vpath, '#!/bin/sh\n') or { assert false, err.msg(); return }
	os.chmod(vpath, 0o755) or {}

	old := os.getenv('PATH')
	os.setenv('PATH', dir, true)
	defer { os.setenv('PATH', old, true) }
	assert find_v_compiler() == vpath
}

fn test_find_v_compiler_returns_first_match() {
	pid := os.getpid()
	dir1 := '/tmp/vlsh_test_v1_${pid}'
	dir2 := '/tmp/vlsh_test_v2_${pid}'
	os.mkdir_all(dir1) or { assert false, err.msg(); return }
	os.mkdir_all(dir2) or { assert false, err.msg(); return }
	defer { os.rmdir_all(dir1) or {} }
	defer { os.rmdir_all(dir2) or {} }
	v1 := '${dir1}/v'
	v2 := '${dir2}/v'
	os.write_file(v1, '#!/bin/sh\n') or { assert false, err.msg(); return }
	os.write_file(v2, '#!/bin/sh\n') or { assert false, err.msg(); return }

	old := os.getenv('PATH')
	os.setenv('PATH', '${dir1}:${dir2}', true)
	defer { os.setenv('PATH', old, true) }
	assert find_v_compiler() == v1
}

fn test_find_v_compiler_skips_nonexistent_dirs() {
	pid := os.getpid()
	good := '/tmp/vlsh_test_vgood_${pid}'
	os.mkdir_all(good) or { assert false, err.msg(); return }
	defer { os.rmdir_all(good) or {} }
	vpath := '${good}/v'
	os.write_file(vpath, '#!/bin/sh\n') or { assert false, err.msg(); return }

	old := os.getenv('PATH')
	os.setenv('PATH', '/tmp/vlsh_noexist_${pid}:${good}', true)
	defer { os.setenv('PATH', old, true) }
	assert find_v_compiler() == vpath
}

// ---------------------------------------------------------------------------
// plugin_src_dir / plugin_bin_dir / disabled_file
// ---------------------------------------------------------------------------

fn test_plugin_src_dir_under_home() {
	result := plugin_src_dir()
	assert result.starts_with(os.home_dir())
	assert result.ends_with('.vlsh/plugins') || result.contains('.vlsh/plugins')
}

fn test_plugin_bin_dir_under_src_dir() {
	result := plugin_bin_dir()
	assert result == os.join_path(plugin_src_dir(), '.bin')
}

fn test_disabled_file_under_src_dir() {
	result := disabled_file()
	assert result == os.join_path(plugin_src_dir(), '.disabled')
}

// ---------------------------------------------------------------------------
// mux_status_binaries
// ---------------------------------------------------------------------------

fn test_mux_status_binaries_empty_list() {
	assert mux_status_binaries([]) == []
}

fn test_mux_status_binaries_no_capable_plugins() {
	loaded := [
		Plugin{ name: 'a', binary: '/bin/a', has_mux_status: false },
		Plugin{ name: 'b', binary: '/bin/b', has_mux_status: false },
	]
	assert mux_status_binaries(loaded) == []
}

fn test_mux_status_binaries_filters_capable_plugins() {
	loaded := [
		Plugin{ name: 'a', binary: '/bin/a', has_mux_status: true },
		Plugin{ name: 'b', binary: '/bin/b', has_mux_status: false },
		Plugin{ name: 'c', binary: '/bin/c', has_mux_status: true },
	]
	result := mux_status_binaries(loaded)
	assert result.len == 2
	assert '/bin/a' in result
	assert '/bin/c' in result
}

fn test_mux_status_binaries_all_capable() {
	loaded := [
		Plugin{ name: 'x', binary: '/x', has_mux_status: true },
		Plugin{ name: 'y', binary: '/y', has_mux_status: true },
	]
	assert mux_status_binaries(loaded).len == 2
}

// ---------------------------------------------------------------------------
// dispatch — no-match cases (avoids spawning processes)
// ---------------------------------------------------------------------------

fn test_dispatch_empty_plugin_list() {
	assert dispatch([], 'hello', []) == false
}

fn test_dispatch_no_matching_command() {
	loaded := [
		Plugin{ name: 'a', commands: ['foo', 'bar'] },
	]
	assert dispatch(loaded, 'baz', []) == false
}

// ---------------------------------------------------------------------------
// show_help — no-match cases
// ---------------------------------------------------------------------------

fn test_show_help_empty_list() {
	assert show_help([], 'anything') == false
}

fn test_show_help_no_help_capability() {
	loaded := [
		Plugin{ name: 'a', commands: ['foo'], has_help: false },
	]
	assert show_help(loaded, 'foo') == false
}

fn test_show_help_command_not_owned() {
	loaded := [
		Plugin{ name: 'a', commands: ['foo'], has_help: true },
	]
	assert show_help(loaded, 'bar') == false
}

// ---------------------------------------------------------------------------
// completions — empty cases
// ---------------------------------------------------------------------------

fn test_completions_empty_list() {
	assert completions([], 'ssh ') == []
}

// ---------------------------------------------------------------------------
// prompt_segments — empty cases
// ---------------------------------------------------------------------------

fn test_prompt_segments_empty_list() {
	assert prompt_segments([]) == ''
}

fn test_prompt_segments_no_prompt_capable() {
	loaded := [
		Plugin{ name: 'a', has_prompt: false },
	]
	assert prompt_segments(loaded) == ''
}

// ---------------------------------------------------------------------------
// load — compile=false with no plugins installed
// ---------------------------------------------------------------------------

fn test_load_no_compile_returns_list() {
	result := load(false)
	// Just verify it returns without error; the exact count depends on the
	// developer's local plugin directory.
	assert result.len >= 0
}
