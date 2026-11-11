module exec

#include "@VMODROOT/exec/process_helpers.h"

@[typedef]
struct C.VlshRedirect {
	fd     int
	op     int
	target int
	path   &char
}

fn C.vlsh_push_redirects(ops &C.VlshRedirect, count int, saved &int, flags &int) int
fn C.vlsh_restore_fds(saved &int, flags &int)

enum RedirectOp {
	input
	output
	append
	duplicate
	close
}

pub struct Redirect {
pub:
	fd     int
	path   string
	op     RedirectOp
	target int
}

pub fn parse_redirect(operator string, word string) !Redirect {
	mut n := 0
	for n < operator.len && operator[n].is_digit() {
		n++
	}
	op := operator[n..]
	fd := if n > 0 {
		operator[..n].int()
	} else if op.starts_with('<') { 0 } else { 1 }
	if fd < 0 || fd > 9 || n > 9 {
		return error('redirection descriptor out of range: ${operator}')
	}
	if op in ['>&', '<&'] {
		if word == '-' {
			return Redirect{ fd: fd, op: .close }
		}
		if word.len == 0 || word.len > 9 || !word.bytes().all(it.is_digit()) || word.int() > 9 {
			return error('invalid redirection descriptor: ${word}')
		}
		return Redirect{ fd: fd, op: .duplicate, target: word.int() }
	}
	mode := match op {
		'<' { RedirectOp.input }
		'>' { RedirectOp.output }
		'>>' { RedirectOp.append }
		else { return error('unsupported redirection: ${operator}') }
	}
	return Redirect{ fd: fd, op: mode, path: word }
}

fn c_redirects(redirects []Redirect) []C.VlshRedirect {
	mut ops := []C.VlshRedirect{cap: redirects.len}
	for r in redirects {
		ops << C.VlshRedirect{
			fd:     r.fd
			op:     int(r.op)
			target: r.target
			path:   if r.op in [.duplicate, .close] { unsafe { nil } } else { &char(r.path.str) }
		}
	}
	return ops
}

pub struct SavedFds {
mut:
	fds   [10]int
	flags [10]int
}

// push_redirects applies redirections to a builtin in the current shell.
pub fn push_redirects(redirects []Redirect) ?SavedFds {
	ops := c_redirects(redirects)
	mut saved := SavedFds{}
	if C.vlsh_push_redirects(ops.data, ops.len, &saved.fds[0], &saved.flags[0]) < 0 {
		return none
	}
	return saved
}

pub fn (mut saved SavedFds) restore() {
	C.vlsh_restore_fds(&saved.fds[0], &saved.flags[0])
}
