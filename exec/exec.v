module exec

import os

import cfg
import utils

// C signal API — used to protect vlsh from SIGINT while a child process runs.
fn C.signal(signum int, handler voidptr) voidptr

pub struct Cmd_object{
	pub mut:
	/*
	cmd is the first ,iven argument which
	we will consider to be an application
	or alias to be executed.
	*/
	cmd						string
	/*
	fullcmd is the joint string of the found
	path leading to the application and the
	first argument passed in (cmd).
	*/
	fullcmd					string
	/*
	args will be all of the following args
	sent [1..]. This will break if we find
	a pipe sign |.
	*/
	args					[]string
	/*
	path is the first found path in paths
	containing an executable with the same
	name as cmd (first arg).
	*/
	path					string
	/*
	cfg is the config object in cfg.v
	*/
	cfg						cfg.Cfg
	/*
	input is only used when handling pipes.
	this is a placeholder for output captured
	from the past command in the pipe chain.
	*/
	input					string
	/*
	set_redirect_stdio is only used when
	handling pipes. it's used in combination
	with intercept_stdio to send output
	along to next command as input.
	*/
	set_redirect_stdio		bool
	/*
	intercept_stdio is only used when handling
	pipes. it's to know if we should slurp the
	output from a command and set it as the
	input of the next command in the pipe chain.
	*/
	intercept_stdio			bool
	/*
	next_pipe_index is used to know which command
	in the pipe chain to execute next. if -1
	then it's the last command in the chain.
	*/
	next_pipe_index			int
	/*
	redirect_file is the path to write stdout to when
	the command uses > or >> output redirection.
	Empty string means no redirection.
	*/
	redirect_file			string
	/*
	redirect_append controls whether > (false, truncate)
	or >> (true, append) semantics are used.
	*/
	redirect_append			bool
}

pub struct Task {
	pub mut:
	/*
	cmd is a command object
	*/
	cmd			Cmd_object
	/*
	pipe_string is only used when handling pipes.
	it's the full string that we get from stdin
	containing all commands and arguments
	*/
	pipe_string	string
	/*
	pipe_cmds is only used when handling pipes.
	it'll be populated with a command object per
	command found in the given pipe_string. the
	next_pipe_index on a Cmd_object corresponds
	to the indexes of this slice.
	*/
	pipe_cmds	[]Cmd_object
	/*
	last_exit_code is the exit code of the last
	child process that was run.
	*/
	last_exit_code int
	/*
	last_output holds the stdout that was captured from the last command
	in the pipeline.  It is populated when output was naturally intercepted
	(e.g. the final stage of a pipe chain received piped input).  For
	commands that run directly on the terminal it remains empty.
	*/
	last_output string
}

pub fn (mut t Task) prepare_task() !int {
	/*
	parse pipe will normalize the pipe_string that
	we get from stdin so that we remove unnecessary
	whitespaces and possible double -pipes, etc.
	then we populate our pipe_cmds -slice.
	*/
	t.parse_pipe()

	t.exec() or {

		return err
	}

	return t.last_exit_code
}

// expand_tilde expands a leading ~ or ~/ to the user's home directory.
fn expand_tilde(s string) string {
	if s == '~' {
		return os.home_dir()
	}
	if s.starts_with('~/') {
		return os.home_dir() + s[1..]
	}
	return s
}

fn requote_args(args []string) string {
	mut parts := []string{}
	for arg in args {
		if arg.contains(' ') {
			parts << '"' + arg + '"'
		} else {
			parts << arg
		}
	}
	return parts.join(' ')
}

fn (mut t Task) parse_pipe() {
	joined := [t.cmd.cmd, requote_args(t.cmd.args)].join(' ').trim_space()
	t.pipe_string = norm_pipe(joined)
	t.walk_pipes()
}

fn norm_pipe(i string) string {
	mut r := []string{}
	m := i.split('|')
	for s in m {
		mut p := s // do trim_space() on s without it being mut?
		p = p.trim_space()
		if p != '' {
			r << p
		}
	}

	return r.join('|')
}

// parse_redirect scans a token list for > or >> operators and extracts the
// redirect target filename.  Returns the cleaned args, filename, and append flag.
fn parse_redirect(tokens []string) ([]string, string, bool) {
	mut out_args     := []string{}
	mut rfile        := ''
	mut rappend      := false
	mut skip_next    := false
	for i, tok in tokens {
		if skip_next {
			skip_next = false
			continue
		}
		if tok == '>>' {
			rappend = true
			if i + 1 < tokens.len {
				rfile     = expand_tilde(tokens[i + 1])
				skip_next = true
			}
		} else if tok == '>' {
			rappend = false
			if i + 1 < tokens.len {
				rfile     = expand_tilde(tokens[i + 1])
				skip_next = true
			}
		} else {
			out_args << tok
		}
	}
	return out_args, rfile, rappend
}

fn (mut t Task) walk_pipes() {
	split_pipe_string := t.pipe_string.split('|')
	len := split_pipe_string.len
	for index, pipe_string in split_pipe_string {
		split_pipe := utils.parse_args(pipe_string.trim_space())
		if split_pipe.len == 0 {
			continue
		}
		cmd := split_pipe[0]
		mut raw_args := []string{}
		if split_pipe.len > 1 {
			raw_args << split_pipe[1..]
		}
		// Extract any > or >> redirection from the argument list.
		args, rfile, rappend := parse_redirect(raw_args)

		mut intercept := true
		mut next_index := index
		if next_index + 1 == len {
			intercept = false
			next_index = -1
		}
		// If there is a file redirect we must capture stdout regardless of pipes.
		effective_intercept    := intercept || rfile != ''
		effective_redirect_out := effective_intercept
		obj := Cmd_object{
			cmd:                cmd,
			args:               args,
			cfg:                t.cmd.cfg,
			intercept_stdio:    effective_intercept,
			set_redirect_stdio: effective_redirect_out,
			next_pipe_index:    next_index,
			redirect_file:      rfile,
			redirect_append:    rappend,
		}
		if index == 0 {
			t.cmd = obj
		} else {
			t.pipe_cmds << obj
		}
	}
}

fn (mut t Task) exec() !int {

	/*
	checking if we have any aliases defined first that we should
	overwrite any actual given command with.
	*/
	t.handle_aliases()

	/*
	locate the given command in specifide paths.

	@todo: should set some standard paths in the code..?
	*/
	t.cmd.find_exe() or {

		return err
	}

	/*
	also find_exec for each pipe cmd following.

	@todo: search for aliases before exec
	*/
	if t.pipe_cmds.len > 0 {
		for i := 0; i < t.pipe_cmds.len; i++ {
			t.pipe_cmds[i].find_exe() or {

				return err
			}
		}
	}

	/*
	apply certain flags to specific commands if they aren't set manually.
	*/
	t.cmd.internal_cmd_modifiers()

	/*
	also find internal_cmd_modifiers for each pipe cmd following.
	*/
	if t.pipe_cmds.len > 0 {
		for i := 0; i < t.pipe_cmds.len; i++ {
			t.pipe_cmds[i].internal_cmd_modifiers()
		}
	}

	/*
	actually run the process and check for a possible
	next pipe cmd to run. an index of -1 will terminate
	a pipe sequence.
	*/
	mut index := t.run(t.cmd)

	if index >= 0 && t.pipe_cmds.len > 0 {
		for {
			index = t.run(t.pipe_cmds[index])
			if index < 0 {
				utils.debug('breaking')
				break
			}
		}
	}

	return t.last_exit_code
}

fn (mut t Task) run(c Cmd_object) (int) {
	mut child := os.new_process(c.fullcmd)

	if c.args.len > 0 {
		child.set_args(c.args.map(expand_tilde(it)))
	}

	// set_redirect_stdio() must be called before run()
	if c.input != '' || c.intercept_stdio {
		child.set_redirect_stdio()
	}

	child.run()

	// After the fork the child already has SIG_DFL; now make the parent
	// ignore SIGINT so that Ctrl+C only kills the child, not vlsh itself.
	unsafe { C.signal(C.SIGINT, voidptr(1)) } // SIG_IGN

	if c.input != '' {
		child.stdin_write(c.input)
	}

	/*
	Close the write-end of the stdin pipe after writing (or immediately
	if there was no input). This signals EOF to the child so it stops
	waiting for more input. Without this, commands like `wc` that read
	until EOF will block forever. It also prevents interactive programs
	like `more` from hanging on an open-but-empty stdin pipe.
	*/
	if c.input != '' || c.intercept_stdio {
		C.close(child.stdio_fd[0])
		child.stdio_fd[0] = -1
	}

	if c.intercept_stdio && c.next_pipe_index >= 0 && c.redirect_file == '' {
		/*
		slurp all stdout before wait() to drain the pipe and avoid
		deadlock. stdout_slurp() blocks until the child closes its
		stdout (i.e. exits), then wait() reaps the process.
		Using stdout_read() here would only capture 4096 bytes.
		*/
		output := child.stdout_slurp()
		child.wait()
		t.pipe_cmds[c.next_pipe_index].input = output
	} else if c.redirect_file != '' {
		// Output redirection: capture stdout and write to file.
		output := child.stdout_slurp()
		child.wait()
		t.last_exit_code = child.code
		flag := if c.redirect_append { 'a' } else { 'w' }
		mut f := os.open_file(c.redirect_file, flag) or {
			utils.fail('cannot open redirect file: ${err.msg()}')
			return c.next_pipe_index
		}
		f.write_string(output) or {}
		f.close()
	} else if c.input != '' {
		/*
		last command in the pipe chain: stdout was redirected so we
		could write to its stdin. slurp and print its output, then wait.
		*/
		output := child.stdout_slurp()
		child.wait()
		t.last_exit_code = child.code
		t.last_output = output
		print(output)
	} else {
		child.wait()
		t.last_exit_code = child.code
	}

	child.close()

	// Restore default SIGINT handling so Ctrl+C works normally at the prompt.
	unsafe { C.signal(C.SIGINT, voidptr(0)) } // SIG_DFL

	return c.next_pipe_index
}

fn (mut t Task) handle_aliases() {
	if alias_key_exists(t.cmd.cmd, t.cmd.cfg.aliases) {
		alias_split := t.cmd.cfg.aliases[t.cmd.cmd].split(' ')
		t.cmd.cmd = alias_split[0]
		t.cmd.args << alias_split[1..]
		utils.debug('found $t.cmd.cmd in $t.cmd.cfg.aliases')
		utils.debug('will try to run $t.cmd.cmd with $t.cmd.args')
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

fn (mut c Cmd_object) find_exe() ! {
	// Expand ~ in the command itself (e.g. ~/bin/myscript)
	expanded_cmd := expand_tilde(c.cmd)

	// Direct paths: absolute (/foo/bar) or explicitly relative (./foo, ../foo).
	is_direct := expanded_cmd.starts_with('/') ||
	             expanded_cmd.starts_with('./') ||
	             expanded_cmd.starts_with('../')

	if is_direct {
		if !os.exists(expanded_cmd) {
			return error('${expanded_cmd}: no such file or directory')
		}
		if expanded_cmd.ends_with('.vsh') {
			c.use_v_run(expanded_cmd)!
			return
		}
		c.fullcmd = expanded_cmd
		c.cmd     = expanded_cmd
		return
	}

	// Bare .vsh filename without a path prefix: check the current directory.
	if expanded_cmd.ends_with('.vsh') {
		rel := './' + expanded_cmd
		if !os.exists(rel) {
			return error('${expanded_cmd}: no such file or directory')
		}
		c.use_v_run(rel)!
		return
	}

	// Search the configured PATH directories.
	mut trimmed_needle := ''
	for path in c.cfg.paths {
		trimmed_needle = c.cmd.replace(path, '').trim_left('/')
		utils.debug('looking for $c.cmd in $path')
		full := [path, trimmed_needle].join('/')
		if os.exists(full) {
			utils.debug('found $trimmed_needle in $path')
			if full.ends_with('.vsh') {
				c.use_v_run(full)!
				return
			}
			c.fullcmd = full
			c.path    = path
			c.cmd     = trimmed_needle
			return
		}
	}

	return error(
		'$trimmed_needle not found in defined aliases or in \$PATH
        \$PATH: $c.cfg.paths'
	)
}

// use_v_run configures the command to execute a .vsh script via `v run`.
// The original args are preserved and appended after `run <vsh_path>`.
fn (mut c Cmd_object) use_v_run(vsh_path string) ! {
	v_exe := find_v_exe(c.cfg.paths)
	if v_exe == '' {
		return error('v: interpreter not found in PATH (required to run .vsh scripts)')
	}
	mut new_args := ['run', vsh_path]
	new_args << c.args
	c.args    = new_args
	c.fullcmd = v_exe
}

// find_v_exe locates the V compiler/interpreter binary.
// It searches vlsh-configured paths first, then falls back to the system PATH.
fn find_v_exe(cfg_paths []string) string {
	mut all_paths := cfg_paths.clone()
	all_paths << os.getenv('PATH').split(':')
	for dir in all_paths {
		if dir == '' { continue }
		full := dir + '/v'
		if os.exists(full) { return full }
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
				c.args << '--color=auto'
			}
		}
		else {}
	}
}
