module shellops

import os
import strings

// ChainPart represents one command in a &&/||/; chain together with the
// operator that precedes it (empty string for the first command).
pub struct ChainPart {
pub:
	cmd    string
	pre_op string // '', '&&', '||', ';'
}

// split_commands splits an input string on &&, ||, and ; operators while
// respecting single and double quotes.  A lone | is left in the buffer
// (it is a pipe, handled later by exec).
pub fn split_commands(input string) []ChainPart {
	mut parts := []ChainPart{}
	mut current := strings.new_builder(64)
	mut in_single := false
	mut in_double := false
	mut cur_op := ''
	mut depth := 0
	mut i := 0
	for i < input.len {
		ch := input[i]
		if ch == `\\` && !in_single && i + 1 < input.len {
			current.write_u8(ch)
			current.write_u8(input[i + 1])
			i += 2
			continue
		}
		if !in_single && ch == `$` && i + 1 < input.len && input[i + 1] == `{` { depth++ }
		if depth > 0 {
			current.write_u8(ch)
			if ch == `}` { depth-- }
			i++
			continue
		}
		if ch == `'` && !in_double {
			in_single = !in_single
			current.write_u8(ch)
		} else if ch == `"` && !in_single {
			in_double = !in_double
			current.write_u8(ch)
		} else if !in_single && !in_double {
			if ch == `&` && i + 1 < input.len && input[i + 1] == `&` {
				s := current.str().trim_space()
				if s != '' { parts << ChainPart{ cmd: s, pre_op: cur_op } }
				current = strings.new_builder(64)
				cur_op = '&&'
				i += 2
				continue
			} else if ch == `|` && i + 1 < input.len && input[i + 1] == `|` {
				s := current.str().trim_space()
				if s != '' { parts << ChainPart{ cmd: s, pre_op: cur_op } }
				current = strings.new_builder(64)
				cur_op = '||'
				i += 2
				continue
			} else if ch == `;` {
				s := current.str().trim_space()
				if s != '' { parts << ChainPart{ cmd: s, pre_op: cur_op } }
				current = strings.new_builder(64)
				cur_op = ';'
				i++
				continue
			} else {
				current.write_u8(ch)
			}
		} else {
			current.write_u8(ch)
		}
		i++
	}
	s := current.str().trim_space()
	if s != '' { parts << ChainPart{ cmd: s, pre_op: cur_op } }
	return parts
}

// write_redirect writes content to a file (truncate or append mode).
pub fn write_redirect(path string, content string, append_mode bool) ! {
	flag := if append_mode { 'a' } else { 'w' }
	mut f := os.open_file(path, flag) or {
		return error('cannot open ${path}: ${err.msg()}')
	}
	defer { f.close() }
	f.write_string(content)!
}

// Validate before dispatch so malformed lists never execute a partial command.
pub fn validate_command_line(input string) ! {
	mut quote := u8(0)
	mut depth := 0
	mut word := false
	mut last_op := ''
	mut i := 0
	for i < input.len {
		ch := input[i]
		if ch == `\\` && quote != `'` {
			if i + 1 >= input.len {
				return error('syntax error: trailing backslash')
			}
			i += 2
			word = true
			continue
		}
		if quote != 0 {
			if ch == quote {
				quote = 0
			}
			i++
			continue
		}
		if ch == `'` || ch == `"` {
			quote = ch
			word = true
			i++
			continue
		}
		if ch == `$` && i + 1 < input.len && input[i + 1] == `{` { depth++ }
		if depth > 0 {
			if ch == `}` { depth-- }
			word = true
			i++
			continue
		}
		if ch == `;` || ch == `|` || (ch == `&` && i + 1 < input.len && input[i + 1] == `&`) {
			if !word {
				return error('syntax error: missing command')
			}
			last_op = ch.ascii_str()
			if i + 1 < input.len && input[i + 1] == ch && ch != `;` {
				last_op += ch.ascii_str()
				i++
			}
			word = false
		} else if ch != ` ` && ch != `\t` && ch != `\n` && ch != `\r` {
			word = true
		}
		i++
	}
	if quote != 0 || depth != 0 {
		return error('syntax error: unterminated quote or parameter expansion')
	}
	if !word && last_op != '' && last_op != ';' {
		return error('syntax error: missing command')
	}
}
