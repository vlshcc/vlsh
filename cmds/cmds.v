module cmds

import os
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
	println('Copyright (c) 2021-2026 David Satime Wallin <david@snogerup.com>')
	println('https://vlsh.ti-l.de')
	println('')
	entries := [
		HelpEntry{'aliases', 'Manage aliases (list / add <name>=<cmd> / remove <name>).'},
		HelpEntry{'cd', 'Change directory; ~ and ~/path are expanded to \$HOME.'},
		HelpEntry{'echo', 'Print arguments (parameter expansion; same as other commands); > / >>.'},
		HelpEntry{'exit', 'Exit the shell.'},
		HelpEntry{'export', 'Set environment variables (export KEY=VALUE).'},
		HelpEntry{'help', 'Displays this message. Use "help <cmd>" for details.'},
		HelpEntry{'ls', 'List directory contents (built-in colorised view).'},
		HelpEntry{'mux', 'Enter multiplexer mode (split panes, Ctrl+V prefix).'},
		HelpEntry{'ocp', 'Copy, overriding an existing destination file.'},
		HelpEntry{'plugins', 'Manage plugins (list / enable / disable / install / delete / reinstall / remote).'},
		HelpEntry{'source', 'Execute commands from a file in the current session.'},
		HelpEntry{'style', 'Manage prompt colors (list / set <key> <r> <g> <b>).'},
		HelpEntry{'unset', 'Remove environment variables (unset KEY [KEY...]).'},
		HelpEntry{'version', 'Print the vlsh version.'},
	]
	for e in entries {
		println('  ${term.bold(e.cmd):-20}  ${e.desc}')
	}
	println('')
	println('${term.bold('Line editing')} — Tab completes files and directories; the first')
	println('word also completes command names from \$PATH. After ${term.bold('cd')} with a')
	println('space, only directory names are suggested. Plugins may add more completions.')
	println('')
	println('${term.bold('Parameter expansion')} — In unquoted (or double-quoted) words:')
	println('  \$VAR  \$\$  \$0  \$?  \${name}  \${#name}  \${var:-word}  \${var:=word}')
	println('  \${var:+word}  \${var:?word}  \${var#pat}  \${var##pat}  \${var%pat}  \${var%%pat}')
	println('  (nested \${...} is supported; # / % patterns use * and ? in glob rules;')
	println('  no [] in patterns yet).')
	println('${term.bold('Word splitting')} — Unquoted words are split on \$IFS (default space,')
	println('  tab, newline when IFS is unset). Custom non-whitespace IFS can yield empty')
	println('  fields between delimiters.')
	println('${term.bold('History expansion')} — Before parsing: `!!`, `!$`, `!n`,')
	println('  `!-n`, `!prefix` (newest line starting with prefix), `!?sub` (newest')
	println('  line containing sub; optional `?` closes sub). See README. Bash-style;')
	println('  not POSIX.')
	println('  Full POSIX shell is not implemented; see README (POSIX compatibility)')
	println('  and docs/posix-inventory.md for scope and gaps.')
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
			println('')
			println('~ and ~/path are expanded to \$HOME.')
			println('Tab completion after cd and a space suggests only directories, not files.')
		}
		'echo' {
			println('${term.bold('echo')} - Print arguments')
			println('')
			println('  ${term.bold('echo')} [args...]              Print arguments separated by spaces.')
			println('  ${term.bold('echo')} [args...] > file       Write output to file (truncate).')
			println('  ${term.bold('echo')} [args...] >> file      Append output to file.')
			println('')
			println('Variable and parameter expansion (same rules as other commands):')
			println('  \$0          The shell name (vlsh).')
			println('  \$VAR        Expands to the value of environment variable VAR.')
			println('  \${name}     Value of name; \${#name} is the string length.')
			println('  \${var:-w}   Default w if var is unset or empty.')
			println('  \${var:=w}   Same, and assigns w to var when unset or empty.')
			println('  \${var:+w}   w if var is set and non-empty; otherwise empty.')
			println('  \${var:?w}   Error message to stderr if unset or empty (see README).')
			println('  \${var#p}    Remove shortest prefix matching glob p; \${var##p} longest.')
			println('  \${var%p}    Remove shortest suffix matching glob p; \${var%%p} longest.')
			println('  Patterns use * and ? only ([] character classes not implemented yet).')
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
			println('')
			println('The overview also summarizes tab completion, parameter expansion,')
			println('word splitting (IFS), history expansion (`!!`, `!$`, `!n`, `!-n`, `!prefix`, `!?`),')
			println('and points to README / docs/posix-inventory.md for POSIX subset details.')
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
		'export' {
			println('${term.bold('export')} - Set environment variables')
			println('')
			println('  ${term.bold('export')}                   List all environment variables.')
			println('  ${term.bold('export')} KEY=VALUE         Set an environment variable.')
			println('  ${term.bold('export')} KEY=VALUE K2=V2   Set multiple variables at once.')
			println('  ${term.bold('export')} KEY               No-op (variable already inherited).')
			println('')
			println('Variables set with export persist for the lifetime of the shell session')
			println('and are inherited by child processes. Use in ~/.vlshrc to set PATH:')
			println('')
			println('  export PATH="/opt/bin:\$PATH"')
		}
		'unset' {
			println('${term.bold('unset')} - Remove environment variables')
			println('')
			println('  ${term.bold('unset')} KEY [KEY...]   Unset one or more environment variables.')
		}
		'source', '.' {
			println('${term.bold('source')} - Execute commands from a file')
			println('')
			println('  ${term.bold('source')} <file>   Read file line-by-line and execute each line.')
			println('  ${term.bold('.')} <file>        Same as source.')
			println('')
			println('Lines starting with # are treated as comments and skipped.')
			println('Returns the exit code of the last executed line.')
		}
		'plugins' {
			println('${term.bold('plugins')} - Manage plugins')
			println('')
			println('  ${term.bold('plugins list')}                  List installed plugins with version and status.')
			println('  ${term.bold('plugins enable')} <name>         Enable a disabled plugin by name.')
			println('  ${term.bold('plugins enable all')}            Enable every plugin at once.')
			println('  ${term.bold('plugins disable')} <name>        Disable a plugin by name.')
			println('  ${term.bold('plugins disable all')}           Disable every plugin at once.')
			println('  ${term.bold('plugins reload')}                Recompile and reload all plugins.')
			println('  ${term.bold('plugins remote')}                List remote plugins; marks installed versions and available updates.')
			println('  ${term.bold('plugins search')} <query>        Search remote plugins by name or description.')
			println('  ${term.bold('plugins install')} <name>        Download and install the latest version of a plugin.')
			println('  ${term.bold('plugins update')} [name]         Update one or all installed plugins to their latest version.')
			println('  ${term.bold('plugins delete')} <name>         Delete an installed plugin.')
			println('  ${term.bold('plugins reinstall')} <name>       Remove a plugin locally and install the latest from remote.')
			println('')
			println('Plugin capabilities:')
			println('  command <name>   Register a new shell command.')
			println('  prompt           Contribute a line above the prompt.')
			println('  pre_hook         Called before every command (args: cmdline).')
			println('  post_hook        Called after every command (args: cmdline exit_code).')
			println('  output_hook      Called after every command with captured stdout')
			println('                   (args: cmdline exit_code output).')
			println('  completion       Provide tab completions (args: current input).')
			println('  mux_status       Contribute text to the mux status bar.')
			println('')
			println('Plugins are stored in versioned directories under ~/.vlsh/plugins/.')
			println('vlsh compiles them automatically on startup (requires v in PATH).')
			println('Plugins can provide commands, prompt decorations, pre/post hooks,')
			println('output capture (output_hook), and custom tab completions.')
			println('')
			println('Remote plugins are fetched from https://github.com/vlshcc/plugins.')
			println('Each plugin has a DESC metadata file with name, author, and description.')
			println('After "plugins install" run "plugins reload" to activate; "plugins reinstall"')
			println('removes the local copy, installs the latest from remote, and reloads plugins.')
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
			println('  Ctrl+V + |           Split current pane vertically (left/right)')
			println('  Ctrl+V + -           Split current pane horizontally (top/bottom)')
			println('  Ctrl+V + ←/→/↑/↓    Navigate to adjacent pane')
			println('  Ctrl+V + Ctrl+←/→    Resize pane horizontally')
			println('  Ctrl+V + Ctrl+↑/↓    Resize pane vertically')
			println('  Ctrl+V + o           Cycle focus to the next pane')
			println('  Ctrl+V + PageUp      Scroll active pane back into scrollback history')
			println('  Ctrl+V + PageDown    Scroll active pane forward toward live output')
			println('  Ctrl+V + q           Quit mux mode (only when all panes closed)')
			println('  Ctrl+V + Ctrl+V      Send literal Ctrl+V to active pane')
			println('  Mouse click          Click a pane to make it active')
			println('  Mouse wheel          Scroll active pane up/down through scrollback')
			println('')
			println('Each pane retains up to 1000 lines of scrollback history.')
			println('An orange indicator in the top-right corner shows scroll position.')
			println('Panes close automatically when their shell process exits.')
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
	current := os.getwd()
	mut target := os.home_dir()
	if args.len > 0 {
		if args[0] == '-' {
			oldpwd := os.getenv('OLDPWD')
			if oldpwd == '' {
				return error('cd: OLDPWD not set')
			}
			target = oldpwd
			println(target)
		} else if args[0] == '~' {
			target = os.home_dir()
		} else if args[0].starts_with('~/') {
			target = os.home_dir() + args[0][1..]
		} else {
			target = args[0]
		}
	}
	if os.is_file(target) {
		return error('${target}: not a directory')
	}
	os.chdir(target) or { return error('could not change directory to ${target}: ${err}') }
	os.setenv('OLDPWD', current, true)
	os.setenv('PWD', os.getwd(), true)
}
