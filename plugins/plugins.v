module plugins

import os
import net.http
import json

// v_compiler is set at build time to the exact V binary that compiled vlsh,
// so plugins are always compiled with a working toolchain.
const v_compiler = @VEXE

const remote_api = 'https://api.github.com/repos/vlshcc/plugins/contents'
const raw_base   = 'https://raw.githubusercontent.com/vlshcc/plugins/main'

struct GHFile {
	name string
	download_url string
}

// Plugin holds the discovered capabilities of a compiled plugin.
pub struct Plugin {
pub mut:
	name            string
	binary          string
	commands        []string
	has_prompt      bool
	has_pre_hook    bool
	has_post_hook   bool
	has_completion  bool
	has_mux_status  bool
}

// completions asks every completion-capable plugin for suggestions given the
// current input line. Each plugin is invoked as: <binary> complete <input>
// and is expected to print one full replacement string per line.
pub fn completions(loaded []Plugin, input string) []string {
	mut results := []string{}
	for p in loaded {
		if !p.has_completion {
			continue
		}
		mut child := os.new_process(p.binary)
		child.set_args(['complete', input])
		child.set_redirect_stdio()
		child.run()
		C.close(child.stdio_fd[0])
		child.stdio_fd[0] = -1
		out := child.stdout_slurp()
		child.wait()
		child.close()
		for line in out.split('\n') {
			t := line.trim_space()
			if t != '' {
				results << t
			}
		}
	}
	return results
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

// enable_all clears the disabled list, making every available plugin active.
pub fn enable_all() ! {
	dis_file := disabled_file()
	if os.exists(dis_file) {
		os.rm(dis_file) or { return err }
	}
}

// disable_all writes every available plugin name to the disabled list.
pub fn disable_all() ! {
	names := available()
	if names.len == 0 {
		return
	}
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
			} else if t == 'completion' {
				plugin.has_completion = true
			} else if t == 'mux_status' {
				plugin.has_mux_status = true
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

// mux_status_binaries returns the binary paths of all loaded plugins that declare
// the mux_status capability.  The mux module uses these to poll for status bar text.
pub fn mux_status_binaries(loaded []Plugin) []string {
	mut bins := []string{}
	for p in loaded {
		if p.has_mux_status {
			bins << p.binary
		}
	}
	return bins
}

// remote_available fetches the list of plugin names available in the remote repository.
pub fn remote_available() ![]string {
	resp := http.get(remote_api) or {
		return error('could not fetch remote plugin list: ${err.msg()}')
	}
	if resp.status_code != 200 {
		return error('remote returned status ${resp.status_code}')
	}
	files := json.decode([]GHFile, resp.body) or {
		return error('could not parse remote plugin list')
	}
	mut names := []string{}
	for f in files {
		if f.name.ends_with('.v') {
			names << f.name[..f.name.len - 2]
		}
	}
	names.sort()
	return names
}

// install downloads a plugin from the remote repository into ~/.vlsh/plugins/.
pub fn install(name string) ! {
	url := '${raw_base}/${name}.v'
	resp := http.get(url) or {
		return error('could not download plugin "${name}": ${err.msg()}')
	}
	if resp.status_code == 404 {
		return error('plugin "${name}" not found in remote repository')
	}
	if resp.status_code != 200 {
		return error('download failed with status ${resp.status_code}')
	}
	src_dir := plugin_src_dir()
	os.mkdir_all(src_dir) or {
		return error('could not create plugin directory: ${err.msg()}')
	}
	dest := os.join_path(src_dir, '${name}.v')
	os.write_file(dest, resp.body) or {
		return error('could not write plugin file: ${err.msg()}')
	}
}

// delete_plugin removes a local plugin's source file and compiled binary.
pub fn delete_plugin(name string) ! {
	src := os.join_path(plugin_src_dir(), '${name}.v')
	if !os.exists(src) {
		return error('plugin "${name}" is not installed')
	}
	os.rm(src) or {
		return error('could not remove plugin source: ${err.msg()}')
	}
	bin := os.join_path(plugin_bin_dir(), name)
	if os.exists(bin) {
		os.rm(bin) or {}
	}
}
