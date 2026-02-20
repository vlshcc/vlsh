module cmds

import os

// ---------------------------------------------------------------------------
// cd — basic navigation
// ---------------------------------------------------------------------------

fn test_cd_no_args_goes_to_home() {
	orig := os.getwd()
	defer { os.chdir(orig) or {} }

	cd([]) or { assert false, err.msg(); return }
	assert os.getwd() == os.home_dir()
}

fn test_cd_explicit_path_changes_directory() {
	orig := os.getwd()
	defer { os.chdir(orig) or {} }

	cd(['/tmp']) or { assert false, err.msg(); return }
	assert os.getwd() == '/tmp'
}

fn test_cd_nonexistent_directory_returns_error() {
	cd(['/this/path/does/not/exist/vlsh_test_xyz_cd']) or {
		assert err.msg().len > 0
		return
	}
	assert false, 'expected error for nonexistent directory'
}

fn test_cd_file_path_returns_not_a_directory_error() {
	pid := os.getpid()
	tmp_file := '/tmp/vlsh_cd_file_test_${pid}'
	os.write_file(tmp_file, 'data') or { assert false, err.msg(); return }
	defer { os.rm(tmp_file) or {} }

	cd([tmp_file]) or {
		assert err.msg().contains('not a directory')
		return
	}
	assert false, 'expected "not a directory" error'
}

// ---------------------------------------------------------------------------
// cd — tilde expansion
// ---------------------------------------------------------------------------

fn test_cd_tilde_alone_goes_to_home() {
	orig := os.getwd()
	defer { os.chdir(orig) or {} }

	cd(['~']) or { assert false, err.msg(); return }
	assert os.getwd() == os.home_dir()
}

fn test_cd_tilde_slash_path_resolves() {
	orig := os.getwd()
	defer { os.chdir(orig) or {} }

	// cd ~/  should land in home directory
	cd(['~/']) or { assert false, err.msg(); return }
	assert os.getwd() == os.home_dir()
}

// ---------------------------------------------------------------------------
// cd — OLDPWD and PWD tracking
// ---------------------------------------------------------------------------

fn test_cd_sets_pwd_env_after_change() {
	orig := os.getwd()
	defer { os.chdir(orig) or {} }

	cd(['/tmp']) or { assert false, err.msg(); return }
	assert os.getenv('PWD') == '/tmp'
}

fn test_cd_sets_oldpwd_to_previous_directory() {
	orig := os.getwd()
	defer {
		os.chdir(orig) or {}
		os.unsetenv('OLDPWD')
	}

	cd(['/tmp']) or { assert false, err.msg(); return }
	assert os.getenv('OLDPWD') == orig
}

fn test_cd_updates_oldpwd_on_second_change() {
	orig := os.getwd()
	defer {
		os.chdir(orig) or {}
		os.unsetenv('OLDPWD')
	}

	cd(['/tmp']) or { assert false, err.msg(); return }
	assert os.getenv('OLDPWD') == orig

	cd(['/']) or { assert false, err.msg(); return }
	assert os.getenv('OLDPWD') == '/tmp'
	assert os.getenv('PWD') == '/'
}

// ---------------------------------------------------------------------------
// cd — dash (cd -)
// ---------------------------------------------------------------------------

fn test_cd_minus_without_oldpwd_returns_error() {
	os.unsetenv('OLDPWD')
	cd(['-']) or {
		assert err.msg().contains('OLDPWD not set')
		return
	}
	assert false, 'expected error when OLDPWD is not set'
}

fn test_cd_minus_returns_to_previous_directory() {
	orig := os.getwd()
	defer {
		os.chdir(orig) or {}
		os.unsetenv('OLDPWD')
	}

	// First cd from orig to /tmp — sets OLDPWD=orig, PWD=/tmp
	cd(['/tmp']) or { assert false, err.msg(); return }
	assert os.getenv('OLDPWD') == orig
	assert os.getwd() == '/tmp'

	// cd - should return to orig
	cd(['-']) or { assert false, err.msg(); return }
	assert os.getwd() == orig
}

fn test_cd_minus_updates_oldpwd_after_dash() {
	orig := os.getwd()
	defer {
		os.chdir(orig) or {}
		os.unsetenv('OLDPWD')
	}

	cd(['/tmp']) or { assert false, err.msg(); return }
	// OLDPWD is now orig
	cd(['-']) or { assert false, err.msg(); return }
	// After cd - (from /tmp back to orig), OLDPWD should be /tmp
	assert os.getenv('OLDPWD') == '/tmp'
}
