module plugins

import os

// v_compiler is set at build time to the exact V binary that compiled vlsh,
// so plugins are always compiled with a working toolchain.
const v_compiler = @VEXE

// Plugin holds the discovered capabilities of a compiled plugin.
pub struct Plugin {
pub mut:
	name         string
	binary       string
	commands     []string
	has_prompt   bool
	has_pre_hook bool
	has_post_hook bool
}

fn plugin_src_dir() string {
	return os.join_path(os.home_dir(), '.vlsh', 'plugins')
}

fn plugin_bin_dir() string {
	return os.join_path(plugin_src_dir(), '.bin')
}

fn disabled_file() string {
	return os.join_path(plugin_src_dir(), '.disabled')
}

fn read_disabled() map[string]bool {
	content := os.read_file(disabled_file()) or { return map[string]bool{} }
	mut result := map[string]bool{}
	for line in content.split('\n') {
		t := line.trim_space()
		if t != '' {
			result[t] = true
		}
	}
	return result
}

// available returns the names of all plugins on disk regardless of enabled state.
pub fn available() []string {
	entries := os.ls(plugin_src_dir()) or { return [] }
	mut names := []string{}
	for entry in entries {
		if entry.ends_with('.v') {
			names << entry[..entry.len - 2]
		}
	}
	names.sort()
	return names
}

// disabled returns the set of plugin names that are currently disabled.
pub fn disabled() map[string]bool {
	return read_disabled()
}

// disable marks a plugin as disabled and persists the change.
pub fn disable(name string) ! {
	dis := read_disabled()
	if dis[name] {
		return
	}
	mut names := dis.keys()
	names << name
	names.sort()
	os.write_file(disabled_file(), names.join('\n') + '\n') or { return err }
}

// enable removes a plugin from the disabled list and persists the change.
pub fn enable(name string) ! {
	dis := read_disabled()
	if !dis[name] {
		return
	}
	filtered := dis.keys().filter(it != name)
	if filtered.len == 0 {
		os.rm(disabled_file()) or {}
		return
	}
	os.write_file(disabled_file(), filtered.join('\n') + '\n') or { return err }
}

fn src_is_newer(src string, bin string) bool {
	if !os.exists(bin) {
		return true
	}
	return os.inode(src).mtime > os.inode(bin).mtime
}

// load scans ~/.vlsh/plugins/ for .v files, compiles any that are out of date,
// queries each binary for its capabilities, and returns the ready plugin list.
pub fn load() []Plugin {
	src_dir := plugin_src_dir()
	bin_dir := plugin_bin_dir()

	if !os.exists(src_dir) {
		return []
	}

	os.mkdir_all(bin_dir) or {
		eprintln('vlsh: could not create plugin bin dir: ${err.msg()}')
		return []
	}

	v_exe := v_compiler

	entries := os.ls(src_dir) or { return [] }
	dis := read_disabled()
	mut result := []Plugin{}

	for entry in entries {
		if !entry.ends_with('.v') {
			continue
		}

		src := os.join_path(src_dir, entry)
		name := entry[..entry.len - 2] // strip the .v extension

		if dis[name] {
			continue
		}
		bin := os.join_path(bin_dir, name)

		if src_is_newer(src, bin) {
			compile := os.execute('${v_exe} -o ${bin} ${src}')
			if compile.exit_code != 0 {
				eprintln('vlsh: failed to compile plugin "${name}":\n${compile.output.trim_space()}')
				continue
			}
		}

		caps := os.execute('${bin} capabilities')
		if caps.exit_code != 0 {
			continue
		}

		mut plugin := Plugin{
			name:   name
			binary: bin
		}

		for line in caps.output.split('\n') {
			t := line.trim_space()
			if t.starts_with('command ') {
				plugin.commands << t.all_after('command ')
			} else if t == 'prompt' {
				plugin.has_prompt = true
			} else if t == 'pre_hook' {
				plugin.has_pre_hook = true
			} else if t == 'post_hook' {
				plugin.has_post_hook = true
			}
		}

		result << plugin
	}

	return result
}

// dispatch runs a plugin command if any loaded plugin claims it.
// Returns true if the command was handled.
pub fn dispatch(loaded []Plugin, cmd string, args []string) bool {
	for p in loaded {
		if cmd in p.commands {
			mut child := os.new_process(p.binary)
			mut run_args := ['run', cmd]
			run_args << args
			child.set_args(run_args)
			child.run()
			child.wait()
			child.close()
			return true
		}
	}
	return false
}

// prompt_segments collects one-line prompt contributions from all plugins.
pub fn prompt_segments(loaded []Plugin) string {
	mut parts := []string{}
	for p in loaded {
		if !p.has_prompt {
			continue
		}
		mut child := os.new_process(p.binary)
		child.set_args(['prompt'])
		child.set_redirect_stdio()
		child.run()
		C.close(child.stdio_fd[0])
		child.stdio_fd[0] = -1
		seg := child.stdout_slurp()
		child.wait()
		child.close()
		t := seg.trim_space()
		if t != '' {
			parts << t
		}
	}
	return parts.join(' ')
}

// run_pre_hooks notifies all interested plugins before a command runs.
pub fn run_pre_hooks(loaded []Plugin, cmdline string) {
	for p in loaded {
		if !p.has_pre_hook {
			continue
		}
		mut child := os.new_process(p.binary)
		child.set_args(['pre_hook', cmdline])
		child.run()
		child.wait()
		child.close()
	}
}

// run_post_hooks notifies all interested plugins after a command completes.
pub fn run_post_hooks(loaded []Plugin, cmdline string, exit_code int) {
	for p in loaded {
		if !p.has_post_hook {
			continue
		}
		mut child := os.new_process(p.binary)
		child.set_args(['post_hook', cmdline, exit_code.str()])
		child.run()
		child.wait()
		child.close()
	}
}
