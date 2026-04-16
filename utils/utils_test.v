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
// expand_vars — POSIX-style ${parameter…} (subset)
// ---------------------------------------------------------------------------

fn test_expand_brace_simple_var() {
	os.setenv('VLSH_BR1', 'ok', true)
	assert expand_vars('$' + '{VLSH_BR1}') == 'ok'
	os.unsetenv('VLSH_BR1')
}

fn test_expand_brace_var_zero() {
	r := expand_vars('$' + '{0}')
	assert r.len > 0
}

fn test_expand_brace_colon_minus_unset_uses_default() {
	os.unsetenv('VLSH_BR2')
	assert expand_vars('$' + '{VLSH_BR2:-fallback}') == 'fallback'
}

fn test_expand_brace_colon_minus_set_uses_value() {
	os.setenv('VLSH_BR2', 'real', true)
	assert expand_vars('$' + '{VLSH_BR2:-fallback}') == 'real'
	os.unsetenv('VLSH_BR2')
}

fn test_expand_brace_colon_minus_empty_uses_default() {
	os.setenv('VLSH_BR2', '', true)
	assert expand_vars('$' + '{VLSH_BR2:-fallback}') == 'fallback'
	os.unsetenv('VLSH_BR2')
}

fn test_expand_brace_colon_equal_assigns_when_unset() {
	os.unsetenv('VLSH_BR3')
	assert expand_vars('$' + '{VLSH_BR3:=assigned}') == 'assigned'
	assert os.getenv('VLSH_BR3') == 'assigned'
	os.unsetenv('VLSH_BR3')
}

fn test_expand_brace_colon_plus_unset_empty() {
	os.unsetenv('VLSH_BR4')
	assert expand_vars('$' + '{VLSH_BR4:+yes}') == ''
}

fn test_expand_brace_colon_plus_set_substitutes() {
	os.setenv('VLSH_BR4', 'x', true)
	assert expand_vars('$' + '{VLSH_BR4:+yes}') == 'yes'
	os.unsetenv('VLSH_BR4')
}

fn test_expand_brace_hash_length() {
	os.setenv('VLSH_BR5', 'abc', true)
	assert expand_vars('$' + '{#VLSH_BR5}') == '3'
	os.unsetenv('VLSH_BR5')
}

fn test_expand_brace_nested_colon_minus() {
	os.unsetenv('VLSH_BR6')
	os.unsetenv('VLSH_BR7')
	os.setenv('VLSH_BR7', 'inner', true)
	assert expand_vars('$' + '{VLSH_BR6:-' + '$' + '{VLSH_BR7:-none}}') == 'inner'
	os.unsetenv('VLSH_BR7')
}

fn test_expand_brace_word_expands_inner_dollar() {
	os.unsetenv('VLSH_BR8')
	os.setenv('VLSH_BR9', 'path', true)
	assert expand_vars('$' + '{VLSH_BR8:-/tmp/' + '$' + '{VLSH_BR9}}') == '/tmp/path'
	os.unsetenv('VLSH_BR9')
}

fn test_expand_brace_hash_shortest_prefix() {
	os.setenv('VLSH_PF1', 'foobar', true)
	assert expand_vars('$' + '{VLSH_PF1#foo}') == 'bar'
	os.unsetenv('VLSH_PF1')
}

fn test_expand_brace_hash_longest_prefix_star() {
	os.setenv('VLSH_PF2', 'abc', true)
	assert expand_vars('$' + '{VLSH_PF2##*}') == ''
	os.unsetenv('VLSH_PF2')
}

fn test_expand_brace_percent_shortest_suffix() {
	os.setenv('VLSH_PF3', 'file.txt', true)
	assert expand_vars('$' + '{VLSH_PF3%.txt}') == 'file'
	os.unsetenv('VLSH_PF3')
}

fn test_expand_brace_percent_longest_suffix() {
	os.setenv('VLSH_PF4', 'a.b.c', true)
	assert expand_vars('$' + '{VLSH_PF4%%.*}') == 'a'
	os.unsetenv('VLSH_PF4')
}

// ---------------------------------------------------------------------------
// parse_args
// ---------------------------------------------------------------------------

fn save_ifs() (bool, string) {
	env := os.environ()
	if 'IFS' in env {
		return true, env['IFS']
	}
	return false, ''
}

fn restore_ifs(had bool, val string) {
	if had {
		os.setenv('IFS', val, true)
	} else {
		os.unsetenv('IFS')
	}
}

fn test_parse_args_default_ifs_tab_and_newline() {
	had, old := save_ifs()
	os.unsetenv('IFS')
	defer { restore_ifs(had, old) }
	assert parse_args('a\tb') == ['a', 'b']
	assert parse_args('a\nb') == ['a', 'b']
}

fn test_parse_args_preserves_utf8_in_tokens() {
	assert parse_args('cd Hämtningar') == ['cd', 'Hämtningar']
	assert parse_args('echo åäö') == ['echo', 'åäö']
}

fn test_parse_args_ifs_colon_splits() {
	had, old := save_ifs()
	os.setenv('IFS', ':', true)
	defer { restore_ifs(had, old) }
	assert parse_args('a:b:c') == ['a', 'b', 'c']
}

fn test_expand_history_bangs_no_double_bang() {
	assert expand_history_bangs('ls -la', '')! == 'ls -la'
}

fn test_expand_history_bangs_substitutes() {
	assert expand_history_bangs('sudo !!', 'ls -la')! == 'sudo ls -la'
	assert expand_history_bangs('echo !!', 'date')! == 'echo date'
}

fn test_expand_history_bangs_all_occurrences() {
	assert expand_history_bangs('!! | !!', 'ls')! == 'ls | ls'
}

fn test_expand_history_bangs_errors_when_no_last() {
	expand_history_bangs('!!', '') or {
		assert err.msg().contains('previous')
		return
	}
	assert false
}

fn test_expand_history_notation_bang_dollar_last_word() {
	last := 'ls -la /tmp'
	assert expand_history_notation('cp !$ /other', last, [])! == 'cp /tmp /other'
}

fn test_expand_history_notation_bang_dollar_errors_without_last() {
	expand_history_notation('echo !$', '', []) or {
		assert err.msg().contains('!\$') || err.msg().contains('previous')
		return
	}
	assert false
}

fn test_expand_history_notation_event_number() {
	h := ['echo a', 'echo b', 'echo c']
	assert expand_history_notation('!2', '', h)! == 'echo b'
	assert expand_history_notation('x !1 z', '', h)! == 'x echo a z'
}

fn test_expand_history_notation_event_number_invalid() {
	expand_history_notation('!0', '', ['a']) or {
		assert err.msg().contains('invalid')
		return
	}
	assert false
}

fn test_expand_history_notation_event_number_out_of_range() {
	expand_history_notation('!9', '', ['only']) or {
		assert err.msg().contains('no such')
		return
	}
	assert false
}

fn test_expand_history_notation_negative_offset() {
	h := ['a', 'b', 'c']
	assert expand_history_notation('x !-1 z', '', h)! == 'x c z'
	assert expand_history_notation('!-2', '', h)! == 'b'
	assert expand_history_notation('!-3', '', h)! == 'a'
}

fn test_expand_history_notation_negative_offset_invalid() {
	expand_history_notation('!-0', '', ['a']) or {
		assert err.msg().contains('invalid')
		return
	}
	assert false
}

fn test_expand_history_notation_prefix() {
	h := ['ls /tmp', 'echo hello', 'date']
	assert expand_history_notation('!echo', '', h)! == 'echo hello'
	assert expand_history_notation('!da', '', h)! == 'date'
}

fn test_expand_history_notation_prefix_missing() {
	expand_history_notation('!zz', '', ['aa']) or {
		assert err.msg().contains('no such')
		return
	}
	assert false
}

fn test_expand_history_notation_contains() {
	h := ['ls /tmp', 'echo hello there', 'date']
	assert expand_history_notation('!?hello', '', h)! == 'echo hello there'
	assert expand_history_notation('!?/tmp?', '', h)! == 'ls /tmp'
}

fn test_expand_history_notation_contains_missing() {
	expand_history_notation('!?xyzzy', '', ['aa']) or {
		assert err.msg().contains('no such') || err.msg().contains('!?')
		return
	}
	assert false
}

fn test_parse_args_ifs_colon_empty_field() {
	had, old := save_ifs()
	os.setenv('IFS', ':', true)
	defer { restore_ifs(had, old) }
	assert parse_args(':a') == ['', 'a']
	assert parse_args('a::b') == ['a', '', 'b']
}

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
	// double-quote inside single-quoted string is literal (echo '"stay"')
	mut cmd := 'echo '
	cmd += "'"
	cmd += '"'
	cmd += 'stay'
	cmd += '"'
	cmd += "'"
	result := parse_args(cmd)
	assert result == ['echo', '"stay"']
}

fn test_parse_args_double_quotes_suppress_single() {
	// single-quote inside double-quoted string is literal
	result := parse_args('echo "it' + "'" + 's fine"')
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

fn test_parse_args_pipe_character_is_token_boundary() {
	result := parse_args('cat file | wc')
	assert result == ['cat', 'file', '|', 'wc']
}

fn test_parse_args_pipe_without_space_after() {
	// Like POSIX: | starts the next command even when glued (e.g. |more).
	result := parse_args('ls -la |more')
	assert result == ['ls', '-la', '|', 'more']
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
	os.mkdir_all(dir) or {
		assert false, err.msg()
		return
	}
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
	os.mkdir_all(sub) or {
		assert false, err.msg()
		return
	}
	defer { os.rmdir_all(dir) or {} }
	os.write_file('${sub}/foo.txt', '') or {}
	result := glob_expand('${dir}/inner/*.txt', false)
	assert result.len == 1
	assert result[0].contains('foo.txt')
}
