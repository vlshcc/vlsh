module utils

import strings

// LexToken preserves source spelling until the command's expansion context is known.
pub struct LexToken {
pub:
	text     string
	operator bool
	start    int
	end      int
}

fn quote_escape(quote u8, next u8) bool {
	return quote == 0 || (quote == `"` && next in [`$`, `"`, `\\`, `\n`, `\x60`])
}

// parameter_end skips a braced expansion, including nested braced words and
// quoted closing braces. start is the first byte after ${.
fn parameter_end(input string, start int) int {
	mut quotes := [u8(0)]
	mut i := start
	for i < input.len {
		ch := input[i]
		quote := quotes.last()
		if ch == `\\` && i + 1 < input.len && quote_escape(quote, input[i + 1]) {
			i += 2
			continue
		}
		if ch in [`'`, `"`] && (quote == 0 || quote == ch) {
			quotes[quotes.len - 1] = if quote == 0 { ch } else { u8(0) }
		} else if quote != `'` && ch == `$` && i + 1 < input.len && input[i + 1] == `{` {
			quotes << u8(0)
			i += 2
			continue
		} else if ch == `}` && quote == 0 {
			quotes.pop()
			if quotes.len == 0 {
				return i + 1
			}
		}
		i++
	}
	return -1
}

// lex recognizes shell syntax without expanding words or consulting IFS.
pub fn lex(input string) ![]LexToken {
	mut tokens := []LexToken{}
	mut word := strings.new_builder(32)
	mut start := 0
	mut quote := u8(0)
	mut i := 0
	for i < input.len {
		ch := input[i]
		if ch == `\\` && quote != `'` {
			if i + 1 >= input.len {
				return error('syntax error: trailing backslash')
			}
			next := input[i + 1]
			if next == `\n` {
				i += 2
				continue
			}
			if quote_escape(quote, next) {
				if word.len == 0 {
					start = i
				}
				word.write_u8(ch)
				word.write_u8(next)
				i += 2
				continue
			}
		}
		if word.len == 0 {
			start = i
		}
		if ch in [`'`, `"`] && (quote == 0 || quote == ch) {
			quote = if quote == 0 { ch } else { u8(0) }
			word.write_u8(ch)
		} else if quote != `'` && ch == `$` && i + 1 < input.len && input[i + 1] == `{` {
			end := parameter_end(input, i + 2)
			if end < 0 {
				return error('syntax error: unterminated parameter expansion')
			}
			word.write_string(input[i..end])
			i = end
			continue
		} else if quote == 0 && word.len == 0 && ch == `#` {
			for i < input.len && input[i] != `\n` {
				i++
			}
			continue
		} else if quote == 0 && ch in [` `, `\t`, `\n`, `;`, `|`, `&`, `>`, `<`] {
			mut op_start := i
			mut op := ''
			mut width := 1
			if ch !in [` `, `\t`] {
				op = ch.ascii_str()
				if i + 1 < input.len {
					next := input[i + 1]
					if (next == ch && ch in [`|`, `&`, `>`, `<`, `;`])
						|| (ch in [`<`, `>`] && next == `&`) {
						op += next.ascii_str()
						width++
					}
				}
				if ch in [`<`, `>`] && word.len > 0 {
					prefix := word.str()
					if prefix.bytes().all(it >= `0` && it <= `9`) {
						op = prefix + op
						op_start = start
					} else {
						tokens << LexToken{ text: prefix, start: start, end: i }
					}
					word = strings.new_builder(32)
				}
			}
			if word.len > 0 {
				tokens << LexToken{ text: word.str(), start: start, end: i }
				word = strings.new_builder(32)
			}
			if op != '' {
				tokens << LexToken{ text: op, operator: true, start: op_start, end: i + width }
				i += width
				continue
			}
		} else {
			word.write_u8(ch)
		}
		i++
	}
	if quote != 0 {
		return error('syntax error: unterminated quote')
	}
	if word.len > 0 {
		tokens << LexToken{ text: word.str(), start: start, end: input.len }
	}
	return tokens
}

pub fn is_redirection(op string) bool {
	return op.contains('<') || op.contains('>')
}
