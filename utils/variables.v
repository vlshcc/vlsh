module utils

import os

// Variables keeps shell-only values separate from the exported environment.
pub struct Variables {
pub mut:
	status          int
	arg0            string
	args            []string
	expansion_error string
mut:
	locals         map[string]string
	exported_unset map[string]bool
	legacy         bool
	isolated       bool
	child_env      map[string]string
}

// fork copies session state for expansion in a pipeline stage. Assignments
// during expansion must stay in the stage, even for exported variables.
pub fn (v Variables) fork() Variables {
	return Variables{
		status:         v.status
		arg0:           v.arg0
		args:           v.args.clone()
		locals:         v.locals.clone()
		exported_unset: v.exported_unset.clone()
		isolated:       true
		child_env:      v.environment()
	}
}

pub fn (v Variables) environment() map[string]string {
	return if v.isolated { v.child_env.clone() } else { os.environ() }
}

fn (v Variables) get_exported(name string) ?string {
	if v.isolated {
		if name in v.child_env {
			return v.child_env[name]
		}
		return none
	}
	return os.getenv_opt(name)
}

pub fn (v Variables) get(name string) ?string {
	if name in v.locals {
		return v.locals[name]
	}
	return v.get_exported(name)
}

pub fn (v Variables) value(name string) string {
	return v.get(name) or { '' }
}

pub fn (mut v Variables) assign(name string, value string) {
	if v.legacy || v.exported_unset[name] || v.get_exported(name) != none {
		v.export(name, value)
	} else {
		v.locals[name] = value
	}
}

pub fn (mut v Variables) export(name string, value string) {
	v.locals.delete(name)
	v.exported_unset.delete(name)
	if v.isolated {
		v.child_env[name] = value
	} else {
		os.setenv(name, value, true)
	}
}

pub fn (mut v Variables) unset(name string) {
	v.locals.delete(name)
	v.exported_unset.delete(name)
	if v.isolated {
		v.child_env.delete(name)
	} else {
		os.unsetenv(name)
	}
}

pub fn (mut v Variables) shift(count int) bool {
	if count < 0 || count > v.args.len {
		return false
	}
	v.args = v.args[count..].clone()
	return true
}

fn (v Variables) parameter(name string) ?string {
	if !v.legacy {
		match name {
			'?' { return v.status.str() }
			'#' { return v.args.len.str() }
			'0' { return v.arg0 }
			'@', '*' {
				ifs := v.get('IFS') or { ' \t\n' }
				runes := ifs.runes()
				return v.args.join(if runes.len == 0 { '' } else { runes[0].str() })
			}
			else {}
		}
		if name.len > 0 && name.bytes().all(it >= `0` && it <= `9`) {
			i := name.int()
			if i > 0 && i <= v.args.len {
				return v.args[i - 1]
			}
			return none
		}
	}
	if name == '0' {
		return if os.args.len > 0 { os.args[0] } else { 'vlsh' }
	}
	if name == '$' {
		return os.getpid().str()
	}
	return v.get(name)
}

pub fn valid_name(name string) bool {
	return is_param_name(name)
}

pub fn (mut v Variables) mark_export(name string) {
	if value := v.get(name) {
		v.export(name, value)
	} else {
		v.exported_unset[name] = true
	}
}

pub struct VariableBackup {
	name     string
	value    ?string
	exported bool
}

pub fn (v Variables) backup(name string) VariableBackup {
	return VariableBackup{
		name:     name
		value:    v.get(name)
		exported: v.exported_unset[name] || v.get_exported(name) != none
	}
}

pub fn (mut v Variables) restore(saved []VariableBackup) {
	for entry in saved {
		v.unset(entry.name)
		if value := entry.value {
			if entry.exported {
				v.export(entry.name, value)
			} else {
				v.assign(entry.name, value)
			}
		} else if entry.exported {
			v.mark_export(entry.name)
		}
	}
}
