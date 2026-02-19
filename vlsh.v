module main

import os
import term
import readline { Readline }

import cfg
import cmds
import exec
import mux
import plugins
import utils

const version = '0.1.4'

struct Prompt {
	mut:
	git_branch string
	git_commit string
	git_prompt string
	git_repo   string
}

fn pre_prompt() string {

	mut prompt := Prompt{}

	style := cfg.style() or {
		utils.fail(err.msg())

		exit(1)
	}

	mut current_dir := term.colorize(term.bold, '$os.getwd() ')
	current_dir = current_dir.replace('$os.home_dir()', '~')

	// Verify and/or update git prompt
	prompt.update_git_info() or {
		utils.fail(err.msg())
	}

	if prompt.git_prompt != '' {
		prompt.git_prompt = term.bg_rgb(
			style['style_git_bg'][0],
			style['style_git_bg'][1],
			style['style_git_bg'][2],
			term.rgb(
				style['style_git_fg'][0],
				style['style_git_fg'][1],
				style['style_git_fg'][2],
				prompt.git_prompt
			)
		)
		return '$prompt.git_prompt\n$current_dir'
	}

	return '$current_dir'
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

fn main() {

	if !os.exists(cfg.config_file) {
		cfg.create_default_config_file() or { panic(err.msg()) }
	}

	term.clear()
	mut loaded_plugins := plugins.load()
	mut r := Readline{}
	r.completion_callback = tab_complete
	for {
		println(pre_prompt())
		seg := plugins.prompt_segments(loaded_plugins)
		if seg != '' {
			println(seg)
		}
		cmd := r.read_line(term.rgb(255, 112, 112, '- ')) or {
			utils.fail(err.msg())
			return
		}
		trimmed := cmd.str().trim_space()
		plugins.run_pre_hooks(loaded_plugins, trimmed)
		main_loop(trimmed, mut loaded_plugins)
		plugins.run_post_hooks(loaded_plugins, trimmed, 0)
	}
}

fn main_loop(input string, mut loaded_plugins []plugins.Plugin) {

	input_split := utils.parse_args(input)
	if input_split.len == 0 {
		return
	}
	cmd := input_split[0]
	mut args := []string{}
	if input_split.len > 1 {
		args << input_split[1..]
	}

	match cmd {
		'aliases' {
			subcmd := if args.len > 0 { args[0] } else { 'list' }
			match subcmd {
				'list' {
					aliases := cfg.aliases() or {
						utils.fail(err.msg())
						return
					}
					for alias_name, alias_cmd in aliases {
						print('${term.bold(alias_name)} : ${term.italic(alias_cmd)}\n')
					}
				}
				'add' {
					if args.len < 2 {
						utils.fail('usage: aliases add <name>=<cmd>')
						return
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
							return
						}
						alias_cmd = args[2..].join(' ')
					}
					if name == '' || alias_cmd == '' {
						utils.fail('alias name and command cannot be empty')
						return
					}
					cfg.add_alias(name, alias_cmd) or {
						utils.fail(err.msg())
						return
					}
					println('alias ${name} added')
				}
				'remove' {
					if args.len < 2 {
						utils.fail('usage: aliases remove <name>')
						return
					}
					cfg.remove_alias(args[1]) or {
						utils.fail(err.msg())
						return
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
						return
					}
					for key, rgb in current_style {
						println('${term.bold(key)}: ${rgb[0]}, ${rgb[1]}, ${rgb[2]}')
					}
				}
				'set' {
					if args.len < 5 {
						utils.fail('usage: style set <key> <r> <g> <b>')
						return
					}
					cfg.set_style(args[1], args[2].int(), args[3].int(), args[4].int()) or {
						utils.fail(err.msg())
						return
					}
					println('style ${args[1]} set to ${args[2]}, ${args[3]}, ${args[4]}')
				}
				else {
					utils.fail('style: unknown subcommand "${subcmd}" (available: list, set)')
				}
			}
		}
		'echo' {
			mut parts := []string{}
			for arg in args {
				if arg == '$0' {
					parts << 'vlsh'
				} else if arg.starts_with('$') {
					parts << os.getenv(arg[1..])
				} else {
					parts << arg
				}
			}
			println(parts.join(' '))
		}
		'cd'      {
			cmds.cd(args) or {
				utils.fail(err.msg())

				return
			}
		}
		'ocp'     { cmds.ocp(args) or { utils.fail(err.msg()) } }
		'exit'    { exit(0) }
		'help'    { cmds.help(version, args) }
		'version' { println('version $version') }
		'share'   {
			link := cmds.share(args) or {
				utils.fail(err.msg())

				return
			}
			println(link)
		}
		'ls' {
			cmds.ls(args) or {
				if err.msg() == '__fallthrough__' {
					// flags were passed — let the system ls handle it
					local_cfg := cfg.get() or {
						utils.fail(err.msg())
						return
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
						return
					}
					for p in current_paths {
						println(p)
					}
				}
				'add' {
					if args.len < 2 {
						utils.fail('usage: path add <dir>')
						return
					}
					dir := args[1]
					if !os.exists(dir) {
						utils.fail('directory does not exist: ${dir}')
						return
					}
					cfg.add_path(dir) or {
						utils.fail(err.msg())
						return
					}
					println('added ${dir} to PATH')
				}
				'remove' {
					if args.len < 2 {
						utils.fail('usage: path remove <dir>')
						return
					}
					cfg.remove_path(args[1]) or {
						utils.fail(err.msg())
						return
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
				return
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
						return
					}
					name := args[1]
					plugins.enable(name) or {
						utils.fail(err.msg())
						return
					}
					loaded_plugins = plugins.load()
					println('${name} enabled')
				}
				'disable' {
					if args.len < 2 {
						utils.fail('usage: plugins disable <name>')
						return
					}
					name := args[1]
					plugins.disable(name) or {
						utils.fail(err.msg())
						return
					}
					loaded_plugins = loaded_plugins.filter(it.name != name)
					println('${name} disabled')
				}
				else {
					utils.fail('plugins: unknown subcommand "${subcmd}" (available: list, reload, enable, disable)')
				}
			}
		}
		else {
			if plugins.dispatch(loaded_plugins, cmd, args) {
				return
			}
			local_cfg := cfg.get() or {
				utils.fail(err.msg())

				return
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
			}
		}
	}
}

fn (mut s Prompt) update_git_info() ! {

	// if we're still in the same git-root, don't update
	if	s.git_repo != '' && os.getwd().contains(s.git_repo) { return }

	git_folder := [os.getwd(), '.git'].join('/')
	if !os.exists(git_folder) {
		s.fully_reset()

		return
	}

	if s.git_repo == '' || !os.getwd().contains(s.git_repo) {
		// assume we're in a new but valid git repo
		s.git_repo = os.getwd()
	}

	head_file := [git_folder, 'HEAD'].join('/').trim_space()
	if !os.exists(head_file) {
		s.fully_reset()

		return
	}

	head_file_content := os.read_file(head_file) or { return err }
	head_file_content_slice := head_file_content.trim_space().split('/')

	// assume, for now, that the last word in the HEAD -file is the branch
	s.git_branch = head_file_content_slice[head_file_content_slice.len - 1]
	s.git_prompt = '$s.git_branch'

	commit_file := [git_folder, 'refs', 'heads', s.git_branch]
		.join('/')
		.trim_space()
	commit_file_content := os.read_file(commit_file) or { return err }
	s.git_commit = commit_file_content.trim_space()[0..7]
	s.git_prompt = '$s.git_prompt $s.git_commit'
}

fn (mut p Prompt) fully_reset() {
	p.git_branch = ''
	p.git_commit = ''
	p.git_prompt = ''
	p.git_repo   = ''
}
