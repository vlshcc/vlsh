# vlsh

**vlsh** is an interactive Unix shell written in [V](https://vlang.io). It is
designed to be simple, fast, and hackable — with a clean codebase that is easy
to read, modify, and extend.

### Features at a glance

- **Pipes, redirection, and AND-chains** — `cmd1 | cmd2`, `> file`, `>> file`, `cmd1 && cmd2`
- **Glob expansion** — `*.v`, `./*.deb`, `~/docs/**` expanded before execution
- **Tilde and environment-variable expansion** — `~/path`, `$VAR`, `VAR=val cmd`
- **Command history** — up/down arrow browsing and `Ctrl+R` incremental search;
  shared across all sessions (last 5000 entries in `~/.vlsh_history`)
- **Tab completion** — files and directories; `cd` completes only directories;
  plugins can register custom completions (e.g. SSH hostname completion)
- **Aliases** — defined in `~/.vlshrc` or managed live with `aliases add/remove`
- **Plugin system** — drop a `.v` file into `~/.vlsh/plugins/`; vlsh compiles and
  loads it automatically. Plugins can add commands, decorate the prompt,
  run pre/post hooks around every command, and provide custom tab completions.
  Browse, install, and delete plugins from the official remote repository at
  https://github.com/vlshcc/plugins using `plugins remote`, `plugins install`,
  and `plugins delete`.
- **Terminal multiplexer** — built-in `mux` command splits the terminal into
  resizable panes, each running its own shell. Supports mouse selection,
  copy/paste, a status bar, per-pane scrollback history (up to 1000 lines,
  scrollable via mouse wheel or `Ctrl+V`+`PageUp`/`PageDown`), and all common
  VT100 sequences so editors like `vim` and `nano` work correctly inside panes.
- **Native `.vsh` script support** — execute V shell scripts directly without
  invoking `v run` manually
- **Session environment variables** — `venv add/rm/list` for temporary
  per-session variable management
- **Theming** — prompt and UI colours configurable via `style set` and `~/.vlshrc`


## INSTALL

### Pre-built packages (recommended)

The latest release is **v1.0.10**. Pre-built packages for 64-bit Linux are
available on the [releases page](https://github.com/DavidSatimeWallin/vlsh/releases).

**Debian / Ubuntu — install via `.deb`:**

```sh
curl -LO https://github.com/DavidSatimeWallin/vlsh/releases/download/v1.0.10/vlsh_1.0.10_amd64.deb
sudo dpkg -i vlsh_1.0.10_amd64.deb
```

The package installs the binary to `/usr/bin/vlsh` and automatically adds it
to `/etc/shells` via the postinst script.

**Other Linux — standalone binary:**

```sh
curl -LO https://github.com/DavidSatimeWallin/vlsh/releases/download/v1.0.10/vlsh_1.0.10_amd64_linux
chmod +x vlsh_1.0.10_amd64_linux
sudo mv vlsh_1.0.10_amd64_linux /usr/local/bin/vlsh
```

### Prerequisites (from source)

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
v run .
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
cmds/cmds.v     – built-in commands: help, cd
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
| `plugins list` | List locally installed plugins |
| `plugins enable <name>` | Enable a disabled plugin by name |
| `plugins enable all` | Enable every plugin at once |
| `plugins disable <name>` | Disable a plugin by name |
| `plugins disable all` | Disable every plugin at once |
| `plugins reload` | Hot-reload all plugins |
| `plugins remote` | List plugins available in the remote repository |
| `plugins remote search <query>` | Filter remote plugins by name |
| `plugins install <name>` | Download and install a plugin from the remote repository |
| `plugins delete <name>` | Delete an installed plugin |
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

**Tab completion** – completes file and directory names. When the command is `cd`, only directories are suggested. Plugins can register a `completion` capability to provide custom completions for their commands (e.g. SSH hostnames for `ssh`).

**Plugins** – drop `.v` source files into `~/.vlsh/plugins/`. Each plugin can expose commands, pre/post-run hooks, prompt decorations, and custom tab completions.

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

### Plugins

Plugins extend vlsh with new commands and prompt decorations without modifying the shell binary.

#### How plugins work

1. Place a `.v` source file in `~/.vlsh/plugins/`.
2. vlsh compiles it automatically on startup (requires `v` in PATH) and caches the binary alongside the source.
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
| `complete <input>` | Print one tab-completion candidate per line for the current input |

Capability tokens (printed in response to `capabilities`):

| Token | Effect |
|-------|--------|
| `command <name>` | Registers `<name>` as a shell command dispatched via `run` |
| `prompt` | Shell calls `prompt` before each prompt and displays the output above `- ` |
| `pre_hook` | Shell calls `pre_hook <cmdline>` before every command |
| `post_hook` | Shell calls `post_hook <cmdline> <exit_code>` after every command |
| `completion` | Shell calls `complete <input>` on Tab; plugin prints full replacement strings |

#### Managing plugins

```
plugins list                      – list all locally installed plugins
plugins enable  <name>            – enable a previously disabled plugin
plugins enable  all               – enable every plugin at once
plugins disable <name>            – disable a plugin without deleting it
plugins disable all               – disable every plugin at once
plugins reload                    – recompile and reload all plugins
plugins remote                    – list plugins in the remote repository
plugins remote search <query>     – filter remote plugins by name
plugins install <name>            – download and install a remote plugin
plugins delete  <name>            – delete a locally installed plugin
```

Plugins are sourced from the official repository at
https://github.com/vlshcc/plugins. No external tooling is required — the
`install` subcommand downloads plugin source files directly. After installing
a new plugin, run `plugins reload` to compile and activate it.

#### Example plugin (`examples/hello_plugin.v`)

A minimal template that shows all four capabilities. Copy it to get started:

```sh
cp examples/hello_plugin.v ~/.vlsh/plugins/myplugin.v
```

It registers a `hello [name]` command, contributes a `[ example plugin ]` prompt line, and has empty `pre_hook` / `post_hook` stubs ready to be filled in.

```v
// Respond to 'capabilities'
println('command hello')
println('prompt')
println('pre_hook')
println('post_hook')

// Respond to 'run hello [name]'
println('Hello, ${name}!')

// Respond to 'prompt'
println('[ example plugin ]')
```

#### Git prompt plugin (`examples/git.v`)

Shows the current git branch and short commit hash in the prompt, styled with your `style_git_bg` / `style_git_fg` colours.

```sh
cp examples/git.v ~/.vlsh/plugins/git.v
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

#### SSH host completion plugin (`examples/ssh_hosts.v`)

`ssh_hosts` provides tab completion for SSH hostnames. When you type `ssh <prefix>` and press Tab, it returns matching hosts gathered from `~/.ssh/config` and `~/.ssh/known_hosts`. It also supports `user@<prefix>` notation.

```sh
cp examples/ssh_hosts.v ~/.vlsh/plugins/ssh_hosts.v
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

#### V module documentation plugin (`examples/v_man.v`)

`vman` is a man-page style viewer for the official V module documentation at
[modules.vlang.io](https://modules.vlang.io/). It fetches the HTML for any
standard-library module, strips the markup, and displays the result in `less`
(with ANSI colour support) so you can scroll, search, and quit just like a
regular man page.

```sh
cp examples/v_man.v ~/.vlsh/plugins/v_man.v
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

### Module API summary

**`cfg`** – `get() !Cfg`, `paths() ![]string`, `aliases() !map[string]string`, `style() !map[string][]int`, `add_path`, `remove_path`, `add_alias`, `remove_alias`, `set_style`

**`exec`** – `Task.prepare_task() !int` runs a command string (with pipes, redirection, tilde expansion) and returns the exit code

**`utils`** – `parse_args(string) []string` tokenises a command line respecting single/double quotes; `fail/warn/ok/debug` for formatted output

**`mux`** – `enter()` is the public entry point; internally uses `Mux`, `Pane`, `LayoutNode`, `InputHandler`

**`plugins`** – `load() []Plugin`, `dispatch(…) bool`, `completions(loaded, input) []string`, `run_pre_hooks`, `run_post_hooks`, `enable(name)`, `disable(name)`, `enable_all()`, `disable_all()`, `remote_available() ![]string`, `install(name) !`, `delete_plugin(name) !`


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
