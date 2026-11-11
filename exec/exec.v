module exec

import os
import strings
import utils

// C signal API — used to protect vlsh from SIGINT while a child process runs.
#include "@VMODROOT/exec/process_helpers.h"

fn C.vlsh_pipe(fds &i32) int
fn C.vlsh_spawn(path &char, argv &&char, env &&char, input int, output int, next_read int, ops &C.VlshRedirect, count int, failure int, message &char) int
fn C.vlsh_wait(pid int) int
fn C.vlsh_read(fd int, buffer voidptr, size usize) int

fn C.signal(signum int, handler voidptr) voidptr

pub struct Cmd_object {
pub mut:
	cmd         string
	fullcmd     string
	args        []string
	path        string
	aliases     map[string]string
	redirects   []Redirect
	assignments map[string]string
	search_path ?string
	no_command  bool
	environment ?map[string]string
	failure     int
	diagnostic  string
}

pub struct Task {
pub mut:
	// Operator provenance is retained from the first and only parse.
	tokens         []utils.ShellToken
	cmd            Cmd_object
	pipe_cmds      []Cmd_object
	last_exit_code int
	// Captured pipeline-tail stdout; standalone commands inherit the terminal.
	last_output string
}

pub fn (mut t Task) prepare_task() !int {
	t.last_output = ''
	t.pipe_cmds = []Cmd_object{}
	t.parse_pipe()!
	return t.exec()
}

// expand_tilde expands a leading ~ or ~/ to the user's home directory.
pub fn expand_tilde(s string) string {
	if s == '~' {
		return os.home_dir()
	}
	if s.starts_with('~/') {
		return os.home_dir() + s[1..]
	}
	return s
}

fn (mut t Task) parse_pipe() ! {
	mut tokens := t.tokens.clone()
	if tokens.len == 0 {
		// Compatibility for callers that already supply parsed argument strings.
		tokens << utils.ShellToken{ text: t.cmd.cmd }
		for arg in t.cmd.args {
			tokens << utils.ShellToken{
				text:     expand_tilde(arg)
				operator: arg in ['|', '>', '>>', '<', '2>&1']
			}
		}
	}
	mut stages := []Cmd_object{}
	mut stage := Cmd_object{ aliases: t.cmd.aliases }
	mut words := []string{}
	mut i := 0
	for i < tokens.len {
		token := tokens[i]
		if token.operator && token.text == '|' {
			if words.len == 0 {
				return error('syntax error: empty pipeline stage')
			}
			stage.cmd = words[0]
			stage.args = words[1..].clone()
			stages << stage
			stage = Cmd_object{ aliases: t.cmd.aliases }
			words = []string{}
		} else if token.operator && utils.is_redirection(token.text) {
			if i + 1 >= tokens.len || tokens[i + 1].operator {
				return error('syntax error: missing redirection target')
			}
			i++
			stage.redirects << parse_redirect(token.text, tokens[i].text)!
		} else {
			words << token.text
		}
		i++
	}
	if words.len == 0 {
		return error('syntax error: empty pipeline stage')
	}
	stage.cmd = words[0]
	stage.args = words[1..].clone()
	stages << stage
	t.cmd = stages[0]
	if stages.len > 1 {
		t.pipe_cmds = stages[1..].clone()
	}
}

// Start every stage before waiting so producers and consumers can stream.
// Stderr inherits the terminal unless explicitly merged into stdout.
fn (mut t Task) exec() !int {
	mut stages := [t.cmd]
	stages << t.pipe_cmds
	return t.run_stages(stages)
}

pub fn (mut t Task) run_stages(stages []Cmd_object) !int {
	t.last_output = ''
	t.last_exit_code = 0
	mut pids := []int{}
	mut input_fd := -1
	mut capture_fd := -1
	mut finished := false
	old_int := unsafe { C.signal(C.SIGINT, voidptr(1)) }
	old_quit := unsafe { C.signal(C.SIGQUIT, voidptr(1)) }
	defer {
		if input_fd >= 0 { C.close(input_fd) }
		if capture_fd >= 0 { C.close(capture_fd) }
		if !finished {
			for pid in pids {
				C.kill(pid, C.SIGKILL)
			}
		}
		for pid in pids {
			C.vlsh_wait(pid)
		}
		unsafe { C.signal(C.SIGINT, old_int) }
		unsafe { C.signal(C.SIGQUIT, old_quit) }
	}
	for index, command in stages {
		mut stage := command
		mut failure := stage.failure
		mut message := stage.diagnostic
		if failure == 0 && stage.fullcmd == '' && !stage.no_command {
			stage.handle_aliases()
			stage.find_exe() or {
				failure = err.code()
				if failure == 0 {
					failure = 126
				}
				message = 'vlsh: ${err.msg()}\n'
			}
			if failure == 0 { stage.internal_cmd_modifiers() }
		}
		mut output_fd := -1
		mut next_fd := -1
		if stages.len > 1 {
			mut fds := [2]i32{}
			if C.vlsh_pipe(&fds[0]) < 0 {
				return error('cannot create pipeline')
			}
			next_fd = int(fds[0])
			output_fd = int(fds[1])
		}
		mut argv := []&char{}
		argv << &char(stage.fullcmd.str)
		for arg in stage.args {
			argv << &char(arg.str)
		}
		argv << unsafe { &char(nil) }
		mut child_env := if env := stage.environment { env.clone() } else { os.environ() }
		for key, value in stage.assignments {
			child_env[key] = value
		}
		entries := child_env.keys().map('${it}=${child_env[it]}')
		mut env := []&char{cap: entries.len + 1}
		for entry in entries {
			env << &char(entry.str)
		}
		env << unsafe { &char(nil) }
		ops := c_redirects(stage.redirects)
		path := if stage.fullcmd == '' { unsafe { &char(nil) } } else { &char(stage.fullcmd.str) }
		pid := C.vlsh_spawn(path, argv.data, env.data, input_fd, output_fd, next_fd,
			ops.data, ops.len, failure, &char(message.str))
		if input_fd >= 0 {
			C.close(input_fd)
			input_fd = -1
		}
		if output_fd >= 0 { C.close(output_fd) }
		if pid < 0 {
			if next_fd >= 0 { C.close(next_fd) }
			return error('cannot start command: ${stage.cmd}')
		}
		pids << pid
		if index < stages.len - 1 {
			input_fd = next_fd
		} else {
			capture_fd = next_fd
		}
	}
	if capture_fd >= 0 {
		mut output := strings.new_builder(1024)
		mut buf := []u8{len: 8192}
		for {
			n := C.vlsh_read(capture_fd, buf.data, usize(buf.len))
			if n < 0 {
				return error('cannot read pipeline output')
			}
			if n == 0 {
				break
			}
			chunk := buf[..int(n)].bytestr()
			output.write_string(chunk)
			print(chunk)
		}
		t.last_output = output.str()
		C.close(capture_fd)
		capture_fd = -1
	}
	for pid in pids {
		t.last_exit_code = C.vlsh_wait(pid)
	}
	finished = true
	pids.clear()
	return t.last_exit_code
}

fn (mut c Cmd_object) handle_aliases() {
	if alias_key_exists(c.cmd, c.aliases) {
		original_args := c.args.clone()
		alias_split := utils.parse_args(c.aliases[c.cmd])
		if alias_split.len == 0 {
			return
		}
		c.cmd = alias_split[0]
		c.args = alias_split[1..].clone()
		c.args << original_args
		utils.debug('found $c.cmd in $c.aliases')
		utils.debug('will try to run $c.cmd with $c.args')
	}
}

fn alias_key_exists(key string, aliases map[string]string) bool {
	for i, _ in aliases {
		if i == key {
			return true
		}
	}

	return false
}

pub fn get_search_paths() []string {
	paths := os.getenv('PATH').split(':').filter(it.len > 0)
	if paths.len > 0 {
		return paths
	}
	return ['/usr/local/bin', '/usr/bin', '/bin']
}

// path_command_completions returns bare command names from $PATH that start with prefix.
// Names containing '/' are not handled here (those use path-style resolution).
pub fn path_command_completions(prefix string) []string {
	if prefix.contains('/') {
		return []string{}
	}
	mut seen := map[string]bool{}
	mut out := []string{}
	for dir in get_search_paths() {
		if !os.exists(dir) || !os.is_dir(dir) {
			continue
		}
		entries := os.ls(dir) or { continue }
		for name in entries {
			if prefix.len > 0 && !name.starts_with(prefix) {
				continue
			}
			if seen[name] {
				continue
			}
			full := '${dir}/${name}'
			if !os.is_file(full) || !os.is_executable(full) {
				continue
			}
			seen[name] = true
			out << name
		}
	}
	out.sort()
	return out
}

fn (mut c Cmd_object) find_exe() ! {
	expanded_cmd := c.cmd

	is_direct := expanded_cmd.contains('/')

	if is_direct {
		if !os.exists(expanded_cmd) {
			return error_with_code('${expanded_cmd}: no such file or directory', 127)
		}
		if expanded_cmd.ends_with('.vsh') {
			c.use_v_run(expanded_cmd)!
			return
		}
		if !os.is_file(expanded_cmd) || !os.is_executable(expanded_cmd) {
			return error_with_code('${expanded_cmd}: permission denied or not a regular file', 126)
		}
		c.fullcmd = expanded_cmd
		c.cmd = expanded_cmd
		return
	}

	if expanded_cmd.ends_with('.vsh') {
		rel := './' + expanded_cmd
		if !os.exists(rel) {
			return error_with_code('${expanded_cmd}: no such file or directory', 127)
		}
		c.use_v_run(rel)!
		return
	}

	if expanded_cmd == '' {
		return error_with_code('empty command name', 127)
	}
	search_paths := if path := c.search_path { path.split(':') } else { get_search_paths() }
	mut denied := false
	for dir in search_paths {
		full := if dir == '' { './${c.cmd}' } else { '${dir}/${c.cmd}' }
		if os.is_file(full) && os.is_executable(full) {
			if full.ends_with('.vsh') {
				c.use_v_run(full)!
				return
			}
			c.fullcmd = full
			c.path = dir
			return
		}
		if os.exists(full) {
			denied = true
		}
	}
	if denied {
		return error_with_code('${c.cmd}: permission denied or not a regular file', 126)
	}
	return error_with_code('${c.cmd}: command not found', 127)
}

// use_v_run configures the command to execute a .vsh script via `v run`.
// The original args are preserved and appended after `run <vsh_path>`.
fn (mut c Cmd_object) use_v_run(vsh_path string) ! {
	v_exe := find_v_exe()
	if v_exe == '' {
		return error('v: interpreter not found in PATH (required to run .vsh scripts)')
	}
	mut new_args := ['run', vsh_path]
	new_args << c.args
	c.args = new_args
	c.fullcmd = v_exe
}

fn find_v_exe() string {
	for dir in get_search_paths() {
		full := dir + '/v'
		if os.is_file(full) && os.is_executable(full) {
			return full
		}
	}
	return ''
}

/*
internal_cmd_modifiers is used to apply certain
default flags on defined commands UNLESS we find that
flag being set manually by the user.

this function should be used a little as possible
not to interfere with the users experience.
*/
fn (mut c Cmd_object) internal_cmd_modifiers() {
	utils.debug('matching $c.cmd in built in modifiers')
	match c.cmd {
		'ls' {
			if !c.args.join(' ').contains('--color') {
				c.args << '--color=always'
			}
		}
		else {}
	}
}
