module mux

#flag -lutil
#flag -I @VMODROOT/mux
#include "pty_helpers.h"

fn C.openpty(amaster &int, aslave &int, name &char, termp voidptr, winp voidptr) int
fn C.forkpty(amaster &int, name &char, termp voidptr, winp voidptr) int
fn C.read(fd int, buf voidptr, count usize) int
fn C.write(fd int, buf voidptr, count usize) int
fn C.close(fd int) int
fn C.kill(pid int, sig int) int
fn C.waitpid(pid int, status &int, options int) int

fn C.vlsh_enter_raw(orig_buf voidptr) int
fn C.vlsh_restore_term(orig_buf voidptr) int
fn C.vlsh_set_pty_size(fd int, rows int, cols int)
fn C.vlsh_get_term_size(rows &int, cols &int)
fn C.vlsh_select_readable(fds &int, nfds int, out_readable &int, timeout_ms int) int
fn C.vlsh_exec(path &char)
fn C.vlsh_install_sigwinch()
fn C.vlsh_check_sigwinch() int

// termios_buf_size must be >= sizeof(struct termios). On Linux x86-64 it is 60 bytes.
const termios_buf_size = 64

// open_pty creates a new PTY pair, returning (master_fd, slave_fd).
pub fn open_pty() !(int, int) {
	mut master := int(0)
	mut slave  := int(0)
	ret := C.openpty(&master, &slave, unsafe { nil }, unsafe { nil }, unsafe { nil })
	if ret < 0 {
		return error('openpty failed')
	}
	return master, slave
}

// set_pty_size resizes the PTY to the given dimensions.
pub fn set_pty_size(fd int, rows int, cols int) {
	C.vlsh_set_pty_size(fd, rows, cols)
}

// get_term_size returns the current terminal dimensions (rows, cols).
pub fn get_term_size() (int, int) {
	mut rows := int(0)
	mut cols := int(0)
	C.vlsh_get_term_size(&rows, &cols)
	return rows, cols
}

// enter_raw_mode puts stdin into raw mode and returns an opaque saved-state buffer.
pub fn enter_raw_mode() ![]u8 {
	mut buf := []u8{len: termios_buf_size}
	if C.vlsh_enter_raw(buf.data) < 0 {
		return error('could not enter raw mode')
	}
	return buf
}

// restore_terminal restores the terminal from a saved-state buffer.
pub fn restore_terminal(orig []u8) {
	mut buf := orig.clone()
	C.vlsh_restore_term(buf.data)
}

// mux_select wraps select() and returns the subset of fds that are readable.
pub fn mux_select(fds []int, timeout_ms int) []int {
	if fds.len == 0 {
		return []int{}
	}
	mut fds_copy := fds.clone()
	mut readable := []int{len: fds.len}
	n := C.vlsh_select_readable(fds_copy.data, fds_copy.len, readable.data, timeout_ms)
	if n <= 0 {
		return []int{}
	}
	return readable[..n].clone()
}

// install_sigwinch installs the SIGWINCH handler.
pub fn install_sigwinch() {
	C.vlsh_install_sigwinch()
}

// check_sigwinch returns true (and clears the flag) if SIGWINCH was received.
pub fn check_sigwinch() bool {
	return C.vlsh_check_sigwinch() != 0
}
