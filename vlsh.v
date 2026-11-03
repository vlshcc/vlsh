module main

import os
import term
import cfg
import cmds
import exec
import mux
import plugins
import shellops { split_commands, write_redirect }
import utils

// Human release line (bump when you cut a release). Unreleased builds from git
// get a compile-time suffix: `make` / pkg/build.sh pass `-d git_sha=<short>`.
const version_base = '1.2'
const git_revision = $d('git_sha', '')
const version = if git_revision != '' { '${version_base}-${git_revision}' } else { version_base }

fn pre_prompt() string {
	mut current_dir := term.colorize(term.bold, '${os.getwd()} ')
	current_dir = current_dir.replace('${os.home_dir()}', '~')
	return current_dir
}

fn tab_complete(input string, loaded []plugins.Plugin) []string {
	parts := input.split(' ')

	// Let plugins handle completion for commands they claim (e.g. ssh).
	if parts.len > 1 {
		plugin_results := plugins.completions(loaded, input)
		if plugin_results.len > 0 {
			return plugin_results
		}
	}

	last_word := parts.last()
	cmd_prefix := if parts.len > 1 { parts[..parts.len - 1].join(' ') + ' ' } else { '' }
	dirs_only := parts[0] == 'cd'

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
			is_dir := os.is_dir(expanded_full_path)
			if dirs_only && !is_dir {
				continue
			}
			suffix := if is_dir { '/' } else { '' }
			quoted := utils.quote_shell_token_if_needed(full_path + suffix)
			results << cmd_prefix + quoted
		}
	}

	// First word, not a path fragment: merge executables from $PATH (same lookup as running a command).
	if parts.len == 1 && !last_word.contains('/') && !dirs_only {
		mut seen := map[string]bool{}
		for r in results {
			seen[r] = true
		}
		for name in exec.path_command_completions(file_prefix) {
			s := cmd_prefix + name
			if !seen[s] {
				seen[s] = true
				results << s
			}
		}
	}

	results.sort()
	return results
}

// load_history populates r.previous_lines from ~/.vlsh_history (last 5000 entries).
fn load_history(mut r VlshReadline) {
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
	// Batch mode has no prompt, history writes, config creation or plugin loading.
	if os.args.len > 1 {
		match os.args[1] {
			'--version', '-v' {
				println('version ${version}')
				return
			}
			'--help', '-h' {
				println('Usage: vlsh [-c command | script]')
				return
			}
			'-c' {
				if os.args.len != 3 {
					eprintln('vlsh: -c requires one command string')
					exit(2)
				}
				mut loaded := []plugins.Plugin{}
				os.setenv('?', '0', true)
				exit(main_loop(os.args[2], mut loaded))
			}
			else {
				content := os.read_file(os.args[1]) or {
					eprintln('vlsh: ${err.msg()}')
					exit(1)
				}
				exit(run_script(content))
			}
		}
	}
	if os.is_atty(0) == 0 {
		exit(run_script(os.get_raw_lines_joined()))
	}
	if !os.exists(cfg.config_file) {
		cfg.create_default_config_file() or { panic(err.msg()) }
	}

	term.clear()
	mut loaded_plugins := plugins.load(false)
	mut r := VlshReadline{}
	r.completion_callback = fn [mut loaded_plugins] (input string) []string {
		return tab_complete(input, loaded_plugins)
	}
	load_history(mut r)
	os.setenv('?', '0', true)
	source_rc(mut loaded_plugins)
	mut history_entries := utils.load_history_entries_from_file()
	mut last_executed_command := ''
	for {
		println(pre_prompt())
		seg := plugins.prompt_segments(loaded_plugins)
		if seg != '' {
			println(seg)
		}
		cmd := vlsh_read_line(mut r, term.rgb(255, 112, 112, '- ')) or {
			// Ctrl+C cancels the current line; re-show the prompt.
			if err.msg() == 'cancelled' {
				continue
			}
			utils.fail(err.msg())
			return
		}
		trimmed := cmd.str().trim_space()
		mut expanded := trimmed
		if trimmed.len > 0 {
			expanded = utils.expand_history_notation(trimmed, last_executed_command, history_entries) or {
				eprintln('vlsh: ${err.msg()}')
				continue
			}
			append_history(trimmed)
			history_entries << trimmed
			if history_entries.len > 5000 {
				history_entries = history_entries[1..].clone()
			}
		}
		plugins.run_pre_hooks(loaded_plugins, trimmed)
		exit_code := main_loop(expanded, mut loaded_plugins)
		os.setenv('?', exit_code.str(), true)
		plugins.run_post_hooks(loaded_plugins, trimmed, exit_code)
		if expanded.len > 0 {
			last_executed_command = expanded
		}
	}
}

fn run_script(content string) int {
	mut loaded := []plugins.Plugin{}
	os.setenv('?', '0', true)
	mut code := 0
	for line in content.split('\n') {
		if line.trim_space() == '' || line.trim_space().starts_with('#') {
			continue
		}
		code = main_loop(line, mut loaded)
		os.setenv('?', code.str(), true)
	}
	return code
}

// source_rc processes export/unset lines from ~/.vlshrc at startup so that
// environment variables (including PATH) are set before the first prompt.
fn source_rc(mut loaded_plugins []plugins.Plugin) {
	if !os.exists(cfg.config_file) {
		return
	}
	lines := os.read_lines(cfg.config_file) or { return }
	for line in lines {
		t := line.trim_space()
		if t.starts_with('export ') || t.starts_with('unset ') {
			main_loop(t, mut loaded_plugins)
		}
	}
}

// dispatch_cmd executes a fully parsed command and returns its exit code.
// Keeping this separate from main_loop lets main_loop set/unset temporary
// KEY=VALUE env-prefix overrides at a single cleanup point.
// full_cmdline is the original, unsplit input used for hook notifications.
fn dispatch_cmd(cmd string, args []string, mut loaded_plugins []plugins.Plugin, full_cmdline string, tokens []utils.ShellToken, alias_depth int) int {
	// Expand aliases before the match so that aliases whose expansion begins
	// with a builtin command (e.g. `nav=cd /tmp`) are dispatched correctly
	// instead of being sent to the external-command executor.
	// Bound indirect alias chains; self-aliases are expanded once by exec.
	alias_cfg := if os.exists(cfg.config_file) { cfg.get() or { cfg.Cfg{} } } else { cfg.Cfg{} }
	if cmd in alias_cfg.aliases {
		if alias_depth >= 32 {
			utils.fail('alias expansion limit exceeded')
			return 1
		}
		alias_tokens := utils.parse_tokens(alias_cfg.aliases[cmd])
		alias_split := alias_tokens.map(it.text)
		if alias_split.len == 0 {
			return 0
		}
		expanded_cmd := alias_split[0]
		if expanded_cmd != cmd {
			mut expanded_args := if alias_split.len > 1 {
				alias_split[1..].clone()
			} else {
				[]string{}
			}
			expanded_args << args
			mut expanded_tokens := alias_tokens.clone()
			expanded_tokens << tokens[1..]
			return dispatch_cmd(expanded_cmd, expanded_args, mut loaded_plugins, full_cmdline, expanded_tokens, alias_depth + 1)
		}
	}

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
			mut clean_args := []string{}
			mut rfile := ''
			mut rappend := false
			mut i := 1
			for i < tokens.len {
				if tokens[i].operator && tokens[i].text in ['>', '>>'] {
					if i + 1 >= tokens.len || tokens[i + 1].operator || tokens[i + 1].text == '' {
						utils.fail('syntax error: missing redirection target')
						return 2
					}
					rappend = tokens[i].text == '>>'
					i++
					rfile = tokens[i].text
				} else {
					clean_args << tokens[i].text
				}
				i++
			}
			output := clean_args.join(' ') + '\n'
			if rfile != '' {
				write_redirect(rfile, output, rappend) or {
					utils.fail(err.msg())
					return 1
				}
			} else {
				print(output)
			}
			plugins.run_output_hooks(loaded_plugins, full_cmdline, 0, output)
		}
		'cd' {
			cmds.cd(args) or {
				utils.fail(err.msg())
				return 1
			}
		}
		'ocp' {
			cmds.ocp(args) or {
				utils.fail(err.msg())
				return 1
			}
		}
		'exit' {
			code := if args.len > 0 { args[0].int() } else { 0 }
			exit(code)
		}
		'export' {
			if args.len == 0 {
				env := os.environ()
				mut keys := env.keys()
				keys.sort()
				for k in keys {
					println('${k}=${env[k]}')
				}
			} else {
				for arg in args {
					if arg.contains('=') {
						eq := arg.index_u8(`=`)
						os.setenv(arg[..eq], arg[eq + 1..], true)
					}
					// 'export VAR' without =: no-op (vars already inherit)
				}
			}
		}
		'unset' {
			for arg in args {
				os.unsetenv(arg)
			}
		}
		'source', '.' {
			if args.len == 0 {
				utils.fail('source: missing filename')
				return 1
			}
			content := os.read_file(args[0]) or {
				utils.fail('source: ${args[0]}: ${err.msg()}')
				return 1
			}
			mut last_code := 0
			for line in content.split('\n') {
				t := line.trim_space()
				if t.len == 0 || t.starts_with('#') {
					continue
				}
				last_code = main_loop(t, mut loaded_plugins)
			}
			return last_code
		}
		'help' {
			if args.len > 0 && plugins.show_help(loaded_plugins, args[0]) {
				// plugin handled the help request
			} else {
				cmds.help(version, args)
			}
		}
		'version' {
			println('version ${version}')
		}
		'ls' {
			cmds.ls(args) or {
				if err.msg() == '__fallthrough__' {
					local_cfg := if os.exists(cfg.config_file) {
						cfg.get() or { cfg.Cfg{} }
					} else {
						cfg.Cfg{}
					}
					mut t := exec.Task{
						tokens: tokens
						cmd:    exec.Cmd_object{
							cmd:     cmd
							args:    args
							aliases: local_cfg.aliases
						}
					}
					ls_code := t.prepare_task() or {
						utils.fail(err.msg())
						return 1
					}
					plugins.run_output_hooks(loaded_plugins, full_cmdline, ls_code, t.last_output)
					return ls_code
				} else {
					utils.fail(err.msg())
					return 1
				}
			}
		}
		'mux' {
			if os.getenv('VLSH_IN_MUX') != '' {
				utils.fail('already inside a mux session')
				return 1
			}
			mux.enter(plugins.mux_status_binaries(loaded_plugins))
		}
		'plugins' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'reload' {
					loaded_plugins = plugins.load(true)
					println('plugins: ${loaded_plugins.len} loaded')
				}
				'list' {
					all := plugins.installed_list()
					if all.len == 0 {
						println('no plugins found in ~/.vlsh/plugins/')
					} else {
						dis := plugins.disabled()
						for ip in all {
							if dis[ip.name] {
								println('${ip.name} ${ip.version}  [disabled]')
							} else {
								for p in loaded_plugins {
									if p.name == ip.name {
										cmds_str := if p.commands.len > 0 {
											'  commands: ${p.commands.join(', ')}'
										} else {
											''
										}
										println('${term.bold(ip.name)} ${ip.version}${cmds_str}')
										break
									}
								}
							}
						}
					}
				}
				'enable' {
					if args.len < 2 {
						utils.fail('usage: plugins enable <name|all>')
						return 1
					}
					name := args[1]
					if name == 'all' {
						plugins.enable_all() or {
							utils.fail(err.msg())
							return 1
						}
						loaded_plugins = plugins.load(true)
						println('all plugins enabled (${loaded_plugins.len} loaded)')
					} else {
						plugins.enable(name) or {
							utils.fail(err.msg())
							return 1
						}
						loaded_plugins = plugins.load(true)
						println('${name} enabled')
					}
				}
				'disable' {
					if args.len < 2 {
						utils.fail('usage: plugins disable <name|all>')
						return 1
					}
					name := args[1]
					if name == 'all' {
						plugins.disable_all() or {
							utils.fail(err.msg())
							return 1
						}
						loaded_plugins = []plugins.Plugin{}
						println('all plugins disabled')
					} else {
						plugins.disable(name) or {
							utils.fail(err.msg())
							return 1
						}
						loaded_plugins = loaded_plugins.filter(it.name != name)
						println('${name} disabled')
					}
				}
				'remote' {
					names := plugins.remote_plugin_names() or {
						utils.fail(err.msg())
						return 1
					}
					if names.len == 0 {
						println('no remote plugins found')
					} else {
						installed := plugins.installed_list()
						mut inst_map := map[string]string{}
						for ip in installed {
							inst_map[ip.name] = ip.version
						}
						for name in names {
							inst_ver := inst_map[name]
							if inst_ver != '' {
								latest := plugins.latest_remote_version(name) or { inst_ver }
								if latest != inst_ver {
									println('${term.bold(name)}  [installed ${inst_ver}, update available: ${latest}]')
								} else {
									println('${term.bold(name)}  [installed ${inst_ver}]')
								}
							} else {
								println(name)
							}
						}
					}
				}
				'search' {
					if args.len < 2 {
						utils.fail('usage: plugins search <query>')
						return 1
					}
					results := plugins.search_remote(args[1]) or {
						utils.fail(err.msg())
						return 1
					}
					if results.len == 0 {
						println('no plugins found matching "${args[1]}"')
					} else {
						for desc in results {
							println('${term.bold(desc.name)}  ${desc.description}')
						}
					}
				}
				'install' {
					if args.len < 2 {
						utils.fail('usage: plugins install <name>')
						return 1
					}
					name := args[1]
					inst_ver := plugins.install(name) or {
						utils.fail(err.msg())
						return 1
					}
					println('${name} ${inst_ver} installed — run "plugins reload" to activate it')
				}
				'update' {
					if args.len < 2 {
						installed := plugins.installed_list()
						if installed.len == 0 {
							println('no plugins installed')
						}
						mut any_updated := false
						for ip in installed {
							new_ver := plugins.update_plugin(ip.name) or {
								if err.msg().contains('already at latest') {
									println('${ip.name}: already at latest (${ip.version})')
								} else {
									utils.fail('${ip.name}: ${err.msg()}')
								}
								continue
							}
							println('${ip.name}: updated to ${new_ver}')
							any_updated = true
						}
						if any_updated {
							loaded_plugins = plugins.load(true)
						}
					} else {
						name := args[1]
						new_ver := plugins.update_plugin(name) or {
							utils.fail(err.msg())
							return 1
						}
						println('${name}: updated to ${new_ver}')
						loaded_plugins = plugins.load(true)
					}
				}
				'delete' {
					if args.len < 2 {
						utils.fail('usage: plugins delete <name>')
						return 1
					}
					name := args[1]
					plugins.delete_plugin(name) or {
						utils.fail(err.msg())
						return 1
					}
					loaded_plugins = loaded_plugins.filter(it.name != name)
					println('${name} deleted')
				}
				'reinstall' {
					if args.len < 2 {
						utils.fail('usage: plugins reinstall <name>')
						return 1
					}
					name := args[1]
					ver := plugins.reinstall_plugin(name) or {
						utils.fail(err.msg())
						return 1
					}
					loaded_plugins = plugins.load(true)
					println('${name} ${ver} reinstalled (${loaded_plugins.len} plugins loaded)')
				}
				else {
					utils.fail('plugins: unknown subcommand "${subcmd}" (available: list, reload, enable, disable, remote, search, install, update, delete, reinstall)')
				}
			}
		}
		else {
			if plugins.dispatch(loaded_plugins, cmd, args) {
				return 0
			}
			local_cfg := if os.exists(cfg.config_file) {
				cfg.get() or { cfg.Cfg{} }
			} else {
				cfg.Cfg{}
			}
			mut t := exec.Task{
				tokens: tokens
				cmd:    exec.Cmd_object{
					cmd:     cmd
					args:    args
					aliases: local_cfg.aliases
				}
			}
			code := t.prepare_task() or {
				utils.fail(err.msg())
				return 1
			}
			plugins.run_output_hooks(loaded_plugins, full_cmdline, code, t.last_output)
			return code
		}
	}
	return 0
}

fn main_loop(input string, mut loaded_plugins []plugins.Plugin) int {
	if input.trim_space().starts_with('#') {
		return os.getenv('?').int()
	}
	shellops.validate_command_line(input) or {
		utils.fail(err.msg())
		return 2
	}
	// Handle &&, ||, and ; chains while respecting quotes.
	chain := split_commands(input)
	if chain.len > 1 {
		mut last_code := 0
		for i, part in chain {
			should_run := i == 0 || (part.pre_op == '&&' && last_code == 0)
				|| (part.pre_op == '||' && last_code != 0) || part.pre_op == ';'
			if should_run {
				last_code = main_loop(part.cmd, mut loaded_plugins)
				os.setenv('?', last_code.str(), true)
			}
		}
		return last_code
	}

	single_input := if chain.len == 1 { chain[0].cmd } else { input }
	tokens := utils.parse_tokens(single_input)
	input_split := tokens.map(it.text)
	if input_split.len == 0 {
		return os.getenv('?').int()
	}

	// Save existence as well as value, including empty and repeated assignments.
	previous_env := os.environ()
	mut env_keys := []string{}
	mut start := 0
	for start < input_split.len && !tokens[start].operator && utils.is_env_assign(input_split[start]) {
		tok := input_split[start]
		eq := tok.index_u8(`=`)
		key := tok[..eq]
		os.setenv(key, tok[eq + 1..], true)
		env_keys << key
		start++
	}
	// Assignment-only commands persist in this shell session.
	if start == input_split.len {
		return 0
	}
	defer { restore_environment(env_keys, previous_env) }
	cmd := input_split[start]
	args := input_split[start + 1..].clone()
	tail := tokens[start..]
	// Streaming pipes and external redirections go through the executor.
	if tail.any(it.operator && it.text == '|') || (cmd != 'echo' && tail.any(it.operator)) {
		local_cfg := if os.exists(cfg.config_file) { cfg.get() or { cfg.Cfg{} } } else { cfg.Cfg{} }
		mut t := exec.Task{
			tokens: tail
			cmd:    exec.Cmd_object{ cmd: cmd, args: args, aliases: local_cfg.aliases }
		}
		code := t.prepare_task() or {
			utils.fail(err.msg())
			return 1
		}
		plugins.run_output_hooks(loaded_plugins, input, code, t.last_output)
		return code
	}
	return dispatch_cmd(cmd, args, mut loaded_plugins, input, tail, 0)
}

// Kept outside defer so older V compilers generate statement-form branches.
fn restore_environment(keys []string, previous map[string]string) {
	for key in keys {
		if key in previous {
			os.setenv(key, previous[key], true)
		} else {
			os.unsetenv(key)
		}
	}
}
