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
}

pub fn new_pane(id int, master_fd int, pid int, x int, y int, w int, h int) Pane {
	mut grid := [][]Cell{len: h, init: []Cell{len: w, init: Cell{ch: ` `}}}
	return Pane{
		id:        id
		master_fd: master_fd
		pid:       pid
		x:         x
		y:         y
		width:     w
		height:    h
		grid:      grid
		cur_x:     0
		cur_y:     0
		alive:     true
		dirty:     true
	}
}

pub fn (mut p Pane) resize(x int, y int, w int, h int) {
	p.x      = x
	p.y      = y
	p.width  = w
	p.height = h
	// Rebuild grid preserving as much content as possible
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
	p.dirty = true
}

// scroll_up shifts all rows up by one, adding a blank row at the bottom.
fn (mut p Pane) scroll_up() {
	if p.height == 0 { return }
	for row := 1; row < p.height; row++ {
		p.grid[row - 1] = p.grid[row].clone()
	}
	p.grid[p.height - 1] = []Cell{len: p.width, init: Cell{ch: ` `}}
}

// put_char writes ch at cur_x/cur_y with current SGR, then advances cursor.
fn (mut p Pane) put_char(ch rune) {
	if p.height == 0 || p.width == 0 { return }
	if p.cur_y >= p.height {
		p.scroll_up()
		p.cur_y = p.height - 1
	}
	if p.cur_x >= p.width {
		p.cur_x = 0
		p.cur_y++
		if p.cur_y >= p.height {
			p.scroll_up()
			p.cur_y = p.height - 1
		}
	}
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
				// Erase in Display
				n := if params_str != '' { params_str.int() } else { 0 }
				if n == 0 {
					// clear from cursor to end of screen
					for col := p.cur_x; col < p.width; col++ {
						p.grid[p.cur_y][col] = Cell{ch: ` `}
					}
					for row := p.cur_y + 1; row < p.height; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = Cell{ch: ` `}
						}
					}
				} else if n == 1 {
					// clear from beginning to cursor
					for row := 0; row < p.cur_y; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = Cell{ch: ` `}
						}
					}
					for col := 0; col <= p.cur_x && col < p.width; col++ {
						p.grid[p.cur_y][col] = Cell{ch: ` `}
					}
				} else if n == 2 || n == 3 {
					// clear entire screen
					for row := 0; row < p.height; row++ {
						for col := 0; col < p.width; col++ {
							p.grid[row][col] = Cell{ch: ` `}
						}
					}
					p.cur_x = 0
					p.cur_y = 0
				}
			}
			`K` {
				// Erase in Line
				n := if params_str != '' { params_str.int() } else { 0 }
				if p.cur_y < p.height {
					if n == 0 {
						for col := p.cur_x; col < p.width; col++ {
							p.grid[p.cur_y][col] = Cell{ch: ` `}
						}
					} else if n == 1 {
						for col := 0; col <= p.cur_x && col < p.width; col++ {
							p.grid[p.cur_y][col] = Cell{ch: ` `}
						}
					} else if n == 2 {
						for col := 0; col < p.width; col++ {
							p.grid[p.cur_y][col] = Cell{ch: ` `}
						}
					}
				}
			}
			`m` {
				// SGR — store verbatim
				if params_str == '' || params_str == '0' {
					p.cur_sgr = ''
				} else {
					p.cur_sgr = '\x1b[${params_str}m'
				}
			}
			`h`, `l` {
				// Mode set/reset (e.g., ?25h show cursor, ?25l hide cursor) — ignore
			}
			`r` {
				// Set Scrolling Region — ignore for now
			}
			`s` {
				// Save cursor position — ignore
			}
			`u` {
				// Restore cursor position — ignore
			}
			else {
				// Unknown sequence — discard
			}
		}
		return
	}

	// ESC ( B  etc. — character set — ignore
	// ESC = / > — keypad mode — ignore
	// ESC 7 / 8 — save/restore cursor — ignore
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

		match b {
			0x1b {
				p.in_esc  = true
				p.esc_buf = ''
			}
			`\r` {
				p.cur_x = 0
			}
			`\n` {
				p.cur_y++
				if p.cur_y >= p.height {
					p.scroll_up()
					p.cur_y = p.height - 1
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
				if b >= 0x20 {
					p.put_char(rune(b))
				}
			}
		}
		i++
	}
	p.dirty = true
}
