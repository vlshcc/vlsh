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
	name     string
	html_url string
}

// PluginDesc holds the metadata from a remote plugin's DESC file.
pub struct PluginDesc {
pub:
	name        string
	author      string
	email       string
	description string
}

// InstalledPlugin holds the name, version and source path of an installed plugin.
pub struct InstalledPlugin {
pub:
	name    string
	version string
	src     string
}

// Plugin holds the discovered capabilities of a compiled plugin.
pub struct Plugin {
pub mut:
	name            string
	version         string
	binary          string
	commands        []string
	has_prompt      bool
	has_pre_hook    bool
	has_post_hook   bool
	has_output_hook bool
	has_completion  bool
	has_mux_status  bool
	has_help        bool
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

fn parse_semver(v string) [3]int {
	s := if v.starts_with('v') { v[1..] } else { v }
	parts := s.split('.')
	mut result := [3]int{}
	for i in 0 .. 3 {
		if i < parts.len {
			result[i] = parts[i].int()
		}
	}
	return result
}

fn compare_semver(a &string, b &string) int {
	av := parse_semver(*a)
	bv := parse_semver(*b)
	for i in 0 .. 3 {
		if av[i] < bv[i] { return -1 }
		if av[i] > bv[i] { return 1 }
	}
	return 0
}

fn compare_installed_name(a &InstalledPlugin, b &InstalledPlugin) int {
	if a.name < b.name { return -1 }
	if a.name > b.name { return 1 }
	return 0
}

fn extract_toml_val(s string) string {
	trimmed := s.trim_space()
	if trimmed.starts_with('"') && trimmed.ends_with('"') && trimmed.len >= 2 {
		return trimmed[1..trimmed.len - 1]
	}
	return trimmed
}

fn parse_desc(content string) PluginDesc {
	mut name        := ''
	mut author      := ''
	mut email       := ''
	mut description := ''
	for line in content.split('\n') {
		t := line.trim_space()
		if t == '' || t.starts_with('#') {
			continue
		}
		eq_idx := t.index('=') or { continue }
		key := t[..eq_idx].trim_space()
		val := extract_toml_val(t[eq_idx + 1..])
		match key {
			'name'        { name = val }
			'author'      { author = val }
			'email'       { email = val }
			'description' { description = val }
			else          {}
		}
	}
	return PluginDesc{ name: name, author: author, email: email, description: description }
}

fn list_installed() []InstalledPlugin {
	src_dir := plugin_src_dir()
	if !os.exists(src_dir) {
		return []
	}
	entries := os.ls(src_dir) or { return [] }
	mut result := []InstalledPlugin{}
	for entry in entries {
		if entry.starts_with('.') {
			continue
		}
		plugin_dir := os.join_path(src_dir, entry)
		if !os.is_dir(plugin_dir) {
			continue
		}
		ver_entries := os.ls(plugin_dir) or { continue }
		mut versions := []string{}
		for ve in ver_entries {
			if ve.starts_with('v') && os.is_dir(os.join_path(plugin_dir, ve)) {
				versions << ve
			}
		}
		if versions.len == 0 {
			continue
		}
		versions.sort_with_compare(compare_semver)
		latest := versions.last()
		src := os.join_path(plugin_dir, latest, '${entry}.v')
		result << InstalledPlugin{
			name:    entry
			version: latest
			src:     src
		}
	}
	result.sort_with_compare(compare_installed_name)
	return result
}

fn install_version(name string, version string) ! {
	url := '${raw_base}/${name}/${version}/${name}.v'
	resp := http.get(url) or {
		return error('could not download plugin "${name}": ${err.msg()}')
	}
	if resp.status_code == 404 {
		return error('plugin "${name}" version ${version} not found in remote repository')
	}
	if resp.status_code != 200 {
		return error('download failed with status ${resp.status_code}')
	}
	dest_dir := os.join_path(plugin_src_dir(), name, version)
	os.mkdir_all(dest_dir) or {
		return error('could not create plugin directory: ${err.msg()}')
	}
	dest := os.join_path(dest_dir, '${name}.v')
	os.write_file(dest, resp.body) or {
		return error('could not write plugin file: ${err.msg()}')
	}
}

fn src_is_newer(src string, bin string) bool {
	if !os.exists(bin) {
		return true
	}
	return os.inode(src).mtime > os.inode(bin).mtime
}

// installed_list returns info about all installed plugins.
pub fn installed_list() []InstalledPlugin {
	return list_installed()
}

// available returns the names of all plugins on disk regardless of enabled state.
pub fn available() []string {
	return list_installed().map(it.name)
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

// load scans ~/.vlsh/plugins/ for versioned plugin dirs, compiles any that are
// out of date, queries each binary for its capabilities, and returns the ready
// plugin list.
pub fn load() []Plugin {
	src_dir := plugin_src_dir()
	bin_dir := plugin_bin_dir()

	os.mkdir_all(src_dir) or {
		eprintln('vlsh: could not create plugin dir: ${err.msg()}')
		return []
	}

	os.mkdir_all(bin_dir) or {
		eprintln('vlsh: could not create plugin bin dir: ${err.msg()}')
		return []
	}

	v_exe := v_compiler
	installed := list_installed()
	dis := read_disabled()
	mut result := []Plugin{}

	for ip in installed {
		if dis[ip.name] {
			continue
		}
		bin := os.join_path(bin_dir, ip.name)

		if src_is_newer(ip.src, bin) {
			compile := os.execute('${v_exe} -o ${bin} ${ip.src}')
			if compile.exit_code != 0 {
				eprintln('vlsh: failed to compile plugin "${ip.name}":\n${compile.output.trim_space()}')
				continue
			}
		}

		caps := os.execute('${bin} capabilities')
		if caps.exit_code != 0 {
			continue
		}

		mut plugin := Plugin{
			name:    ip.name
			version: ip.version
			binary:  bin
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
			} else if t == 'output_hook' {
				plugin.has_output_hook = true
			} else if t == 'completion' {
				plugin.has_completion = true
			} else if t == 'mux_status' {
				plugin.has_mux_status = true
			} else if t == 'help' {
				plugin.has_help = true
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

// run_output_hooks sends the captured stdout of a completed command to every
// output-hook-capable plugin.  The plugin receives three arguments:
//   output_hook <cmdline> <exit_code>
// and the captured output is passed as a fourth argument.  For commands that
// run directly on the terminal (not piped), output may be an empty string.
pub fn run_output_hooks(loaded []Plugin, cmdline string, exit_code int, output string) {
	for p in loaded {
		if !p.has_output_hook {
			continue
		}
		mut child := os.new_process(p.binary)
		child.set_args(['output_hook', cmdline, exit_code.str(), output])
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

// fetch_desc fetches and parses the DESC metadata file for a remote plugin.
pub fn fetch_desc(plugin_name string) !PluginDesc {
	url := '${raw_base}/${plugin_name}/DESC'
	resp := http.get(url) or {
		return error('could not fetch DESC for "${plugin_name}": ${err.msg()}')
	}
	if resp.status_code != 200 {
		return error('DESC not found for "${plugin_name}" (status ${resp.status_code})')
	}
	return parse_desc(resp.body)
}

// remote_plugin_names fetches the list of plugin names available in the remote repository.
pub fn remote_plugin_names() ![]string {
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
		if f.html_url.contains('/tree/') {
			names << f.name
		}
	}
	names.sort()
	return names
}

// remote_versions returns all available semver versions for a remote plugin, sorted ascending.
pub fn remote_versions(plugin_name string) ![]string {
	resp := http.get('${remote_api}/${plugin_name}') or {
		return error('could not fetch versions for "${plugin_name}": ${err.msg()}')
	}
	if resp.status_code == 404 {
		return error('plugin "${plugin_name}" not found in the remote repository')
	}
	if resp.status_code != 200 {
		return error('remote returned status ${resp.status_code}')
	}
	files := json.decode([]GHFile, resp.body) or {
		return error('could not parse version list for "${plugin_name}"')
	}
	mut versions := []string{}
	for f in files {
		if f.html_url.contains('/tree/') && f.name.starts_with('v') {
			versions << f.name
		}
	}
	versions.sort_with_compare(compare_semver)
	return versions
}

// latest_remote_version returns the newest available semver version for a remote plugin.
pub fn latest_remote_version(plugin_name string) !string {
	versions := remote_versions(plugin_name)!
	if versions.len == 0 {
		return error('no versions found for "${plugin_name}"')
	}
	return versions.last()
}

// install downloads the latest version of a plugin from the remote repository.
// Returns the installed version string.
pub fn install(name string) !string {
	version := latest_remote_version(name)!
	install_version(name, version)!
	return version
}

// update_plugin upgrades an installed plugin to the latest remote version.
// Returns the new version string, or an error if already at latest.
pub fn update_plugin(name string) !string {
	installed := list_installed()
	mut current_version := ''
	for ip in installed {
		if ip.name == name {
			current_version = ip.version
			break
		}
	}
	if current_version == '' {
		return error('plugin "${name}" is not installed')
	}
	latest := latest_remote_version(name)!
	if latest == current_version {
		return error('already at latest version ${latest}')
	}
	old_dir := os.join_path(plugin_src_dir(), name, current_version)
	os.rmdir_all(old_dir) or {
		return error('could not remove old version: ${err.msg()}')
	}
	bin := os.join_path(plugin_bin_dir(), name)
	if os.exists(bin) {
		os.rm(bin) or {}
	}
	install_version(name, latest)!
	return latest
}

// delete_plugin removes a local plugin's folder and compiled binary.
pub fn delete_plugin(name string) ! {
	plugin_dir := os.join_path(plugin_src_dir(), name)
	if !os.exists(plugin_dir) {
		return error('plugin "${name}" is not installed')
	}
	os.rmdir_all(plugin_dir) or {
		return error('could not remove plugin: ${err.msg()}')
	}
	bin := os.join_path(plugin_bin_dir(), name)
	if os.exists(bin) {
		os.rm(bin) or {}
	}
}

// show_help invokes <binary> help [cmd] for any loaded plugin that owns cmd
// and declares the help capability.  Prints the plugin's output and returns
// true.  Returns false when no matching plugin with help support is found.
pub fn show_help(loaded []Plugin, cmd string) bool {
	for p in loaded {
		if !p.has_help {
			continue
		}
		if cmd in p.commands {
			result := os.execute('${p.binary} help ${cmd}')
			print(result.output)
			return true
		}
	}
	return false
}

// search_remote fetches all remote plugins and filters by name or description.
pub fn search_remote(query string) ![]PluginDesc {
	q := query.to_lower()
	names := remote_plugin_names()!
	mut results := []PluginDesc{}
	for name in names {
		desc := fetch_desc(name) or { continue }
		if desc.name.to_lower().contains(q) || desc.description.to_lower().contains(q) {
			results << desc
		}
	}
	return results
}
