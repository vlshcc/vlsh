// Git branch/commit prompt plugin for vlsh.
//
// Copy this file to ~/.vlsh/plugins/git.v
// vlsh will compile it automatically on the next start (requires `v` in PATH).
//
// Shows the current git branch and short commit hash above the prompt,
// coloured using style_git_bg / style_git_fg from ~/.vlshrc.

module main

import os

// read_style_color reads an R,G,B colour value from ~/.vlshrc.
// Returns default_rgb if the key is not found or the file cannot be read.
fn read_style_color(config_file string, key string, default_rgb []int) []int {
	lines := os.read_lines(config_file) or { return default_rgb }
	prefix := '${key}='
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with(prefix) {
			parts := trimmed[prefix.len..].split(',')
			if parts.len == 3 {
				return [parts[0].int(), parts[1].int(), parts[2].int()]
			}
		}
	}
	return default_rgb
}

// git_prompt_line returns a styled "branch commit" string if the current
// directory is inside a git repository, or an empty string otherwise.
fn git_prompt_line() string {
	git_folder := os.getwd() + '/.git'
	if !os.exists(git_folder) { return '' }

	head_file := git_folder + '/HEAD'
	head_content := os.read_file(head_file) or { return '' }
	parts := head_content.trim_space().split('/')
	branch := parts[parts.len - 1]
	if branch == '' { return '' }

	commit_file := git_folder + '/refs/heads/' + branch
	commit_content := os.read_file(commit_file) or { return '' }
	trimmed_commit := commit_content.trim_space()
	commit := if trimmed_commit.len >= 7 { trimmed_commit[..7] } else { trimmed_commit }

	config_file := os.home_dir() + '/.vlshrc'
	bg := read_style_color(config_file, 'style_git_bg', [44, 59, 71])
	fg := read_style_color(config_file, 'style_git_fg', [251, 255, 234])

	label := ' ${branch} ${commit} '
	return '\x1b[48;2;${bg[0]};${bg[1]};${bg[2]}m\x1b[38;2;${fg[0]};${fg[1]};${fg[2]}m${label}\x1b[0m'
}

fn main() {
	op := if os.args.len > 1 { os.args[1] } else { '' }
	match op {
		'capabilities' {
			println('prompt')
		}
		'prompt' {
			line := git_prompt_line()
			if line != '' {
				println(line)
			}
		}
		else {}
	}
}
