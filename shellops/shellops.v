module shellops

import os
import utils

// write_redirect writes content to a file (truncate or append mode).
pub fn write_redirect(path string, content string, append_mode bool) ! {
	flag := if append_mode { 'a' } else { 'w' }
	mut f := os.open_file(path, flag) or {
		return error('cannot open ${path}: ${err.msg()}')
	}
	defer { f.close() }
	f.write_string(content)!
}

pub struct RedirectWord {
pub:
	operator string
	target   string
}

pub struct SimpleCommand {
pub mut:
	assignments []string
	words       []string
	redirects   []RedirectWord
}

pub struct ChainPart {
pub:
	cmd    string
	pre_op string
	stages []SimpleCommand
}

// parse_commands recognizes lists of pipelines of simple commands. Newlines
// separate complete commands and continue a pipeline or conditional list.
pub fn parse_commands(input string) ![]ChainPart {
	tokens := utils.lex(input)!
	mut parts := []ChainPart{}
	mut stages := []SimpleCommand{}
	mut stage := SimpleCommand{}
	mut start := 0
	mut end := 0
	mut pre_op := ''
	mut pending_pipe := false
	mut i := 0
	for i < tokens.len {
		token := tokens[i]
		if !token.operator {
			if stage.words.len == 0 && utils.is_env_assign(token.text) {
				stage.assignments << token.text
			} else {
				stage.words << token.text
			}
		} else if utils.is_redirection(token.text) {
			if token.text.contains('<<') {
				return error('syntax error: here-documents are not supported')
			}
			i++
			if i >= tokens.len || tokens[i].operator {
				return error('syntax error: missing redirection target')
			}
			stage.redirects << RedirectWord{ operator: token.text, target: tokens[i].text }
		} else {
			has_stage := stage.words.len > 0 || stage.assignments.len > 0 || stage.redirects.len > 0
			match token.text {
				'|' {
					if !has_stage {
						return error('syntax error: missing pipeline stage')
					}
					stages << stage
					stage = SimpleCommand{}
					pending_pipe = true
				}
				';', '&&', '||', '\n' {
					if !has_stage {
						if token.text != '\n' {
							return error('syntax error: missing command')
						}
						if !pending_pipe {
							start = token.end
						}
						i++
						continue
					}
					stages << stage
					parts << ChainPart{ cmd: input[start..end].trim_space(), pre_op: pre_op, stages: stages }
					stages = []
					stage = SimpleCommand{}
					pre_op = if token.text == '\n' { ';' } else { token.text }
					pending_pipe = false
					start = token.end
				}
				else { return error('syntax error: unsupported operator ${token.text}') }
			}
			i++
			continue
		}
		end = tokens[i].end
		pending_pipe = false
		i++
	}
	if stage.words.len > 0 || stage.assignments.len > 0 || stage.redirects.len > 0 {
		stages << stage
		parts << ChainPart{ cmd: input[start..end].trim_space(), pre_op: pre_op, stages: stages }
	} else if pending_pipe || pre_op in ['&&', '||'] {
		return error('syntax error: missing command')
	}
	return parts
}

pub fn split_commands(input string) []ChainPart {
	parts := parse_commands(input) or { return [] }
	return parts.map(ChainPart{ cmd: it.cmd, pre_op: it.pre_op })
}

pub fn validate_command_line(input string) ! {
	_ := parse_commands(input)!
}
