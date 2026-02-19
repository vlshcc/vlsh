module cfg

import os

pub const config_file = [os.home_dir(), '.vlshrc'].join('/')

pub struct Cfg {
	pub mut:
	paths     []string
	aliases   map[string]string
	style     map[string][]int
}

pub fn get() !Cfg {
	mut loc_cfg := Cfg{}

	if !os.exists(config_file) {
		create_default_config_file() or { return err }
	}

	config_file_data := os.read_lines(config_file) or {

		return error('could not read from $config_file')
	}
	loc_cfg.extract_aliases(config_file_data)
	loc_cfg.extract_paths(config_file_data) or { return err }
	loc_cfg.extract_style(config_file_data) or { return err }

	return loc_cfg
}

pub fn create_default_config_file() ! {
	default_config_file := [
		'"paths',
		'path=/usr/local/bin',
		'path=/usr/bin;/bin',
		'"aliases',
		'alias gs=git status',
		'alias gps=git push',
		'alias gpl=git pull',
		'alias gd=git diff',
		'alias gc=git commit -sa',
		'alias gl=git log',
		'alias vim=nvim',
		'"style (define in RGB colors)',
		'"style_git_bg=44,59,71',
		'"style_git_fg=251,255,234',
		'"style_debug_bg=255,255,255',
		'"style_debug_fb=251,255,234'
	]
	mut f := os.open_file(config_file, 'w') or {

		return error('could not open $config_file')
	}
	for row in default_config_file {
		f.writeln(row) or {

			return error('could not write $row to $config_file')
		}
	}
	f.close()
}

pub fn add_path(p string) ! {
	lines := os.read_lines(config_file) or {
		return error('could not read ${config_file}')
	}
	// find last path= line and insert after it; if none found, append
	mut insert_at := -1
	for i, line in lines {
		if line.trim_space().starts_with('path=') {
			insert_at = i
		}
	}
	entry := 'path=${p}'
	mut new_lines := lines.clone()
	if insert_at >= 0 {
		new_lines.insert(insert_at + 1, entry)
	} else {
		new_lines << entry
	}
	mut f := os.open_file(config_file, 'w') or {
		return error('could not open ${config_file}')
	}
	for line in new_lines {
		f.writeln(line) or { return error('could not write to ${config_file}') }
	}
	f.close()
}

pub fn remove_path(p string) ! {
	lines := os.read_lines(config_file) or {
		return error('could not read ${config_file}')
	}
	entry := 'path=${p}'
	mut new_lines := []string{}
	mut found := false
	for line in lines {
		if line.trim_space() == entry {
			found = true
			continue
		}
		new_lines << line
	}
	if !found {
		return error('path not found in config: ${p}')
	}
	mut f := os.open_file(config_file, 'w') or {
		return error('could not open ${config_file}')
	}
	for line in new_lines {
		f.writeln(line) or { return error('could not write to ${config_file}') }
	}
	f.close()
}

pub fn add_alias(name string, cmd string) ! {
	lines := os.read_lines(config_file) or {
		return error('could not read ${config_file}')
	}
	entry := 'alias ${name}=${cmd}'
	mut new_lines := []string{}
	mut found := false
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('alias ') && trimmed[6..].trim_space().starts_with('${name}=') {
			new_lines << entry
			found = true
			continue
		}
		new_lines << line
	}
	if !found {
		mut insert_at := -1
		for i, line in lines {
			if line.trim_space().starts_with('alias ') {
				insert_at = i
			}
		}
		new_lines = lines.clone()
		if insert_at >= 0 {
			new_lines.insert(insert_at + 1, entry)
		} else {
			new_lines << entry
		}
	}
	mut f := os.open_file(config_file, 'w') or {
		return error('could not open ${config_file}')
	}
	for line in new_lines {
		f.writeln(line) or { return error('could not write to ${config_file}') }
	}
	f.close()
}

pub fn remove_alias(name string) ! {
	lines := os.read_lines(config_file) or {
		return error('could not read ${config_file}')
	}
	mut new_lines := []string{}
	mut found := false
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('alias ') && trimmed[6..].trim_space().starts_with('${name}=') {
			found = true
			continue
		}
		new_lines << line
	}
	if !found {
		return error('alias not found: ${name}')
	}
	mut f := os.open_file(config_file, 'w') or {
		return error('could not open ${config_file}')
	}
	for line in new_lines {
		f.writeln(line) or { return error('could not write to ${config_file}') }
	}
	f.close()
}

pub fn set_style(key string, r int, g int, b int) ! {
	lines := os.read_lines(config_file) or {
		return error('could not read ${config_file}')
	}
	entry := '${key}=${r},${g},${b}'
	mut new_lines := []string{}
	mut found := false
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('${key}=') {
			new_lines << entry
			found = true
			continue
		}
		new_lines << line
	}
	if !found {
		mut insert_at := -1
		for i, line in lines {
			trimmed := line.trim_space()
			if trimmed.starts_with('style') || trimmed.starts_with('"style') {
				insert_at = i
			}
		}
		new_lines = lines.clone()
		if insert_at >= 0 {
			new_lines.insert(insert_at + 1, entry)
		} else {
			new_lines << entry
		}
	}
	mut f := os.open_file(config_file, 'w') or {
		return error('could not open ${config_file}')
	}
	for line in new_lines {
		f.writeln(line) or { return error('could not write to ${config_file}') }
	}
	f.close()
}

pub fn paths() ![]string {
	loc_cfg := get() or {

		return error('could not get paths from $config_file')
	}

	return loc_cfg.paths
}

pub fn aliases() !map[string]string {
	loc_cfg := get() or {

		return error('could not get aliases from $config_file')
	}

	return loc_cfg.aliases
}

pub fn style() !map[string][]int {
	loc_cfg := get() or {

		return error('could not get style from $config_file')
	}

	return loc_cfg.style
}

fn (mut loc_cfg Cfg) extract_style(cfd []string) ! {
	for ent in cfd {
		if ent == '' {
			continue
		}
		if ent[0..5].trim_space() == 'style' {
			split_style := ent.trim_space().split('=')
			if split_style.len < 2 {

				return error('style wasn\'t formatted correctly: $ent')
			}
			rgb_split := split_style[1].trim_space().split(',')
			if rgb_split.len != 3 {

				return error('not correct rgb definition: $ent')
			}

			mut style_int_slice := []int{}
			for v in rgb_split {
				style_int_slice << v.int()
			}
			loc_cfg.style[split_style[0]] = style_int_slice
		}
	}
	mut default := map[string][]int{}
	default['style_git_bg']      = [44, 59, 71]
	default['style_git_fg']      = [251, 255, 234]
	default['style_debug_bg']    = [44, 59, 71]
	default['style_debug_fg']    = [251, 255, 234]
	default['style_mux_bar_bg']  = [44, 124, 67] // #2c7c43

	for k, v in default {
		if k !in loc_cfg.style {
			loc_cfg.style[k] << v
		}
	}

}

fn (mut loc_cfg Cfg) extract_aliases(cfd []string) {
	for ent in cfd {
		if ent == '' {
			continue
		}
		if ent[0..5].trim_space() == 'alias' {
			split_alias := ent.replace('alias', '').trim_space().split('=')
			loc_cfg.aliases[split_alias[0]] = split_alias[1]
		}
	}
}

fn (mut loc_cfg Cfg) extract_paths(cfd []string) ! {
	for ent in cfd {
		if ent == '' {
			continue
		}
		if ent[0..4].trim_space() == 'path' {
			cleaned_ent := ent.replace('path', '').replace('=', '')
			mut split_paths := cleaned_ent.trim_space().split(';')
			for mut path in split_paths {
				path = path.trim_right('/')
				if os.exists(os.real_path(path)) {
					loc_cfg.paths << path
				} else {
					real_path := os.real_path(path)

					return error('could not find ${real_path}')
				}
			}
		}
	}
}
