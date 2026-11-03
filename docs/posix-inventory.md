# POSIX shell subset — inventory (vlsh)

This document tracks how vlsh relates to the POSIX shell command language ([XCU §2](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)). It supports the **incremental subset** roadmap in `README.md` (POSIX compatibility → Roadmap).

Legend: **yes** = supported for typical use, **partial** = gaps/edge cases, **no** = not implemented, **n/a** = out of scope for the subset (vlsh extensions).

## Interactive extensions (bash-like, not POSIX)

| Feature | Status | Notes |
|--------|--------|--------|
| `!!` repeat last command | yes | Replaced with last **expanded** line from the interactive prompt (`utils.expand_history_notation`, `vlsh.v`) |
| `!$` last word of last command | yes | Last token after the same rules as `parse_args` on the last expanded line |
| `!n` history by index | yes | **1-based** index into `~/.vlsh_history` (last 5000 non-empty lines at startup, oldest first) plus each new typed line appended in order; `!1` is oldest in that list. Not bash’s event numbers. |
| `!-n` (n ≥ 1) | yes | **n** commands back from the newest stored line (`!-1` = newest line in the list, same idea as `!!` when that line is the previous command) |
| `!prefix` | yes | Newest history line whose text **starts with** `prefix` (non-empty word until whitespace); `!echo`, `!ls` |
| `!?sub` | yes | Newest line **containing** substring `sub`; `!?foo?` or `!?foo` (word / `?`-delimited); see `parse_bang_question` |
| `!string` (bash `!`) | partial | Only the `!prefix` form above, not bash’s full `!` grammar |

## Word splitting and quoting

| Feature | Status | Notes |
|--------|--------|--------|
| Field splitting on `IFS` (space/tab/newline) | partial | Default `IFS` (space/tab/newline) when unset; custom non-whitespace `IFS` splits with empty fields; empty `IFS` in env still uses default whitespace for lexer (POSIX nuance) |
| Single quotes `'…'` | yes | Literal; see `utils.parse_args` tests |
| Double quotes `"…"` | yes | Literal except `$` expansion applied in `expand_vars` |
| Backslash escapes | partial | Escaped quotes, spaces, and operators are preserved; double quotes only remove backslashes before `$`, `"`, `\\`, or newline |

## Parameter expansion

| Feature | Status | Notes |
|--------|--------|--------|
| `$parameter`, simple names | yes | `expand_vars` |
| `$?` `$!` `$#` (env-backed / special) | partial | Mapped via environment where applicable |
| `$0` … `$9` | partial | `$0` from `os.args`; `$1`–`9` via env if set |
| `$$` | yes | Process ID |
| `${parameter}` | yes | |
| `${#parameter}` | yes | String length (UTF-8 byte length in V) |
| `${parameter:-word}` | yes | Unset or empty → `word` |
| `${parameter:=word}` | yes | Assigns with `os.setenv` when unset or empty |
| `${parameter:+word}` | yes | Set and non-empty → `word` |
| `${parameter:?word}` | partial | Prints diagnostic to stderr; returns empty (POSIX may abort) |
| `${parameter#pattern}` `${parameter##pattern}` | partial | Glob-style `*` / `?` (no `[]` yet); shortest / longest prefix trim |
| `${parameter%pattern}` `${parameter%%pattern}` | partial | Same; shortest / longest suffix trim |
| `${parameter//x/y}` … | no | |
| Nested `${…}` in words | yes | Via recursive `expand_vars` on word parts |

## Commands and control flow

| Feature | Status | Notes |
|--------|--------|--------|
| `&&` `\|\|` `;` lists | yes | `shellops.split_commands` + `main_loop`; malformed lists are rejected before dispatch |
| Pipelines `\|` | yes | Concurrent OS pipes in `exec`; status is the final stage’s exit code |
| `if` / `for` / `while` / `case` / functions | no | |
| Subshells `( )` | no | |
| Background `&` | no | Job control is not implemented |

## Redirections

| Feature | Status | Notes |
|--------|--------|--------|
| `>`, `>>`, `<` | partial | External commands use file descriptors, including empty input files; `echo` supports output redirection. Multiple redirections are collapsed to the last target per stream. Process substitution `<( )` **no** |
| `2>&1` | partial | Merges stderr into stdout at the OS descriptor level; order relative to output redirections is not yet modeled |
| Here-documents `<<` | no | |

## Builtins (common POSIX)

| Builtin | Status | Notes |
|---------|--------|--------|
| `:` / `true` / `false` | partial | External commands on `PATH` typically |
| `cd` | yes | See README |
| `echo` | yes | With vlsh variable expansion rules |
| `export`, `unset` | yes | |
| `exit` | yes | |
| `read` | no | |
| `set` / `shift` / `umask` | no | |

## Testing

Run `make test` for module tests plus shell integration tests. See [testing.md](testing.md) for isolation, timeouts, CI, and remaining manual checks. Module coverage includes:

- `utils/utils_test.v` — `expand_vars`, `parse_args`, `is_env_assign`, glob
- `shellops/shellops_test.v` — command lists and operators
- `exec/exec_test.v` — pipeline parsing and executable lookup
- `tests/test_shell.py` — execution, streaming I/O, environment restoration, and terminal behavior

When adding a POSIX-shaped feature, add a **small test** next to the relevant module.

## Next candidates (not yet committed)

- `[]` character classes in `${#/%}` patterns; full pathname-pattern parity
- Post-expansion field splitting (split expanded words on `IFS` separately from lexer)
- True empty-`IFS` lexer behaviour vs POSIX
- `read`, `set -e`-style options (policy decision)
- More of the XCU §2 grammar with tests ported from public suites
