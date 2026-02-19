module main

import os
import strings
import term
import readline { Readline }

import cfg
import cmds
import exec
import mux
import plugins
import utils

const version = '1.0.3'

fn pre_prompt() string {
	mut current_dir := term.colorize(term.bold, '$os.getwd() ')
	current_dir = current_dir.replace('$os.home_dir()', '~')
	return current_dir
}

fn tab_complete(input string) []string {
	parts := input.split(' ')
	last_word := parts.last()
	cmd_prefix := if parts.len > 1 { parts[..parts.len - 1].join(' ') + ' ' } else { '' }

	mut search_dir := '.'
	mut file_prefix := last_word
	mut path_prefix := ''

	if last_word.contains('/') {
		slash_parts := last_word.split('/')
		file_prefix = slash_parts.last()
		dir_part := slash_parts[..slash_parts.len - 1].join('/')
		search_dir = if dir_part == '' { '/' } else { dir_part }
		path_prefix = if search_dir.ends_with('/') { search_dir } else { search_dir + '/' }
	}

	// Expand ~ to home directory for filesystem operations
	expanded_search_dir := if search_dir.starts_with('~') {
		os.home_dir() + search_dir[1..]
	} else {
		search_dir
	}

	entries := os.ls(expanded_search_dir) or { return []string{} }

	mut results := []string{}
	for entry in entries {
		if entry.starts_with(file_prefix) {
			full_path := path_prefix + entry
			expanded_full_path := if full_path.starts_with('~') {
				os.home_dir() + full_path[1..]
			} else {
				full_path
			}
			suffix := if os.is_dir(expanded_full_path) { '/' } else { '' }
			results << cmd_prefix + full_path + suffix
		}
	}

	results.sort()
	return results
}

// load_history populates r.previous_lines from ~/.vlsh_history (last 5000 entries).
fn load_history(mut r Readline) {
	hfile := os.home_dir() + '/.vlsh_history'
	content := os.read_file(hfile) or { return }
	lines := content.split('\n')
	r.previous_lines = [[]rune{}]
	for i := lines.len - 1; i >= 0; i-- {
		line := lines[i]
		if line.len > 0 {
			r.previous_lines << line.runes()
		}
	}
}

// append_history appends entry to ~/.vlsh_history and trims to 5000 entries.
fn append_history(entry string) {
	hfile := os.home_dir() + '/.vlsh_history'
	mut f := os.open_file(hfile, 'a') or { return }
	f.write_string(entry + '\n') or {}
	f.close()
	content := os.read_file(hfile) or { return }
	lines := content.split('\n').filter(it.len > 0)
	if lines.len > 5000 {
		os.write_file(hfile, lines[lines.len - 5000..].join('\n') + '\n') or {}
	}
}

fn main() {

	if !os.exists(cfg.config_file) {
		cfg.create_default_config_file() or { panic(err.msg()) }
	}

	term.clear()
	mut loaded_plugins := plugins.load()
	mut r := Readline{}
	r.completion_callback = tab_complete
	load_history(mut r)
	for {
		println(pre_prompt())
		seg := plugins.prompt_segments(loaded_plugins)
		if seg != '' {
			println(seg)
		}
		cmd := vlsh_read_line(mut r, term.rgb(255, 112, 112, '- ')) or {
			// Ctrl+C cancels the current line; re-show the prompt.
			if err.msg() == 'cancelled' { continue }
			utils.fail(err.msg())
			return
		}
		trimmed := cmd.str().trim_space()
		if trimmed.len > 0 {
			append_history(trimmed)
		}
		plugins.run_pre_hooks(loaded_plugins, trimmed)
		exit_code := main_loop(trimmed, mut loaded_plugins)
		plugins.run_post_hooks(loaded_plugins, trimmed, exit_code)
	}
}

// builtin_redirect strips > and >> redirection tokens from a built-in command's
// argument list, returning (cleanArgs, targetFile, appendMode).
fn builtin_redirect(args []string) ([]string, string, bool) {
	mut out      := []string{}
	mut rfile    := ''
	mut rappend  := false
	mut skip     := false
	for i, tok in args {
		if skip { skip = false; continue }
		if tok == '>>' {
			rappend = true
			if i + 1 < args.len {
				rfile = if args[i+1].starts_with('~/') {
					os.home_dir() + args[i+1][1..]
				} else if args[i+1] == '~' {
					os.home_dir()
				} else {
					args[i+1]
				}
				skip = true
			}
		} else if tok == '>' {
			rappend = false
			if i + 1 < args.len {
				rfile = if args[i+1].starts_with('~/') {
					os.home_dir() + args[i+1][1..]
				} else if args[i+1] == '~' {
					os.home_dir()
				} else {
					args[i+1]
				}
				skip = true
			}
		} else {
			out << tok
		}
	}
	return out, rfile, rappend
}

// write_redirect writes output to a file (create/truncate or append).
fn write_redirect(path string, content string, append_mode bool) ! {
	flag := if append_mode { 'a' } else { 'w' }
	mut f := os.open_file(path, flag) or {
		return error('cannot open ${path}: ${err.msg()}')
	}
	f.write_string(content) or {}
	f.close()
}

// split_and_chain splits an input string on && tokens while respecting single
// and double quotes.  Each returned element is a trimmed sub-command string.
fn split_and_chain(input string) []string {
	mut parts     := []string{}
	mut current   := strings.new_builder(64)
	mut in_single := false
	mut in_double := false
	mut i         := 0
	for i < input.len {
		ch := input[i]
		if ch == `'` && !in_double {
			in_single = !in_single
			current.write_u8(ch)
		} else if ch == `"` && !in_single {
			in_double = !in_double
			current.write_u8(ch)
		} else if ch == `&` && !in_single && !in_double && i + 1 < input.len && input[i + 1] == `&` {
			s := current.str().trim_space()
			if s != '' { parts << s }
			current = strings.new_builder(64)
			i += 2
			continue
		} else {
			current.write_u8(ch)
		}
		i++
	}
	s := current.str().trim_space()
	if s != '' { parts << s }
	return parts
}

// venv helpers — the list of venv-managed variable names is stored inside the
// environment itself (as a colon-separated value) so no global state is needed.
const venv_registry = '__VLSH_VENV'

fn venv_tracked() []string {
	reg := os.getenv(venv_registry)
	if reg == '' { return []string{} }
	return reg.split(':').filter(it.len > 0)
}

fn venv_track(key string) {
	mut keys := venv_tracked()
	if key !in keys { keys << key }
	os.setenv(venv_registry, keys.join(':'), true)
}

fn venv_untrack(key string) {
	keys := venv_tracked().filter(it != key)
	if keys.len == 0 {
		os.unsetenv(venv_registry)
	} else {
		os.setenv(venv_registry, keys.join(':'), true)
	}
}

// dispatch_cmd executes a fully parsed command and returns its exit code.
// Keeping this separate from main_loop lets main_loop set/unset temporary
// KEY=VALUE env-prefix overrides at a single cleanup point.
fn dispatch_cmd(cmd string, args []string, mut loaded_plugins []plugins.Plugin) int {
	match cmd {
		'aliases' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'list' {
					aliases := cfg.aliases() or {
						utils.fail(err.msg())
						return 1
					}
					for alias_name, alias_cmd in aliases {
						print('${term.bold(alias_name)} : ${term.italic(alias_cmd)}\n')
					}
				}
				'add' {
					if args.len < 2 {
						utils.fail('usage: aliases add <name>=<cmd>')
						return 1
					}
					mut name := ''
					mut alias_cmd := ''
					if args[1].contains('=') {
						eq_idx := args[1].index('=') or { 0 }
						name = args[1][..eq_idx]
						alias_cmd = args[1][eq_idx + 1..]
					} else {
						name = args[1]
						if args.len < 3 {
							utils.fail('usage: aliases add <name> <cmd>')
							return 1
						}
						alias_cmd = args[2..].join(' ')
					}
					if name == '' || alias_cmd == '' {
						utils.fail('alias name and command cannot be empty')
						return 1
					}
					cfg.add_alias(name, alias_cmd) or {
						utils.fail(err.msg())
						return 1
					}
					println('alias ${name} added')
				}
				'remove' {
					if args.len < 2 {
						utils.fail('usage: aliases remove <name>')
						return 1
					}
					cfg.remove_alias(args[1]) or {
						utils.fail(err.msg())
						return 1
					}
					println('alias ${args[1]} removed')
				}
				else {
					utils.fail('aliases: unknown subcommand "${subcmd}" (available: list, add, remove)')
				}
			}
		}
		'style' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'list' {
					current_style := cfg.style() or {
						utils.fail(err.msg())
						return 1
					}
					for key, rgb in current_style {
						println('${term.bold(key)}: ${rgb[0]}, ${rgb[1]}, ${rgb[2]}')
					}
				}
				'set' {
					if args.len < 5 {
						utils.fail('usage: style set <key> <r> <g> <b>')
						return 1
					}
					cfg.set_style(args[1], args[2].int(), args[3].int(), args[4].int()) or {
						utils.fail(err.msg())
						return 1
					}
					println('style ${args[1]} set to ${args[2]}, ${args[3]}, ${args[4]}')
				}
				else {
					utils.fail('style: unknown subcommand "${subcmd}" (available: list, set)')
				}
			}
		}
		'echo' {
			clean_args, rfile, rappend := builtin_redirect(args)
			mut parts := []string{}
			for arg in clean_args {
				if arg == '$0' {
					parts << 'vlsh'
				} else if arg.starts_with('$') {
					parts << os.getenv(arg[1..])
				} else {
					parts << arg
				}
			}
			output := parts.join(' ') + '\n'
			if rfile != '' {
				write_redirect(rfile, output, rappend) or { utils.fail(err.msg()) }
			} else {
				print(output)
			}
		}
		'cd' {
			cmds.cd(args) or {
				utils.fail(err.msg())
				return 1
			}
		}
		'ocp'     { cmds.ocp(args) or { utils.fail(err.msg()) } }
		'exit'    { exit(0) }
		'help'    { cmds.help(version, args) }
		'version' { println('version $version') }
		'share' {
			link := cmds.share(args) or {
				utils.fail(err.msg())
				return 1
			}
			println(link)
		}
		'ls' {
			cmds.ls(args) or {
				if err.msg() == '__fallthrough__' {
					// flags were passed — let the system ls handle it
					local_cfg := cfg.get() or {
						utils.fail(err.msg())
						return 1
					}
					mut t := exec.Task{
						cmd: exec.Cmd_object{
							cmd  : cmd,
							args : args,
							cfg  : local_cfg
						}
					}
					t.prepare_task() or {
						utils.fail(err.msg())
						return 1
					}
				} else {
					utils.fail(err.msg())
				}
			}
		}
		'path' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'list' {
					current_paths := cfg.paths() or {
						utils.fail(err.msg())
						return 1
					}
					for p in current_paths {
						println(p)
					}
				}
				'add' {
					if args.len < 2 {
						utils.fail('usage: path add <dir>')
						return 1
					}
					dir := args[1]
					if !os.exists(dir) {
						utils.fail('directory does not exist: ${dir}')
						return 1
					}
					cfg.add_path(dir) or {
						utils.fail(err.msg())
						return 1
					}
					println('added ${dir} to PATH')
				}
				'remove' {
					if args.len < 2 {
						utils.fail('usage: path remove <dir>')
						return 1
					}
					cfg.remove_path(args[1]) or {
						utils.fail(err.msg())
						return 1
					}
					println('removed ${args[1]} from PATH')
				}
				else {
					utils.fail('path: unknown subcommand "${subcmd}" (available: list, add, remove)')
				}
			}
		}
		'mux' {
			if os.getenv('VLSH_IN_MUX') != '' {
				utils.fail('already inside a mux session')
				return 1
			}
			mux.enter()
		}
		'plugins' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'reload' {
					loaded_plugins = plugins.load()
					println('plugins: ${loaded_plugins.len} loaded')
				}
				'list' {
					all := plugins.available()
					if all.len == 0 {
						println('no plugins found in ~/.vlsh/plugins/')
					} else {
						dis := plugins.disabled()
						for name in all {
							if dis[name] {
								println('${name}  [disabled]')
							} else {
								for p in loaded_plugins {
									if p.name == name {
										cmds_str := if p.commands.len > 0 { '  commands: ${p.commands.join(', ')}' } else { '' }
										println('${term.bold(name)}${cmds_str}')
										break
									}
								}
							}
						}
					}
				}
				'enable' {
					if args.len < 2 {
						utils.fail('usage: plugins enable <name>')
						return 1
					}
					name := args[1]
					plugins.enable(name) or {
						utils.fail(err.msg())
						return 1
					}
					loaded_plugins = plugins.load()
					println('${name} enabled')
				}
				'disable' {
					if args.len < 2 {
						utils.fail('usage: plugins disable <name>')
						return 1
					}
					name := args[1]
					plugins.disable(name) or {
						utils.fail(err.msg())
						return 1
					}
					loaded_plugins = loaded_plugins.filter(it.name != name)
					println('${name} disabled')
				}
				else {
					utils.fail('plugins: unknown subcommand "${subcmd}" (available: list, reload, enable, disable)')
				}
			}
		}
		'venv' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'list' {
					keys := venv_tracked()
					if keys.len == 0 {
						println('no session variables set')
					} else {
						for key in keys {
							println('${term.bold(key)}=${os.getenv(key)}')
						}
					}
				}
				'add' {
					if args.len < 3 {
						utils.fail('usage: venv add <NAME> <value>')
						return 1
					}
					name  := args[1]
					value := args[2..].join(' ')
					os.setenv(name, value, true)
					venv_track(name)
					println('${name} set to ${value}')
				}
				'rm' {
					if args.len < 2 {
						utils.fail('usage: venv rm <NAME>')
						return 1
					}
					name := args[1]
					os.unsetenv(name)
					venv_untrack(name)
					println('${name} unset')
				}
				else {
					utils.fail('venv: unknown subcommand "${subcmd}" (available: list, add, rm)')
				}
			}
		}
		else {
			if plugins.dispatch(loaded_plugins, cmd, args) {
				return 0
			}
			local_cfg := cfg.get() or {
				utils.fail(err.msg())
				return 1
			}
			mut t := exec.Task{
				cmd: exec.Cmd_object{
					cmd  : cmd,
					args : args,
					cfg  : local_cfg
				}
			}
			code := t.prepare_task() or {
				utils.fail(err.msg())
				return 1
			}
			return code
		}
	}
	return 0
}

fn main_loop(input string, mut loaded_plugins []plugins.Plugin) int {

	// Handle && chains: run each command in sequence; stop on first failure.
	and_parts := split_and_chain(input)
	if and_parts.len > 1 {
		for part in and_parts {
			code := main_loop(part, mut loaded_plugins)
			if code != 0 { return code }
		}
		return 0
	}

	input_split := utils.parse_args(input)
	if input_split.len == 0 {
		return 0
	}

	// Strip leading KEY=VALUE env assignments (e.g. `FOO=bar cmd args…`).
	// They are set in the parent's environment so the child inherits them,
	// then unset after the command returns so they don't persist.
	mut env_keys := []string{}
	mut start    := 0
	for start < input_split.len && utils.is_env_assign(input_split[start]) {
		tok := input_split[start]
		eq  := tok.index_u8(`=`)
		os.setenv(tok[..eq], tok[eq + 1..], true)
		env_keys << tok[..eq]
		start++
	}

	cmd  := if start < input_split.len { input_split[start] } else { '' }
	args := if start + 1 < input_split.len { input_split[start + 1..].clone() } else { []string{} }

	if cmd == '' {
		for key in env_keys { os.unsetenv(key) }
		return 0
	}

	code := dispatch_cmd(cmd, args, mut loaded_plugins)
	for key in env_keys { os.unsetenv(key) }
	return code
}

