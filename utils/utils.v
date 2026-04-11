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
//   ${parameter…}       — brace parameter expansion (see expand_brace_param)
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
// Variable references ($VAR, $?, $0, etc.) are expanded in each token, then
// unquoted tokens that contain * or ? are glob-expanded against the filesystem;
// if no files match the pattern is passed through unchanged.
pub fn parse_args(input string) []string {
	mut args       := []string{}
	mut current    := strings.new_builder(32)
	mut in_single  := false
	mut in_double  := false
	mut has_quoted := false // any part of the current token was inside quotes
	for ch in input {
		if ch == `'` && !in_double {
			in_single  = !in_single
			has_quoted = true
		} else if ch == `"` && !in_single {
			in_double  = !in_double
			has_quoted = true
		} else if ch == ` ` && !in_single && !in_double {
			if current.len > 0 {
				args << glob_expand(expand_vars(current.str()), has_quoted)
				current    = strings.new_builder(32)
				has_quoted = false
			}
		} else {
			current.write_u8(ch)
		}
	}
	if current.len > 0 {
		args << glob_expand(expand_vars(current.str()), has_quoted)
	}
	return args
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
		dir      := pattern[..last_sep]
		file_pat := pattern[last_sep + 1..]
		real_dir := os.real_path(dir)
		if real_dir != '' && os.is_dir(real_dir) {
			pattern = '${real_dir}/${file_pat}'
		}
	}
	matches := os.glob(pattern) or { return [tok] }
	if matches.len == 0 { return [tok] }
	return matches
}

// is_env_assign reports whether tok is a shell-style KEY=VALUE assignment.
// The key must be a non-empty identifier (letter or underscore, then letters,
// digits, or underscores).  Used to detect leading env-var prefixes on a
// command line, e.g. `FOO=bar cmd arg`.
pub fn is_env_assign(tok string) bool {
	eq := tok.index('=') or { return false }
	if eq == 0 { return false } // empty key
	key := tok[..eq]
	first := key[0]
	if !first.is_letter() && first != `_` { return false }
	for ch in key[1..].bytes() {
		if !ch.is_letter() && !ch.is_digit() && ch != `_` { return false }
	}
	return true
}

pub fn debug[T](input ...T) {
	style := cfg.style() or {
		fail(err.msg())

		return
	}
	if debug_mode == 'true' {
		print(
			term.bg_rgb(
				style['style_debug_bg'][0],
				style['style_debug_bg'][1],
				style['style_debug_bg'][2],
				term.rgb(
					style['style_debug_fg'][0],
					style['style_debug_fg'][1],
					style['style_debug_fg'][2],
					'debug::\t\t'
				)
			)
		)
		for i in input {
			print(
				term.bg_rgb(
					style['style_git_bg'][0],
					style['style_git_bg'][1],
					style['style_git_bg'][2],
					term.rgb(
						style['style_git_fg'][0],
						style['style_git_fg'][1],
						style['style_git_fg'][2],
						i.str()
					)
				)
			)
		}
		print('\n')
	}
}

