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
	println('https://vlsh.cc')
	println('')
	entries := [
		HelpEntry{':', 'Do nothing and return success (after expansion and redirection).'},
		HelpEntry{'aliases', 'Manage aliases (list / add <name>=<cmd> / remove <name>).'},
		HelpEntry{'cd', 'Change directory; ~ and ~/path are expanded to \$HOME.'},
		HelpEntry{'echo', 'Print arguments.'},
		HelpEntry{'exit', 'Exit the shell.'},
		HelpEntry{'export', 'Export shell variables to child commands, optionally assigning values.'},
		HelpEntry{'help', 'Displays this message. Use "help <cmd>" for details.'},
		HelpEntry{'ls', 'List directory contents (built-in colorised view).'},
		HelpEntry{'mux', 'Enter multiplexer mode (split panes, Ctrl+V prefix).'},
		HelpEntry{'ocp', 'Copy, overriding an existing destination file.'},
		HelpEntry{'plugins', 'Manage plugins (list / enable / disable / install / delete / reinstall / remote).'},
		HelpEntry{'set', 'Replace positional parameters with set -- [args...].'},
		HelpEntry{'shift', 'Remove positional parameters: shift [N] (default 1).'},
		HelpEntry{'source', 'Execute commands from a file in the current session.'},
		HelpEntry{'style', 'Manage prompt colors (list / set <key> <r> <g> <b>).'},
		HelpEntry{'unset', 'Remove shell variables and their export attributes.'},
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
	println('  \$VAR  \$\$  \$0  \$1  \$#  \"\$@\"  \$?  \${name}  \${#name}  \${var:-word}  \${var:=word}')
	println('  \${var:+word}  \${var:?word}  \${var#pat}  \${var##pat}  \${var%pat}  \${var%%pat}')
	println('  (nested \${...} is supported; # / % patterns use * and ? in glob rules;')
	println('  no [] in patterns yet).')
	println('${term.bold('Word splitting')} — Unquoted expansions split on \$IFS (default space,')
	println('  tab, newline when unset; empty IFS disables splitting). Custom IFS can yield empty')
	println('  fields between delimiters.')
	println('${term.bold('Variables')} — NAME=value stays local until export NAME.')
	println('  External-command prefixes are scoped; special-builtin prefixes persist.')
	println('${term.bold('Redirections')} — <, >, >>, 2>file, 2>&1 and descriptor closing')
	println('  apply from left to right to builtins and external commands (descriptors 0-9).')
	println('${term.bold('Scripts')} — Multiline pipelines, conditional lists, quoted words,')
	println('  backslash continuations, and comments at unquoted token boundaries are supported.')
	println('  Missing commands return 127; commands found but not executable return 126.')
	println('  Use help syntax for examples and remaining grammar limitations.')
	println('${term.bold('History expansion')} — Before parsing: `!!`, `!\$`, `!n`,')
	println('  `!-n`, `!prefix` (newest line starting with prefix), `!?sub` (newest')
	println('  line containing sub; optional `?` closes sub). See README. Bash-style;')
	println('  not POSIX.')
	println('  Full POSIX shell is not implemented; see README (POSIX compatibility)')
	println('  and docs/posix-inventory.md for scope and gaps.')
	println('')
}

fn help_sub(cmd string) {
	match cmd {
		':' {
			println(': - Do nothing and return success')
			println('')
			println('  : [args...]   Expand arguments and apply redirections, then return 0.')
		}
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
			println('  \$0          Script filename, -c name, or shell name.')
			println('  \$1, \${10}   Positional parameters; \$# is their count.')
			println('  \"\$@\"        One field per positional argument, preserving empty values.')
			println('  \$VAR        Expands to the value of shell variable VAR.')
			println('  \${name}     Value of name; \${#name} is the string length.')
			println('  \${var:-w}   Default w if var is unset or empty.')
			println('  \${var:=w}   Same, and assigns w to var when unset or empty.')
			println('  \${var:+w}   w if var is set and non-empty; otherwise empty.')
			println('  \${var:?w}   Report an error and stop this input if unset or empty.')
			println('  Without the colon, default operators test for unset values only.')
			println('  \${var#p}    Remove shortest prefix matching glob p; \${var##p} longest.')
			println('  \${var%p}    Remove shortest suffix matching glob p; \${var%%p} longest.')
			println('  Patterns use * and ? only ([] character classes not implemented yet).')
		}
		'exit' {
			println('${term.bold('exit')} - Exit the shell')
			println('')
			println('  ${term.bold('exit')} [N]   Quit with status N, or the last command status when omitted.')
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
			println('${term.bold('export')} - Export shell variables to child commands')
			println('')
			println('  ${term.bold('export')}                   List all environment variables.')
			println('  ${term.bold('export')} KEY=VALUE         Set an environment variable.')
			println('  ${term.bold('export')} KEY=VALUE K2=V2   Set multiple variables at once.')
			println('  ${term.bold('export')} KEY               Mark a shell variable for export.')
			println('  ${term.bold('export')} -p                List exported values as shell commands.')
			println('')
			println('NAME=value creates a shell-local variable; export NAME makes it available')
			println('to child commands. Reassigning an exported variable keeps it exported.')
			println('Use export in ~/.vlshrc to set PATH:')
			println('')
			println('  export PATH="/opt/bin:\$PATH"')
		}
		'unset' {
			println('${term.bold('unset')} - Remove shell variables and export attributes')
			println('')
			println('  ${term.bold('unset')} KEY [KEY...]   Unset one or more shell variables, whether local or exported.')
		}
		'source', '.' {
			println('${term.bold('source')} - Execute commands from a file')
			println('')
			println('  ${term.bold('source')} <file>   Parse and execute a script in the current shell.')
			println('  ${term.bold('.')} <file>        Same as source.')
			println('')
			println('Multiline pipelines, conditional lists, and quoted words are supported.')
			println('An unquoted # at the start of a token begins a comment.')
			println('Returns the exit code of the last executed command.')
		}
		'set' {
			println('${term.bold('set')} - Replace positional parameters')
			println('')
			println('  set -- [args...]   Set \$1, \$2, ...; \$# becomes the argument count.')
			println('  set --             Clear positional parameters.')
			println('Only set -- is supported; shell options such as set -e are not implemented.')
		}
		'shift' {
			println('${term.bold('shift')} - Remove positional parameters')
			println('')
			println('  shift [N]   Remove the first N parameters (default 1).')
			println('Returns nonzero for an invalid count or too few parameters.')
		}
		'syntax' {
			println('Shell syntax - documented POSIX subset')
			println('')
			println('  echo hello # comment')
			println('  printf hello | sed s/hello/world/')
			println('  command && echo success || echo failure')
			println('  command > log 2>&1    Send both streams to log.')
			println('  command 2>&1 > log    Keep stderr on the original stdout.')
			println('  NAME=value           Keep a variable local to the shell.')
			println('  export NAME          Make it available to child commands.')
			println('  set -- "one two" ""; printf "<%s>\\n" "\$@"')
			println('')
			println('Unquoted expansions split on IFS, then undergo pathname expansion.')
			println('Quoting preserves empty arguments; empty IFS disables field splitting.')
			println('Assignments and redirection filenames stay single values.')
			println('Pipelines, &&/|| lists, quoted words, and backslash continuations can span lines.')
			println('Command substitution, arithmetic expansion, loops, functions, subshells,')
			println('here-documents, and background jobs remain unsupported.')
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

fn expand_cd_path(s string) string {
	if s == '~' {
		return os.home_dir()
	}
	if s.starts_with('~/') {
		return os.home_dir() + s[1..]
	}
	return s
}

pub fn cd(args []string) ! {
	current := os.getwd()
	mut target := os.home_dir()
	if args.len > 0 {
		if args[0] == '-' {
			if args.len > 1 {
				return error('cd: too many arguments')
			}
			oldpwd := os.getenv('OLDPWD')
			if oldpwd == '' {
				return error('cd: OLDPWD not set')
			}
			target = oldpwd
			println(target)
		} else if args.len > 1 {
			// Unquoted paths typed as multiple words (e.g. "cd .moonchild productions/")
			// join to one directory path when it exists.
			joined := args.join(' ')
			target = expand_cd_path(joined)
			if os.is_file(target) {
				return error('${target}: not a directory')
			}
		} else {
			target = expand_cd_path(args[0])
		}
	}
	if os.is_file(target) {
		return error('${target}: not a directory')
	}
	os.chdir(target) or { return error('could not change directory to ${target}: ${err}') }
	os.setenv('OLDPWD', current, true)
	os.setenv('PWD', os.getwd(), true)
}
