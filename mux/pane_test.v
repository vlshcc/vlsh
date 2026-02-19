module mux

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// cell_str returns the visible characters in the given row as a plain string.
fn row_str(p Pane, row int) string {
	mut s := ''
	for cell in p.grid[row] {
		s += cell.ch.str()
	}
	return s
}

// visible_rows returns every row as a string, trimming trailing spaces.
fn visible_rows(p Pane) []string {
	mut rows := []string{}
	for row in p.grid {
		mut s := ''
		for cell in row { s += cell.ch.str() }
		rows << s.trim_right(' ')
	}
	return rows
}

// feed_str is a convenience wrapper that feeds a plain string as bytes.
fn feed_str(mut p Pane, s string) {
	p.feed(s.bytes())
}

// ---------------------------------------------------------------------------
// new_pane
// ---------------------------------------------------------------------------

fn test_new_pane_dimensions() {
	p := new_pane(1, -1, -1, 0, 0, 80, 24)
	assert p.width  == 80
	assert p.height == 24
	assert p.grid.len == 24
	assert p.grid[0].len == 80
}

fn test_new_pane_initial_cursor_at_origin() {
	p := new_pane(1, -1, -1, 0, 0, 80, 24)
	assert p.cur_x == 0
	assert p.cur_y == 0
}

fn test_new_pane_initial_grid_is_spaces() {
	p := new_pane(1, -1, -1, 0, 0, 10, 5)
	for row in p.grid {
		for cell in row {
			assert cell.ch == ` `
		}
	}
}

fn test_new_pane_alive_and_dirty() {
	p := new_pane(1, -1, -1, 0, 0, 10, 5)
	assert p.alive == true
	assert p.dirty == true
}

fn test_new_pane_position_stored() {
	p := new_pane(3, 5, 42, 10, 2, 40, 12)
	assert p.id == 3
	assert p.x  == 10
	assert p.y  == 2
}

// ---------------------------------------------------------------------------
// feed — plain text
// ---------------------------------------------------------------------------

fn test_feed_plain_text_writes_to_grid() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'hello')
	assert p.grid[0][0].ch == `h`
	assert p.grid[0][1].ch == `e`
	assert p.grid[0][2].ch == `l`
	assert p.grid[0][3].ch == `l`
	assert p.grid[0][4].ch == `o`
}

fn test_feed_plain_text_advances_cursor() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'hi')
	assert p.cur_x == 2
	assert p.cur_y == 0
}

fn test_feed_marks_dirty() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	p.dirty = false
	feed_str(mut p, 'x')
	assert p.dirty == true
}

// ---------------------------------------------------------------------------
// feed — control characters
// ---------------------------------------------------------------------------

fn test_feed_newline_increments_row() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\n')
	assert p.cur_y == 1
}

fn test_feed_carriage_return_resets_column() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'hello\r')
	assert p.cur_x == 0
	assert p.cur_y == 0
}

fn test_feed_crlf_moves_to_next_row_col_zero() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'hello\r\n')
	assert p.cur_x == 0
	assert p.cur_y == 1
}

fn test_feed_backspace_moves_cursor_left() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'ab\b')
	assert p.cur_x == 1
}

fn test_feed_backspace_does_not_go_negative() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\b\b\b')
	assert p.cur_x == 0
}

fn test_feed_tab_advances_to_next_tab_stop() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 5)
	// cursor at col 0 → first tab stop is col 8
	feed_str(mut p, '\t')
	assert p.cur_x == 8
}

fn test_feed_tab_from_col_5_goes_to_col_8() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 5)
	feed_str(mut p, 'abcde\t')
	assert p.cur_x == 8
}

fn test_feed_tab_from_col_8_goes_to_col_16() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 5)
	feed_str(mut p, 'abcdefgh\t') // 8 chars + tab
	assert p.cur_x == 16
}

// ---------------------------------------------------------------------------
// feed — scroll
// ---------------------------------------------------------------------------

fn test_feed_scroll_when_newline_at_bottom() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 3)
	// Write 'A' on line 0, 'B' on line 1, 'C' on line 2, then newline scrolls
	feed_str(mut p, 'A\r\nB\r\nC\r\n')
	// After scroll, 'A' is gone, 'B' is row 0, 'C' is row 1, blank is row 2
	assert p.grid[0][0].ch == `B`
	assert p.grid[1][0].ch == `C`
	assert p.grid[2][0].ch == ` `
	assert p.cur_y == 2
}

fn test_feed_scroll_blank_row_added_at_bottom() {
	mut p := new_pane(1, -1, -1, 0, 0, 5, 2)
	feed_str(mut p, 'X\r\nY\r\nZ')
	// After two scrolls: row 0 = 'Y', row 1 = 'Z'
	assert p.grid[0][0].ch == `Y`
	assert p.grid[1][0].ch == `Z`
}

// ---------------------------------------------------------------------------
// feed — VT100 cursor movement sequences
// ---------------------------------------------------------------------------

fn test_feed_cursor_home_esc_seq() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'hello\r\n\r\n')
	feed_str(mut p, '\x1b[H') // cursor home → (0,0)
	assert p.cur_y == 0
	assert p.cur_x == 0
}

fn test_feed_cursor_position_absolute() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 24)
	feed_str(mut p, '\x1b[5;10H') // row 5, col 10 (1-based) → (4,9) 0-based
	assert p.cur_y == 4
	assert p.cur_x == 9
}

fn test_feed_cursor_position_clamps_to_bounds() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, '\x1b[99;99H') // way outside
	assert p.cur_y == 4 // height-1
	assert p.cur_x == 9 // width-1
}

fn test_feed_cursor_up() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 10)
	feed_str(mut p, '\x1b[5;1H') // row 5 (1-based) → cur_y=4
	feed_str(mut p, '\x1b[2A')   // up 2 → cur_y=2
	assert p.cur_y == 2
}

fn test_feed_cursor_up_does_not_go_above_zero() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 10)
	feed_str(mut p, '\x1b[1A') // already at row 0
	assert p.cur_y == 0
}

fn test_feed_cursor_down() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 10)
	feed_str(mut p, '\x1b[3B') // down 3 → cur_y=3
	assert p.cur_y == 3
}

fn test_feed_cursor_down_clamps_to_bottom() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[50B')
	assert p.cur_y == 4 // height-1
}

fn test_feed_cursor_forward() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[5C') // right 5
	assert p.cur_x == 5
}

fn test_feed_cursor_forward_clamps_to_right() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, '\x1b[50C')
	assert p.cur_x == 9 // width-1
}

fn test_feed_cursor_backward() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[10;8H') // col 7 (0-based)
	feed_str(mut p, '\x1b[3D')    // left 3 → col 4
	assert p.cur_x == 4
}

fn test_feed_cursor_backward_clamps_to_zero() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[50D')
	assert p.cur_x == 0
}

fn test_feed_cursor_horizontal_absolute() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[8G') // col 8 (1-based) → cur_x=7
	assert p.cur_x == 7
}

fn test_feed_cursor_vertical_absolute() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 10)
	feed_str(mut p, '\x1b[4d') // row 4 (1-based) → cur_y=3
	assert p.cur_y == 3
}

// ---------------------------------------------------------------------------
// feed — erase sequences
// ---------------------------------------------------------------------------

fn test_feed_erase_to_end_of_line() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, 'hello')
	feed_str(mut p, '\x1b[1;3H') // col 3 (1-based) → cur_x=2
	feed_str(mut p, '\x1b[K')    // erase from col 2 to end of line
	assert p.grid[0][0].ch == `h`
	assert p.grid[0][1].ch == `e`
	assert p.grid[0][2].ch == ` `
	assert p.grid[0][4].ch == ` `
}

fn test_feed_erase_to_start_of_line() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, 'hello')
	feed_str(mut p, '\x1b[1;4H') // cur_x=3
	feed_str(mut p, '\x1b[1K')   // erase from start to col 3
	assert p.grid[0][0].ch == ` `
	assert p.grid[0][3].ch == ` `
	assert p.grid[0][4].ch == `o`
}

fn test_feed_erase_entire_line() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, 'hello')
	feed_str(mut p, '\x1b[2K') // erase entire line
	for col := 0; col < 10; col++ {
		assert p.grid[0][col].ch == ` `
	}
}

fn test_feed_erase_display_to_end() {
	mut p := new_pane(1, -1, -1, 0, 0, 5, 3)
	feed_str(mut p, 'AAAAA\r\nBBBBB\r\nCCCCC')
	feed_str(mut p, '\x1b[2;3H') // row 2, col 3 (1-based) → (1,2)
	feed_str(mut p, '\x1b[J')    // erase from cursor to end
	// row 0 must be intact
	assert p.grid[0][0].ch == `A`
	// row 1 col 2 onward must be blank
	assert p.grid[1][2].ch == ` `
	// row 2 must be entirely blank
	for col := 0; col < 5; col++ {
		assert p.grid[2][col].ch == ` `
	}
}

fn test_feed_erase_entire_display() {
	mut p := new_pane(1, -1, -1, 0, 0, 5, 3)
	feed_str(mut p, 'AAAAA\r\nBBBBB\r\nCCCCC')
	feed_str(mut p, '\x1b[2J') // erase entire display
	for row in p.grid {
		for cell in row {
			assert cell.ch == ` `
		}
	}
	assert p.cur_x == 0
	assert p.cur_y == 0
}

// ---------------------------------------------------------------------------
// feed — SGR (Select Graphic Rendition)
// ---------------------------------------------------------------------------

fn test_feed_sgr_sets_cur_sgr() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[31m')
	assert p.cur_sgr == '\x1b[31m'
}

fn test_feed_sgr_reset_clears_cur_sgr() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[31m')
	feed_str(mut p, '\x1b[0m')
	assert p.cur_sgr == ''
}

fn test_feed_sgr_stored_in_cell() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, '\x1b[32mA')
	assert p.grid[0][0].sgr == '\x1b[32m'
	assert p.grid[0][0].ch  == `A`
}

fn test_feed_sgr_not_applied_to_cells_before_sequence() {
	mut p := new_pane(1, -1, -1, 0, 0, 20, 5)
	feed_str(mut p, 'X\x1b[31mY')
	assert p.grid[0][0].sgr == '' // 'X' written before color set
	assert p.grid[0][1].sgr == '\x1b[31m'
}

// ---------------------------------------------------------------------------
// resize
// ---------------------------------------------------------------------------

fn test_resize_updates_dimensions() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 24)
	p.resize(0, 0, 40, 12)
	assert p.width  == 40
	assert p.height == 12
	assert p.grid.len == 12
	assert p.grid[0].len == 40
}

fn test_resize_preserves_content_within_new_bounds() {
	mut p := new_pane(1, -1, -1, 0, 0, 10, 5)
	feed_str(mut p, 'hello')
	p.resize(0, 0, 10, 5) // same size
	assert p.grid[0][0].ch == `h`
	assert p.grid[0][4].ch == `o`
}

fn test_resize_truncates_cursor_to_new_bounds() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 24)
	feed_str(mut p, '\x1b[20;70H') // cur_y=19, cur_x=69
	p.resize(0, 0, 40, 10)
	assert p.cur_x <= 39
	assert p.cur_y <= 9
}

fn test_resize_marks_dirty() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 24)
	p.dirty = false
	p.resize(0, 0, 40, 12)
	assert p.dirty == true
}

fn test_resize_updates_position() {
	mut p := new_pane(1, -1, -1, 0, 0, 80, 24)
	p.resize(10, 5, 40, 12)
	assert p.x == 10
	assert p.y == 5
}
