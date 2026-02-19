module mux

pub enum MuxAction {
	passthrough   // forward bytes to active pane as-is
	split_v       // Ctrl+V + |  → vertical split (left/right)
	split_h       // Ctrl+V + -  → horizontal split (top/bottom)
	nav_left      // Ctrl+V + ←
	nav_right     // Ctrl+V + →
	nav_up        // Ctrl+V + ↑
	nav_down      // Ctrl+V + ↓
	resize_left   // Ctrl+V + Ctrl+←
	resize_right  // Ctrl+V + Ctrl+→
	resize_up     // Ctrl+V + Ctrl+↑
	resize_down   // Ctrl+V + Ctrl+↓
	close_pane    // Ctrl+V + x
	quit_mux      // Ctrl+V + q
	send_prefix   // Ctrl+V + Ctrl+V  → send \x16 to pane
	none
}

enum InputState {
	normal
	prefix_wait
}

pub struct InputHandler {
mut:
	state InputState
}

// handle parses a chunk of bytes from stdin and returns the corresponding MuxAction.
// If the action is .passthrough, the caller should forward the original bytes to the active pane.
pub fn (mut h InputHandler) handle(bytes []u8) MuxAction {
	if bytes.len == 0 { return .none }

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
		`x`  { return .close_pane }
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
	}

	return .passthrough
}
