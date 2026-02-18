module cmds

import os
import term
import math

pub fn ls(args []string) ! {
	// If any flags are passed, bail out and let the caller fall through to
	// the system ls so we don't have to reimplement every option.
	for arg in args {
		if arg.starts_with('-') {
			return error('__fallthrough__')
		}
	}

	mut target := '.'
	if args.len > 0 {
		target = args[0]
	}

	entries := os.ls(target) or {
		return error("ls: cannot access '${target}': ${err.msg()}")
	}

	mut dirs := []string{}
	mut files := []string{}

	for entry in entries {
		path := if target == '.' { entry } else { target + '/' + entry }
		if os.is_dir(path) {
			dirs << entry + '/'
		} else {
			files << entry
		}
	}

	dirs.sort()
	files.sort()

	mut items := []string{}
	items << dirs
	items << files

	if items.len == 0 {
		return
	}

	// Column layout based on terminal width
	term_width, _ := term.get_terminal_size()
	mut max_len := 0
	for item in items {
		if item.len > max_len {
			max_len = item.len
		}
	}
	col_width := max_len + 2
	cols := if col_width >= term_width { 1 } else { term_width / col_width }
	rows := int(math.ceil(f64(items.len) / f64(cols)))

	for row in 0 .. rows {
		for col in 0 .. cols {
			idx := col * rows + row
			if idx >= items.len {
				break
			}
			item := items[idx]
			// Color: dirs bold bright-blue, files plain
			colored := if item.ends_with('/') {
				term.bold(term.bright_blue(item))
			} else {
				item
			}
			// Determine whether this is the last entry on the row
			is_last := col == cols - 1 || (col + 1) * rows + row >= items.len
			if is_last {
				println(colored)
			} else {
				print(colored + ' '.repeat(col_width - item.len))
			}
		}
	}
}
