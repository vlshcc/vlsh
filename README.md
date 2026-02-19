# vlsh
A shell coded in [V](https://vlang.io). Work in progress.
Many features are missing and lots of bugs exist. Do **NOT** use for anything important or in anyway other than as a toy or experiment.


## INSTALL

### Prerequisites

- [V](https://vlang.io) — install with `v up` or from https://github.com/vlang/v

### Build and run (try it out)

```sh
git clone https://github.com/dvwallin/vlsh.git
cd vlsh
v .
./vlsh
```

Or run directly without compiling first:

```sh
v run vlsh.v
```

### System-wide install

After building, copy the binary to a directory on your system `PATH`:

```sh
sudo cp vlsh /usr/local/bin/vlsh
```

Verify it is accessible:

```sh
which vlsh   # should print /usr/local/bin/vlsh
vlsh --version 2>/dev/null || vlsh -c 'version'
```

### Set vlsh as your default login shell

1. Add vlsh to the list of approved shells:

   ```sh
   echo /usr/local/bin/vlsh | sudo tee -a /etc/shells
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


## TODO
This list is not in any specific order and is in no way complete.
- [x] ~~save unique commands~~
- [x] ~~config file for aliases and paths~~
- [x] ~~command history by using arrow keys~~
- [x] search command history with ctrl+r
- [x] plugin support
- [x] ~~theme support~~
- [x] pipes
- [x] ~~create a default config file if none exists~~


## CONFIG
vlsh will look for the configuration file `$HOME/.vlshrc`.
Here's an example -file:

```
"paths
path=/usr/local/bin
path=/usr/bin;/bin

"aliases
alias gs=git status
alias gps=git push
alias gpl=git pull
alias gd=git diff
alias gc=git commit -sa
alias gl=git log
alias vim=nvim

"style (define in RGB colors)
style_git_bg=44,59,71
style_git_fg=251,255,234
style_debug_bg=255,255,255
style_debug_fb=251,255,234
```


## DOCUMENTATION

### Architecture overview

```
vlsh.v          – main entry point, prompt rendering, read-eval loop
cfg/cfg.v       – config file (~/.vlshrc) parsing, aliases, paths, style
cmds/cmds.v     – built-in commands: help, cd, share
cmds/ls.v       – built-in colorised ls
cmds/cp.v       – built-in overwrite-copy (ocp)
exec/exec.v     – external-command execution, pipe chains, I/O redirection
mux/mux.v       – terminal multiplexer entry point and event loop
mux/pane.v      – per-pane VT100 parser and cell grid
mux/layout.v    – binary-tree layout engine (splits/resize/navigation)
mux/render.v    – grid-to-terminal renderer
mux/input.v     – key-sequence parser for mux prefix bindings
mux/pty.v       – PTY helpers (thin wrappers around C functions)
mux/pty_helpers.h – C helpers: raw mode, winsize, select, forkpty, exec
utils/utils.v   – shared helpers: parse_args, fail/warn/ok/debug
plugins/        – plugin loader and hook dispatcher
```

### Config file (~/.vlshrc)

A plain-text file read on every command. Lines beginning with `"` are comments.

| Directive | Example | Meaning |
|-----------|---------|---------|
| `path=<dir>` | `path=/usr/bin;/bin` | Add dirs to executable search path (`;`-separated) |
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
| `cd [dir]` | Change directory (`~` expands to `$HOME`; home if omitted) |
| `echo [args…]` | Print arguments; expands `$VAR` and `$0`; supports `>` / `>>` |
| `exit` | Exit the shell |
| `help [cmd]` | Show command list, or detailed help for a specific command |
| `ls [dir]` | Colorised directory listing (falls through to system `ls` when flags are passed) |
| `mux` | Enter terminal multiplexer mode |
| `ocp <src> <dst>` | Copy file, overwriting destination |
| `path list` | Show PATH entries |
| `path add <dir>` | Append a directory to PATH |
| `path remove <dir>` | Remove a directory from PATH |
| `plugins list` | List available plugins |
| `plugins enable <name>` | Enable a plugin |
| `plugins disable <name>` | Disable a plugin |
| `plugins reload` | Hot-reload all plugins |
| `share <file>` | Upload a file to dpaste.com and print the URL |
| `style list` | Show current style/colour settings |
| `style set <key> <r> <g> <b>` | Set a prompt colour (RGB 0–255) |
| `venv list` | List shell environment variables set via `venv` |
| `venv add <NAME> <value>` | Set an environment variable for the current session |
| `venv rm <NAME>` | Unset an environment variable |
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

**AND-chains** – run the next command only if the previous one succeeds:
```
touch /tmp/x && echo "file created"
```

**Tilde expansion** – `~` and `~/path` are expanded to `$HOME` in both commands and arguments:
```
vi ~/.config/nvim/init.vim
```

**Environment-variable prefix** – set variables only for the duration of one command:
```
FIELD_LIST='used,avail' df -h --no-sync .
```

**Variable expansion in echo** – `$VAR` expands to the environment variable value; `$0` expands to `vlsh`.

**Command history** – up/down arrows browse history; `Ctrl+R` searches history.
All instances share a global history file at `~/.vlsh_history` (last 5000 entries).

**Tab completion** – completes file and directory names.

**Plugins** – drop executable scripts into `~/.vlsh/plugins/`. Each plugin can expose commands and pre/post-run hooks.

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
vlsh looks for the `v` binary in the configured `path=` directories first, then falls back to the system `PATH`.

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
| `Ctrl+V` + `q` | Exit mux (only when all panes have been closed) |
| `Ctrl+V` + `Ctrl+V` | Send a literal Ctrl+V to the active pane |
| Mouse click | Click a pane to make it active |

Panes close automatically when their shell process exits. The terminal is fully restored on exit and a confirmation message is printed.

### Module API summary

**`cfg`** – `get() !Cfg`, `paths() ![]string`, `aliases() !map[string]string`, `style() !map[string][]int`, `add_path`, `remove_path`, `add_alias`, `remove_alias`, `set_style`

**`exec`** – `Task.prepare_task() !int` runs a command string (with pipes, redirection, tilde expansion) and returns the exit code

**`utils`** – `parse_args(string) []string` tokenises a command line respecting single/double quotes; `fail/warn/ok/debug` for formatted output

**`mux`** – `enter()` is the public entry point; internally uses `Mux`, `Pane`, `LayoutNode`, `InputHandler`

**`plugins`** – `load() []Plugin`, `dispatch(…) bool`, `run_pre_hooks`, `run_post_hooks`


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
