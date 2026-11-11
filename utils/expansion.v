module utils

import os
import strings

#include <glob.h>

@[typedef]
struct C.glob_t {
	gl_pathc usize
	gl_pathv &&char
}

fn C.glob(&char, int, voidptr, &C.glob_t) int
fn C.globfree(&C.glob_t)

// ShellToken is an expanded word or an operator recognized in the source.
pub struct ShellToken {
pub:
	text     string
	operator bool
}

struct WordChar {
	ch       rune
	quoted   bool
	split    bool
	anchor   bool // a quoted empty part preserves an otherwise empty field
	boundary bool // a separator between the arguments of quoted "$@"
}

fn word_chars(value string, quoted bool, split bool) []WordChar {
	if value == '' && quoted {
		return [WordChar{ anchor: true }]
	}
	return value.runes().map(WordChar{ ch: it, quoted: quoted, split: split })
}

fn word_text(chars []WordChar) string {
	mut text := strings.new_builder(chars.len)
	for atom in chars {
		if !atom.anchor && !atom.boundary { text.write_rune(atom.ch) }
	}
	return text.str()
}

fn expand_brace_param(inner string, mut vars Variables) []WordChar {
	if inner.starts_with('#') && inner.len > 1 {
		value := vars.parameter(inner[1..]) or { '' }
		return word_chars(value.runes().len.str(), false, true)
	}
	if inner == '' {
		return []
	}
	mut name_end := 0
	if inner[0] in [`?`, `!`, `#`, `$`, `@`, `*`] {
		name_end = 1
	} else {
		for name_end < inner.len && (inner[name_end].is_letter() || inner[name_end].is_digit()
			|| inner[name_end] == `_`) {
			name_end++
		}
	}
	if name_end == 0 {
		return []
	}
	name := inner[..name_end]
	rest := inner[name_end..]
	maybe_value := vars.parameter(name)
	value := maybe_value or { '' }
	if rest == '' {
		return word_chars(value, false, true)
	}
	if rest[0] in [`#`, `%`] {
		longest := rest.len > 1 && rest[0] == rest[1]
		pat := word_text(expand_word_chars(rest[if longest { 2 } else { 1 }..], false, false, mut vars))
		trimmed := if rest[0] == `#` {
			if longest { remove_longest_prefix(value, pat) } else { remove_shortest_prefix(value, pat) }
		} else {
			if longest { remove_longest_suffix(value, pat) } else { remove_shortest_suffix(value, pat) }
		}
		return word_chars(trimmed, false, true)
	}
	colon := rest[0] == `:`
	op_index := if colon { 1 } else { 0 }
	if op_index >= rest.len || rest[op_index] !in [`-`, `=`, `+`, `?`] {
		return []
	}
	op := rest[op_index]
	missing := maybe_value == none || (colon && value == '')
	if op == `+` && missing {
		return []
	}
	if op != `+` && !missing {
		return word_chars(value, false, true)
	}
	word := expand_word_chars(rest[op_index + 1..], true, false, mut vars)
	if op == `=` && valid_name(name) && vars.expansion_error == '' {
		vars.assign(name, word_text(word))
	}
	if op == `?` && vars.expansion_error == '' {
		msg := word_text(word)
		vars.expansion_error = if msg == '' {
			'${name}: parameter null or unset'
		} else {
			'${name}: ${msg}'
		}
	}
	return word
}

fn expand_dollar(raw string, start int, quoted bool, multiple bool, mut vars Variables) ([]WordChar, int) {
	if start + 1 >= raw.len {
		return word_chars('$', quoted, false), start + 1
	}
	mut end := start + 2
	next := raw[start + 1]
	mut name := ''
	if next == `{` {
		end = parameter_end(raw, start + 2)
		if end < 0 {
			return word_chars('$', quoted, false), start + 1
		}
		name = raw[start + 2..end - 1]
	} else if next.is_letter() || next == `_` {
		for end < raw.len && (raw[end].is_letter() || raw[end].is_digit() || raw[end] == `_`) {
			end++
		}
		name = raw[start + 1..end]
	} else if next.is_digit() || next in [`?`, `!`, `#`, `$`, `@`, `*`] {
		name = raw[start + 1..end]
	} else {
		return word_chars('$', quoted, false), start + 1
	}
	if name == '@' && quoted && multiple && !vars.legacy {
		mut args := []WordChar{}
		for i, arg in vars.args {
			if i > 0 { args << WordChar{ boundary: true } }
			args << word_chars(arg, true, false)
		}
		return args, end
	}
	if next != `{` {
		value := vars.parameter(name) or { '' }
		return word_chars(value, quoted, !quoted), end
	}
	parts := expand_brace_param(name, mut vars)
	if !quoted {
		return parts, end
	}
	return word_chars(word_text(parts), true, false), end
}

// expand_vars provides string expansion for callers that do not have a shell
// session (such as the parser stress harness).
pub fn expand_vars(s string) string {
	mut vars := Variables{ legacy: true }
	mut result := strings.new_builder(s.len)
	mut i := 0
	for i < s.len {
		if s[i] == `$` {
			chars, next := expand_dollar(s, i, false, false, mut vars)
			result.write_string(word_text(chars))
			i = next
		} else {
			result.write_u8(s[i])
			i++
		}
	}
	if vars.expansion_error != '' { eprintln(vars.expansion_error) }
	return result.str()
}

fn expand_word_chars(raw string, literal_split bool, multiple bool, mut vars Variables) []WordChar {
	mut chars := []WordChar{}
	mut quote := u8(0)
	mut empty_quote := false
	mut i := 0
	if raw == '~' || raw.starts_with('~/') {
		chars << word_chars(vars.get('HOME') or { os.home_dir() }, true, false)
		i = 1
	}
	for i < raw.len {
		ch := raw[i]
		if ch in [`'`, `"`] && (quote == 0 || ch == quote) {
			if quote != 0 && empty_quote { chars << WordChar{ anchor: true } }
			quote = if quote == 0 { ch } else { u8(0) }
			empty_quote = quote != 0
			i++
			continue
		}
		empty_quote = false
		if ch == `$` && quote != `'` {
			part, next := expand_dollar(raw, i, quote != 0, multiple, mut vars)
			chars << part
			i = next
			if vars.expansion_error != '' && !vars.legacy {
				break
			}
			continue
		}
		mut escaped := false
		if ch == `\\` && i + 1 < raw.len && quote_escape(quote, raw[i + 1]) {
			i++
			if raw[i] == `\n` {
				i++
				continue
			}
			escaped = true
		}
		size := utf8_char_len_at(raw, i)
		protected := escaped || quote != 0
		chars << WordChar{
			ch:     raw[i..i + size].runes()[0]
			quoted: protected
			split:  literal_split && !protected
		}
		i += size
	}
	return chars
}

fn ifs_delimiter(atom WordChar, ifs []rune) bool {
	return atom.split && !atom.anchor && !atom.boundary && atom.ch in ifs
}

fn ifs_space(ch rune) bool {
	return ch in [` `, `\t`, `\n`]
}

fn split_fields(chars []WordChar, ifs []rune) [][]WordChar {
	mut fields := [][]WordChar{}
	mut field := []WordChar{}
	mut i := 0
	for i < chars.len {
		atom := chars[i]
		if atom.boundary {
			fields << field
			field = []
			i++
		} else if ifs_delimiter(atom, ifs) {
			mut nonwhite := !ifs_space(atom.ch)
			for i < chars.len && ifs_delimiter(chars[i], ifs) && ifs_space(chars[i].ch) {
				i++
			}
			if i < chars.len && ifs_delimiter(chars[i], ifs) {
				nonwhite = true
				i++
				for i < chars.len && ifs_delimiter(chars[i], ifs) && ifs_space(chars[i].ch) {
					i++
				}
			}
			if field.len > 0 || nonwhite {
				fields << field
				field = []
			}
		} else {
			field << atom
			i++
		}
	}
	if field.len > 0 { fields << field }
	return fields
}

fn expand_pathname(chars []WordChar) []string {
	literal := word_text(chars)
	mut pattern := strings.new_builder(literal.len)
	mut wildcard := false
	for atom in chars {
		if atom.anchor {
			continue
		}
		if atom.ch == `\\` || (atom.quoted && atom.ch in [`*`, `?`, `[`, `]`]) {
			pattern.write_u8(`\\`)
		}
		if !atom.quoted && atom.ch in [`*`, `?`, `[`] {
			wildcard = true
		}
		pattern.write_rune(atom.ch)
	}
	if !wildcard {
		return [literal]
	}
	pat := pattern.str()
	// Preserve the existing recursive-glob extension.
	if !pat.contains('\\') && '**' in pat.split('/') {
		return glob_expand(literal, false)
	}
	mut matches := C.glob_t{}
	defer { C.globfree(&matches) }
	if C.glob(&char(pat.str), 0, unsafe { nil }, &matches) != 0 {
		return [literal]
	}
	mut result := []string{cap: int(matches.gl_pathc)}
	for i in 0 .. int(matches.gl_pathc) {
		result << unsafe { cstring_to_vstring(matches.gl_pathv[i]) }
	}
	return result
}

pub fn expand_word(raw string, mut vars Variables) []string {
	chars := expand_word_chars(raw, false, true, mut vars)
	ifs := (vars.get('IFS') or { ' \t\n' }).runes()
	mut words := []string{}
	for field in split_fields(chars, ifs) {
		words << expand_pathname(field)
	}
	return words
}

pub fn expand_scalar(raw string, mut vars Variables) string {
	return word_text(expand_word_chars(raw, false, false, mut vars))
}

// parse_tokens is the expanded view used by completion, history and tools.
pub fn parse_tokens(input string) []ShellToken {
	raw := lex(input) or { return [] }
	mut vars := Variables{ legacy: true }
	mut tokens := []ShellToken{}
	mut redirection := false
	for token in raw {
		if token.operator {
			if token.text != '\n' { tokens << ShellToken{ text: token.text, operator: true } }
			redirection = is_redirection(token.text)
		} else if redirection || is_env_assign(token.text) {
			tokens << ShellToken{ text: expand_scalar(token.text, mut vars) }
			redirection = false
		} else {
			for field in expand_word(token.text, mut vars) {
				tokens << ShellToken{ text: field }
			}
		}
	}
	if vars.expansion_error != '' { eprintln(vars.expansion_error) }
	return tokens
}

pub fn parse_args(input string) []string {
	return parse_tokens(input).map(it.text)
}
