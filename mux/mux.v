module mux

import os

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

	// Hide cursor, clear screen
	print('\x1b[?25l\x1b[2J\x1b[H')

	// Install SIGWINCH handler
	install_sigwinch()

	mut m := Mux{
		term_w:    cols
		term_h:    rows
		orig_term: orig
		next_id:   1
		dirty:     true
	}

	if !m.spawn_first_pane() {
		restore_terminal(orig)
		print('\x1b[?25h')
		println('mux: failed to create first pane')
		return
	}

	m.run()

	restore_terminal(orig)
	print('\x1b[?25h\x1b[2J\x1b[H')
}

// spawn_first_pane creates the initial pane that fills the whole terminal.
fn (mut m Mux) spawn_first_pane() bool {
	vlsh_exe := os.executable()
	mut master := int(0)
	pid := C.forkpty(&master, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if pid < 0 { return false }
	if pid == 0 {
		// Child
		os.setenv('VLSH_IN_MUX', '1', true)
		C.vlsh_set_pty_size(0, m.term_h, m.term_w)
		exe_cstr := &char(vlsh_exe.str)
		C.vlsh_exec(exe_cstr)
	}
	// Parent
	id := m.next_id
	m.next_id++
	set_pty_size(master, m.term_h, m.term_w)
	p := new_pane(id, master, pid, 0, 0, m.term_w, m.term_h)
	m.panes << p
	m.active_id = id
	m.layout = new_layout(id, m.term_w, m.term_h)
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
	m.layout.recalc(0, 0, m.term_w, m.term_h)
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
	m.layout.recalc(0, 0, m.term_w, m.term_h)
	m.sync_pane_geometries()
	m.dirty = true
}

fn (mut m Mux) do_close() {
	mut idx := -1
	for i, p in m.panes {
		if p.id == m.active_id { idx = i; break }
	}
	if idx < 0 { return }

	p := m.panes[idx]
	C.kill(p.pid, 15) // SIGTERM
	mut status := int(0)
	C.waitpid(p.pid, &status, 0)
	C.close(p.master_fd)
	m.panes.delete(idx)

	if m.panes.len == 0 { return }

	m.layout.remove(m.active_id)
	m.layout.recalc(0, 0, m.term_w, m.term_h)
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

fn (mut m Mux) run() {
	mut buf := []u8{len: 4096}

	for {
		if m.panes.len == 0 { break }

		mut fds := [0] // stdin
		for p in m.panes {
			if p.alive { fds << p.master_fd }
		}

		readable := mux_select(fds, 50)

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
			m.layout.recalc(0, 0, cols, rows)
			m.sync_pane_geometries()
			m.dirty = true
		}

		// Render
		if m.dirty {
			render_all(m.panes, &m.layout, m.active_id, m.term_w, m.term_h)
			for mut p in m.panes { p.dirty = false }
			m.dirty = false
		} else {
			render_dirty(mut m.panes, &m.layout, m.active_id, m.term_w, m.term_h)
		}
	}
}
