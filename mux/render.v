module mux

import strings

// move_cursor emits an ANSI sequence to move to absolute terminal position (row, col), 1-based.
fn move_cursor(row int, col int) string {
	return '\x1b[${row + 1};${col + 1}H'
}

// sel_contains reports whether the cell at (cell_col, cell_row) — in pane-relative
// coordinates — falls within the given selection.
fn sel_contains(sel Selection, pane_id int, cell_col int, cell_row int) bool {
	if !sel.active || pane_id != sel.pane_id { return false }
	mut r1 := sel.start_row
	mut c1 := sel.start_col
	mut r2 := sel.end_row
	mut c2 := sel.end_col
	// Normalise so r1/c1 is before r2/c2 in reading order
	if r1 > r2 || (r1 == r2 && c1 > c2) {
		r1, c1, r2, c2 = r2, c2, r1, c1
	}
	if cell_row < r1 || cell_row > r2       { return false }
	if cell_row == r1 && cell_col < c1      { return false }
	if cell_row == r2 && cell_col > c2      { return false }
	return true
}

// render_statusbar_sb draws the 1-row status bar at the very top of the terminal.
fn render_statusbar_sb(mut sb strings.Builder, panes []Pane, term_w int, bar_bg []int) {
	r    := if bar_bg.len >= 1 { bar_bg[0] } else { 44 }
	g    := if bar_bg.len >= 2 { bar_bg[1] } else { 124 }
	b    := if bar_bg.len >= 3 { bar_bg[2] } else { 67 }

	alive := panes.filter(it.alive).len
	pane_str := if alive == 1 { '1 pane' } else { '${alive} panes' }

	left  := '  vlsh mux  '
	right := '  ${pane_str}  '

	fill := term_w - left.len - right.len

	sb.write_string(move_cursor(0, 0))
	// 24-bit background colour + bright white foreground
	sb.write_string('\x1b[48;2;${r};${g};${b}m\x1b[97m')
	sb.write_string(left)
	if fill > 0 {
		sb.write_string(' '.repeat(fill))
	}
	sb.write_string(right)
	sb.write_string('\x1b[0m')
}

// render_all clears and redraws everything: borders first, then pane content.
pub fn render_all(panes []Pane, layout &LayoutNode, active_id int, term_w int, term_h int, sel Selection, bar_bg []int) {
	mut sb := strings.new_builder(term_w * term_h * 4)
	// Hide cursor while drawing
	sb.write_string('\x1b[?25l')
	// Clear screen
	sb.write_string('\x1b[2J')

	render_statusbar_sb(mut sb, panes, term_w, bar_bg)
	render_borders_sb(mut sb, layout, active_id)

	for p in panes {
		if p.alive {
			render_pane_sb(mut sb, p, p.id == active_id, sel)
		}
	}

	// Position cursor at the active pane's tracked cursor location.
	// Clamp to valid range: put_char() may leave cur_x == width after
	// writing the last column before the next wrap is triggered.
	for p in panes {
		if p.id == active_id && p.alive {
			cx := if p.cur_x >= p.width  { p.width  - 1 } else if p.cur_x < 0 { 0 } else { p.cur_x }
			cy := if p.cur_y >= p.height { p.height - 1 } else if p.cur_y < 0 { 0 } else { p.cur_y }
			sb.write_string('\x1b[0m')
			sb.write_string(move_cursor(p.y + cy, p.x + cx))
			break
		}
	}

	// Show cursor
	sb.write_string('\x1b[?25h')

	print(sb.str())
	// Flush in case the C runtime is buffering stdout (some V builds use
	// libc FILE* for print(); the direct write() path makes this a no-op).
	C.fflush(C.stdout)
}

// render_pane_sb writes pane content into the string builder, highlighting any
// selected cells with reverse-video (SGR 7).
// When p.scroll_offset > 0 the view is anchored into the scrollback buffer.
fn render_pane_sb(mut sb strings.Builder, p Pane, active bool, sel Selection) {
	if p.width <= 0 || p.height <= 0 { return }
	_ = active // border highlight is handled by render_borders_sb

	is_scrolled := p.scroll_offset > 0
	// Index in the combined (scrollback ++ grid) buffer where the display starts.
	// When scroll_offset == 0 this equals scrollback.len, meaning we show the
	// live grid from the beginning.
	scroll_start := p.scrollback.len - p.scroll_offset

	for row := 0; row < p.height && row < p.grid.len; row++ {
		sb.write_string(move_cursor(p.y + row, p.x))
		mut prev_sgr := ''
		mut prev_highlighted := false

		// Resolve which row of data to display: scrollback or live grid.
		combined_idx := scroll_start + row
		actual_row := if combined_idx < 0 {
			// Requested position is before the oldest scrollback row: blank.
			[]Cell{len: p.width, init: Cell{ch: ` `}}
		} else if combined_idx < p.scrollback.len {
			p.scrollback[combined_idx]
		} else {
			grid_idx := combined_idx - p.scrollback.len
			if grid_idx < p.grid.len { p.grid[grid_idx] } else { []Cell{len: p.width, init: Cell{ch: ` `}} }
		}

		for col := 0; col < p.width && col < actual_row.len; col++ {
			cell := actual_row[col]
			// Selection highlights only apply in the live view.
			highlighted := !is_scrolled && sel_contains(sel, p.id, col, row)
			if cell.sgr != prev_sgr || highlighted != prev_highlighted {
				sb.write_string('\x1b[0m')
				if highlighted {
					sb.write_string('\x1b[7m') // reverse video for selection highlight
				} else if cell.sgr != '' {
					sb.write_string(cell.sgr)
				}
				prev_sgr = cell.sgr
				prev_highlighted = highlighted
			}
			if cell.ch == 0 || cell.ch == rune(` `) {
				sb.write_u8(u8(` `))
			} else {
				sb.write_string(cell.ch.str())
			}
		}
		// Reset at end of each line
		sb.write_string('\x1b[0m')
	}

	// Scroll position indicator: rendered in the top-right corner of the pane
	// when the user has scrolled back into the scrollback buffer.
	if is_scrolled {
		indicator := ' -${p.scroll_offset} lines '
		ix := p.x + p.width - indicator.len
		if ix >= p.x {
			sb.write_string(move_cursor(p.y, ix))
			// Orange background, black foreground
			sb.write_string('\x1b[48;2;255;165;0m\x1b[30m${indicator}\x1b[0m')
		}
	}
}

// render_borders_sb draws divider lines for all internal nodes.
fn render_borders_sb(mut sb strings.Builder, node &LayoutNode, active_id int) {
	if node.is_leaf { return }

	left_ids := if !isnil(node.left) { node.left.all_pane_ids() } else { []int{} }
	right_ids := if !isnil(node.right) { node.right.all_pane_ids() } else { []int{} }
	active_side_left  := active_id in left_ids
	active_side_right := active_id in right_ids
	_ = active_side_left
	_ = active_side_right

	if node.dir == .vertical {
		// Vertical divider between left and right
		divider_col := if !isnil(node.left) { node.left.x + node.left.w } else { node.x + int(f32(node.w) * node.ratio) }
		for row := node.y; row < node.y + node.h; row++ {
			sb.write_string(move_cursor(row, divider_col))
			sb.write_string('\x1b[0m│')
		}
	} else {
		// Horizontal divider between top and bottom
		divider_row := if !isnil(node.left) { node.left.y + node.left.h } else { node.y + int(f32(node.h) * node.ratio) }
		for col := node.x; col < node.x + node.w; col++ {
			sb.write_string(move_cursor(divider_row, col))
			sb.write_string('\x1b[0m─')
		}
	}

	// Recurse into children
	if !isnil(node.left)  { render_borders_sb(mut sb, node.left,  active_id) }
	if !isnil(node.right) { render_borders_sb(mut sb, node.right, active_id) }
}

// render_dirty re-renders only panes that have dirty=true.
pub fn render_dirty(mut panes []Pane, layout &LayoutNode, active_id int, term_w int, term_h int, sel Selection, bar_bg []int) {
	mut needs_full := false
	for p in panes {
		if p.dirty {
			needs_full = true
			break
		}
	}
	if needs_full {
		render_all(panes, layout, active_id, term_w, term_h, sel, bar_bg)
		for mut p in panes {
			p.dirty = false
		}
	}
}
