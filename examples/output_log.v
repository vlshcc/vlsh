// output_log — vlsh plugin that records every command and its captured output
// to a structured session log at ~/.vlsh/output.log.
//
// Install:
//   mkdir -p ~/.vlsh/plugins/output_log/v1.0.0
//   cp output_log.v ~/.vlsh/plugins/output_log/v1.0.0/output_log.v
// Then inside vlsh:
//   plugins reload
//
// Log format (one block per command):
//   --- 2026-02-20 14:32:01 | exit:0 | ls -la ---
//   total 48
//   drwxr-xr-x  8 user group ...
//   ---
//
// Commands with no captured output (interactive programs, direct-terminal
// commands not in a pipe chain) still get a header so the timeline is complete.
//
// Use "output_search <pattern>" to grep through the log from inside the shell.

module main

import os
import time

const log_file = os.home_dir() + '/.vlsh/output.log'

// timestamp returns the current local time as "YYYY-MM-DD HH:MM:SS".
fn timestamp() string {
	t := time.now()
	return '${t.year:04d}-${t.month:02d}-${t.day:02d} ${t.hour:02d}:${t.minute:02d}:${t.second:02d}'
}

// append_log writes text to the log file, creating it if necessary.
fn append_log(text string) {
	os.mkdir_all(os.dir(log_file)) or {}
	mut f := os.open_file(log_file, 'a') or { return }
	f.write_string(text) or {}
	f.close()
}

fn main() {
	op := if os.args.len > 1 { os.args[1] } else { '' }

	match op {
		'capabilities' {
			println('output_hook')
			println('command output_search')
			println('command output_log_clear')
		}

		// output_hook <cmdline> <exit_code> <output>
		// Record the command header and whatever output was captured.
		'output_hook' {
			cmdline   := if os.args.len > 2 { os.args[2] } else { '' }
			exit_code := if os.args.len > 3 { os.args[3] } else { '?' }
			output    := if os.args.len > 4 { os.args[4] } else { '' }

			// Skip internal shell noise (empty lines, plugin management).
			if cmdline == '' || cmdline.starts_with('plugins ') {
				return
			}

			mut entry := '--- ${timestamp()} | exit:${exit_code} | ${cmdline} ---\n'
			if output != '' {
				entry += output
				// Ensure the output ends with a newline before the closing marker.
				if !output.ends_with('\n') {
					entry += '\n'
				}
			}
			entry += '---\n\n'
			append_log(entry)
		}

		// output_search <pattern> — grep the log and print matching blocks.
		'run' {
			cmd := if os.args.len > 2 { os.args[2] } else { '' }
			match cmd {
				'output_search' {
					pattern := if os.args.len > 3 { os.args[3..].join(' ') } else { '' }
					if pattern == '' {
						eprintln('usage: output_search <pattern>')
						exit(1)
					}
					if !os.exists(log_file) {
						eprintln('output_log: no log file found at ${log_file}')
						exit(1)
					}
					content := os.read_file(log_file) or {
						eprintln('output_log: cannot read log: ${err}')
						exit(1)
					}
					// Print every block (separated by blank lines) that contains the pattern.
					blocks := content.split('\n\n')
					mut found := 0
					for block in blocks {
						if block.to_lower().contains(pattern.to_lower()) {
							println(block.trim_space())
							println('')
							found++
						}
					}
					if found == 0 {
						println('output_log: no entries matching "${pattern}"')
					}
				}
				'output_log_clear' {
					os.rm(log_file) or {}
					println('output_log: log cleared')
				}
				else {}
			}
		}

		else {}
	}
}
