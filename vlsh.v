module main

import os
import strconv
import term
import cfg
import cmds
import exec
import mux
import plugins
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
				println('Usage: vlsh [-c command [name [args...]] | script [args...]]')
				println('       vlsh [--help | --version]')
				println('')
				println('-c command   Execute a command string; name sets \$0 and args set positional parameters.')
				println('script       Execute a script file with optional positional arguments.')
				println('No arguments starts the interactive shell, or reads commands from piped stdin.')
				println('Use help for builtins and help syntax for the supported shell language.')
				return
			}
			'-c' {
				if os.args.len < 3 {
					eprintln('vlsh: -c requires a command string')
					exit(2)
				}
				arg0 := if os.args.len > 3 { os.args[3] } else { os.args[0] }
				args := if os.args.len > 4 { os.args[4..] } else { []string{} }
				exit(run_script(os.args[2], arg0, args))
			}
			'--builtin-stage' {
				if os.args.len < 4 || !pipeline_builtin(os.args[3]) { exit(2) }
				mut loaded := []plugins.Plugin{}
				mut vars := utils.Variables{
					arg0:   os.args[0]
					status: os.args[2].int()
				}
				exit(dispatch_cmd(os.args[3], os.args[4..], mut loaded, '', mut vars))
			}
			else {
				content := os.read_file(os.args[1]) or {
					eprintln('vlsh: ${err.msg()}')
					exit(1)
				}
				exit(run_script(content, os.args[1], os.args[2..]))
			}
		}
	}
	if os.is_atty(0) == 0 {
		exit(run_script(os.get_raw_lines_joined(), os.args[0], []))
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
	mut vars := utils.Variables{
		arg0: os.args[0]
	}
	source_rc(mut loaded_plugins, mut vars)
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
			expanded = utils.expand_history_notation(trimmed, last_executed_command,
				history_entries) or {
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
		exit_code := evaluate(expanded, mut loaded_plugins, mut vars)
		plugins.run_post_hooks(loaded_plugins, trimmed, exit_code)
		if expanded.len > 0 {
			last_executed_command = expanded
		}
	}
}

fn run_script(content string, arg0 string, args []string) int {
	mut loaded := []plugins.Plugin{}
	mut vars := utils.Variables{
		arg0: arg0
		args: args
	}
	return evaluate(content, mut loaded, mut vars)
}

// Apply startup exports and unsets without executing the config's directives.
fn source_rc(mut loaded_plugins []plugins.Plugin, mut vars utils.Variables) {
	lines := os.read_lines(cfg.config_file) or { return }
	for line in lines {
		t := line.trim_space()
		if t.starts_with('export ') || t.starts_with('unset ') {
			evaluate(t, mut loaded_plugins, mut vars)
		}
	}
}

fn dispatch_cmd(cmd string, args []string, mut loaded_plugins []plugins.Plugin, full_cmdline string, mut vars utils.Variables) int {
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
		':' {}
		'echo' {
			output := args.join(' ') + '\n'
			print(output)
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
			code := if args.len > 0 { args[0].int() } else { vars.status }
			exit(code)
		}
		'export' {
			if args.len == 0 || args == ['-p'] {
				env := os.environ()
				mut keys := env.keys()
				keys.sort()
				for k in keys {
					if args.len == 0 {
						println('${k}=${env[k]}')
					} else if utils.valid_name(k) {
						quoted := env[k].replace("'", "'\\''")
						println("export ${k}='${quoted}'")
					}
				}
			} else {
				mut code := 0
				for arg in args {
					eq := arg.index_u8(`=`)
					name := if eq < 0 { arg } else { arg[..eq] }
					if !utils.valid_name(name) {
						utils.fail('export: invalid name: ${name}')
						code = 1
					} else if eq < 0 {
						vars.mark_export(name)
					} else {
						vars.export(name, arg[eq + 1..])
					}
				}
				return code
			}
		}
		'unset' {
			names := if args.len > 0 && args[0] == '-v' { args[1..] } else { args }
			for arg in names {
				vars.unset(arg)
			}
		}
		'set' {
			if args.len == 0 || args[0] != '--' {
				utils.fail('set: only set -- [args...] is supported')
				return 2
			}
			vars.args = args[1..].clone()
		}
		'shift' {
			if args.len > 1 {
				utils.fail('shift: expected at most one count')
				return 1
			}
			mut count := 1
			if args.len == 1 {
				// V 0.5.2 hoists collection expressions out of boolean guards.
				// Read the argument only after checking that it exists.
				raw := args[0]
				if raw.len == 0 || !raw.bytes().all(it.is_digit()) {
					utils.fail('shift: invalid count')
					return 1
				}
				count = strconv.atoi(raw) or {
					utils.fail('shift: invalid count')
					return 1
				}
			}
			if !vars.shift(count) {
				utils.fail('shift: invalid count or too few positional parameters')
				return 1
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
			return evaluate_list(content, mut loaded_plugins, mut vars)
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
					return run_external([
						exec.Cmd_object{ cmd: cmd, args: args, search_path: vars.get('PATH') },
					], full_cmdline, loaded_plugins)
				}
				utils.fail(err.msg())
				return 1
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
			return 127
		}
	}

	return 0
}
