# vlsh

**vlsh** is an interactive Unix shell written in [V](https://vlang.io). It is
designed to be simple, fast, and hackable — with a clean codebase that is easy
to read, modify, and extend.

### Features at a glance

- **Pipes, redirection, and command chaining** — `cmd1 | cmd2`, `> file`, `>> file`, `< file`, `2> file`, and `2>&1` (merge stderr into stdout); AND-chains (`&&`), OR-chains (`||`), and unconditional sequences (`;`)
- **Glob expansion** — `*.v`, `./*.deb`, `~/docs/**` expanded before execution
- **Tilde and parameter expansion** — `~/path`, `$VAR`, `${var:-word}`, `${#var}`, `${var#pat}` / `${var%pat}` (glob `*`/`?` in `pat`), nested `${…}`, `VAR=val cmd`; unquoted expansions split on session **`IFS`** (default space/tab/newline) (see [docs/posix-inventory.md](docs/posix-inventory.md))
- **Command history** — up/down arrow browsing and `Ctrl+R` incremental search;
  shared across all sessions (last 5000 entries in `~/.vlsh_history`);   bash-style **`!!`**, **`!$`**, **`!n`**, **`!-n`**, **`!prefix`**, **`!?sub`**
  (see docs), interactive prompt only
- **Tab completion** — files and directories; the first word also completes
  command names found in `$PATH`; after `cd` with a space, only directories are
  suggested; plugins can register custom completions (e.g. SSH hostname completion)
- **Inline autosuggestions** — as you type, the most recent matching history
  entry is shown as dimmed ghost text; `cd` suggestions are validated against
  the current filesystem and fall back to live directory listing when no valid
  history match exists; press `→` or `End` to accept
- **Aliases** — defined in `~/.vlshrc` or managed live with `aliases add/remove`
- **Plugin system** — plugins are installed from the official remote repository
  into versioned directories under `~/.vlsh/plugins/<name>/<version>/`; vlsh
  compiles them automatically. Plugins can add commands, decorate the prompt,
  run pre/post hooks around every command, capture command output via the
  `output_hook` capability, provide custom tab completions, contribute live
  text to the mux status bar (`mux_status` capability), and expose their own
  help text via the `help` capability (surfaced through the built-in `help` command).
  Search plugins by name or description with `plugins search`, install the
  latest version with `plugins install`, keep them up to date with
  `plugins update`, remove them with `plugins delete`, or purge and
  re-fetch the latest with `plugins reinstall`. The official
  repository is at https://github.com/vlshcc/plugins.
- **Terminal multiplexer** — built-in `mux` command splits the terminal into
  resizable panes, each running its own shell. Supports mouse selection,
  copy/paste, a status bar, per-pane scrollback history (up to 1000 lines,
  scrollable via mouse wheel or `Ctrl+V`+`PageUp`/`PageDown`), and all common
  VT100 sequences so editors like `vim` and `nano` work correctly inside panes.
- **Native `.vsh` script support** — execute V shell scripts directly without
  invoking `v run` manually
- **POSIX environment variables** — `export`, `unset`, and `VAR=val cmd` prefix
- **Theming** — prompt and UI colours configurable via `style set` and `~/.vlshrc`


## INSTALL

### Pre-built packages (recommended)

The latest published release is **v1.2** (package version **1.2.0**). The Linux
`.deb` and standalone binary are available on the
[releases page](https://github.com/vlshcc/vlsh/releases/tag/v1.2).
The behavior documented below follows the current `main` branch; build from
source for the unreleased stability and packaging fixes in [CHANGELOG.md](CHANGELOG.md).

**Debian / Ubuntu — install via `.deb`:**

```sh
curl -LO https://github.com/vlshcc/vlsh/releases/download/v1.2/vlsh_1.2.0_amd64.deb
sudo dpkg -i vlsh_1.2.0_amd64.deb
```

The package installs the binary to `/usr/bin/vlsh` and automatically adds it
to `/etc/shells` via the postinst script.

**Fedora / RHEL — build an `.rpm` from source:**

The published release has no RPM asset. With V and `rpmbuild` installed:

```sh
git clone https://github.com/vlshcc/vlsh.git
cd vlsh
make dist-rpm
sudo rpm -U builds/vlsh-1.2.0-1.*.rpm
```

**Other Linux — standalone binary:**

```sh
curl -LO https://github.com/vlshcc/vlsh/releases/download/v1.2/vlsh_1.2.0_amd64_linux
chmod +x vlsh_1.2.0_amd64_linux
sudo mv vlsh_1.2.0_amd64_linux /usr/local/bin/vlsh
```

### Prerequisites (from source)

- [V](https://vlang.io) — CI uses V 0.5.2; install from https://github.com/vlang/v
- `make` and a C compiler; Python 3 for `make test`

### Build and run (try it out)

```sh
git clone https://github.com/vlshcc/vlsh.git
cd vlsh
v .
./vlsh
```

From the same directory, `make help` summarizes Makefile targets; `make test` runs the V module tests and Python 3 shell integration tests (see [Testing and stability](docs/testing.md)), `make build` compiles (`v .`), and `make clean` removes the `vlsh` binary. **`make fuzz`** runs `tools/fuzz_shell.v` to stress parsers with random input (`FUZZ_ITER`, optional decimal `FUZZ_SEED` as a full integer string). Random lines can trigger stderr from parameter expansion diagnostics; use `2>/dev/null` if you want a quiet run. Override the compiler with `make V=/path/to/v`.

`make install` installs the already-built `vlsh` into `$(PREFIX)/bin` (default `/usr/local/bin`) and adds that path to `/etc/shells` if it is missing. Run `make build` as your regular user first, then `sudo make install`. Installation does not invoke V, so the compiler does not need to be in sudo's PATH. Set `REGISTER_SHELL=0` to skip registration (for example, for a user-local install). Staged installs with `DESTDIR` skip registration; `SHELLS_FILE` overrides the registry path for testing.

**Distribution builds** — `make dist` (same as `make dist-build`) runs `pkg/dist.sh build`. Existing artifacts for the selected targets and host architecture are preserved with a timestamp; earlier archives and other targets are left in place. The default builds all targets:

- **Linux** — `.deb` (needs `dpkg-deb`), `.rpm` (needs `rpmbuild`), and a standalone `vlsh_*_*_linux` binary
- **FreeBSD** and **DragonFly** — cross-compiled binaries (needs `clang` and `lld`; DragonFly also downloads an ISO once — use `bsdtar` *or* GNU `tar` to extract it, plus `curl` and `bunzip2`)
- **NetBSD** and **OpenBSD** — native builds only: when `dist` runs on Linux, these steps no-op; run `pkg/build.sh --netbsd` or `--openbsd` **on** NetBSD/OpenBSD to produce `builds/vlsh_*_*_netbsd` / `_openbsd` (V does not yet ship a Linux→NetBSD/OpenBSD cross sysroot like FreeBSD).

Use `make dist-deb` for only `.deb`, `make dist-rpm` for only `.rpm`, or `make dist-linux` for available Linux packages plus the standalone binary. Explicit package targets require their packaging tool and fail if it is missing. Both scripts accept `--deb`, `--rpm`, `--linux`, and `--standalone`; `pkg/dist.sh build` also accepts combinations with BSD targets. For example, `make dist DIST_FLAGS="--deb --netbsd"` selects those two targets. `make V=/path/to/v` also applies to distribution builds.

**FreeBSD cross-build** — `pkg/build.sh` pre-clones the FreeBSD sysroot (same GitHub tree V uses for linking) *before* invoking `v`, because V currently builds third-party C objects before it downloads that sysroot; without this step, `pthread.h` and similar headers are missing during `gc.o` compilation.

BSD port templates under `pkg/` are drafts with placeholder checksums and require native validation. See [FreeBSD port notes](docs/freebsd-port.md), [DragonFly port notes](docs/dragonfly-port.md), and [DragonFly build notes](docs/dragonfly-support.md).

`make dist-install` runs `pkg/dist.sh install`: it selects the **newest** suitable `.deb`, `.rpm`, or OS-specific binary in `builds/` for the current platform (by modification time) and installs it (`sudo` when not root).

Running `make dist build` executes **both** the `dist` and `build` targets in order (a full distribution build, then an extra `v .` for the current tree — usually you only need `make dist`).

Or run directly without compiling first:

```sh
v run .
```

### Non-interactive execution

```sh
./vlsh -c 'printf hello | cat'
./vlsh path/to/script arg1 arg2
./vlsh -c 'printf "%s\n" "$0" "$@"' name arg1 arg2
printf 'echo hello\nfalse\n' | ./vlsh
./vlsh --version
```

Batch execution returns the last command's exit code and skips prompts, history,
startup exports, and automatic plugin loading. Existing aliases are read from
`~/.vlshrc`; batch mode does not create that file. Scripts support multiline
pipelines, conditional lists, quoted words, and backslash continuations. An
unquoted `#` at the start of a token introduces a comment. The shell supports
the simple-command subset described below.

### System-wide install

After building, install the binary to your `PATH`:

```sh
make build
sudo make install
# or: sudo cp vlsh /usr/local/bin/vlsh
```

Verify it is accessible:

```sh
which vlsh   # should print /usr/local/bin/vlsh
vlsh --version 2>/dev/null || vlsh -c 'version'
```

### Set vlsh as your default login shell

1. Install and register vlsh in the list of approved shells:

   ```sh
   make build
   sudo make install
   ```

2. Change your login shell:

   ```sh
   chsh -s /usr/local/bin/vlsh
   ```

3. Log out and back in (or open a new terminal). Your session should now start in vlsh.

To revert at any time:

```sh
chsh -s /bin/bash   # or /bin/zsh, etc.
```

## USE
I'm using vlsh as my daily shell. That does not mean you should be.
It is likely that you will run into bugs when using vlsh.


## CONFIG
vlsh will look for the configuration file `$HOME/.vlshrc`.
Here's an example -file:

```
# Environment
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Aliases
alias gs=git status
alias gps=git push
alias gpl=git pull
alias gd=git diff
alias gc=git commit -sa
alias gl=git log
alias vim=nvim

# Style (define in RGB colors)
#style_git_bg=44,59,71
#style_git_fg=251,255,234
#style_debug_bg=255,255,255
#style_debug_fb=251,255,234
```


## DOCUMENTATION

### Architecture overview

```
vlsh.v          – main entry point, prompt rendering, builtins
evaluator.v     – evaluates command lists, expands words, and dispatches commands
cfg/cfg.v       – config file (~/.vlshrc) parsing, aliases, paths, style
cmds/cmds.v     – built-in commands: help, cd
cmds/ls.v       – built-in colorised ls
cmds/cp.v       – built-in overwrite-copy (ocp)
exec/exec.v     – concurrent pipeline execution and I/O redirection
exec/process_helpers.h – POSIX process, pipe, signal, and wait helpers
shellops/       – parser for lists of simple commands and pipelines
tests/         – shell, installation, and packaging integration tests
mux/mux.v       – terminal multiplexer entry point and event loop
mux/pane.v      – per-pane VT100 parser and cell grid
mux/layout.v    – binary-tree layout engine (splits/resize/navigation)
mux/render.v    – grid-to-terminal renderer
mux/input.v     – key-sequence parser for mux prefix bindings
mux/pty.v       – PTY helpers (thin wrappers around C functions)
mux/pty_helpers.h – C helpers: raw mode, winsize, select, forkpty, exec
utils/          – lexer, word expansion, shell variables, and shared helpers
plugins/        – plugin loader and hook dispatcher
```

### Config file (~/.vlshrc)

A plain-text file sourced at startup. Lines beginning with `#` are comments.
`export` and `unset` lines are executed as shell commands; `alias` and `style`
lines use the config syntax below.

| Directive | Example | Meaning |
|-----------|---------|---------|
| `export KEY=VALUE` | `export PATH="/opt/bin:$PATH"` | Set an environment variable (`$VAR` is expanded) |
| `alias <name>=<cmd>` | `alias gs=git status` | Define a command alias |
| `style_git_bg=r,g,b` | `style_git_bg=44,59,71` | Git-branch prompt background colour |
| `style_git_fg=r,g,b` | `style_git_fg=251,255,234` | Git-branch prompt foreground colour |
| `style_debug_bg=r,g,b` | | Debug-output background (when `VLSHDEBUG=true`) |
| `style_debug_fg=r,g,b` | | Debug-output foreground |

### Built-in commands

| Command | Description |
|---------|-------------|
| `aliases list` | List all defined aliases |
| `aliases add <name>=<cmd>` | Add or update an alias |
| `aliases remove <name>` | Remove an alias |
| `: [args…]` | Expand arguments and apply redirections, then return success |
| `cd [dir]` | Change directory; `~` and `~/path` expand to `$HOME`; home if omitted; `cd -` returns to the previous directory |
| `echo [args…]` | Print arguments |
| `exit [N]` | Exit the shell with an optional status code (defaults to the last status) |
| `export [NAME[=value] …]` | Mark variables for export to child processes, optionally assigning values; `export -p` lists exported values as shell commands |
| `help [cmd]` | Show commands or detailed command help; `help syntax` explains the supported shell language |
| `ls [dir]` | Colorised directory listing (falls through to system `ls` when flags are passed) |
| `mux` | Enter terminal multiplexer mode |
| `ocp <src> <dst>` | Copy file, overwriting destination |
| `plugins list` | List locally installed plugins with version and status |
| `plugins enable <name>` | Enable a disabled plugin by name |
| `plugins enable all` | Enable every plugin at once |
| `plugins disable <name>` | Disable a plugin by name |
| `plugins disable all` | Disable every plugin at once |
| `plugins reload` | Hot-reload all plugins |
| `plugins remote` | List remote plugins; shows installed version and available updates |
| `plugins search <query>` | Search remote plugins by name or description |
| `plugins install <name>` | Download and install the latest version of a plugin |
| `plugins update [name]` | Update one or all installed plugins to their latest version |
| `plugins delete <name>` | Delete an installed plugin |
| `plugins reinstall <name>` | Remove the local plugin and install the latest from the remote repository |
| `source <file>` / `. <file>` | Execute a script in the current shell context (respects `#` comments and blank lines) |
| `set -- [args…]` / `shift [N]` | Replace positional parameters or remove the first `N` (default 1) |
| `style list` | Show current style/colour settings |
| `style set <key> <r> <g> <b>` | Set a prompt colour (RGB 0–255) |
| `unset <NAME> …` | Remove one or more environment variables |
| `version` | Print the vlsh version |

### Shell features

**Pipes** – chain commands with `|`:
```
ls | grep .v | wc -l
```

**Output redirection** – write or append stdout to a file:
```
echo "hello" > file.txt
echo "world" >> file.txt
```

**Redirecting stderr** – `2> file` sends stderr to a file, and `2>&1` duplicates the current stdout onto stderr. Both work with builtins and external commands:
```
some_cmd > log.txt 2>&1
some_cmd 2>&1 | grep -i error
```
Redirections apply from left to right, after setting up any pipeline.
`cmd > log.txt 2>&1` sends both streams to the file; `cmd 2>&1 > log.txt`
sends stderr to the original stdout. Descriptors 0–9 can be opened, duplicated,
or closed. A standalone builtin restores the original descriptors when it finishes.

**Input redirection** – feed a file into a command's stdin with `<`:
```
wc -l < report.txt
grep error < app.log | wc -l
```

**AND-chains** – run the next command only if the previous one succeeds (exit 0):
```
touch /tmp/x && echo "file created"
```

**OR-chains** – run the next command only if the previous one fails (exit non-0):
```
ping -c1 host || echo "host unreachable"
```

**Unconditional sequences** – run commands one after another regardless of exit status:
```
echo hello ; echo world
make ; make install
```

**Tilde expansion** – `~` and `~/path` are expanded to `$HOME` in both commands and arguments:
```
vi ~/.config/nvim/init.vim
```

**Environment-variable prefix** – scope variables to an external command or a regular builtin; previous values are restored afterwards:
```
FIELD_LIST='used,avail' df -h --no-sync .
```

Assignment-only commands such as `NAME=value` persist in the current session.
New variables stay local to the shell until `export NAME`; an already exported
variable stays exported when reassigned. Each pipeline stage has its own prefix
assignments. Prefix assignments on POSIX special builtins such as `export` and `.` persist in the shell.

**Parameter expansion** – Supports `$VAR`, `$$`, `$?`, `$0`, positional
parameters (`$1`, `${10}`, `$#`, `"$@"`), and brace forms such as `${VAR}`,
`${#VAR}`, `${var:-word}`, `${var:=word}`, `${var:+word}`, `${var:?word}`,
and prefix/suffix trimming. Omitting the colon makes the default operators test
for unset values only. A required parameter error stops the current input; inside a pipeline it stops that stage.
Single quotes preserve literal text; double quotes allow expansion and preserve
the result as one field (except for `"$@"`).

**Field splitting** – Unquoted expansion results split on `IFS` (space, tab,
and newline when unset). Empty `IFS` disables splitting, and literal source
text is never split by `IFS`. Assignment values and redirection filenames
are kept as single values. Pathname expansion follows field splitting.

**Last exit status** – `$?` holds the exit code of the most recently run command and is updated after every command, including each step in `&&` / `||` / `;` chains:
```
false
echo $?    # prints 1
true && echo $?   # prints 0
```

**Command history** – up/down arrows browse history; `Ctrl+R` searches history.
All instances share a global history file at `~/.vlsh_history` (last 5000 entries).
**History expansion** (bash-style, not POSIX) — runs on the raw line before
parsing, at the interactive prompt only:

- **`!!`** — replaced with the **expanded** text of the previous command (e.g.
  `sudo !!` after `ls -la` → `sudo ls -la`). Errors if nothing has run yet.
- **`!$`** — replaced with the **last word** of that previous expanded line (same
  tokenisation as normal parsing, e.g. after `ls -la /tmp` → `/tmp`).
- **`!n`** — replaced with the **n**th stored history line (**1-based**): lines
  loaded from `~/.vlsh_history` (last 5000 non-empty lines, **oldest** = `!1`)
  plus each new line you type in this session, in order. This is **not** the same
  numbering as bash’s `history` event IDs.
- **`!-n`** (n ≥ 1) — **n** lines back from the **newest** stored entry (`!-1` is
  the most recent line in the list — usually the same as the last command you
  typed, analogous to `!!` when that entry is the previous command).
- **`!prefix`** — the **newest** history line that **starts with** `prefix`
  (one non-empty word, no leading digit — those are `!n`). Example: `!echo`
  after `echo hello` → `echo hello`.
- **`!?sub`** — the **newest** line **containing** `sub`. Use `!?foo?` to end the
  substring at the next `?`, or `!?foo` to use a single word (`foo`).

**Note:** `!!` substitutes the **last expanded** command line, while `!-1` (and
`!n`) refer to **stored history text** (what was typed). After you run `!!`,
history records the characters `!!`, not the expanded command — so `!-1` can
differ from `!!` in that case.

If expansion fails (e.g. `!99` out of range), vlsh prints an error and skips the
line. Lines from scripts (`source`, `.vlshrc`) do not append to this list or
update the “last command” used for `!!` / `!$`.

**Tab completion** – completes file and directory names. For the first word on the line (the command), names from `$PATH` are merged with matches in the current directory (unless you are typing a path that contains `/`, which is completed only as a filesystem path). When the command is `cd`, only directories are suggested. Plugins can register a `completion` capability to provide custom completions for their commands (e.g. SSH hostnames for `ssh`).

**Inline autosuggestions** – as you type, vlsh searches command history (most-recent first) for the first entry that starts with the current input and displays the untyped remainder as dimmed ghost text to the right of the cursor. Pressing `→` (right arrow) or `End` when the cursor is already at the end of the line accepts the full suggestion and inserts it into the input.

For `cd` commands, each history candidate is validated against the filesystem before being offered: if the target directory no longer exists the entry is skipped and the next matching history entry is tried. When no valid history entry is found, the shell falls back to the tab-completion engine to generate a filesystem suggestion — for `cd` this is the first alphabetically sorted directory in the current working directory (or inside the partial path already typed); for other commands it is the first matching file, `$PATH` command name, or plugin completion result.

The ghost text is erased cleanly when you press Enter, so only the text you actually typed appears in the executed command line.

### POSIX compatibility

vlsh is not a POSIX-conformant shell, but it supports the most commonly used POSIX shell features so that everyday scripts and interactive habits carry over without surprises.

#### Roadmap: incremental POSIX subset

The goal is **option (b)**: grow a **documented, tested subset** of POSIX *sh* behavior—without claiming full conformance and without removing vlsh-specific features.

**Counted as vlsh-only (not part of the POSIX subset goal):** plugins, `.vsh` / `v run`, `mux`, fish-style inline autosuggestions, and other extensions documented elsewhere.

**Suggested phases**

1. **Stabilise the current surface** — Keep tests for tokenisation and quotes (`lex`), command lists (`parse_commands`), `$` expansion (`expand_vars`), globs, leading `VAR=value` assignments, builtins such as `export`, `unset`, `cd`, `source` / `.`, pipes, and redirection. Extend **`make test`** whenever behavior is fixed or specified more precisely (see `utils/*_test.v`, `shellops/*_test.v`, `exec/*_test.v`). A **feature inventory** (what is implemented vs not) is maintained in [`docs/posix-inventory.md`](docs/posix-inventory.md).

2. **Parameter expansion and word splitting** — The lexer preserves source
   spelling, then expansion distinguishes arguments, assignments, and
   redirection targets. Continue filling the pattern matching and expansion
   gaps in the inventory.

3. **Shell grammar** — The parser handles lists of simple commands and pipelines.
   Command substitution, arithmetic expansion, here-documents, compound commands,
   functions, and subshells remain candidates for separate increments.

4. **Hardening** — Port or adapt individual cases from public POSIX-style shell test suites where practical; full certification is not the target.

**Contributing** — Prefer small, test-backed changes that match existing modules (`utils`, `shellops`, `exec`, `cmds`) rather than large rewrites.

#### Command chaining operators

| Operator | Behaviour |
|----------|-----------|
| `cmd1 && cmd2` | Run `cmd2` only if `cmd1` exits 0 |
| `cmd1 \|\| cmd2` | Run `cmd2` only if `cmd1` exits non-0 |
| `cmd1 ; cmd2` | Run `cmd2` unconditionally after `cmd1` |

All three operators respect single and double quotes (an operator inside quotes is treated as literal text), and a lone `|` is always treated as a pipe, not part of `||`.

#### Input redirection

```
sort < unsorted.txt
diff <(sort a.txt) <(sort b.txt)   # requires process substitution; not yet supported
grep pattern < file.txt | wc -l
```

#### Exit status (`$?`)

`$?` is set after every command — including each step in a chain — and can be read with `echo $?`. It is initialised to `0` when the shell starts. A command that cannot be found returns 127; one found but not executable returns 126.

#### `export` and `unset`

`export` is the standard way to set environment variables, including `PATH`.
It works both interactively and in `~/.vlshrc`:

```
export PATH="/opt/bin:$PATH" # prepend to PATH ($PATH is expanded)
export EDITOR=nvim           # set and mark variable for child processes
export                       # list all current environment variables
unset EDITOR                 # remove a variable from the environment
```

#### `source` / `.`

Execute a script file in the current shell context. It uses the same command parser as batch mode, including multiline pipelines and comments. The return value is the exit code of the last command in the file.

```
source ./session.sh
. ./session.sh       # POSIX dot-command synonym
```

`export` and `unset` lines in `~/.vlshrc` are executed automatically at startup. Use `source` for files containing shell commands. Config-only `alias` and `style` directives are handled by the configuration loader.

#### `cd` improvements

| Invocation | Behaviour |
|-----------|-----------|
| `cd` | Change to `$HOME` |
| `cd ~` | Change to `$HOME` |
| `cd ~/path` | Change to `$HOME/path` |
| `cd -` | Change to the previous working directory (stored in `$OLDPWD`) and print the new path |
| `cd /some/dir` | Change to the given path |

`$PWD` and `$OLDPWD` are kept in sync after every successful `cd`.

#### `exit N`

```
exit        # exit with code 0
exit 1      # exit with code 1
exit 42     # exit with code 42
```

The exit code is visible to the parent process (`echo $?` in an outer shell).

#### Aliases that expand to builtins

Aliases whose expansion begins with a builtin command work correctly:

```
aliases add nav cd /tmp
nav           # equivalent to: cd /tmp
aliases add home cd ~
home          # equivalent to: cd ~
```

**Plugins** – installed from the remote repository into versioned directories under `~/.vlsh/plugins/<name>/<version>/`. Each plugin can expose commands, pre/post-run hooks, output capture hooks (`output_hook`), prompt decorations, custom tab completions, and help text (`help` capability) shown by the built-in `help` command.

**Aliases** – defined in `~/.vlshrc` or managed with the `aliases` built-in; resolved before PATH lookup.

**Debug mode** – set `VLSHDEBUG=true` in the environment to print internal debug output.

**`.vsh` scripts** – vlsh natively runs V shell scripts (`.vsh` files) via `v run`. You can execute them directly without specifying `v run` manually:
```
./myscript.vsh
~/bin/myscript.vsh
myscript.vsh          # looked up in current directory
```
A `.vsh` file is a regular V source file with all `os` module functions available globally (no `os.` prefix needed). Use the following shebang to make the file directly executable outside vlsh too:
```v
#!/usr/bin/env -S v
```
Example script (`hello.vsh`):
```v
#!/usr/bin/env -S v
println('Hello from a .vsh script!')
files := ls('.') or { [] }
for f in files {
    println(f)
}
```
vlsh looks for the `v` binary in `$PATH`.

### Plugins

Plugins extend vlsh with new commands and prompt decorations without modifying the shell binary.

#### How plugins work

1. Install a plugin from the remote repository with `plugins install <name>`. The source is stored in `~/.vlsh/plugins/<name>/<version>/`.
2. vlsh compiles it automatically on startup (requires `v` in PATH) and caches the compiled binary in `~/.vlsh/plugins/.bin/`.
3. The binary is called by the shell with a single argument that tells it what to do (see the protocol below).
4. Use the built-in `plugins` command to manage them at runtime.

#### Plugin protocol

Your plugin's `main()` must handle these arguments:

| Argument | Description |
|----------|-------------|
| `capabilities` | Print what the plugin provides, one item per line (see table below) |
| `run <command> [args…]` | Execute a registered command |
| `prompt` | Print a single line shown above the `- ` prompt |
| `pre_hook <cmdline>` | Called before every command runs |
| `post_hook <cmdline> <exit_code>` | Called after every command finishes |
| `output_hook <cmdline> <exit_code> <output>` | Called after every command; `<output>` is the captured stdout (empty for interactive/direct-terminal commands not in a pipe chain) |
| `complete <input>` | Print one tab-completion candidate per line for the current input |
| `mux_status` | Print a single line shown centred in the mux status bar (polled ~1 s) |
| `help [command]` | Print help text for the plugin or a specific command (called by the built-in `help` command) |

Capability tokens (printed in response to `capabilities`):

| Token | Effect |
|-------|--------|
| `command <name>` | Registers `<name>` as a shell command dispatched via `run` |
| `prompt` | Shell calls `prompt` before each prompt and displays the output above `- ` |
| `pre_hook` | Shell calls `pre_hook <cmdline>` before every command |
| `post_hook` | Shell calls `post_hook <cmdline> <exit_code>` after every command |
| `output_hook` | Shell calls `output_hook <cmdline> <exit_code> <output>` after every command with the captured stdout |
| `completion` | Shell calls `complete <input>` on Tab; plugin prints full replacement strings |
| `mux_status` | Shell calls `mux_status` roughly once per second in mux mode; plugin prints a single line that appears centred in the status bar |
| `help` | Shell calls `help [command]` when the user runs `help <cmd>` and the plugin owns that command; plugin prints its own help text |

#### Managing plugins

```
plugins list                      – list installed plugins with version and status
plugins enable  <name>            – enable a previously disabled plugin
plugins enable  all               – enable every plugin at once
plugins disable <name>            – disable a plugin without deleting it
plugins disable all               – disable every plugin at once
plugins reload                    – recompile and reload all plugins
plugins remote                    – list remote plugins; shows installed version and updates
plugins search  <query>           – search remote plugins by name or description
plugins install <name>            – download and install the latest version
plugins update  [name]            – update one or all plugins to their latest version
plugins delete  <name>            – delete a locally installed plugin
plugins reinstall <name>          – remove local copy and install latest from remote
```

Plugins are sourced from the official repository at
https://github.com/vlshcc/plugins. Each plugin has a `DESC` metadata file
with its name, author, and description — used by `plugins search`. No
external tooling is required; `install` downloads source directly. After
installing a plugin, run `plugins reload` to compile and activate it.
`plugins reinstall` removes the local copy, installs the latest from remote,
and reloads plugins in one step.

#### Example plugin (`examples/hello_plugin.v`)

A minimal template that shows all capabilities. Copy it to get started:

```sh
cp examples/hello_plugin.v ~/.vlsh/plugins/myplugin.v
```

It registers a `hello [name]` command, contributes a `[ example plugin ]` prompt line, has empty `pre_hook` / `post_hook` / `output_hook` stubs ready to be filled in, demonstrates the `mux_status` capability with a static label, and implements the `help` capability so that `help hello` prints usage text.

```v
// Respond to 'capabilities'
println('command hello')
println('help')
println('prompt')
println('pre_hook')
println('post_hook')
println('mux_status')

// Respond to 'run hello [name]'
println('Hello, ${name}!')

// Respond to 'help [command]'
println('hello - greet someone (example plugin command)')
println('')
println('Usage:')
println('  hello [name]   Print "Hello, <name>!"')
println('')
println('If name is omitted, greets "world".')

// Respond to 'prompt'
println('[ example plugin ]')

// Respond to 'output_hook <cmdline> <exit_code> <output>'
// os.args[2] = cmdline, os.args[3] = exit code, os.args[4] = captured stdout

// Respond to 'mux_status'
println('[ example plugin ]')
```

#### Git prompt plugin

Shows the current git branch and short commit hash in the prompt, styled with your `style_git_bg` / `style_git_fg` colours.

```sh
plugins install git
plugins reload
```

When inside a git repository the line above the `- ` prompt becomes:

```
 main a1b2c3d
```

(coloured block using the 24-bit ANSI colour values from `~/.vlshrc`)

The plugin reads colours from `~/.vlshrc`; defaults are `44,59,71` (dark blue-grey background) and `251,255,234` (near-white foreground). Override them with:

```
style set style_git_bg 44 59 71
style set style_git_fg 251 255 234
```

#### SSH host completion plugin

`ssh_hosts` provides tab completion for SSH hostnames. When you type `ssh <prefix>` and press Tab, it returns matching hosts gathered from `~/.ssh/config` and `~/.ssh/known_hosts`. It also supports `user@<prefix>` notation.

```sh
plugins install ssh_hosts
plugins reload
```

Usage:
```
ssh web<Tab>       → ssh webserver, ssh web01 …
ssh root@db<Tab>   → ssh root@db1, ssh root@db2 …
```

Sources read (automatically, no configuration needed):
- `~/.ssh/config` — `Host` entries (wildcard patterns like `*` are skipped)
- `~/.ssh/known_hosts` — all non-hashed entries (hashed `|1|…` lines are skipped)

#### V module documentation plugin

`vman` is a man-page style viewer for the official V module documentation at
[modules.vlang.io](https://modules.vlang.io/). It fetches the HTML for any
standard-library module, strips the markup, and displays the result in `less`
(with ANSI colour support) so you can scroll, search, and quit just like a
regular man page.

```sh
plugins install v_man
plugins reload
```

Usage:
```
vman os
vman strings
vman net.http
vman math
```

What it does:

1. Fetches `https://modules.vlang.io/<module>.html`.
2. Converts the HTML to ANSI-formatted text:
   - headings become **bold** (h1 also underlined)
   - inline `code` and `pre` blocks are cyan
   - lists, paragraphs, and horizontal rules are preserved
   - `<script>`, `<style>`, and `<noscript>` blocks are stripped
3. Opens the result in `less -R` (or `more` if `less` is unavailable). Falls
   back to printing directly if neither pager is found.

#### Output log plugin (`examples/output_log.v`)

`output_log` uses the `output_hook` capability to record every command and its captured stdout to `~/.vlsh/output.log`, one timestamped block per command. It also registers two commands: `output_search <pattern>` to grep through the log from within the shell, and `output_log_clear` to wipe it.

```sh
mkdir -p ~/.vlsh/plugins/output_log/v1.0.0
cp examples/output_log.v ~/.vlsh/plugins/output_log/v1.0.0/output_log.v
plugins reload
```

Usage:
```
output_search error       # find all log blocks containing "error"
output_log_clear          # wipe the log
```

> **Note:** output is captured only for commands run through a pipe chain or the `echo` built-in. Interactive programs (`vim`, `htop`, etc.) and simple direct-terminal commands log a header with an empty body, preserving the timeline without breaking TTY behaviour.

#### Share plugin (`plugins/share.v`)

`share` uploads a file to [dpaste.com](https://dpaste.com) and prints the resulting URL. It is available as a plugin in the official repository.

```sh
plugins install share
plugins reload
```

Usage:
```
share <file>
```

### Multiplexer (mux)

Start with `mux`. A new vlsh session fills the terminal. All key sequences require the **Ctrl+V** prefix.

| Key | Action |
|-----|--------|
| `Ctrl+V` + `\|` | Split active pane vertically (left / right) |
| `Ctrl+V` + `-` | Split active pane horizontally (top / bottom) |
| `Ctrl+V` + `←/→/↑/↓` | Navigate to the adjacent pane |
| `Ctrl+V` + `Ctrl+←/→` | Resize pane horizontally |
| `Ctrl+V` + `Ctrl+↑/↓` | Resize pane vertically |
| `Ctrl+V` + `o` | Cycle focus to the next pane |
| `Ctrl+V` + `PageUp` | Scroll active pane back into scrollback history |
| `Ctrl+V` + `PageDown` | Scroll active pane forward toward live output |
| `Ctrl+V` + `q` | Exit mux (only when all panes have been closed) |
| `Ctrl+V` + `Ctrl+V` | Send a literal Ctrl+V to the active pane |
| Mouse click | Click a pane to make it active |
| Mouse wheel | Scroll active pane up/down through scrollback history |

Each pane retains up to 1000 lines of scrollback history. While scrolled back, an orange indicator in the top-right corner of the pane shows how many lines above live output you are. Panes close automatically when their shell process exits. The terminal is fully restored on exit and a confirmation message is printed.

The status bar at the top shows `vlsh mux` on the left and the live pane count on the right. Plugins that declare the `mux_status` capability contribute text that is displayed centred between those labels and refreshed roughly once per second.

### Module API summary

**`cfg`** – `get() !Cfg`, `aliases() !map[string]string`, `style() !map[string][]int`, `add_alias`, `remove_alias`, `set_style`

**`exec`** – `Task.prepare_task() !int` executes expanded tokens; `Task.run_stages` executes prepared pipeline stages with ordered redirections and returns the final status

**`utils`** – `parse_tokens(string) []ShellToken` retains operator provenance; `parse_args(string) []string` tokenises a command line respecting single/double quotes; `fail/warn/ok/debug` for formatted output

**`mux`** – `enter(status_providers []string)` is the public entry point; internally uses `Mux`, `Pane`, `LayoutNode`, `InputHandler`

**`plugins`** – `load() []Plugin`, `installed_list() []InstalledPlugin`, `available() []string`, `dispatch(…) bool`, `completions(loaded, input) []string`, `run_pre_hooks`, `run_post_hooks`, `run_output_hooks(loaded, cmdline, exit_code, output)`, `prompt_segments(loaded) string`, `mux_status_binaries(loaded) []string`, `enable(name)`, `disable(name)`, `enable_all()`, `disable_all()`, `remote_plugin_names() ![]string`, `remote_versions(name) ![]string`, `latest_remote_version(name) !string`, `fetch_desc(name) !PluginDesc`, `install(name) !string`, `update_plugin(name) !string`, `delete_plugin(name) !`, `reinstall_plugin(name) !string`, `search_remote(query) ![]PluginDesc`


## DISCLAIMER

vlsh is provided **as-is**, without warranty of any kind. The creator and contributors are not liable for any damage, data loss, system instability, security issues, or any other consequence — direct or indirect — that may arise from using vlsh or any of its plugins. You use this software entirely at your own risk. This applies equally to the shell itself, the bundled example plugins, and any third-party plugins you install.


## CREDITS
Originally created by [onyxcode](https://github.com/onyxcode/vish)


## LICENSE
MIT License

Copyright (c) [2021-2026] [David Satime Wallin <david@snogerup.com>]

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
