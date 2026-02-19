# vlsh
A shell coded in [V](https://vlang.io). Work in progress.
Many features are missing and lots of bugs exist. Do **NOT** use for anything important or in anyway other than as a toy or experiment.


## INSTALL
either
```
git clone https://github.com/dvwallin/vlsh.git
cd vlsh
v .
./vlsh
```

or
```
git clone https://github.com/dvwallin/vlsh.git
cd vlsh
v run vlsh.v
```

## USE
vlsh is **NOT** stable enough for daily use or any kind of production.
If you wanna use it just compile it and run it and experiment but there will be loads of bugs.

To get debug-info simply start it like so: `VLSHDEBUG=true vlsh` or `VLSHDEBUG=true v run vlsh.v`


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


## CREDITS
Originally created by [onyxcode](https://github.com/onyxcode/vish)


## LICENSE
MIT License

Copyright (c) [2021] [David Satime Wallin <david@dwall.in>]

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
