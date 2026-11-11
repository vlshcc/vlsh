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
| Field splitting on `IFS` | yes | Splits unquoted expansion results, using space/tab/newline when unset; empty `IFS` disables splitting. Assignments and redirection operands remain scalar. |
| Comments | yes | An unquoted `#` at a token boundary starts a comment; a quoted or embedded `#` stays literal. |
| Pathname expansion | partial | POSIX glob matching for ordinary patterns, including mixed quoting; retains vlsh’s recursive `**` extension. |
| Single quotes `'…'` | yes | Literal; see `utils.parse_args` tests |
| Double quotes `"…"` | yes | Literal except `$` expansion applied in `expand_vars` |
| Backslash escapes | partial | Escaped quotes, spaces, and operators are preserved; double quotes only remove backslashes before `$`, `"`, `\\`, or newline |

## Parameter expansion

| Feature | Status | Notes |
|--------|--------|--------|
| `$parameter`, simple names | yes | `expand_vars` |
| `$?` and `$#` | yes | Last command status and number of positional parameters. `$!` awaits background execution. |
| Positional parameters | partial | Script and `-c` arguments, numbered parameters, and `"$@"` preserve boundaries. Further `$@`/ `$*` edge cases remain. |
| `$$` | yes | Process ID |
| `${parameter}` | yes | |
| `${#parameter}` | partial | Counts Unicode code points; locale-dependent character semantics remain. |
| `${parameter:-word}` | yes | Unset or empty → `word` |
| `${parameter:=word}` | yes | Assigns a shell variable when unset or empty |
| `${parameter:+word}` | yes | Set and non-empty → `word` |
| `${parameter:?word}` | yes | Reports an error and stops the current input. Inside a pipeline, the error stays in that stage. |
| Colon-free default operators | yes | `${var-word}`, `${var=word}`, `${var+word}`, and `${var?word}` distinguish unset from empty. |
| `${parameter#pattern}` `${parameter##pattern}` | partial | Glob-style `*` / `?` (no `[]` yet); shortest / longest prefix trim |
| `${parameter%pattern}` `${parameter%%pattern}` | partial | Same; shortest / longest suffix trim |
| `${parameter//x/y}` … | no | |
| Nested `${…}` in words | yes | Via recursive `expand_vars` on word parts |

## Commands and control flow

| Feature | Status | Notes |
|--------|--------|--------|
| `&&` `\|\|` `;` lists | yes | `shellops.parse_commands` parses command lists and multiline continuations. |
| Pipelines `\|` | partial | Concurrent OS pipes; status comes from the final stage. Core builtins run in isolated processes. Negation, `pipefail`, and other builtins remain. |
| Command lookup failure | yes | 127 when missing, 126 when found but not executable. Shell interpretation after `ENOEXEC` remains unsupported. |
| Command substitution and arithmetic | no | `$(...)`, backquotes, and `$((...))` remain unsupported. |
| `if` / `for` / `while` / `case` / functions | no | |
| Subshells `( )` | no | |
| Background `&` | no | Job control is not implemented |

## Redirections

| Feature | Status | Notes |
|--------|--------|--------|
| `>`, `>>`, `<`, descriptor duplication and closing | yes | Ordered for builtins and external commands, using descriptors 0–9. Builtins restore descriptors after execution. |
| `<>`, `>\|`, here-strings | no | Read/write redirection and noclobber override remain unsupported. Here-strings are an extension. |
| Here-documents `<<` | no | |

## Builtins (common POSIX)

| Builtin | Status | Notes |
|---------|--------|--------|
| `:` / `true` / `false` | yes | `:` is builtin; `true` and `false` are usually external utilities. |
| `cd` | yes | See README |
| `echo` | yes | With vlsh variable expansion rules |
| `export`, `unset` | partial | Shell-local values, export attributes, and command prefixes are distinct. Some option and error semantics remain. |
| `exit` | yes | |
| `read` | no | |
| `set` / `shift` | partial | `set --` replaces positional parameters; `shift [N]` removes parameters. Other `set` options remain. |
| `umask` | no | |

## Testing

Run `make test` for module tests plus shell integration tests. See [testing.md](testing.md) for isolation, timeouts, CI, and remaining manual checks. Module coverage includes:

- `utils/utils_test.v` — `expand_vars`, `parse_args`, `is_env_assign`, glob
- `shellops/shellops_test.v` — command lists and operators
- `exec/exec_test.v` — pipeline parsing and executable lookup
- `tests/test_shell.py` — execution, streaming I/O, environment restoration, and terminal behavior

When adding a POSIX-shaped feature, add a **small test** next to the relevant module.

## Next candidates (not yet committed)

- `[]` character classes in `${#/%}` patterns; full pathname-pattern parity
- Command substitution and arithmetic expansion
- Compound commands and here-documents
- `read`, `set -e`-style options (policy decision)
- More of the XCU §2 grammar with tests ported from public suites
