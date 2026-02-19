module cfg

// ---------------------------------------------------------------------------
// extract_aliases (private, accessible within module)
// ---------------------------------------------------------------------------

fn test_extract_aliases_single() {
	mut c := Cfg{}
	c.extract_aliases(['"aliases', 'alias gs=git status'])
	assert c.aliases['gs'] == 'git status'
}

fn test_extract_aliases_multiple() {
	mut c := Cfg{}
	c.extract_aliases([
		'"aliases',
		'alias gs=git status',
		'alias gps=git push',
		'alias gpl=git pull',
	])
	assert c.aliases['gs']  == 'git status'
	assert c.aliases['gps'] == 'git push'
	assert c.aliases['gpl'] == 'git pull'
}

fn test_extract_aliases_ignores_non_alias_lines() {
	mut c := Cfg{}
	c.extract_aliases(['"paths', 'path=/tmp', '"aliases', 'alias ll=ls -la'])
	assert c.aliases.len == 1
	assert c.aliases['ll'] == 'ls -la'
}

fn test_extract_aliases_empty_input() {
	mut c := Cfg{}
	c.extract_aliases([])
	assert c.aliases.len == 0
}

fn test_extract_aliases_skips_blank_lines() {
	mut c := Cfg{}
	c.extract_aliases(['', 'alias vim=nvim', ''])
	assert c.aliases['vim'] == 'nvim'
}

// ---------------------------------------------------------------------------
// extract_style (private, accessible within module)
// ---------------------------------------------------------------------------

fn test_extract_style_parses_rgb() {
	mut c := Cfg{}
	c.extract_style(['style_git_bg=44,59,71']) or { assert false, err.msg() }
	assert c.style['style_git_bg'] == [44, 59, 71]
}

fn test_extract_style_multiple_keys() {
	mut c := Cfg{}
	c.extract_style(['style_git_bg=44,59,71', 'style_git_fg=251,255,234']) or {
		assert false, err.msg()
	}
	assert c.style['style_git_bg'] == [44, 59, 71]
	assert c.style['style_git_fg'] == [251, 255, 234]
}

fn test_extract_style_injects_defaults_for_missing_keys() {
	mut c := Cfg{}
	// provide nothing — should still fill in all defaults
	c.extract_style([]) or { assert false, err.msg() }
	assert 'style_git_bg'   in c.style
	assert 'style_git_fg'   in c.style
	assert 'style_debug_bg' in c.style
	assert 'style_debug_fg' in c.style
}

fn test_extract_style_existing_key_not_overwritten_by_default() {
	mut c := Cfg{}
	c.extract_style(['style_git_bg=10,20,30']) or { assert false, err.msg() }
	// user-provided value must survive the defaults-injection pass
	assert c.style['style_git_bg'] == [10, 20, 30]
}

fn test_extract_style_skips_blank_lines() {
	mut c := Cfg{}
	c.extract_style(['', 'style_git_bg=1,2,3', '']) or { assert false, err.msg() }
	assert c.style['style_git_bg'] == [1, 2, 3]
}

// ---------------------------------------------------------------------------
// extract_paths (private, accessible within module)
// ---------------------------------------------------------------------------

fn test_extract_paths_valid_directory() {
	mut c := Cfg{}
	// /tmp is present on every POSIX system
	c.extract_paths(['path=/tmp']) or { assert false, err.msg() }
	assert '/tmp' in c.paths
}

fn test_extract_paths_semicolon_separated() {
	mut c := Cfg{}
	c.extract_paths(['path=/tmp;/tmp']) or { assert false, err.msg() }
	// /tmp may appear twice (each segment is checked individually)
	assert c.paths.len >= 1
	assert '/tmp' in c.paths
}

fn test_extract_paths_ignores_non_path_lines() {
	mut c := Cfg{}
	c.extract_paths(['"paths', '"aliases', 'path=/tmp']) or { assert false, err.msg() }
	assert c.paths.len == 1
	assert '/tmp' in c.paths
}

fn test_extract_paths_missing_directory_returns_error() {
	mut c := Cfg{}
	c.extract_paths(['path=/this/path/does/not/exist/vlsh_test_xyz']) or {
		// We expect an error here
		assert err.msg().contains('could not find')
		return
	}
	assert false, 'expected an error for a missing path'
}

fn test_extract_paths_empty_input() {
	mut c := Cfg{}
	c.extract_paths([]) or { assert false, err.msg() }
	assert c.paths.len == 0
}
