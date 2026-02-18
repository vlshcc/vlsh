// Example vlsh plugin — copy this file to ~/.vlsh/plugins/ and rename it.
//
// vlsh will compile it automatically on the next start (requires `v` in PATH).
//
// PROTOCOL
// --------
// vlsh calls your plugin binary with one of these first arguments:
//
//   capabilities          — print what this plugin provides (one item per line):
//                             command <name>   registers a new shell command
//                             prompt           contributes a line above the prompt
//                             pre_hook         called before every command
//                             post_hook        called after every command
//
//   run <command> [args]  — run a registered command
//   prompt                — print a single line shown above the '- ' prompt
//   pre_hook  <cmdline>   — notification before a command runs
//   post_hook <cmdline> <exit_code>   — notification after a command finishes

module main

import os

fn main() {
	op := if os.args.len > 1 { os.args[1] } else { '' }

	match op {
		'capabilities' {
			println('command hello')
			println('prompt')
			println('pre_hook')
			println('post_hook')
		}
		'run' {
			cmd := if os.args.len > 2 { os.args[2] } else { '' }
			match cmd {
				'hello' {
					name := if os.args.len > 3 { os.args[3] } else { 'world' }
					println('Hello, ${name}!')
				}
				else {}
			}
		}
		'prompt' {
			// Return a single line that appears above the '- ' prompt.
			// Leave this empty (or remove 'prompt' from capabilities) if not needed.
			println('[ example plugin ]')
		}
		'pre_hook' {
			cmdline := if os.args.len > 2 { os.args[2] } else { '' }
			// Called before every command. cmdline is the full input string.
			// Uncomment to log commands:
			// os.append_file('/tmp/vlsh_history.log', '${cmdline}\n') or {}
			_ = cmdline
		}
		'post_hook' {
			cmdline   := if os.args.len > 2 { os.args[2] } else { '' }
			exit_code := if os.args.len > 3 { os.args[3].int() } else { 0 }
			// Called after every command completes.
			_ = cmdline
			_ = exit_code
		}
		else {}
	}
}
