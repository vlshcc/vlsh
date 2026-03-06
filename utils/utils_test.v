module utils

import os

// ---------------------------------------------------------------------------
// expand_vars
// ---------------------------------------------------------------------------

fn test_expand_vars_no_dollar_is_unchanged() {
	assert expand_vars('hello world') == 'hello world'
}

fn test_expand_vars_dollar_question_mark() {
	os.setenv('?', '42', true)
	assert expand_vars('$?') == '42'
	os.setenv('?', '0', true)
}

fn test_expand_vars_dollar_question_embedded() {
	os.setenv('?', '1', true)
	assert expand_vars('code=$?') == 'code=1'
	os.setenv('?', '0', true)
}

fn test_expand_vars_regular_var() {
	os.setenv('VLSH_TEST_X', 'hello', true)
	assert expand_vars('\$VLSH_TEST_X') == 'hello'
	os.unsetenv('VLSH_TEST_X')
}

fn test_expand_vars_var_with_literal_suffix() {
	os.setenv('VLSH_TEST_X', 'foo', true)
	assert expand_vars('\$VLSH_TEST_X!') == 'foo!'
	os.unsetenv('VLSH_TEST_X')
}

fn test_expand_vars_digit_suffix_after_special_param() {
	// $0? should expand $0 (shell binary) and keep ? as literal
	result := expand_vars('$0?')
	assert result.ends_with('?')
	assert result.len > 1
}

fn test_expand_vars_multiple_vars_in_string() {
	os.setenv('VLSH_TEST_A', 'hello', true)
	os.setenv('VLSH_TEST_B', 'world', true)
	assert expand_vars('\$VLSH_TEST_A \$VLSH_TEST_B') == 'hello world'
	os.unsetenv('VLSH_TEST_A')
	os.unsetenv('VLSH_TEST_B')
}

fn test_expand_vars_undefined_var_expands_to_empty() {
	os.unsetenv('VLSH_UNDEF_TEST')
	assert expand_vars('\$VLSH_UNDEF_TEST') == ''
}

fn test_expand_vars_unknown_dollar_sequence_kept_literal() {
	assert expand_vars('$-') == '$-'
}

fn test_expand_vars_double_dollar_is_pid() {
	result := expand_vars('$$')
	assert result.int() > 0
}

fn test_expand_vars_dollar_at_end_of_string_kept_literal() {
	assert expand_vars('hello$') == 'hello$'
}

// ---------------------------------------------------------------------------
// parse_args
// ---------------------------------------------------------------------------

fn test_parse_args_empty_string() {
	assert parse_args('') == []string{}
}

fn test_parse_args_single_word() {
	assert parse_args('hello') == ['hello']
}

fn test_parse_args_multiple_words() {
	assert parse_args('echo hello world') == ['echo', 'hello', 'world']
}

fn test_parse_args_leading_trailing_spaces() {
	assert parse_args('  ls  ') == ['ls']
}

fn test_parse_args_multiple_internal_spaces() {
	// consecutive spaces produce a single token boundary
	assert parse_args('echo  hello') == ['echo', 'hello']
}

fn test_parse_args_single_quoted_token() {
	result := parse_args("echo 'hello world'")
	assert result == ['echo', 'hello world']
}

fn test_parse_args_double_quoted_token() {
	result := parse_args('echo "hello world"')
	assert result == ['echo', 'hello world']
}

fn test_parse_args_single_quotes_suppress_double() {
	// double-quote inside single-quoted string is literal
	result := parse_args("echo '\"stay\"'")
	assert result == ['echo', '"stay"']
}

fn test_parse_args_double_quotes_suppress_single() {
	// single-quote inside double-quoted string is literal
	result := parse_args('echo "it\'s fine"')
	assert result == ['echo', "it's fine"]
}

fn test_parse_args_quoted_value_with_equals() {
	result := parse_args('aliases add name="git status"')
	assert result == ['aliases', 'add', 'name=git status']
}

fn test_parse_args_multiple_quoted_args() {
	result := parse_args('"foo bar" "baz qux"')
	assert result == ['foo bar', 'baz qux']
}

fn test_parse_args_empty_quoted_string() {
	result := parse_args('echo ""')
	// empty quoted token is discarded (current.len == 0 after closing quote)
	assert result == ['echo']
}

fn test_parse_args_only_spaces() {
	assert parse_args('   ') == []string{}
}

fn test_parse_args_pipe_character_is_not_special() {
	// parse_args is a tokenizer; pipe handling is exec's responsibility
	result := parse_args('cat file | wc')
	assert result == ['cat', 'file', '|', 'wc']
}

fn test_parse_args_env_assign_stays_one_token() {
	// KEY=VALUE must remain a single token so is_env_assign can detect it
	result := parse_args('FOO=bar cmd')
	assert result == ['FOO=bar', 'cmd']
}

fn test_parse_args_var_expansion() {
	os.setenv('VLSH_TEST_GREET', 'hi', true)
	result := parse_args('echo \$VLSH_TEST_GREET')
	assert result == ['echo', 'hi']
	os.unsetenv('VLSH_TEST_GREET')
}

fn test_parse_args_special_param_expansion() {
	os.setenv('?', '5', true)
	result := parse_args('echo $?')
	assert result == ['echo', '5']
	os.setenv('?', '0', true)
}

// ---------------------------------------------------------------------------
// is_env_assign
// ---------------------------------------------------------------------------

fn test_is_env_assign_simple() {
	assert is_env_assign('FOO=bar') == true
}

fn test_is_env_assign_with_underscore_key() {
	assert is_env_assign('MY_VAR=value') == true
}

fn test_is_env_assign_key_starting_with_underscore() {
	assert is_env_assign('_VAR=value') == true
}

fn test_is_env_assign_empty_value() {
	assert is_env_assign('FOO=') == true
}

fn test_is_env_assign_empty_key_is_false() {
	assert is_env_assign('=value') == false
}

fn test_is_env_assign_no_equals_is_false() {
	assert is_env_assign('FOO') == false
}

fn test_is_env_assign_key_with_digit_start_is_false() {
	assert is_env_assign('1FOO=bar') == false
}

fn test_is_env_assign_key_with_hyphen_is_false() {
	assert is_env_assign('MY-VAR=value') == false
}

fn test_is_env_assign_key_with_dot_is_false() {
	assert is_env_assign('my.var=value') == false
}

fn test_is_env_assign_numeric_key_is_false() {
	assert is_env_assign('123=value') == false
}

fn test_is_env_assign_lowercase_key() {
	assert is_env_assign('path=value') == true
}

fn test_is_env_assign_key_with_digits_after_first() {
	assert is_env_assign('VAR2=value') == true
}

// ---------------------------------------------------------------------------
// glob_expand
// ---------------------------------------------------------------------------

fn test_glob_expand_quoted_token_returned_unchanged() {
	assert glob_expand('*.v', true) == ['*.v']
}

fn test_glob_expand_no_wildcards_returned_unchanged() {
	assert glob_expand('hello', false) == ['hello']
}

fn test_glob_expand_star_in_tmp() {
	pid := os.getpid()
	dir := '/tmp/vlsh_glob_test_${pid}'
	os.mkdir_all(dir) or { assert false, err.msg(); return }
	defer { os.rmdir_all(dir) or {} }
	os.write_file('${dir}/aaa.txt', '') or {}
	os.write_file('${dir}/bbb.txt', '') or {}
	result := glob_expand('${dir}/*.txt', false)
	assert result.len == 2
	assert result.any(it.contains('aaa.txt'))
	assert result.any(it.contains('bbb.txt'))
}

fn test_glob_expand_no_matches_returns_literal() {
	result := glob_expand('/tmp/vlsh_glob_noexist_xyzzy_/*.xyz', false)
	assert result == ['/tmp/vlsh_glob_noexist_xyzzy_/*.xyz']
}

fn test_glob_expand_with_subdirectory_pattern() {
	pid := os.getpid()
	dir := '/tmp/vlsh_glob_sub_${pid}'
	sub := '${dir}/inner'
	os.mkdir_all(sub) or { assert false, err.msg(); return }
	defer { os.rmdir_all(dir) or {} }
	os.write_file('${sub}/foo.txt', '') or {}
	result := glob_expand('${dir}/inner/*.txt', false)
	assert result.len == 1
	assert result[0].contains('foo.txt')
}
