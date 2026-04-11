# POSIX shell subset — inventory (vlsh)

This document tracks how vlsh relates to the POSIX shell command language ([XCU §2](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html)). It supports the **incremental subset** roadmap in `README.md` (POSIX compatibility → Roadmap).

Legend: **yes** = supported for typical use, **partial** = gaps/edge cases, **no** = not implemented, **n/a** = out of scope for the subset (vlsh extensions).

## Interactive extensions (bash-like, not POSIX)

| Feature | Status | Notes |
|--------|--------|--------|
| `!!` repeat last command | yes | Every `!!` in the line is replaced with the last **expanded** interactive command; `utils.expand_history_bangs` in `vlsh.v` main loop; `!$`, `!n`, etc. **no** |

## Word splitting and quoting

| Feature | Status | Notes |
|--------|--------|--------|
| Field splitting on `IFS` (space/tab/newline) | partial | Default `IFS` (space/tab/newline) when unset; custom non-whitespace `IFS` splits with empty fields; empty `IFS` in env still uses default whitespace for lexer (POSIX nuance) |
| Single quotes `'…'` | yes | Literal; see `utils.parse_args` tests |
| Double quotes `"…"` | yes | Literal except `$` expansion applied in `expand_vars` |
| Backslash escapes | partial | Not a full POSIX escape table in all contexts |

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
| `&&` `\|\|` `;` lists | yes | `shellops.split_commands` + `main_loop` |
| Pipelines `\|` | yes | Handled in execution path (`exec` / `walk_pipes`) |
| `if` / `for` / `while` / `case` / functions | no | |
| Subshells `( )` | no | |
| Background `&` | partial / no | Depends on existing exec support |

## Redirections

| Feature | Status | Notes |
|--------|--------|--------|
| `>`, `>>`, `<` | partial | Supported where documented; process substitution `<( )` **no** |
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

Regression coverage lives in `v test .`, especially:

- `utils/utils_test.v` — `expand_vars`, `parse_args`, `is_env_assign`, glob
- `shellops/shellops_test.v` — command lists and operators
- `exec/exec_test.v` — external command behaviour

When adding a POSIX-shaped feature, add a **small test** next to the relevant module.

## Next candidates (not yet committed)

- `[]` character classes in `${#/%}` patterns; full pathname-pattern parity
- Post-expansion field splitting (split expanded words on `IFS` separately from lexer)
- True empty-`IFS` lexer behaviour vs POSIX
- `read`, `set -e`-style options (policy decision)
- More of the XCU §2 grammar with tests ported from public suites
