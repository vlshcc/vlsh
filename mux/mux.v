module mux

import os
import strings
import cfg

// Selection represents the current text selection within a pane.
pub struct Selection {
pub:
	active    bool
	pane_id   int
	start_col int
	start_row int
	end_col   int
	end_row   int
}

pub struct Mux {
mut:
	panes     []Pane
	layout    LayoutNode
	active_id int
	next_id   int
	term_w    int
	term_h    int
	orig_term []u8
	input     InputHandler
	dirty     bool
	// Status-bar background colour [r, g, b]
	bar_bg    []int
	// Text selection state
	sel_active    bool
	sel_pane_id   int
	sel_start_col int
	sel_start_row int
	sel_end_col   int
	sel_end_row   int
	clipboard     string
}

// enter is the public entry point for the multiplexer.
pub fn enter() {
	if os.getenv('VLSH_IN_MUX') != '' {
		println('mux: already inside a mux session')
		return
	}

	rows, cols := get_term_size()

	orig := enter_raw_mode() or {
		println('mux: could not enter raw mode: ${err}')
		return
	}

	// Hide cursor, clear screen, enable button-event tracking + SGR extended mouse
	print('\x1b[?25l\x1b[2J\x1b[H\x1b[?1002h\x1b[?1006h')

	// Install SIGWINCH handler
	install_sigwinch()

	// Read status-bar colour from user config (fall back to #2c7c43 if absent)
	style_data := cfg.style() or { map[string][]int{} }
	bar_bg := if 'style_mux_bar_bg' in style_data {
		style_data['style_mux_bar_bg']
	} else {
		[44, 124, 67]
	}

	mut m := Mux{
		term_w:    cols
		term_h:    rows
		orig_term: orig
		next_id:   1
		dirty:     true
		bar_bg:    bar_bg
	}

	if !m.spawn_first_pane() {
		restore_terminal(orig)
		print('\x1b[?25h')
		println('mux: failed to create first pane')
		return
	}

	m.run()

	restore_terminal(orig)
	// Disable mouse tracking, restore cursor, clear screen
	print('\x1b[?1006l\x1b[?1002l\x1b[?25h\x1b[2J\x1b[H')
	println('Exited mux mode')
}

// spawn_first_pane creates the initial pane that fills the whole terminal.
fn (mut m Mux) spawn_first_pane() bool {
	vlsh_exe := os.executable()
	mut master := int(0)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return false }
	if pid == 0 {
		// Child — the pane occupies term_h-1 rows (row 0 is the status bar)
		os.setenv('VLSH_IN_MUX', '1', true)
		C.vlsh_set_pty_size(0, m.term_h - 1, m.term_w)
		exe_cstr := &char(vlsh_exe.str)
		C.vlsh_exec(exe_cstr)
	}
	// Parent
	id := m.next_id
	m.next_id++
	set_pty_size(master, m.term_h - 1, m.term_w)
	p := new_pane(id, master, pid, 0, 1, m.term_w, m.term_h - 1)
	m.panes << p
	m.active_id = id
	m.layout = new_layout(id, m.term_w, m.term_h - 1)
	m.layout.recalc(0, 1, m.term_w, m.term_h - 1)
	return true
}

// do_split forks a new vlsh child and splits the active pane.
fn (mut m Mux) do_split(dir SplitDir) {
	ax, ay, aw, ah := m.layout.get_geometry(m.active_id)
	if ax < 0 { return }
	if dir == .vertical   && aw < 8 { return }
	if dir == .horizontal && ah < 4 { return }

	vlsh_exe := os.executable()
	mut master := int(0)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return }
	if pid == 0 {
		os.setenv('VLSH_IN_MUX', '1', true)
		C.vlsh_exec(&char(vlsh_exe.str))
	}

	new_id := m.next_id
	m.next_id++
	p := new_pane(new_id, master, pid, ax, ay, aw, ah)
	m.panes << p

	m.layout.split(m.active_id, new_id, dir)
	m.layout.recalc(0, 1, m.term_w, m.term_h - 1)
	m.sync_pane_geometries()
	m.active_id = new_id
	m.dirty = true
}

fn (mut m Mux) do_navigate(dir SplitDir, toward_right bool) {
	neighbor := m.layout.find_neighbor(m.active_id, dir, toward_right)
	if neighbor >= 0 {
		m.active_id = neighbor
		m.dirty = true
	}
}

fn (mut m Mux) do_resize(dir SplitDir, grow bool) {
	delta := if grow { f32(0.05) } else { f32(-0.05) }
	m.layout.adjust_ratio_dir(m.active_id, dir, delta)
	m.layout.recalc(0, 1, m.term_w, m.term_h - 1)
	m.sync_pane_geometries()
	m.dirty = true
}

// do_cycle advances active_id to the next live pane in m.panes order.
fn (mut m Mux) do_cycle() {
	if m.panes.len <= 1 { return }
	mut idx := -1
	for i, p in m.panes {
		if p.id == m.active_id { idx = i; break }
	}
	if idx < 0 { return }
	// Find the next alive pane
	for step := 1; step <= m.panes.len; step++ {
		next := (idx + step) % m.panes.len
		if m.panes[next].alive {
			m.active_id = m.panes[next].id
			m.dirty = true
			return
		}
	}
}

// do_mouse_left_press switches focus to the clicked pane and starts a new selection.
fn (mut m Mux) do_mouse_left_press(col int, row int) {
	for p in m.panes {
		if !p.alive { continue }
		if col >= p.x && col < p.x + p.width && row >= p.y && row < p.y + p.height {
			if m.active_id != p.id {
				m.active_id = p.id
			}
			pane_col := col - p.x
			pane_row := row - p.y
			if m.input.is_double_click {
				// Double-click: select the word under the cursor
				sc, ec := m.word_boundaries(p.id, pane_col, pane_row)
				m.sel_active    = true
				m.sel_pane_id   = p.id
				m.sel_start_col = sc
				m.sel_start_row = pane_row
				m.sel_end_col   = ec
				m.sel_end_row   = pane_row
				m.clipboard = m.extract_selection_text()
			} else {
				// Normal press: start a new drag selection
				m.sel_active    = true
				m.sel_pane_id   = p.id
				m.sel_start_col = pane_col
				m.sel_start_row = pane_row
				m.sel_end_col   = pane_col
				m.sel_end_row   = pane_row
			}
			m.dirty = true
			return
		}
	}
	// Clicked outside any pane — clear selection
	m.sel_active = false
	m.dirty = true
}

// do_mouse_motion extends the selection while the left button is held.
fn (mut m Mux) do_mouse_motion(col int, row int) {
	if !m.sel_active { return }
	for p in m.panes {
		if p.id != m.sel_pane_id { continue }
		pane_col := col - p.x
		pane_row := row - p.y
		// Clamp to pane bounds
		ec := if pane_col < 0 { 0 } else if pane_col >= p.width  { p.width  - 1 } else { pane_col }
		er := if pane_row < 0 { 0 } else if pane_row >= p.height { p.height - 1 } else { pane_row }
		m.sel_end_col = ec
		m.sel_end_row = er
		m.dirty = true
		return
	}
}

// do_mouse_left_release finalises the selection and copies the text to the clipboard.
fn (mut m Mux) do_mouse_left_release(col int, row int) {
	if !m.sel_active { return }
	m.do_mouse_motion(col, row)
	// A zero-size selection (plain click, no drag) clears the selection state.
	if m.sel_start_col == m.sel_end_col && m.sel_start_row == m.sel_end_row {
		m.sel_active = false
	} else {
		m.clipboard = m.extract_selection_text()
	}
	m.dirty = true
}

// do_middle_paste writes the clipboard to the pane under the middle-click.
fn (mut m Mux) do_middle_paste(col int, row int) {
	// Switch focus to the clicked pane (if any)
	for p in m.panes {
		if !p.alive { continue }
		if col >= p.x && col < p.x + p.width && row >= p.y && row < p.y + p.height {
			m.active_id = p.id
			break
		}
	}
	if m.clipboard.len == 0 { return }
	fd := m.active_pane_fd()
	if fd < 0 { return }
	C.write(fd, m.clipboard.str, usize(m.clipboard.len))
}

// extract_selection_text builds a string from the currently selected cells.
fn (m &Mux) extract_selection_text() string {
	for i := 0; i < m.panes.len; i++ {
		p := m.panes[i]
		if p.id != m.sel_pane_id { continue }
		mut r1 := m.sel_start_row
		mut c1 := m.sel_start_col
		mut r2 := m.sel_end_row
		mut c2 := m.sel_end_col
		// Normalise so r1/c1 is before r2/c2 in reading order
		if r1 > r2 || (r1 == r2 && c1 > c2) {
			r1, c1, r2, c2 = r2, c2, r1, c1
		}
		mut sb := strings.new_builder(256)
		for row := r1; row <= r2 && row < p.grid.len; row++ {
			col_start := if row == r1 { c1 } else { 0 }
			col_end   := if row == r2 { c2 } else { p.width - 1 }
			for col := col_start; col <= col_end && col < p.grid[row].len; col++ {
				ch := p.grid[row][col].ch
				if ch == 0 || ch == rune(` `) {
					sb.write_u8(u8(` `))
				} else {
					sb.write_string(ch.str())
				}
			}
			if row < r2 {
				sb.write_u8(u8(`\n`))
			}
		}
		return sb.str()
	}
	return ''
}

// word_boundaries returns (start_col, end_col) of the word at (col, row) in the given pane.
fn (m &Mux) word_boundaries(pane_id int, col int, row int) (int, int) {
	for i := 0; i < m.panes.len; i++ {
		p := m.panes[i]
		if p.id != pane_id { continue }
		if row < 0 || row >= p.grid.len          { return col, col }
		if col < 0 || col >= p.grid[row].len     { return col, col }
		ch := p.grid[row][col].ch
		// Clicking on whitespace selects only that cell
		if ch == rune(` `) || ch == 0            { return col, col }
		mut start_col := col
		mut end_col   := col
		// Expand left
		for start_col > 0 {
			prev := p.grid[row][start_col - 1].ch
			if prev == rune(` `) || prev == 0 { break }
			start_col--
		}
		// Expand right
		for end_col < p.grid[row].len - 1 {
			next := p.grid[row][end_col + 1].ch
			if next == rune(` `) || next == 0 { break }
			end_col++
		}
		return start_col, end_col
	}
	return col, col
}

fn (mut m Mux) do_close() {
	// If the closing pane owns the selection, clear it.
	if m.sel_pane_id == m.active_id {
		m.sel_active = false
	}

	mut idx := -1
	for i, p in m.panes {
		if p.id == m.active_id { idx = i; break }
	}
	if idx < 0 { return }

	p := m.panes[idx]
	// Try a non-blocking reap first; the process may have already exited.
	// WNOHANG = 1
	mut status := int(0)
	if C.waitpid(p.pid, &status, 1) == 0 {
		// Still running — send SIGTERM and do a blocking wait.
		C.kill(p.pid, 15)
		C.waitpid(p.pid, &status, 0)
	}
	C.close(p.master_fd)
	m.panes.delete(idx)

	if m.panes.len == 0 { return }

	m.layout.remove(m.active_id)
	m.layout.recalc(0, 1, m.term_w, m.term_h - 1)
	m.active_id = m.panes[0].id
	m.sync_pane_geometries()
	m.dirty = true
}

fn (mut m Mux) sync_pane_geometries() {
	for mut p in m.panes {
		x, y, w, h := m.layout.get_geometry(p.id)
		if x >= 0 && w > 0 && h > 0 {
			p.resize(x, y, w, h)
			set_pty_size(p.master_fd, h, w)
		}
	}
}

fn (m &Mux) active_pane_fd() int {
	for p in m.panes {
		if p.id == m.active_id { return p.master_fd }
	}
	return -1
}

fn (m &Mux) current_selection() Selection {
	return Selection{
		active:    m.sel_active
		pane_id:   m.sel_pane_id
		start_col: m.sel_start_col
		start_row: m.sel_start_row
		end_col:   m.sel_end_col
		end_row:   m.sel_end_row
	}
}

fn (mut m Mux) run() {
	mut buf := []u8{len: 4096}

	for {
		if m.panes.len == 0 { break }

		mut fds := [0] // stdin
		for p in m.panes {
			if p.alive { fds << p.master_fd }
		}

		readable := mux_select(fds, 5)

		// Handle stdin
		if 0 in readable {
			n := C.read(0, buf.data, usize(256))
			if n > 0 {
				input_bytes := buf[..n].clone()
				action := m.input.handle(input_bytes)
				match action {
					.passthrough {
						fd := m.active_pane_fd()
						if fd >= 0 {
							C.write(fd, input_bytes.data, usize(input_bytes.len))
						}
					}
					.send_prefix {
						fd := m.active_pane_fd()
						if fd >= 0 {
							mut pb := [u8(0x16)]
							C.write(fd, pb.data, usize(1))
						}
					}
					.split_v      { m.do_split(.vertical) }
					.split_h      { m.do_split(.horizontal) }
					.nav_left     { m.do_navigate(.vertical,   false) }
					.nav_right    { m.do_navigate(.vertical,   true) }
					.nav_up       { m.do_navigate(.horizontal, false) }
					.nav_down     { m.do_navigate(.horizontal, true) }
					.resize_left  { m.do_resize(.vertical,   false) }
					.resize_right { m.do_resize(.vertical,   true) }
					.resize_up    { m.do_resize(.horizontal, false) }
					.resize_down  { m.do_resize(.horizontal, true) }
					.close_pane   {
						m.do_close()
						if m.panes.len == 0 { break }
					}
					.cycle_pane         { m.do_cycle() }
					.mouse_left_press   { m.do_mouse_left_press(m.input.click_col, m.input.click_row) }
					.mouse_motion       { m.do_mouse_motion(m.input.click_col, m.input.click_row) }
					.mouse_left_release { m.do_mouse_left_release(m.input.click_col, m.input.click_row) }
					.mouse_middle_press { m.do_middle_paste(m.input.click_col, m.input.click_row) }
					.quit_mux     { break }
					.none         {}
				}
			}
		}

		// Read from pane PTYs
		for mut p in m.panes {
			if !p.alive { continue }
			if p.master_fd in readable {
				n := C.read(p.master_fd, buf.data, usize(4096))
				if n <= 0 {
					p.alive   = false
					m.active_id = p.id
					m.do_close()
					if m.panes.len == 0 { break }
				} else {
					p.feed(buf[..n].clone())
				}
			}
		}

		if m.panes.len == 0 { break }

		// Handle terminal resize
		if check_sigwinch() {
			rows, cols := get_term_size()
			m.term_w = cols
			m.term_h = rows
			m.layout.recalc(0, 1, cols, rows - 1)
			m.sync_pane_geometries()
			m.dirty = true
		}

		// Render
		sel := m.current_selection()
		if m.dirty {
			render_all(m.panes, &m.layout, m.active_id, m.term_w, m.term_h, sel, m.bar_bg)
			for mut p in m.panes { p.dirty = false }
			m.dirty = false
		} else {
			render_dirty(mut m.panes, &m.layout, m.active_id, m.term_w, m.term_h, sel, m.bar_bg)
		}
	}
}
