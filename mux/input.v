module mux

import time

pub enum MuxAction {
	passthrough        // forward bytes to active pane as-is
	split_v            // Ctrl+V + |  → vertical split (left/right)
	split_h            // Ctrl+V + -  → horizontal split (top/bottom)
	nav_left           // Ctrl+V + ←
	nav_right          // Ctrl+V + →
	nav_up             // Ctrl+V + ↑
	nav_down           // Ctrl+V + ↓
	resize_left        // Ctrl+V + Ctrl+←
	resize_right       // Ctrl+V + Ctrl+→
	resize_up          // Ctrl+V + Ctrl+↑
	resize_down        // Ctrl+V + Ctrl+↓
	close_pane         // auto-close when pane process exits
	quit_mux           // Ctrl+V + q
	send_prefix        // Ctrl+V + Ctrl+V  → send \x16 to pane
	cycle_pane         // Ctrl+V + o  → cycle focus to next pane
	mouse_left_press   // left button down — start/reset selection
	mouse_left_release // left button up   — finalise selection & copy
	mouse_motion       // motion while left button held — extend selection
	mouse_middle_press // middle button down → paste clipboard
	scroll_pane_up     // mouse wheel up or Ctrl+V+PageUp — scroll active pane back
	scroll_pane_down   // mouse wheel down or Ctrl+V+PageDown — scroll active pane forward
	none
}

enum InputState {
	normal
	prefix_wait
}

pub struct InputHandler {
pub mut:
	state          InputState
	click_col      int  // 0-based terminal column of the last mouse event
	click_row      int  // 0-based terminal row of the last mouse event
	is_double_click bool // true when the current left press is a double-click
	last_press_col int
	last_press_row int
	last_press_ms  i64
}

// handle parses a chunk of bytes from stdin and returns the corresponding MuxAction.
// If the action is .passthrough, the caller should forward the original bytes to the active pane.
pub fn (mut h InputHandler) handle(bytes []u8) MuxAction {
	if bytes.len == 0 { return .none }

	// SGR extended mouse event: ESC [ < Cb ; Cx ; Cy M  (press/motion)
	//                       or: ESC [ < Cb ; Cx ; Cy m  (release)
	// Enabled by ?1002h (button-event tracking) + ?1006h (SGR extended coords).
	//
	// Cb values:
	//   0 = left press/release   1 = middle press/release   2 = right press/release
	//  32 = left drag (motion while left held)
	if bytes.len >= 7 && bytes[0] == 0x1b && bytes[1] == u8(`[`) && bytes[2] == u8(`<`) {
		mut end_pos := -1
		mut is_release := false
		for k := 3; k < bytes.len; k++ {
			if bytes[k] == u8(`M`) {
				end_pos = k
				is_release = false
				break
			}
			if bytes[k] == u8(`m`) {
				end_pos = k
				is_release = true
				break
			}
		}
		if end_pos > 3 {
			params := bytes[3..end_pos].bytestr()
			parts := params.split(';')
			if parts.len == 3 {
				cb := parts[0].int()
				h.click_col = parts[1].int() - 1 // convert to 0-based
				h.click_row = parts[2].int() - 1

				// Mouse wheel up (cb=64) / down (cb=65)
				if cb == 64 {
					return .scroll_pane_up
				}
				if cb == 65 {
					return .scroll_pane_down
				}
				// Middle button
				if cb == 1 && !is_release {
					return .mouse_middle_press
				}
				// Left drag (motion while left held)
				if cb == 32 {
					return .mouse_motion
				}
				// Left button
				if cb == 0 {
					if is_release {
						return .mouse_left_release
					}
					// Detect double-click: same cell within 400 ms
					now_ms := time.now().unix_milli()
					h.is_double_click = (now_ms - h.last_press_ms < 400
						&& h.click_col == h.last_press_col
						&& h.click_row == h.last_press_row)
					h.last_press_col = h.click_col
					h.last_press_row = h.click_row
					h.last_press_ms  = now_ms
					return .mouse_left_press
				}
			}
		}
		return .none
	}

	if h.state == .normal {
		// Ctrl+V = 0x16
		if bytes[0] == 0x16 {
			h.state = .prefix_wait
			return .none
		}
		return .passthrough
	}

	// h.state == .prefix_wait
	h.state = .normal

	if bytes.len == 0 { return .none }
	b := bytes[0]

	// Ctrl+V again → send literal \x16 to the active pane
	if b == 0x16 { return .send_prefix }

	// Single-byte commands
	match b {
		`|`  { return .split_v }
		`-`  { return .split_h }
		`o`  { return .cycle_pane }
		`q`  { return .quit_mux }
		else {}
	}

	// Arrow key sequences: ESC [ A/B/C/D  (plain arrows)
	//                  or  ESC [ 1 ; 5 A/B/C/D  (Ctrl+arrow)
	if bytes.len >= 3 && bytes[0] == 0x1b && bytes[1] == `[` {
		if bytes.len == 3 {
			match bytes[2] {
				`A` { return .nav_up }
				`B` { return .nav_down }
				`C` { return .nav_right }
				`D` { return .nav_left }
				else {}
			}
		}
		// Ctrl+Arrow: ESC [ 1 ; 5 A/B/C/D
		if bytes.len >= 6 && bytes[2] == `1` && bytes[3] == `;` && bytes[4] == `5` {
			match bytes[5] {
				`A` { return .resize_up }
				`B` { return .resize_down }
				`C` { return .resize_right }
				`D` { return .resize_left }
				else {}
			}
		}
		// Page Up (ESC [ 5 ~) / Page Down (ESC [ 6 ~)
		if bytes.len >= 4 && bytes[3] == `~` {
			if bytes[2] == `5` { return .scroll_pane_up }
			if bytes[2] == `6` { return .scroll_pane_down }
		}
	}

	return .passthrough
}
