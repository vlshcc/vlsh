module mux

struct Cell {
mut:
	ch  rune
	sgr string
}

pub struct Pane {
pub mut:
	id        int
	master_fd int
	pid       int
	x         int
	y         int
	width     int
	height    int
	grid      [][]Cell
	cur_x     int
	cur_y     int
	cur_sgr   string
	dirty     bool
	alive     bool
	// VT100 parser state
	esc_buf   string
	in_esc    bool
	// UTF-8 multi-byte accumulator
	utf8_buf  []u8
	utf8_rem  int
	// Scroll region (DECSTBM): rows are 0-based.  Default covers full pane.
	scroll_top int
	scroll_bot int
	// Saved cursor state (ESC 7 / ESC 8 / CSI s / CSI u)
	saved_cur_x   int
	saved_cur_y   int
	saved_cur_sgr string
	// Alternate screen buffer (CSI ?1049h / CSI ?1049l)
	alt_grid      [][]Cell
	on_alt_screen bool
}

pub fn new_pane(id int, master_fd int, pid int, x int, y int, w int, h int) Pane {
	mut grid := [][]Cell{len: h, init: []Cell{len: w, init: Cell{ch: ` `}}}
	return Pane{
		id:         id
		master_fd:  master_fd
		pid:        pid
		x:          x
		y:          y
		width:      w
		height:     h
		grid:       grid
		cur_x:      0
		cur_y:      0
		alive:      true
		dirty:      true
		scroll_top: 0
		scroll_bot: h - 1
	}
}

pub fn (mut p Pane) resize(x int, y int, w int, h int) {
	p.x      = x
	p.y      = y
	p.width  = w
	p.height = h
	// Rebuild main grid preserving as much content as possible
	mut new_grid := [][]Cell{len: h, init: []Cell{len: w, init: Cell{ch: ` `}}}
	for row := 0; row < h && row < p.grid.len; row++ {
		for col := 0; col < w && col < p.grid[row].len; col++ {
			new_grid[row][col] = p.grid[row][col]
		}
	}
	p.grid  = new_grid
	p.cur_x = if p.cur_x >= w { w - 1 } else { p.cur_x }
	p.cur_y = if p.cur_y >= h { h - 1 } else { p.cur_y }
	if p.cur_x < 0 { p.cur_x = 0 }
	if p.cur_y < 0 { p.cur_y = 0 }
	// Reset scroll region to full pane on resize
	p.scroll_top = 0
	p.scroll_bot = h - 1
	// Resize alt_grid too if it exists
	if p.alt_grid.len > 0 {
		mut new_alt := [][]Cell{len: h, init: []Cell{len: w, init: Cell{ch: ` `}}}
		for row := 0; row < h && row < p.alt_grid.len; row++ {
			for col := 0; col < w && col < p.alt_grid[row].len; col++ {
				new_alt[row][col] = p.alt_grid[row][col]
			}
		}
		p.alt_grid = new_alt
	}
	p.dirty = true
}

// scroll_up shifts rows upward within the current scroll region, adding a
// blank row at the bottom of the region.
fn (mut p Pane) scroll_up() {
	if p.height == 0 { return }
	top := p.scroll_top
	bot := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
	for row := top + 1; row <= bot; row++ {
		p.grid[row - 1] = p.grid[row].clone()
	}
	blank := Cell{ch: ` `, sgr: p.cur_sgr}
	p.grid[bot] = []Cell{len: p.width, init: blank}
}

// scroll_down shifts rows downward within the current scroll region, adding a
// blank row at the top of the region (used by Reverse Index / ESC M).
fn (mut p Pane) scroll_down() {
	if p.height == 0 { return }
	top := p.scroll_top
	bot := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
	for row := bot; row > top; row-- {
		p.grid[row] = p.grid[row - 1].clone()
	}
	blank := Cell{ch: ` `, sgr: p.cur_sgr}
	p.grid[top] = []Cell{len: p.width, init: blank}
}

// put_char writes ch at cur_x/cur_y with current SGR, then advances cursor.
// Line wrapping respects the active scroll region.
fn (mut p Pane) put_char(ch rune) {
	if p.height == 0 || p.width == 0 { return }
	bot := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
	// If the cursor ended up below the scroll region somehow, scroll it back.
	if p.cur_y > bot {
		p.scroll_up()
		p.cur_y = bot
	}
	// Line wrap
	if p.cur_x >= p.width {
		p.cur_x = 0
		if p.cur_y == bot {
			p.scroll_up()
			// cur_y stays at bot after the scroll
		} else {
			p.cur_y++
			if p.cur_y >= p.height { p.cur_y = p.height - 1 }
		}
	}
	if p.cur_y < 0 { p.cur_y = 0 }
	p.grid[p.cur_y][p.cur_x] = Cell{ch: ch, sgr: p.cur_sgr}
	p.cur_x++
}

// handle_escape processes a complete escape sequence stored in p.esc_buf.
// esc_buf contains everything after the ESC character.
fn (mut p Pane) handle_escape(seq string) {
	if seq.len == 0 { return }

	// OSC sequences: ESC ] ... BEL/ST — discard
	if seq.starts_with(']') { return }

	// Handle ESC [ sequences (CSI)
	if seq.starts_with('[') {
		params_and_final := seq[1..]
		if params_and_final.len == 0 { return }
		final_byte := params_and_final[params_and_final.len - 1]
		params_str  := params_and_final[..params_and_final.len - 1]

		match final_byte {
			`H`, `f` {
				// Cursor Position: ESC[row;colH  (1-based relative to pane)
				parts := params_str.split(';')
				mut row := if parts.len > 0 && parts[0] != '' { parts[0].int() - 1 } else { 0 }
				mut col := if parts.len > 1 && parts[1] != '' { parts[1].int() - 1 } else { 0 }
				if row < 0 { row = 0 }
				if col < 0 { col = 0 }
				if row >= p.height { row = p.height - 1 }
				if col >= p.width  { col = p.width  - 1 }
				p.cur_y = row
				p.cur_x = col
			}
			`A` {
				n := if params_str != '' { params_str.int() } else { 1 }
				p.cur_y -= if n > 0 { n } else { 1 }
				if p.cur_y < 0 { p.cur_y = 0 }
			}
			`B` {
				n := if params_str != '' { params_str.int() } else { 1 }
				p.cur_y += if n > 0 { n } else { 1 }
				if p.cur_y >= p.height { p.cur_y = p.height - 1 }
			}
			`C` {
				n := if params_str != '' { params_str.int() } else { 1 }
				p.cur_x += if n > 0 { n } else { 1 }
				if p.cur_x >= p.width { p.cur_x = p.width - 1 }
			}
			`D` {
				n := if params_str != '' { params_str.int() } else { 1 }
				p.cur_x -= if n > 0 { n } else { 1 }
				if p.cur_x < 0 { p.cur_x = 0 }
			}
			`G` {
				// Cursor Horizontal Absolute
				col := if params_str != '' { params_str.int() - 1 } else { 0 }
				p.cur_x = if col < 0 { 0 } else if col >= p.width { p.width - 1 } else { col }
			}
			`d` {
				// Cursor Vertical Absolute
				row := if params_str != '' { params_str.int() - 1 } else { 0 }
				p.cur_y = if row < 0 { 0 } else if row >= p.height { p.height - 1 } else { row }
			}
			`J` {
				// Erase in Display — use current SGR so background colour is preserved (BCE).
				blank := Cell{ch: ` `, sgr: p.cur_sgr}
				n := if params_str != '' { params_str.int() } else { 0 }
				if n == 0 {
					// clear from cursor to end of screen
					for col := p.cur_x; col < p.width; col++ {
						p.grid[p.cur_y][col] = blank
					}
					for row := p.cur_y + 1; row < p.height; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = blank
						}
					}
				} else if n == 1 {
					// clear from beginning to cursor
					for row := 0; row < p.cur_y; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = blank
						}
					}
					for col := 0; col <= p.cur_x && col < p.width; col++ {
						p.grid[p.cur_y][col] = blank
					}
				} else if n == 2 || n == 3 {
					// clear entire screen
					for row := 0; row < p.height; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = blank
						}
					}
					p.cur_x = 0
					p.cur_y = 0
				}
			}
			`K` {
				// Erase in Line — use current SGR so background colour is preserved (BCE).
				blank := Cell{ch: ` `, sgr: p.cur_sgr}
				n := if params_str != '' { params_str.int() } else { 0 }
				if p.cur_y < p.height {
					if n == 0 {
						for col := p.cur_x; col < p.width; col++ {
							p.grid[p.cur_y][col] = blank
						}
					} else if n == 1 {
						for col := 0; col <= p.cur_x && col < p.width; col++ {
							p.grid[p.cur_y][col] = blank
						}
					} else if n == 2 {
						for col := 0; col < p.width; col++ {
							p.grid[p.cur_y][col] = blank
						}
					}
				}
			}
			`X` {
				// Erase Character: fill n chars at cursor with space (cursor doesn't move)
				n := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				if p.cur_y < p.height {
					blank := Cell{ch: ` `, sgr: p.cur_sgr}
					for col := p.cur_x; col < p.cur_x + count && col < p.width; col++ {
						p.grid[p.cur_y][col] = blank
					}
				}
			}
			`L` {
				// Insert Line: insert n blank lines at cursor row within scroll region
				n     := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				bot   := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
				blank := Cell{ch: ` `, sgr: ''}
				for i := 0; i < count; i++ {
					// Shift rows down within the scroll region, dropping the bottom row
					for row := bot; row > p.cur_y; row-- {
						p.grid[row] = p.grid[row - 1].clone()
					}
					p.grid[p.cur_y] = []Cell{len: p.width, init: blank}
				}
				p.cur_x = 0
			}
			`M` {
				// Delete Line: delete n lines at cursor row within scroll region
				n     := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				bot   := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
				blank := Cell{ch: ` `, sgr: ''}
				for i := 0; i < count; i++ {
					for row := p.cur_y + 1; row <= bot; row++ {
						p.grid[row - 1] = p.grid[row].clone()
					}
					p.grid[bot] = []Cell{len: p.width, init: blank}
				}
				p.cur_x = 0
			}
			`P` {
				// Delete Character: delete n chars at cursor, shift line left, fill end
				n     := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				if p.cur_y < p.height {
					for col := p.cur_x; col < p.width - count; col++ {
						if col + count < p.grid[p.cur_y].len {
							p.grid[p.cur_y][col] = p.grid[p.cur_y][col + count]
						}
					}
					blank := Cell{ch: ` `, sgr: ''}
					for col := p.width - count; col < p.width; col++ {
						if col >= 0 && col < p.grid[p.cur_y].len {
							p.grid[p.cur_y][col] = blank
						}
					}
				}
			}
			`S` {
				// Scroll Up: scroll region up by n lines
				n     := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				for i := 0; i < count; i++ { p.scroll_up() }
			}
			`T` {
				// Scroll Down: scroll region down by n lines
				n     := if params_str != '' { params_str.int() } else { 1 }
				count := if n < 1 { 1 } else { n }
				for i := 0; i < count; i++ { p.scroll_down() }
			}
			`m` {
				// SGR — store verbatim
				if params_str == '' || params_str == '0' {
					p.cur_sgr = ''
				} else {
					p.cur_sgr = '\x1b[${params_str}m'
				}
			}
			`r` {
				// DECSTBM — Set Scrolling Region: CSI top ; bot r  (1-based)
				parts := params_str.split(';')
				top := if parts.len > 0 && parts[0] != '' { parts[0].int() - 1 } else { 0 }
				bot := if parts.len > 1 && parts[1] != '' { parts[1].int() - 1 } else { p.height - 1 }
				p.scroll_top = if top >= 0 { top } else { 0 }
				p.scroll_bot = if bot > top && bot < p.height { bot } else { p.height - 1 }
				// DECSTBM always moves cursor to home
				p.cur_x = 0
				p.cur_y = 0
			}
			`s` {
				// Save cursor position (ANSI)
				p.saved_cur_x   = p.cur_x
				p.saved_cur_y   = p.cur_y
				p.saved_cur_sgr = p.cur_sgr
			}
			`u` {
				// Restore cursor position (ANSI)
				p.cur_x   = p.saved_cur_x
				p.cur_y   = p.saved_cur_y
				p.cur_sgr = p.saved_cur_sgr
			}
			`h` {
				// Mode set — only handle alternate screen; ignore everything else
				if params_str == '?1049' || params_str == '?1047' {
					if !p.on_alt_screen {
						p.saved_cur_x   = p.cur_x
						p.saved_cur_y   = p.cur_y
						p.saved_cur_sgr = p.cur_sgr
						p.alt_grid      = p.grid
						p.grid          = [][]Cell{len: p.height, init: []Cell{len: p.width, init: Cell{ch: ` `}}}
						p.on_alt_screen = true
						p.cur_x         = 0
						p.cur_y         = 0
						p.cur_sgr       = ''
						p.scroll_top    = 0
						p.scroll_bot    = p.height - 1
					}
				}
				// all other ?NNNh modes (cursor visibility, mouse, etc.) — ignore
			}
			`l` {
				// Mode reset — only handle alternate screen; ignore everything else
				if params_str == '?1049' || params_str == '?1047' {
					if p.on_alt_screen {
						p.grid          = p.alt_grid
						p.alt_grid      = [][]Cell{}
						p.on_alt_screen = false
						p.cur_x         = p.saved_cur_x
						p.cur_y         = p.saved_cur_y
						p.cur_sgr       = p.saved_cur_sgr
						p.scroll_top    = 0
						p.scroll_bot    = p.height - 1
					}
				}
				// all other ?NNNl modes — ignore
			}
			else {
				// Unknown sequence — discard
			}
		}
		return
	}

	// Non-CSI two-byte ESC sequences
	match seq {
		'M' {
			// Reverse Index (RI): move cursor up; if at scroll_top, scroll region down
			if p.cur_y == p.scroll_top {
				p.scroll_down()
			} else if p.cur_y > 0 {
				p.cur_y--
			}
		}
		'7' {
			// DECSC — Save cursor + SGR
			p.saved_cur_x   = p.cur_x
			p.saved_cur_y   = p.cur_y
			p.saved_cur_sgr = p.cur_sgr
		}
		'8' {
			// DECRC — Restore cursor + SGR
			p.cur_x   = p.saved_cur_x
			p.cur_y   = p.saved_cur_y
			p.cur_sgr = p.saved_cur_sgr
		}
		else {
			// ESC ( B, ESC =, ESC >, etc. — character set / keypad mode — ignore
		}
	}
}

// utf8_seq_len returns the total byte count for a UTF-8 sequence starting with b,
// or 0 if b is not a valid leading byte.
fn utf8_seq_len(b u8) int {
	if b < 0x80  { return 1 }
	if b < 0xC0  { return 0 } // continuation byte — not a leading byte
	if b < 0xE0  { return 2 }
	if b < 0xF0  { return 3 }
	return 4
}

// utf8_buf_to_rune decodes a fully-accumulated UTF-8 byte sequence to a rune.
fn utf8_buf_to_rune(buf []u8) rune {
	if buf.len == 0 { return rune(0) }
	b0 := u32(buf[0])
	if buf.len == 1 { return rune(b0) }
	if buf.len == 2 {
		return rune(((b0 & 0x1F) << 6) | u32(buf[1] & 0x3F))
	}
	if buf.len == 3 {
		return rune(((b0 & 0x0F) << 12) | (u32(buf[1] & 0x3F) << 6) | u32(buf[2] & 0x3F))
	}
	return rune(((b0 & 0x07) << 18) | (u32(buf[1] & 0x3F) << 12) | (u32(buf[2] & 0x3F) << 6) | u32(buf[3] & 0x3F))
}

// feed processes raw bytes from the PTY master and updates the pane grid.
pub fn (mut p Pane) feed(data []u8) {
	mut i := 0
	for i < data.len {
		b := data[i]

		if p.in_esc {
			p.esc_buf += b.ascii_str()
			// Determine if the escape sequence is complete.
			// CSI sequences end when a byte in 0x40–0x7E is received after the '['.
			// Other two-char ESC sequences: ESC + any byte 0x20–0x7E that isn't '['.
			seq := p.esc_buf
			if seq.len == 1 {
				// Just got first byte after ESC
				if b == `[` || b == `]` || b == `(` || b == `)` {
					// Need more bytes
					i++
					continue
				} else {
					// Two-byte ESC sequence complete
					p.handle_escape(seq)
					p.in_esc   = false
					p.esc_buf  = ''
					i++
					continue
				}
			}
			// CSI: ESC [ <params> <final>
			if seq[0] == `[` {
				if b >= 0x40 && b <= 0x7e {
					p.handle_escape(seq)
					p.in_esc  = false
					p.esc_buf = ''
				}
				i++
				continue
			}
			// OSC: ESC ] ... BEL or ST
			if seq[0] == `]` {
				if b == 0x07 || (b == 0x5c && seq.len >= 2 && seq[seq.len - 2] == 0x1b) {
					p.handle_escape(seq)
					p.in_esc  = false
					p.esc_buf = ''
				}
				i++
				continue
			}
			// Character set or other multi-byte: one param byte is enough
			if seq.len >= 2 {
				p.handle_escape(seq)
				p.in_esc  = false
				p.esc_buf = ''
			}
			i++
			continue
		}

		// Handle partial UTF-8 multi-byte sequences.
		if p.utf8_rem > 0 {
			if b >= 0x80 && b < 0xC0 {
				// Valid continuation byte
				p.utf8_buf << b
				p.utf8_rem--
				if p.utf8_rem == 0 {
					p.put_char(utf8_buf_to_rune(p.utf8_buf))
					p.utf8_buf = []u8{}
				}
			} else {
				// Invalid continuation — discard the partial sequence and reprocess b.
				p.utf8_buf = []u8{}
				p.utf8_rem = 0
				continue // reprocess this byte without incrementing i
			}
			i++
			continue
		}

		match b {
			0x1b {
				p.in_esc  = true
				p.esc_buf = ''
				// Discard any partial UTF-8 accumulation.
				p.utf8_buf = []u8{}
				p.utf8_rem = 0
			}
			`\r` {
				p.cur_x = 0
			}
			`\n` {
				// Newline respects the active scroll region.
				bot := if p.scroll_bot < p.height { p.scroll_bot } else { p.height - 1 }
				if p.cur_y == bot {
					p.scroll_up()
					// cursor row stays at bot
				} else {
					p.cur_y++
					if p.cur_y >= p.height { p.cur_y = p.height - 1 }
				}
			}
			`\b` {
				if p.cur_x > 0 { p.cur_x-- }
			}
			0x07 {
				// BEL — ignore
			}
			0x09 {
				// TAB — advance to next tab stop
				next_tab := ((p.cur_x / 8) + 1) * 8
				p.cur_x = if next_tab >= p.width { p.width - 1 } else { next_tab }
			}
			0x0d {
				p.cur_x = 0
			}
			else {
				if b >= 0xC0 {
					// Start of a 2-, 3-, or 4-byte UTF-8 sequence.
					seq_len := utf8_seq_len(b)
					if seq_len >= 2 {
						p.utf8_buf = [b]
						p.utf8_rem = seq_len - 1
					}
					// If seq_len == 0 (invalid), just skip.
				} else if b >= 0x80 {
					// Stray continuation byte — skip.
				} else if b >= 0x20 {
					// Plain ASCII printable character.
					p.put_char(rune(b))
				}
				// b < 0x20 and unmatched above — control character, ignore.
			}
		}
		i++
	}
	p.dirty = true
}
