#ifndef VLSH_PTY_HELPERS_H
#define VLSH_PTY_HELPERS_H

#include <pty.h>
#include <termios.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/wait.h>
#include <signal.h>

/* Enter raw mode; saves original termios into orig_buf. Returns 0 on success. */
static int vlsh_enter_raw(void *orig_buf) {
    struct termios orig, raw;
    if (tcgetattr(0, &orig) < 0) return -1;
    memcpy(orig_buf, &orig, sizeof(struct termios));
    raw = orig;
    raw.c_iflag &= ~(unsigned)(ICRNL | IXON);
    raw.c_oflag &= ~(unsigned)OPOST;
    raw.c_lflag &= ~(unsigned)(ECHO | ICANON | ISIG | IEXTEN);
    raw.c_cc[VMIN]  = 1;
    raw.c_cc[VTIME] = 0;
    return tcsetattr(0, TCSANOW, &raw);
}

/* Restore terminal from opaque buffer. */
static int vlsh_restore_term(void *orig_buf) {
    return tcsetattr(0, TCSANOW, (struct termios *)orig_buf);
}

/* Resize a PTY to the given dimensions. */
static void vlsh_set_pty_size(int fd, int rows, int cols) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    ws.ws_row = (unsigned short)rows;
    ws.ws_col = (unsigned short)cols;
    ioctl(fd, TIOCSWINSZ, &ws);
}

/* Query current terminal dimensions. */
static void vlsh_get_term_size(int *rows, int *cols) {
    struct winsize ws;
    memset(&ws, 0, sizeof(ws));
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 1) {
        *rows = (int)ws.ws_row;
        *cols = (int)ws.ws_col;
    } else {
        *rows = 24;
        *cols = 80;
    }
}

/*
 * select() wrapper.
 * fds[0..nfds-1]: input file descriptors.
 * out_readable[0..return_value-1]: readable fds on return.
 * Returns count of readable fds (0 on timeout/error).
 */
static int vlsh_select_readable(int *fds, int nfds, int *out_readable, int timeout_ms) {
    fd_set set;
    struct timeval tv;
    int maxfd = 0, i, n = 0, ret;
    FD_ZERO(&set);
    for (i = 0; i < nfds; i++) {
        FD_SET(fds[i], &set);
        if (fds[i] > maxfd) maxfd = fds[i];
    }
    tv.tv_sec  = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    ret = select(maxfd + 1, &set, NULL, NULL, &tv);
    if (ret <= 0) return 0;
    for (i = 0; i < nfds; i++)
        if (FD_ISSET(fds[i], &set))
            out_readable[n++] = fds[i];
    return n;
}

/* exec vlsh (or any binary) as a child process after forkpty. Never returns. */
static void vlsh_exec(const char *path) {
    char *const argv[] = { (char *)path, NULL };
    execvp(path, argv);
    _exit(1);
}

/* SIGWINCH flag and helpers. */
static volatile int _vlsh_sigwinch_flag = 0;
static void _vlsh_sigwinch_handler(int s) { (void)s; _vlsh_sigwinch_flag = 1; }
static void vlsh_install_sigwinch(void) { signal(SIGWINCH, _vlsh_sigwinch_handler); }
static int  vlsh_check_sigwinch(void)   {
    int v = _vlsh_sigwinch_flag;
    _vlsh_sigwinch_flag = 0;
    return v;
}

#endif /* VLSH_PTY_HELPERS_H */
