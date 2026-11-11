module main

import os
import cfg
import exec
import plugins
import shellops
import utils

fn evaluate(input string, mut loaded []plugins.Plugin, mut vars utils.Variables) int {
	vars.expansion_error = ''
	code := evaluate_list(input, mut loaded, mut vars)
	if vars.expansion_error != '' { eprintln('vlsh: ${vars.expansion_error}') }
	return code
}

fn evaluate_list(input string, mut loaded []plugins.Plugin, mut vars utils.Variables) int {
	parts := shellops.parse_commands(input) or {
		utils.fail(err.msg())
		vars.status = 2
		return 2
	}
	for part in parts {
		if (part.pre_op == '&&' && vars.status != 0) || (part.pre_op == '||' && vars.status == 0) {
			continue
		}
		vars.status = run_pipeline(part, mut loaded, mut vars)
		if vars.expansion_error != '' {
			vars.status = 2
			break
		}
	}
	return vars.status
}

fn expand_aliases(original shellops.SimpleCommand, aliases map[string]string) !shellops.SimpleCommand {
	mut stage := original
	mut visited := map[string]bool{}
	for stage.words.len > 0 && stage.words[0] in aliases {
		name := stage.words[0]
		if visited[name] || visited.len >= 32 {
			return error('alias expansion limit exceeded')
		}
		visited[name] = true
		parts := shellops.parse_commands(aliases[name])!
		if parts.len == 0 {
			break
		}
		if parts.len != 1 || parts[0].stages.len != 1 {
			return error('alias must expand to a simple command: ${name}')
		}
		alias := parts[0].stages[0]
		mut words := alias.words.clone()
		words << stage.words[1..]
		mut assigns := stage.assignments.clone()
		assigns << alias.assignments
		mut redirects := alias.redirects.clone()
		redirects << stage.redirects
		stage = shellops.SimpleCommand{ words: words, assignments: assigns, redirects: redirects }
		if stage.words.len > 0 && stage.words[0] == name {
			break
		}
	}
	return stage
}

fn prepare_command(stage shellops.SimpleCommand, mut vars utils.Variables) !exec.Cmd_object {
	mut words := []string{}
	for raw in stage.words {
		if words.len > 0 && words[0] == 'export' && utils.is_env_assign(raw) {
			eq := raw.index_u8(`=`)
			value := utils.expand_scalar(raw[eq + 1..], mut vars)
			words << raw[..eq + 1] + value
		} else {
			words << utils.expand_word(raw, mut vars)
		}
		if vars.expansion_error != '' {
			return error(vars.expansion_error)
		}
	}
	mut redirects := []exec.Redirect{}
	// Command arguments and redirects see the shell's values, before any prefix.
	if words.len > 0 {
		redirects = prepare_redirects(stage.redirects, mut vars)!
	}
	mut saved := []utils.VariableBackup{}
	defer { vars.restore(saved) }
	mut assignments := map[string]string{}
	for raw in stage.assignments {
		eq := raw.index_u8(`=`)
		name := raw[..eq]
		value := utils.expand_scalar(raw[eq + 1..], mut vars)
		if vars.expansion_error != '' {
			return error(vars.expansion_error)
		}
		if name !in assignments { saved << vars.backup(name) }
		assignments[name] = value
		vars.assign(name, value)
	}
	if words.len == 0 {
		redirects = prepare_redirects(stage.redirects, mut vars)!
	}
	return exec.Cmd_object{
		cmd:         if words.len > 0 { words[0] } else { '' }
		args:        if words.len > 0 { words[1..].clone() } else { []string{} }
		no_command:  words.len == 0
		assignments: assignments
		redirects:   redirects
		search_path: vars.get('PATH')
	}
}

fn prepare_redirects(raw []shellops.RedirectWord, mut vars utils.Variables) ![]exec.Redirect {
	mut redirects := []exec.Redirect{cap: raw.len}
	for redirect in raw {
		target := utils.expand_scalar(redirect.target, mut vars)
		if vars.expansion_error != '' {
			return error(vars.expansion_error)
		}
		redirects << exec.parse_redirect(redirect.operator, target)!
	}
	return redirects
}

fn run_pipeline(part shellops.ChainPart, mut loaded []plugins.Plugin, mut vars utils.Variables) int {
	conf := if os.exists(cfg.config_file) { cfg.get() or { cfg.Cfg{} } } else { cfg.Cfg{} }
	mut stages := []exec.Cmd_object{cap: part.stages.len}
	for stage in part.stages {
		raw := expand_aliases(stage, conf.aliases) or {
			utils.fail(err.msg())
			return 1
		}
		if part.stages.len == 1 {
			command := prepare_command(raw, mut vars) or {
				if vars.expansion_error == '' { utils.fail(err.msg()) }
				return 1
			}
			return run_single(command, part.cmd, mut loaded, mut vars)
		}
		mut stage_vars := vars.fork()
		mut command := prepare_command(raw, mut stage_vars) or {
			stages << exec.Cmd_object{
				failure:    if stage_vars.expansion_error == '' { 1 } else { 2 }
				diagnostic: 'vlsh: ${err.msg()}\n'
			}
			continue
		}
		command.environment = stage_vars.environment()
		// Run core builtins in a fresh copy of vlsh, preserving argv without
		// re-parsing it and keeping their state changes out of the parent.
		if pipeline_builtin(command.cmd) {
			command.fullcmd = os.executable()
			mut args := ['--builtin-stage', vars.status.str(), command.cmd]
			args << command.args
			command.args = args
		}
		stages << command
	}
	return run_external(stages, part.cmd, loaded)
}

fn pipeline_builtin(name string) bool {
	return name in [':', 'cd', 'echo', 'exit', 'export', 'unset']
}

fn run_single(command exec.Cmd_object, input string, mut loaded []plugins.Plugin, mut vars utils.Variables) int {
	if !command.no_command && !pipeline_builtin(command.cmd)
		&& command.cmd !in ['aliases', 'style', 'ocp', 'source', '.', 'help', 'version', 'ls',
			'mux', 'plugins', 'set', 'shift']
		&& !loaded.any(command.cmd in it.commands) {
		return run_external([command], input, loaded)
	}
	special := command.no_command || command.cmd in [':', 'exit', 'export', 'unset', '.', 'set',
		'shift']
	mut saved_vars := []utils.VariableBackup{}
	for name, value in command.assignments {
		if special {
			vars.assign(name, value)
		} else {
			saved_vars << vars.backup(name)
			vars.export(name, value)
		}
	}
	defer { vars.restore(saved_vars) }
	mut saved_fds := exec.push_redirects(command.redirects) or { return 1 }
	defer { saved_fds.restore() }
	if command.no_command {
		return 0
	}
	return dispatch_cmd(command.cmd, command.args, mut loaded, input, mut vars)
}

fn run_external(stages []exec.Cmd_object, input string, loaded []plugins.Plugin) int {
	mut task := exec.Task{}
	code := task.run_stages(stages) or {
		utils.fail(err.msg())
		return 1
	}
	plugins.run_output_hooks(loaded, input, code, task.last_output)
	return code
}
