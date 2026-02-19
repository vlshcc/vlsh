module exec

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
