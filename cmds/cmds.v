module cmds

import os
import net.http
import term

struct HelpEntry {
	cmd  string
	desc string
}

pub fn help(version string, args []string) {
	if args.len > 0 {
		help_sub(args[0])
		return
	}
	println('${term.bold('vlsh')} - V Lang SHell v${version}')
	println('---------------------------------------')
	println('Copyright (c) 2021 David Satime Wallin <david@dwall.in>')
	println('https://vlsh.ti-l.de')
	println('')
	entries := [
		HelpEntry{'aliases', 'Manage aliases (list / add <name>=<cmd> / remove <name>).'},
		HelpEntry{'cd',      'Change to provided directory.'},
		HelpEntry{'echo',    'Print arguments, expanding shell variables.'},
		HelpEntry{'exit',    'Exit the shell.'},
		HelpEntry{'help',    'Displays this message. Use "help <cmd>" for details.'},
		HelpEntry{'ls',      'List directory contents (built-in colorised view).'},
		HelpEntry{'mux',     'Enter multiplexer mode (split panes, Ctrl+A prefix).'},
		HelpEntry{'ocp',     'Copy, overriding an existing destination file.'},
		HelpEntry{'path',    'Manage PATH entries (list / add <dir> / remove <dir>).'},
		HelpEntry{'plugins', 'Manage plugins (list / enable / disable / reload).'},
		HelpEntry{'share',   'Upload a file to dpaste.com and print the link.'},
		HelpEntry{'style',   'Manage prompt colors (list / set <key> <r> <g> <b>).'},
		HelpEntry{'version', 'Print the vlsh version.'},
	]
	for e in entries {
		println('  ${term.bold(e.cmd):-20}  ${e.desc}')
	}
	println('')
}

fn help_sub(cmd string) {
	match cmd {
		'aliases' {
			println('${term.bold('aliases')} - Manage shell aliases')
			println('')
			println('  ${term.bold('aliases list')}                  List all defined aliases.')
			println('  ${term.bold('aliases add')} <name>=<cmd>      Add or update an alias.')
			println('  ${term.bold('aliases add')} <name> <cmd...>   Add or update an alias (space form).')
			println('  ${term.bold('aliases remove')} <name>         Remove an alias.')
			println('')
			println('Examples:')
			println('  aliases add ll=ls -la')
			println('  aliases add gs git status')
			println('  aliases remove ll')
		}
		'cd' {
			println('${term.bold('cd')} - Change directory')
			println('')
			println('  ${term.bold('cd')} [dir]   Change to dir, or to home directory if omitted.')
		}
		'echo' {
			println('${term.bold('echo')} - Print arguments')
			println('')
			println('  ${term.bold('echo')} [args...]   Print arguments separated by spaces.')
			println('')
			println('Variable expansion:')
			println('  \$0          The shell name (vlsh).')
			println('  \$VAR        Expands to the value of environment variable VAR.')
		}
		'exit' {
			println('${term.bold('exit')} - Exit the shell')
			println('')
			println('  ${term.bold('exit')}   Quit vlsh.')
		}
		'help' {
			println('${term.bold('help')} - Display help')
			println('')
			println('  ${term.bold('help')}          Show overview of all built-in commands.')
			println('  ${term.bold('help')} <cmd>    Show detailed help for a specific command.')
		}
		'ls' {
			println('${term.bold('ls')} - List directory contents')
			println('')
			println('  ${term.bold('ls')} [dir]   List files in dir (or current directory).')
			println('')
			println('The built-in ls shows colorised output. Flags are passed to the system ls.')
		}
		'ocp' {
			println('${term.bold('ocp')} - Overwriting copy')
			println('')
			println('  ${term.bold('ocp')} <src> <dst>   Copy src to dst, overriding if dst exists.')
		}
		'path' {
			println('${term.bold('path')} - Manage PATH entries')
			println('')
			println('  ${term.bold('path list')}           List all directories in PATH.')
			println('  ${term.bold('path add')} <dir>      Add dir to PATH.')
			println('  ${term.bold('path remove')} <dir>   Remove dir from PATH.')
		}
		'plugins' {
			println('${term.bold('plugins')} - Manage plugins')
			println('')
			println('  ${term.bold('plugins list')}             List available plugins.')
			println('  ${term.bold('plugins enable')} <name>    Enable a plugin.')
			println('  ${term.bold('plugins disable')} <name>   Disable a plugin.')
			println('  ${term.bold('plugins reload')}           Reload all plugins.')
		}
		'share' {
			println('${term.bold('share')} - Share a file via dpaste.com')
			println('')
			println('  ${term.bold('share')} <file>   Upload file and print the URL.')
		}
		'style' {
			println('${term.bold('style')} - Manage prompt colors')
			println('')
			println('  ${term.bold('style list')}                      List current color settings.')
			println('  ${term.bold('style set')} <key> <r> <g> <b>    Set a color by RGB values.')
		}
		'mux' {
			println('${term.bold('mux')} - Terminal multiplexer')
			println('')
			println('  ${term.bold('mux')}   Enter multiplexer mode with split pane support.')
			println('')
			println('Key bindings (prefix: Ctrl+V):')
			println('  Ctrl+V + |          Split current pane vertically (left/right)')
			println('  Ctrl+V + -          Split current pane horizontally (top/bottom)')
			println('  Ctrl+V + ←/→/↑/↓   Navigate to adjacent pane')
			println('  Ctrl+V + Ctrl+←/→   Resize pane horizontally')
			println('  Ctrl+V + Ctrl+↑/↓   Resize pane vertically')
			println('  Ctrl+V + x          Close current pane')
			println('  Ctrl+V + q          Quit mux mode (closes all panes)')
			println('  Ctrl+V + Ctrl+V     Send literal Ctrl+V to active pane')
		}
		'version' {
			println('${term.bold('version')} - Print version')
			println('')
			println('  ${term.bold('version')}   Print the current vlsh version string.')
		}
		else {
			println('help: no help entry for "${cmd}"')
		}
	}
}

pub fn cd(args []string) ! {
	mut target := os.home_dir()
	if args.len > 0 {
		target = args[0]
	}
	os.chdir(target) or {
		return error('could not change directory to ${target}: ${err.msg}')
	}
}

pub fn share(args []string) !string {
	if args.len != 1 {
		return error('usage: share <file>')
	}
	if !os.exists(args[0]) {
		return error('could not find ${args[0]}')
	}
	file_content := os.read_file(args[0]) or {
		return error('could not read ${args[0]}')
	}

	mut data := map[string]string
	host := 'https://dpaste.com/api/'
	data['content'] = file_content
	resp := http.post_form(host, data) or {
		return error('could not post file: ${err.msg}')
	}

	if resp.status_code == 200 || resp.status_code == 201 {
		return resp.bytestr()
	}
	return error('status_code: ${resp.status_code}')
}
