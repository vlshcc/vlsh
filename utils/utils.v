module utils

import os
import strings
import term
import cfg

const debug_mode = os.getenv('VLSHDEBUG')

// brace_closing_index returns the index *after* the `}` that matches `{` at open_brace_idx.
fn brace_closing_index(s string, open_brace_idx int) int {
	mut depth := 1
	mut j := open_brace_idx + 1
	for j < s.len && depth > 0 {
		if s[j] == `{` {
			depth++
		} else if s[j] == `}` {
			depth--
		}
		j++
	}
	return j
}

// ifs_chars_for_split returns the delimiter set used by parse_args for unquoted
// token boundaries. If IFS is unset, POSIX default space/tab/newline applies.
// If IFS is set to empty, we still use that default for lexer tokenisation so
// simple commands remain usable (true post-expansion empty-IFS behaviour is
// not implemented yet).
fn ifs_chars_for_split() string {
	env := os.environ()
	if 'IFS' !in env {
		return ' \t\n'
	}
	val := env['IFS']
	if val.len == 0 {
		return ' \t\n'
	}
	return val
}

fn ifs_whitespace_only(ifs string) bool {
	for ch in ifs {
		if ch != ` ` && ch != `\t` && ch != `\n` && ch != `\r` {
			return false
		}
	}
	return true
}

fn is_ifs_rune(ch rune, ifs string) bool {
	for r in ifs {
		if r == ch {
			return true
		}
	}
	return false
}

// glob_match implements POSIX-style pattern matching for ${parameter#word} etc.
// Supports * and ? and literal bytes; [] classes are not implemented yet.
fn glob_match(pattern string, s string) bool {
	if pattern.len == 0 {
		return s.len == 0
	}
	if pattern[0] == `*` {
		for k := 0; k <= s.len; k++ {
			if glob_match(pattern[1..], s[k..]) {
				return true
			}
		}
		return false
	}
	if pattern[0] == `?` {
		if s.len == 0 {
			return false
		}
		mut adv := 1
		fb := s[0]
		if fb >= 0x80 {
			if (fb & 0xe0) == 0xc0 {
				adv = 2
			} else if (fb & 0xf0) == 0xe0 {
				adv = 3
			} else if (fb & 0xf8) == 0xf0 {
				adv = 4
			}
		}
		return glob_match(pattern[1..], s[adv..])
	}
	if s.len == 0 {
		return false
	}
	if pattern[0] == s[0] {
		return glob_match(pattern[1..], s[1..])
	}
	return false
}

fn remove_shortest_prefix(val string, pat string) string {
	for i := 0; i <= val.len; i++ {
		prefix := val[..i]
		if glob_match(pat, prefix) {
			return val[i..]
		}
	}
	return val
}

fn remove_longest_prefix(val string, pat string) string {
	for i := val.len; i >= 0; i-- {
		prefix := val[..i]
		if glob_match(pat, prefix) {
			return val[i..]
		}
	}
	return val
}

fn remove_shortest_suffix(val string, pat string) string {
	for i := val.len; i >= 0; i-- {
		suffix := val[i..]
		if glob_match(pat, suffix) {
			return val[..i]
		}
	}
	return val
}

fn remove_longest_suffix(val string, pat string) string {
	for i := 0; i <= val.len; i++ {
		suffix := val[i..]
		if glob_match(pat, suffix) {
			return val[..i]
		}
	}
	return val
}

fn param_value(name string) string {
	if name == '0' {
		return if os.args.len > 0 { os.args[0] } else { 'vlsh' }
	}
	return os.getenv(name)
}

fn is_param_name(name string) bool {
	if name.len == 0 {
		return false
	}
	f := name[0]
	if !f.is_letter() && f != `_` {
		return false
	}
	for k := 1; k < name.len; k++ {
		ch := name[k]
		if !ch.is_letter() && !ch.is_digit() && ch != `_` {
			return false
		}
	}
	return true
}

// expand_brace_param evaluates the inside of ${...} (POSIX-style parameter expansion subset).
fn expand_brace_param(inner string) string {
	if inner.len == 0 {
		return ''
	}
	// ${#name} — length of expansion (in characters)
	if inner[0] == `#` {
		nm := inner[1..]
		if nm == '0' {
			arg0 := if os.args.len > 0 { os.args[0] } else { 'vlsh' }
			return arg0.len.str()
		}
		if nm.len == 1 && (nm[0] == `?` || nm[0] == `!` || nm[0] == `#`) {
			return os.getenv(nm).len.str()
		}
		if nm.len == 1 && nm[0] >= `1` && nm[0] <= `9` {
			return os.getenv(nm).len.str()
		}
		if is_param_name(nm) {
			return os.getenv(nm).len.str()
		}
		return ''
	}
	mut name_end := 0
	for name_end < inner.len {
		ch := inner[name_end]
		if ch.is_letter() || ch.is_digit() || ch == `_` {
			name_end++
		} else {
			break
		}
	}
	if name_end == 0 {
		// Single special char: $? $! $#
		if inner.len == 1 {
			c := inner[0]
			if c == `?` || c == `!` || c == `#` {
				return os.getenv(inner)
			}
			if c >= `1` && c <= `9` {
				return os.getenv(inner)
			}
			if c == `0` {
				return if os.args.len > 0 { os.args[0] } else { 'vlsh' }
			}
		}
		return ''
	}
	name := inner[..name_end]
	rest := inner[name_end..]
	if rest == '' {
		if name == '0' {
			return if os.args.len > 0 { os.args[0] } else { 'vlsh' }
		}
		return os.getenv(name)
	}
	if rest.starts_with(':-') {
		word := expand_vars(rest[2..])
		val := os.getenv(name)
		if val == '' {
			return word
		}
		return val
	}
	if rest.starts_with(':=') {
		word := expand_vars(rest[2..])
		val := os.getenv(name)
		if val == '' {
			os.setenv(name, word, true)
			return word
		}
		return val
	}
	if rest.starts_with(':+') {
		word := expand_vars(rest[2..])
		val := os.getenv(name)
		if val == '' {
			return ''
		}
		return word
	}
	if rest.starts_with(':?') {
		word := expand_vars(rest[2..])
		val := os.getenv(name)
		if val == '' {
			msg := if word != '' { '${name}: ${word}' } else { '${name}: parameter null or unset' }
			eprintln(msg)
			return ''
		}
		return val
	}
	if rest.starts_with('##') {
		pat := expand_vars(rest[2..])
		val := param_value(name)
		return remove_longest_prefix(val, pat)
	}
	if rest.starts_with('#') {
		pat := expand_vars(rest[1..])
		val := param_value(name)
		return remove_shortest_prefix(val, pat)
	}
	if rest.starts_with('%%') {
		pat := expand_vars(rest[2..])
		val := param_value(name)
		return remove_longest_suffix(val, pat)
	}
	if rest.starts_with('%') {
		pat := expand_vars(rest[1..])
		val := param_value(name)
		return remove_shortest_suffix(val, pat)
	}
	return ''
}

pub fn ok(input string) {
	println(term.ok_message('OKY| ${input}'))
}

pub fn fail(input string) {
	println(term.fail_message('ERR| ${input}'))
}

pub fn warn(input string) {
	println(term.warn_message('WRN| ${input}'))
}

// expand_vars replaces $VAR references in s with their values.
// Recognised forms (in order of precedence):
//   ${parameter…}       — brace parameter expansion (see expand_brace_param:
//                         :- := :+ :? # ## % %% and simple ${name})
//   $?  $!  $#          — single-char special parameters (looked up in env)
//   $$                  — current process ID
//   $0                  — shell binary name (os.args[0])
//   $1–$9               — positional parameters (looked up in env)
//   $[A-Za-z_][…]       — regular environment variables
// Any other $X sequence is passed through unchanged.
pub fn expand_vars(s string) string {
	if !s.contains('$') {
		return s
	}
	mut result := strings.new_builder(s.len)
	mut i := 0
	for i < s.len {
		if s[i] == `$` && i + 1 < s.len {
			if s[i + 1] == `{` {
				close := brace_closing_index(s, i + 1)
				if close <= i + 2 {
					result.write_u8(s[i])
					i++
					continue
				}
				inner := s[i + 2..close - 1]
				result.write_string(expand_brace_param(inner))
				i = close
				continue
			}
			next := s[i + 1]
			if next == `?` || next == `!` || next == `#` {
				result.write_string(os.getenv(s[i + 1..i + 2]))
				i += 2
			} else if next == `$` {
				result.write_string(os.getpid().str())
				i += 2
			} else if next >= `0` && next <= `9` {
				if next == `0` {
					result.write_string(if os.args.len > 0 { os.args[0] } else { 'vlsh' })
				} else {
					result.write_string(os.getenv(s[i + 1..i + 2]))
				}
				i += 2
			} else if (next >= `a` && next <= `z`) || (next >= `A` && next <= `Z`) || next == `_` {
				mut j := i + 1
				for j < s.len && (s[j].is_letter() || s[j].is_digit() || s[j] == `_`) {
					j++
				}
				result.write_string(os.getenv(s[i + 1..j]))
				i = j
			} else {
				// Unknown $X — keep the $ literally
				result.write_u8(s[i])
				i++
			}
		} else {
			result.write_u8(s[i])
			i++
		}
	}
	return result.str()
}

// parse_args splits a command string into tokens, respecting single and
// double quoted strings (which are kept as one token with quotes stripped).
// Unquoted boundaries use IFS (default space, tab, newline when IFS is unset).
// When IFS contains only whitespace, consecutive delimiters collapse; otherwise
// each delimiter can produce an empty field. Variable references ($VAR, $?, $0,
// etc.) are expanded in each token, then unquoted tokens that contain * or ?
// are glob-expanded against the filesystem; if no files match the pattern is
// passed through unchanged.
pub fn parse_args(input string) []string {
	ifs := ifs_chars_for_split()
	collapse := ifs_whitespace_only(ifs)
	mut args := []string{}
	mut current := strings.new_builder(32)
	mut in_single := false
	mut in_double := false
	mut has_quoted := false // any part of the current token was inside quotes
	// Iterate runes, not bytes: `for ch in string` in V is byte-wise; UTF-8
	// would be split (e.g. ä → Ã¤) and paths like Hämtningar would break cd.
	for ch in input.runes() {
		if ch == `'` && !in_double {
			in_single = !in_single
			has_quoted = true
		} else if ch == `"` && !in_single {
			in_double = !in_double
			has_quoted = true
		} else if !in_single && !in_double && is_ifs_rune(ch, ifs) {
			if collapse {
				if current.len > 0 {
					args << glob_expand(expand_vars(current.str()), has_quoted)
					current = strings.new_builder(32)
					has_quoted = false
				}
			} else {
				args << glob_expand(expand_vars(current.str()), has_quoted)
				current = strings.new_builder(32)
				has_quoted = false
			}
		} else {
			current.write_rune(ch)
		}
	}
	if current.len > 0 {
		args << glob_expand(expand_vars(current.str()), has_quoted)
	}
	return args
}

fn utf8_char_len_at(s string, i int) int {
	if i >= s.len {
		return 0
	}
	b := s[i]
	if b < 0x80 {
		return 1
	}
	if (b & 0xe0) == 0xc0 {
		return 2
	}
	if (b & 0xf0) == 0xe0 {
		return 3
	}
	if (b & 0xf8) == 0xf0 {
		return 4
	}
	return 1
}

fn last_word_last_command(line string) string {
	args := parse_args(line)
	if args.len == 0 {
		return ''
	}
	return args[args.len - 1]
}

// history_find_prefix returns the index of the newest entry starting with prefix.
fn history_find_prefix(entries []string, prefix string) !int {
	if prefix.len == 0 {
		return error('empty prefix after !')
	}
	for i := entries.len - 1; i >= 0; i-- {
		if entries[i].starts_with(prefix) {
			return i
		}
	}
	return error('!${prefix}: no such event')
}

// history_find_contains returns the index of the newest entry containing sub.
fn history_find_contains(entries []string, sub string) !int {
	if sub.len == 0 {
		return error('empty search string for !?')
	}
	for i := entries.len - 1; i >= 0; i-- {
		if entries[i].contains(sub) {
			return i
		}
	}
	return error('!?${sub}: no such event')
}

// parse_bang_question parses !?foo? or !?foo (word until space/end). start is the index of '!'.
fn parse_bang_question(input string, start int) !(string, int) {
	if start + 2 > input.len || input[start + 1] != `?` {
		return error('internal: expected !?')
	}
	j := start + 2
	if j >= input.len {
		return error('no search string for !?')
	}
	mut end := j
	for end < input.len {
		if input[end] == `?` {
			sub := input[j..end]
			if sub.len == 0 {
				return error('empty substring for !?')
			}
			return sub, end + 1
		}
		if input[end] == ` ` || input[end] == `\t` || input[end] == `\n` || input[end] == `\r` {
			break
		}
		end++
	}
	sub := input[j..end]
	if sub.len == 0 {
		return error('no search string for !?')
	}
	return sub, end
}

// load_history_entries_from_file returns ~/.vlsh_history lines (oldest first),
// trimmed to the last 5000 non-empty lines to match append_history.
pub fn load_history_entries_from_file() []string {
	hfile := os.home_dir() + '/.vlsh_history'
	content := os.read_file(hfile) or { return []string{} }
	lines := content.split('\n').filter(it.len > 0)
	if lines.len > 5000 {
		return lines[lines.len - 5000..].clone()
	}
	return lines.clone()
}

// expand_history_notation applies bash-style history expansion on the raw line
// before parse_args: `!!`, `!$`, `!-n`, `!?sub`, `!n` (positive), `!prefix`.
// Not POSIX. Scan is UTF-8 safe for non-ASCII outside `!` sequences.
pub fn expand_history_notation(input string, last string, history_entries []string) !string {
	if !input.contains('!') {
		return input
	}
	mut out := strings.new_builder(input.len * 2)
	mut segment_start := 0
	mut i := 0
	for i < input.len {
		if i + 1 < input.len && input[i] == `!` && input[i + 1] == `!` {
			if last == '' {
				return error('no previous command for !!')
			}
			out.write_string(input[segment_start..i])
			out.write_string(last)
			i += 2
			segment_start = i
			continue
		}
		if i + 1 < input.len && input[i] == `!` && input[i + 1] == `$` {
			if last == '' {
				return error('no previous command for !$')
			}
			lw := last_word_last_command(last)
			out.write_string(input[segment_start..i])
			out.write_string(lw)
			i += 2
			segment_start = i
			continue
		}
		if i + 1 < input.len && input[i] == `!` && input[i + 1] == `-` {
			if i + 2 >= input.len || input[i + 2] < `0` || input[i + 2] > `9` {
				return error('!-: invalid history event')
			}
			mut j := i + 2
			for j < input.len && input[j] >= `0` && input[j] <= `9` {
				j++
			}
			k := input[i + 2..j].int()
			if k < 1 {
				return error('!-${k}: invalid history event')
			}
			if k > history_entries.len {
				return error('!-${k}: no such history event')
			}
			idx := history_entries.len - k
			out.write_string(input[segment_start..i])
			out.write_string(history_entries[idx])
			i = j
			segment_start = i
			continue
		}
		if i + 1 < input.len && input[i] == `!` && input[i + 1] == `?` {
			sub, new_i := parse_bang_question(input, i) or {
				return err
			}
			idx := history_find_contains(history_entries, sub) or {
				return err
			}
			out.write_string(input[segment_start..i])
			out.write_string(history_entries[idx])
			i = new_i
			segment_start = i
			continue
		}
		if i + 1 < input.len && input[i] == `!` && input[i + 1] >= `0` && input[i + 1] <= `9` {
			mut j := i + 1
			for j < input.len && input[j] >= `0` && input[j] <= `9` {
				j++
			}
			num_str := input[i + 1..j]
			n := num_str.int()
			if n < 1 {
				return error('!${num_str}: invalid history event')
			}
			if n > history_entries.len {
				return error('!${n}: no such history event')
			}
			out.write_string(input[segment_start..i])
			out.write_string(history_entries[n - 1])
			i = j
			segment_start = i
			continue
		}
		if i + 1 < input.len && input[i] == `!` {
			next := input[i + 1]
			if next != `!` && next != `$` && next != `?` && next != `-` && !(next >= `0` && next <= `9`) {
				mut j := i + 1
				for j < input.len && input[j] != ` ` && input[j] != `\t` && input[j] != `\n` && input[j] != `\r` {
					j++
				}
				if j == i + 1 {
					i += utf8_char_len_at(input, i)
					continue
				}
				prefix := input[i + 1..j]
				idx := history_find_prefix(history_entries, prefix) or {
					return err
				}
				out.write_string(input[segment_start..i])
				out.write_string(history_entries[idx])
				i = j
				segment_start = i
				continue
			}
		}
		i += utf8_char_len_at(input, i)
	}
	out.write_string(input[segment_start..])
	return out.str()
}

// expand_history_bangs replaces every `!!` with last. Same as expand_history_notation
// with an empty history list (`!n` always fails if present).
pub fn expand_history_bangs(input string, last string) !string {
	return expand_history_notation(input, last, []string{})
}

// glob_expand returns the filesystem matches for tok when it is unquoted and
// contains wildcard characters (* or ?).  Falls back to [tok] if quoted, no
// wildcards, or no matches found.
fn glob_expand(tok string, was_quoted bool) []string {
	if was_quoted || (!tok.contains('*') && !tok.contains('?')) {
		return [tok]
	}
	// Expand a leading ~ before handing the pattern to the OS glob.
	mut pattern := if tok == '~' {
		os.home_dir()
	} else if tok.starts_with('~/') {
		os.home_dir() + tok[1..]
	} else {
		tok
	}
	// V's os.glob cannot handle path components like ../ or ./ because its
	// internal walker skips '.' and '..' entries.  Resolve the directory part
	// to an absolute path so os.glob only sees a plain filename pattern.
	if pattern.contains('/') {
		last_sep := pattern.last_index_u8(`/`)
		dir := pattern[..last_sep]
		file_pat := pattern[last_sep + 1..]
		real_dir := os.real_path(dir)
		if real_dir != '' && os.is_dir(real_dir) {
			pattern = '${real_dir}/${file_pat}'
		}
	}
	matches := os.glob(pattern) or { return [tok] }
	if matches.len == 0 {
		return [tok]
	}
	return matches
}

// is_env_assign reports whether tok is a shell-style KEY=VALUE assignment.
// The key must be a non-empty identifier (letter or underscore, then letters,
// digits, or underscores).  Used to detect leading env-var prefixes on a
// command line, e.g. `FOO=bar cmd arg`.
pub fn is_env_assign(tok string) bool {
	eq := tok.index('=') or { return false }
	if eq == 0 {
		return false
	}
	// empty key
	key := tok[..eq]
	first := key[0]
	if !first.is_letter() && first != `_` {
		return false
	}
	for ch in key[1..].bytes() {
		if !ch.is_letter() && !ch.is_digit() && ch != `_` {
			return false
		}
	}
	return true
}

pub fn debug[T](input ...T) {
	style := cfg.style() or {
		fail(err.msg())

		return
	}
	if debug_mode == 'true' {
		print(term.bg_rgb(style['style_debug_bg'][0], style['style_debug_bg'][1], style['style_debug_bg'][2],
			term.rgb(style['style_debug_fg'][0], style['style_debug_fg'][1], style['style_debug_fg'][2],
			'debug::\t\t')))
		for i in input {
			print(term.bg_rgb(style['style_git_bg'][0], style['style_git_bg'][1], style['style_git_bg'][2],
				term.rgb(style['style_git_fg'][0], style['style_git_fg'][1], style['style_git_fg'][2],
				i.str())))
		}
		print('\n')
	}
}
