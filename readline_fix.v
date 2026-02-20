// readline_fix.v — custom readline loop for vlsh that fixes Backspace at column 0.
//
// The standard vlib readline module's delete_character() is a no-op when the
// cursor is already at position 0.  This file reimplements the read loop using
// only the *public* Readline API (enable/disable_raw_mode, read_char and the
// pub-mut struct fields) so we can apply the fix without touching vlib.
module main

import encoding.utf8.east_asian
import readline { Readline }
import term
import os

fn C.raise(sig i32)
fn C.getppid() i32

// ── action enum ──────────────────────────────────────────────────────────────

enum VlshAction {
	eof
	nothing
	insert_character
	commit_line
	delete_left
	delete_right
	delete_word_left
	delete_line
	move_cursor_left
	move_cursor_right
	move_cursor_start
	move_cursor_end
	move_cursor_word_left
	move_cursor_word_right
	history_previous
	history_next
	overwrite
	clear_screen
	suspend
	completion
	history_search
	cancel_line // Ctrl+C — clear the current line and re-prompt
}

// ── terminal helpers ──────────────────────────────────────────────────────────

fn vlsh_get_screen_columns() int {
	w, _ := term.get_terminal_size()
	return if w <= 0 { 80 } else { w }
}

// vlsh_get_prompt_offset returns the number of bytes consumed by ANSI escape
// sequences in prompt (so we can subtract them from display_width).
fn vlsh_get_prompt_offset(prompt string) int {
	mut invisible := 0
	for i := 0; i < prompt.len; i++ {
		if prompt[i] == `\e` {
			for ; i < prompt.len && prompt[i] != `m`; i++ {
				invisible++
			}
			invisible++ // count the 'm'
		}
	}
	return invisible
}

fn vlsh_calculate_screen_position(x_in int, y_in int, screen_columns int, char_count int, inp []int) []int {
	mut out := inp.clone()
	mut x := x_in
	mut y := y_in
	out[0] = x
	out[1] = y
	for chars_remaining := char_count; chars_remaining > 0; {
		chars_this_row := if (x + chars_remaining) < screen_columns {
			chars_remaining
		} else {
			screen_columns - x
		}
		out[0] = x + chars_this_row
		out[1] = y
		chars_remaining -= chars_this_row
		x = 0
		y++
	}
	if out[0] == screen_columns {
		out[0] = 0
		out[1]++
	}
	return out
}

fn vlsh_shift_cursor(xpos int, yoffset int) {
	if yoffset != 0 {
		if yoffset > 0 {
			term.cursor_down(yoffset)
		} else {
			term.cursor_up(-yoffset)
		}
	}
	print('\x1b[${xpos + 1}G')
}

// vlsh_get_suggestion returns ghost-text for the current input.
//
// Strategy:
//  1. Search history (most-recent first) for an entry that starts with the
//     current input.  For 'cd' commands the target directory is validated; if
//     it no longer exists on disk that entry is skipped.
//  2. If no usable history entry is found, fall back to the completion
//     callback (the same engine that drives Tab), and use its first result as
//     the suggestion.
fn vlsh_get_suggestion(r Readline) []rune {
	if r.current.len == 0 {
		return []rune{}
	}
	prefix := r.current.string()
	cmd := prefix.trim_space().split(' ')[0]
	is_cd := cmd == 'cd'

	// ── 1. history ────────────────────────────────────────────────────────────
	for i := 1; i < r.previous_lines.len; i++ {
		entry := r.previous_lines[i].string()
		if !entry.starts_with(prefix) || entry.len <= prefix.len {
			continue
		}
		if is_cd {
			// Skip history entries whose target directory no longer exists.
			entry_parts := entry.trim_space().split(' ')
			if entry_parts.len < 2 || entry_parts[1].len == 0 {
				continue
			}
			path := entry_parts[1]
			expanded := if path.starts_with('~') {
				os.home_dir() + path[1..]
			} else {
				path
			}
			if !os.is_dir(expanded) {
				continue
			}
		}
		return r.previous_lines[i][r.current.len..].clone()
	}

	// ── 2. completion-based fallback ─────────────────────────────────────────
	if r.completion_callback != unsafe { nil } {
		opts := r.completion_callback(prefix)
		if opts.len > 0 {
			first := opts[0]
			if first.len > prefix.len {
				return first[prefix.len..].runes()
			}
		}
	}

	return []rune{}
}

fn vlsh_refresh_line(mut r Readline) {
	mut end_of_input := [0, 0]
	last_prompt_line := if r.prompt.contains('\n') {
		r.prompt.all_after_last('\n')
	} else {
		r.prompt
	}
	last_prompt_width := east_asian.display_width(last_prompt_line, 1) -
		vlsh_get_prompt_offset(last_prompt_line)
	current_width := east_asian.display_width(r.current.string(), 1)
	cursor_prefix_width := east_asian.display_width(r.current[..r.cursor].string(), 1)

	suggestion := vlsh_get_suggestion(r)

	end_of_input = vlsh_calculate_screen_position(last_prompt_width, 0, vlsh_get_screen_columns(),
		current_width, end_of_input)
	end_of_input[1] += r.current.filter(it == `\n`).len
	mut cursor_pos := [0, 0]
	cursor_pos = vlsh_calculate_screen_position(last_prompt_width, 0, vlsh_get_screen_columns(),
		cursor_prefix_width, cursor_pos)
	vlsh_shift_cursor(0, -r.cursor_row_offset)
	term.erase_toend()
	print(last_prompt_line)
	print(r.current.string())
	if suggestion.len > 0 {
		print('\x1b[38;5;240m')
		print(suggestion.string())
		print('\x1b[0m')
	}
	if end_of_input[0] == 0 && end_of_input[1] > 0 {
		print('\n')
	}
	vlsh_shift_cursor(cursor_pos[0], -(end_of_input[1] - cursor_pos[1]))
	r.cursor_row_offset = cursor_pos[1]
}

// ── key analysis ──────────────────────────────────────────────────────────────

fn vlsh_analyse_escape(r Readline) VlshAction {
	c2 := r.read_char() or { return .nothing }
	if u8(c2) != `[` {
		return .nothing
	}
	c3 := r.read_char() or { return .nothing }
	match u8(c3) {
		`C` { return .move_cursor_right }
		`D` { return .move_cursor_left }
		`B` { return .history_next }
		`A` { return .history_previous }
		`H` { return .move_cursor_start }
		`F` { return .move_cursor_end }
		`P` { return .delete_right } // ESC[P — DCH (Delete Character); DEL key on some terminals
		`1` {
			// \x1b[1;5C / \x1b[1;5D — Ctrl+Right / Ctrl+Left
			_ = r.read_char() or { return .nothing } // ';'
			c5 := r.read_char() or { return .nothing }
			if u8(c5) == `5` {
				direction := r.read_char() or { return .nothing }
				return match u8(direction) {
					`C` { VlshAction.move_cursor_word_right }
					`D` { VlshAction.move_cursor_word_left }
					else { VlshAction.nothing }
				}
			}
			return .nothing
		}
		`2`, `3`, `4` {
			// \x1b[2~ (Insert) / \x1b[3~ (Delete) / \x1b[4~ (End)
			c4 := r.read_char() or { return .nothing }
			if u8(c4) == `~` {
				return match u8(c3) {
					`3` { VlshAction.delete_right }
					`2` { VlshAction.overwrite }
					`4` { VlshAction.move_cursor_end }
					else { VlshAction.nothing }
				}
			}
			return .nothing
		}
		else { return .nothing }
	}
}

fn vlsh_analyse(r Readline, c int) (VlshAction, int) {
	if c > 255 {
		return VlshAction.insert_character, c
	}
	match u8(c) {
		`\0`, 0x4, 255 { return VlshAction.eof, c }
		0x3            { return VlshAction.cancel_line, c } // Ctrl+C
		`\n`, `\r` { return VlshAction.commit_line, c }
		`\t` { return VlshAction.completion, c }
		`\f` { return VlshAction.clear_screen, c }
		`\b`, 127 { return VlshAction.delete_left, c }
		27 { return vlsh_analyse_escape(r), c }
		21 { return VlshAction.delete_line, c } // Ctrl+U
		23 { return VlshAction.delete_word_left, c } // Ctrl+W
		1 { return VlshAction.move_cursor_start, c } // Ctrl+A
		5 { return VlshAction.move_cursor_end, c } // Ctrl+E
		18 { return VlshAction.history_search, c } // Ctrl+R
		26 { return VlshAction.suspend, c } // Ctrl+Z
		else {
			if c >= ` ` {
				return VlshAction.insert_character, c
			}
			return VlshAction.nothing, c
		}
	}
}

// ── editing operations ────────────────────────────────────────────────────────

fn vlsh_completion_clear(mut r Readline) {
	r.last_prefix_completion.clear()
	r.last_completion_offset = 0
}

fn vlsh_eof(mut r Readline) bool {
	r.previous_lines.insert(1, r.current)
	r.cursor = r.current.len
	if r.is_tty {
		vlsh_refresh_line(mut r)
	}
	return true
}

fn vlsh_insert_character(mut r Readline, c int) {
	if !r.overwrite || r.cursor == r.current.len {
		r.current.insert(r.cursor, c)
	} else {
		r.current[r.cursor] = rune(c)
	}
	r.cursor++
	if r.is_tty {
		vlsh_refresh_line(mut r)
	}
}

// vlsh_delete_character handles the Backspace key (0x08).
fn vlsh_delete_character(mut r Readline) {
	if r.cursor <= 0 {
		return
	}
	r.cursor--
	r.current.delete(r.cursor)
	vlsh_refresh_line(mut r)
	vlsh_completion_clear(mut r)
}

fn vlsh_suppr_character(mut r Readline) {
	if r.cursor >= r.current.len {
		return
	}
	r.current.delete(r.cursor)
	vlsh_refresh_line(mut r)
	vlsh_completion_clear(mut r)
}

fn vlsh_delete_word_left(mut r Readline) {
	if r.cursor == 0 {
		return
	}
	orig_cursor := r.cursor
	if r.cursor >= r.current.len {
		r.cursor = r.current.len - 1
	}
	if r.current[r.cursor] != ` ` && r.current[r.cursor - 1] == ` ` {
		r.cursor--
	}
	if r.current[r.cursor] == ` ` {
		for r.cursor > 0 && r.current[r.cursor] == ` ` {
			r.cursor--
		}
		for r.cursor > 0 && r.current[r.cursor - 1] != ` ` {
			r.cursor--
		}
	} else {
		for r.cursor > 0 {
			if r.current[r.cursor - 1] == ` ` {
				break
			}
			r.cursor--
		}
	}
	r.current.delete_many(r.cursor, orig_cursor - r.cursor)
	vlsh_refresh_line(mut r)
	vlsh_completion_clear(mut r)
}

fn vlsh_delete_line(mut r Readline) {
	r.current = []
	r.cursor = 0
	vlsh_refresh_line(mut r)
	vlsh_completion_clear(mut r)
}

fn vlsh_commit_line(mut r Readline) bool {
	r.previous_lines.insert(1, r.current)
	r.cursor = r.current.len
	if r.is_tty {
		vlsh_refresh_line(mut r)
		print('\x1b[K')
		println('')
	}
	r.current << `\n`
	return true
}

fn vlsh_move_cursor_left(mut r Readline) {
	if r.cursor > 0 {
		r.cursor--
		vlsh_refresh_line(mut r)
	}
}

fn vlsh_move_cursor_right(mut r Readline) {
	if r.cursor < r.current.len {
		r.cursor++
		vlsh_refresh_line(mut r)
	} else {
		suggestion := vlsh_get_suggestion(r)
		if suggestion.len > 0 {
			r.current << suggestion
			r.cursor = r.current.len
			vlsh_refresh_line(mut r)
		}
	}
}

fn vlsh_move_cursor_start(mut r Readline) {
	r.cursor = 0
	vlsh_refresh_line(mut r)
}

fn vlsh_move_cursor_end(mut r Readline) {
	if r.cursor == r.current.len {
		suggestion := vlsh_get_suggestion(r)
		if suggestion.len > 0 {
			r.current << suggestion
			r.cursor = r.current.len
			vlsh_refresh_line(mut r)
			return
		}
	}
	r.cursor = r.current.len
	vlsh_refresh_line(mut r)
}

fn vlsh_is_break_character(c string) bool {
	break_characters := ' \t\v\f\a\b\r\n`~!@#\$%^&*()-=+[{]}\\|;:\'",<.>/?'
	return break_characters.contains(c)
}

fn vlsh_move_cursor_word_left(mut r Readline) {
	if r.cursor > 0 {
		for r.cursor > 0 && vlsh_is_break_character(r.current[r.cursor - 1].str()) {
			r.cursor--
		}
		for r.cursor > 0 && !vlsh_is_break_character(r.current[r.cursor - 1].str()) {
			r.cursor--
		}
		vlsh_refresh_line(mut r)
	}
}

fn vlsh_move_cursor_word_right(mut r Readline) {
	if r.cursor < r.current.len {
		for r.cursor < r.current.len && vlsh_is_break_character(r.current[r.cursor].str()) {
			r.cursor++
		}
		for r.cursor < r.current.len && !vlsh_is_break_character(r.current[r.cursor].str()) {
			r.cursor++
		}
		vlsh_refresh_line(mut r)
	}
}

fn vlsh_history_previous(mut r Readline) {
	if r.search_index + 2 >= r.previous_lines.len {
		return
	}
	if r.search_index == 0 {
		r.previous_lines[0] = r.current
	}
	r.search_index++
	prev_line := r.previous_lines[r.search_index]
	if r.skip_empty && prev_line == [] {
		vlsh_history_previous(mut r)
	} else {
		r.current = prev_line
		r.cursor = r.current.len
		vlsh_refresh_line(mut r)
	}
}

fn vlsh_history_next(mut r Readline) {
	if r.search_index <= 0 {
		return
	}
	r.search_index--
	r.current = r.previous_lines[r.search_index]
	r.cursor = r.current.len
	vlsh_refresh_line(mut r)
}

fn vlsh_switch_overwrite(mut r Readline) {
	r.overwrite = !r.overwrite
}

fn vlsh_cancel_line(mut r Readline) bool {
	// Print visual feedback then signal cancellation via a sentinel rune.
	// The sentinel (rune 3, i.e. the Ctrl+C character) is detected in
	// vlsh_read_line to return error('cancelled') so main() can re-prompt.
	print('^C\r\n')
	r.current = [rune(3)]
	r.cursor = 0
	return true
}

fn vlsh_clear_screen(mut r Readline) {
	term.set_cursor_position(x: 1, y: 1)
	term.erase_clear()
	vlsh_refresh_line(mut r)
}

fn vlsh_suspend(mut r Readline) {
	r.disable_raw_mode()
	is_standalone := os.getenv('VCHILD') != 'true'
	if !is_standalone {
		unsafe {
			ppid := C.getppid()
			C.kill(ppid, C.SIGSTOP)
		}
	}
	unsafe { C.raise(C.SIGSTOP) }
	r.enable_raw_mode()
	vlsh_refresh_line(mut r)
}

fn vlsh_completion(mut r Readline) {
	if r.completion_list.len == 0 && r.completion_callback == unsafe { nil } {
		return
	}
	// If the current input ends with '/' and we have a saved prefix from a
	// previous cycling session, the user wants to explore inside the selected
	// directory rather than continue cycling the old level.  Reset so that
	// this tab press starts fresh from the current path.
	if r.last_prefix_completion.len > 0 && r.current.len > 0 && r.current.last() == `/` {
		vlsh_completion_clear(mut r)
	}
	prefix := if r.last_prefix_completion.len > 0 { r.last_prefix_completion } else { r.current }
	if prefix.len == 0 {
		return
	}
	opts := if r.completion_list.len > 0 {
		sprefix := prefix.string()
		r.completion_list.filter(it.starts_with(sprefix))
	} else if r.completion_callback != unsafe { nil } {
		r.completion_callback(prefix.string())
	} else {
		[]string{}
	}
	if opts.len == 0 {
		vlsh_completion_clear(mut r)
		return
	}
	if r.last_prefix_completion.len != 0 {
		if opts.len > r.last_completion_offset + 1 {
			r.last_completion_offset += 1
		} else {
			r.last_completion_offset = 0
		}
	} else {
		r.last_prefix_completion = r.current
	}
	r.current = opts[r.last_completion_offset].runes()
	r.cursor = r.current.len
	vlsh_refresh_line(mut r)
}

// ── history search (Ctrl+R) ───────────────────────────────────────────────────

fn vlsh_do_search(mut r Readline) {
	query := r.search_query.string()
	if query.len > 0 {
		mut match_count := 0
		for i := 1; i < r.previous_lines.len; i++ {
			if r.previous_lines[i].len == 0 {
				continue
			}
			if r.previous_lines[i].string().contains(query) {
				if match_count == r.search_match_index {
					r.current = r.previous_lines[i].clone()
					r.cursor = r.current.len
					r.prompt = "(reverse-i-search)'${query}': "
					r.prompt_offset = 0
					vlsh_refresh_line(mut r)
					return
				}
				match_count++
			}
		}
		if match_count > 0 {
			r.search_match_index = match_count - 1
			vlsh_do_search(mut r)
			return
		}
	}
	r.current = []rune{}
	r.cursor = 0
	r.prompt = "(reverse-i-search)'${query}': "
	r.prompt_offset = 0
	vlsh_refresh_line(mut r)
}

fn vlsh_start_history_search(mut r Readline) {
	r.search_mode = true
	r.search_query = []rune{}
	r.search_match_index = 0
	r.search_saved_prompt = r.prompt
	r.search_saved_prompt_offset = r.prompt_offset
	r.search_saved_current = r.current.clone()
	vlsh_do_search(mut r)
}

fn vlsh_execute_search(mut r Readline, a VlshAction, c int) bool {
	match a {
		.insert_character {
			r.search_query << rune(c)
			r.search_match_index = 0
			vlsh_do_search(mut r)
		}
		.delete_left {
			if r.search_query.len > 0 {
				r.search_query.pop()
				r.search_match_index = 0
				vlsh_do_search(mut r)
			}
		}
		.history_search {
			// Ctrl+R again: go to next (older) match
			r.search_match_index++
			vlsh_do_search(mut r)
		}
		.commit_line {
			r.search_mode = false
			r.prompt = r.search_saved_prompt
			r.prompt_offset = r.search_saved_prompt_offset
			return vlsh_commit_line(mut r)
		}
		.cancel_line {
			r.search_mode = false
			r.prompt = r.search_saved_prompt
			r.prompt_offset = r.search_saved_prompt_offset
			return vlsh_cancel_line(mut r)
		}
		else {
			// Any other key cancels search and restores the saved line
			r.search_mode = false
			r.prompt = r.search_saved_prompt
			r.prompt_offset = r.search_saved_prompt_offset
			r.current = r.search_saved_current.clone()
			r.cursor = r.current.len
			vlsh_refresh_line(mut r)
		}
	}
	return false
}

fn vlsh_execute(mut r Readline, a VlshAction, c int) bool {
	match a {
		.eof         { return vlsh_eof(mut r) }
		.cancel_line { return vlsh_cancel_line(mut r) }
		.insert_character {
			r.last_prefix_completion.clear()
			vlsh_insert_character(mut r, c)
		}
		.commit_line {
			r.last_prefix_completion.clear()
			return vlsh_commit_line(mut r)
		}
		.delete_left { vlsh_delete_character(mut r) }
		.delete_right { vlsh_suppr_character(mut r) }
		.delete_line { vlsh_delete_line(mut r) }
		.delete_word_left { vlsh_delete_word_left(mut r) }
		.move_cursor_left { vlsh_move_cursor_left(mut r) }
		.move_cursor_right { vlsh_move_cursor_right(mut r) }
		.move_cursor_start { vlsh_move_cursor_start(mut r) }
		.move_cursor_end { vlsh_move_cursor_end(mut r) }
		.move_cursor_word_left { vlsh_move_cursor_word_left(mut r) }
		.move_cursor_word_right { vlsh_move_cursor_word_right(mut r) }
		.history_previous { vlsh_history_previous(mut r) }
		.history_next { vlsh_history_next(mut r) }
		.overwrite { vlsh_switch_overwrite(mut r) }
		.clear_screen { vlsh_clear_screen(mut r) }
		.suspend { vlsh_suspend(mut r) }
		.completion { vlsh_completion(mut r) }
		.history_search { vlsh_start_history_search(mut r) }
		.nothing {}
	}
	return false
}

// ── main entry point ──────────────────────────────────────────────────────────

// vlsh_read_line is a drop-in replacement for r.read_line(prompt) that fixes
// the Backspace-at-column-0 bug without modifying vlib.
fn vlsh_read_line(mut r Readline, prompt string) !string {
	r.current = []rune{}
	r.cursor = 0
	r.prompt = prompt
	r.search_index = 0
	r.prompt_offset = vlsh_get_prompt_offset(prompt)
	if r.previous_lines.len <= 1 {
		r.previous_lines << []rune{}
		r.previous_lines << []rune{}
	} else {
		r.previous_lines[0] = []rune{}
	}
	if !r.is_raw {
		r.enable_raw_mode()
	}
	print(r.prompt)
	for {
		flush_stdout()
		c := r.read_char() or { return err }
		a, ch := vlsh_analyse(r, c)
		done := if r.search_mode {
			vlsh_execute_search(mut r, a, ch)
		} else {
			vlsh_execute(mut r, a, ch)
		}
		if done {
			break
		}
	}
	r.previous_lines[0] = []rune{}
	r.search_index = 0
	r.disable_raw_mode()
	// Ctrl+C leaves a sentinel rune(3) so we can distinguish it from an
	// empty Enter press (both result in a short r.current after the loop).
	if r.current.len == 1 && r.current[0] == rune(3) {
		return error('cancelled')
	}
	if r.current.len == 0 {
		return error('empty line')
	}
	if r.current.last() == `\n` {
		r.current.pop()
	}
	return r.current.string()
}
