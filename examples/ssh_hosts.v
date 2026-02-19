// ssh_hosts — SSH host autocomplete plugin for vlsh.
//
// Copy this file to ~/.vlsh/plugins/ssh_hosts.v
// vlsh will compile it automatically on the next start (requires `v` in PATH).
//
// When the user types `ssh <prefix>` and presses Tab, this plugin returns
// matching hostnames gathered from:
//   ~/.ssh/config     — explicit Host entries (wildcards excluded)
//   ~/.ssh/known_hosts — hostnames from the known-hosts file
//
// Usage examples:
//   ssh web<Tab>     → ssh webserver, ssh web01 …
//   ssh user@db<Tab> → ssh user@db1, ssh user@db2 …

module main

import os

// hosts_from_config reads Host entries from ~/.ssh/config.
// Wildcard patterns (containing * or ?) are skipped.
fn hosts_from_config() []string {
	config_file := os.join_path(os.home_dir(), '.ssh', 'config')
	lines := os.read_lines(config_file) or { return [] }
	mut hosts := []string{}
	for line in lines {
		trimmed := line.trim_space()
		lower := trimmed.to_lower()
		if !lower.starts_with('host ') {
			continue
		}
		// A Host line may list multiple patterns separated by spaces.
		tokens := trimmed[5..].split(' ')
		for token in tokens {
			t := token.trim_space()
			if t == '' || t.contains('*') || t.contains('?') {
				continue
			}
			hosts << t
		}
	}
	return hosts
}

// hosts_from_known_hosts reads hostnames from ~/.ssh/known_hosts.
// Hashed entries (starting with |1|) and bare IP addresses are included as-is.
fn hosts_from_known_hosts() []string {
	kh_file := os.join_path(os.home_dir(), '.ssh', 'known_hosts')
	lines := os.read_lines(kh_file) or { return [] }
	mut hosts := []string{}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') {
			continue
		}
		// Hashed entries (|1|…) cannot be reversed — skip them.
		if trimmed.starts_with('|') {
			continue
		}
		// First field is the hostname/IP field; may be "host:port" or "host,ip".
		first_field := trimmed.split(' ')[0]
		// Handle comma-separated host,ip entries — take each part separately.
		for part in first_field.split(',') {
			p := part.trim_space()
			if p == '' {
				continue
			}
			// Strip optional [host]:port bracket notation used for non-22 ports.
			if p.starts_with('[') {
				bracket_end := p.index(']') or { continue }
				hosts << p[1..bracket_end]
			} else {
				hosts << p
			}
		}
	}
	return hosts
}

// unique returns a deduplicated, sorted copy of the input slice.
fn unique(items []string) []string {
	mut seen := map[string]bool{}
	mut out := []string{}
	for item in items {
		if !seen[item] {
			seen[item] = true
			out << item
		}
	}
	out.sort()
	return out
}

// complete_ssh returns full replacement strings for the given input line.
// Input must start with "ssh " for this plugin to produce results.
fn complete_ssh(input string) []string {
	// Only handle lines that begin with "ssh " and have at least one char after.
	if !input.starts_with('ssh ') {
		return []
	}

	after_ssh := input[4..] // everything the user typed after "ssh "

	// Support optional user@ prefix: keep it verbatim in the completions.
	mut user_at := ''
	mut host_prefix := after_ssh
	if after_ssh.contains('@') {
		at_idx := after_ssh.last_index('@') or { -1 }
		if at_idx >= 0 {
			user_at = after_ssh[..at_idx + 1]    // e.g. "user@"
			host_prefix = after_ssh[at_idx + 1..] // e.g. "db"
		}
	}

	mut combined := hosts_from_config()
	combined << hosts_from_known_hosts()
	all_hosts := unique(combined)

	mut results := []string{}
	for host in all_hosts {
		if host.starts_with(host_prefix) {
			results << 'ssh ${user_at}${host}'
		}
	}
	return results
}

fn main() {
	op := if os.args.len > 1 { os.args[1] } else { '' }
	match op {
		'capabilities' {
			println('completion')
		}
		'complete' {
			// The full current input line is passed as the third argument.
			input := if os.args.len > 2 { os.args[2] } else { '' }
			for result in complete_ssh(input) {
				println(result)
			}
		}
		else {}
	}
}
