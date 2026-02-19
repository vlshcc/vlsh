module mux

// ---------------------------------------------------------------------------
// InputHandler — prefix key is Ctrl+V (0x16)
// ---------------------------------------------------------------------------

fn test_handle_empty_bytes_returns_none() {
	mut h := InputHandler{}
	assert h.handle([]) == .none
}

fn test_handle_regular_byte_is_passthrough() {
	mut h := InputHandler{}
	assert h.handle([u8(`a`)]) == .passthrough
}

fn test_handle_non_prefix_control_byte_is_passthrough() {
	mut h := InputHandler{}
	// Ctrl+A (0x01) is no longer the prefix — it must pass through
	assert h.handle([u8(0x01)]) == .passthrough
}

fn test_handle_prefix_alone_returns_none() {
	mut h := InputHandler{}
	// Ctrl+V alone just arms the prefix state; no action yet
	assert h.handle([u8(0x16)]) == .none
}

fn test_handle_prefix_then_pipe_splits_vertically() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(`|`)]) == .split_v
}

fn test_handle_prefix_then_dash_splits_horizontally() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(`-`)]) == .split_h
}

fn test_handle_prefix_then_x_closes_pane() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(`x`)]) == .close_pane
}

fn test_handle_prefix_then_q_quits_mux() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(`q`)]) == .quit_mux
}

fn test_handle_prefix_then_ctrl_v_sends_prefix_byte() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x16)]) == .send_prefix
}

fn test_handle_prefix_then_arrow_up_navigates_up() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`A`)]) == .nav_up
}

fn test_handle_prefix_then_arrow_down_navigates_down() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`B`)]) == .nav_down
}

fn test_handle_prefix_then_arrow_right_navigates_right() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`C`)]) == .nav_right
}

fn test_handle_prefix_then_arrow_left_navigates_left() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`D`)]) == .nav_left
}

fn test_handle_prefix_then_ctrl_arrow_up_resizes_up() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`1`), u8(`;`), u8(`5`), u8(`A`)]) == .resize_up
}

fn test_handle_prefix_then_ctrl_arrow_down_resizes_down() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`1`), u8(`;`), u8(`5`), u8(`B`)]) == .resize_down
}

fn test_handle_prefix_then_ctrl_arrow_right_resizes_right() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`1`), u8(`;`), u8(`5`), u8(`C`)]) == .resize_right
}

fn test_handle_prefix_then_ctrl_arrow_left_resizes_left() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	assert h.handle([u8(0x1b), u8(`[`), u8(`1`), u8(`;`), u8(`5`), u8(`D`)]) == .resize_left
}

fn test_handle_prefix_then_unknown_byte_is_passthrough() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	// 'z' is not a bound key after the prefix
	assert h.handle([u8(`z`)]) == .passthrough
}

fn test_handle_state_resets_after_each_command() {
	mut h := InputHandler{}
	h.handle([u8(0x16)])
	h.handle([u8(`|`)]) // split_v — consumes prefix state
	// Next regular byte should be passthrough, not a command
	assert h.handle([u8(`q`)]) == .passthrough
}

fn test_handle_prefix_must_be_followed_by_second_call() {
	// Prefix and command in the SAME byte slice still requires two calls
	// because handle() checks bytes[0] and transitions state.
	// If the first byte is the prefix, the rest of the slice is ignored.
	mut h := InputHandler{}
	result := h.handle([u8(0x16), u8(`|`)])
	// Single-call with prefix only arms the state; the '|' is not processed
	assert result == .none
	// Second call with '|' now fires split_v
	assert h.handle([u8(`|`)]) == .split_v
}
