module mux

import strings

// move_cursor emits an ANSI sequence to move to absolute terminal position (row, col), 1-based.
fn move_cursor(row int, col int) string {
	return '\x1b[${row + 1};${col + 1}H'
}

// render_all clears and redraws everything: borders first, then pane content.
pub fn render_all(panes []Pane, layout &LayoutNode, active_id int, term_w int, term_h int) {
	mut sb := strings.new_builder(term_w * term_h * 4)
	// Hide cursor while drawing
	sb.write_string('\x1b[?25l')
	// Clear screen
	sb.write_string('\x1b[2J')

	render_borders_sb(mut sb, layout, active_id)

	for p in panes {
		if p.alive {
			render_pane_sb(mut sb, p, p.id == active_id)
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

// render_pane_sb writes pane content into the string builder.
fn render_pane_sb(mut sb strings.Builder, p Pane, active bool) {
	if p.width <= 0 || p.height <= 0 { return }
	_ = active // border highlight is handled by render_borders_sb
	for row := 0; row < p.height && row < p.grid.len; row++ {
		sb.write_string(move_cursor(p.y + row, p.x))
		mut prev_sgr := ''
		for col := 0; col < p.width && col < p.grid[row].len; col++ {
			cell := p.grid[row][col]
			if cell.sgr != prev_sgr {
				if cell.sgr == '' {
					sb.write_string('\x1b[0m')
				} else {
					sb.write_string('\x1b[0m')
					sb.write_string(cell.sgr)
				}
				prev_sgr = cell.sgr
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
pub fn render_dirty(mut panes []Pane, layout &LayoutNode, active_id int, term_w int, term_h int) {
	mut needs_full := false
	for p in panes {
		if p.dirty {
			needs_full = true
			break
		}
	}
	if needs_full {
		render_all(panes, layout, active_id, term_w, term_h)
		for mut p in panes {
			p.dirty = false
		}
	}
}
