module main

// fuzz_shell — stress parse_args, expand_vars, expand_history_notation, split_commands.
//
// From the repo root:
//   v run tools/fuzz_shell.v
//   FUZZ_ITER=100000 FUZZ_SEED=32423425234234 v run tools/fuzz_shell.v
//   make fuzz
//   make fuzz FUZZ_ITER=200000
//
// FUZZ_SEED: optional decimal string (any length that fits in u64). Mapped to
// rand.seed via two u32 words. Omit for PID-based seed.
//
// Noise: parse_args/expand_vars may call eprintln for ${var:?…} and may set
// env vars via ${var:=…} when random text matches. Use 2>/dev/null to silence
// stderr, or accept occasional diagnostics.

import os
import rand
import shellops
import utils

const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
const specials = '!"#$%&\'()*+,-./:;<=>?@[\\]^_`{|}~ \n\t'

const history_samples = [
	'ls -la',
	'echo hello world',
	'cd /tmp',
	'!!',
	'!-1',
	'!1',
	'!?echo?',
	'export FOO=bar',
	'a && b || c ; d',
]

fn env_int(name string, default int) int {
	s := os.getenv(name)
	if s == '' {
		return default
	}
	return s.int()
}

// parse_decimal_u64 parses a non-empty decimal string into u64 (no overflow check beyond u64 wrap).
fn parse_decimal_u64(s string) !u64 {
	if s.len == 0 {
		return error('empty FUZZ_SEED')
	}
	mut v := u64(0)
	for c in s {
		if c < `0` || c > `9` {
			return error('FUZZ_SEED must be decimal digits only')
		}
		d := u64(c - `0`)
		v = v * 10 + d
	}
	return v
}

fn rand_string(max_len int) string {
	if max_len < 1 {
		return ''
	}
	n := rand.intn(max_len) or { 0 }
	if n < 1 {
		return ''
	}
	mut b := []u8{len: n}
	pool := alphabet + specials
	pl := pool.len
	for i in 0 .. n {
		b[i] = pool[rand.intn(pl) or { 0 }]
	}
	return b.bytestr()
}

fn fuzz_round() {
	mut s := rand_string(400)
	// Bias toward structured samples + junk
	match rand.intn(12) or { 0 } {
		0...2 {
			s = history_samples[rand.intn(history_samples.len) or { 0 }] + rand_string(120)
		}
		3...4 {
			s = rand_string(80) + history_samples[rand.intn(history_samples.len) or { 0 }]
		}
		else {}
	}
	_ := utils.parse_args(s)
	_ := utils.expand_vars(s)
	_ := shellops.split_commands(s)
	mut hist := []string{}
	for _ in 0 .. 8 {
		hist << history_samples[rand.intn(history_samples.len) or { 0 }]
	}
	utils.expand_history_notation(s, 'echo last', hist) or { '' }
	utils.expand_history_notation(s, '', hist) or { '' }
	_ := utils.is_env_assign(s)
}

fn main() {
	iter := env_int('FUZZ_ITER', 20_000)
	seed_str := os.getenv('FUZZ_SEED')
	mut seed_line := ''
	if seed_str != '' {
		seed_u64 := parse_decimal_u64(seed_str) or {
			eprintln('fuzz_shell: bad FUZZ_SEED: ${err.msg()}')
			exit(1)
		}
		rand.seed([u32(seed_u64), u32(seed_u64 >> 32)])
		seed_line = 'FUZZ_SEED=${seed_u64} (decimal from env)'
	} else {
		p := u32(os.getpid())
		rand.seed([p, p ^ 0xdeadbeef])
		seed_line = 'FUZZ_SEED omitted (PID-based)'
	}
	println('fuzz_shell: ${iter} iterations (FUZZ_ITER), ${seed_line}; stderr may be noisy (2>/dev/null to hide)')
	for i := 0; i < iter; i++ {
		fuzz_round()
	}
	println('fuzz_shell: ok (${iter} iterations)')
}
