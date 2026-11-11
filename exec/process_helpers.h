#ifndef VLSH_PROCESS_HELPERS_H
#define VLSH_PROCESS_HELPERS_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <stdio.h>

#define VLSH_USER_FDS 10

/* Keep internal descriptors outside the range accepted by shell redirections. */
static int vlsh_pipe(int *fds) {
    if (pipe(fds) < 0) return -1;
    for (int i = 0; i < 2; ++i) {
        int copy = fcntl(fds[i], F_DUPFD_CLOEXEC, VLSH_USER_FDS);
        close(fds[i]);
        if (copy < 0) {
            close(fds[1 - i]);
            return -1;
        }
        fds[i] = copy;
    }
    return 0;
}

typedef struct {
    int fd;
    int op;
    int target;
    const char *path;
} VlshRedirect;

enum { VLSH_INPUT, VLSH_OUTPUT, VLSH_APPEND, VLSH_DUP, VLSH_CLOSE };

static void vlsh_write_error(const char *message) {
    size_t len = 0;
    while (message[len] != '\0') ++len;
    (void)write(STDERR_FILENO, message, len);
}

static int vlsh_apply_redirects(const VlshRedirect *ops, int count) {
    for (int i = 0; i < count; ++i) {
        const VlshRedirect *r = &ops[i];
        if (r->op == VLSH_CLOSE) {
            if (close(r->fd) == 0 || errno == EBADF) continue;
        } else if (r->op == VLSH_DUP) {
            if (dup2(r->target, r->fd) >= 0) continue;
        } else {
            int flags = r->op == VLSH_INPUT ? O_RDONLY :
                O_WRONLY | O_CREAT | (r->op == VLSH_APPEND ? O_APPEND : O_TRUNC);
            int fd = open(r->path, flags, 0666);
            if (fd == r->fd) continue;
            if (fd >= 0) {
                int result = dup2(fd, r->fd);
                close(fd);
                if (result >= 0) continue;
            }
        }
        vlsh_write_error("vlsh: cannot redirect ");
        if (r->path) vlsh_write_error(r->path);
        else vlsh_write_error("file descriptor");
        vlsh_write_error("\n");
        return -1;
    }
    return 0;
}

static void vlsh_restore_fds(const int *saved, const int *flags) {
    fflush(NULL);
    for (int fd = 0; fd < VLSH_USER_FDS; ++fd) {
        if (saved[fd] >= 0) {
            (void)dup2(saved[fd], fd);
            (void)fcntl(fd, F_SETFD, flags[fd]);
            close(saved[fd]);
        } else if (saved[fd] == -1) {
            close(fd);
        }
    }
    clearerr(stdin);
    clearerr(stdout);
    clearerr(stderr);
}

static int vlsh_push_redirects(const VlshRedirect *ops, int count, int *saved, int *flags) {
    fflush(NULL);
    for (int fd = 0; fd < VLSH_USER_FDS; ++fd) saved[fd] = -2;
    for (int i = 0; i < count; ++i) {
        int fd = ops[i].fd;
        if (saved[fd] != -2) continue;
        flags[fd] = fcntl(fd, F_GETFD);
        if (flags[fd] < 0 && errno == EBADF) {
            saved[fd] = -1;
            continue;
        }
        int copy = fcntl(fd, F_DUPFD_CLOEXEC, VLSH_USER_FDS);
        if (copy < 0) {
            vlsh_write_error("vlsh: cannot save file descriptor\n");
            vlsh_restore_fds(saved, flags);
            return -1;
        }
        saved[fd] = copy;
    }
    if (vlsh_apply_redirects(ops, count) < 0) {
        vlsh_restore_fds(saved, flags);
        return -1;
    }
    return 0;
}

/* The child only calls async-signal-safe functions between fork and exec. */
static int vlsh_spawn(const char *path, char *const argv[], char *const env[],
                     int input, int output, int next_read, const VlshRedirect *ops,
                     int count, int failure, const char *message) {
    pid_t pid = fork();
    if (pid != 0) return (int)pid;
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    if ((input >= 0 && dup2(input, STDIN_FILENO) < 0) ||
        (output >= 0 && dup2(output, STDOUT_FILENO) < 0)) {
        _exit(126);
    }
    if (input >= 0) close(input);
    if (output >= 0) close(output);
    if (next_read >= 0) close(next_read);
    if (vlsh_apply_redirects(ops, count) < 0) _exit(1);
    if (failure) {
        vlsh_write_error(message);
        _exit(failure);
    }
    if (!path) _exit(0); /* Assignment- or redirection-only stage. */
    execve(path, argv, env);
    int code = errno == ENOENT ? 127 : 126;
    vlsh_write_error("vlsh: cannot execute command\n");
    _exit(code);
}

static int vlsh_wait(int pid) {
    int status;
    pid_t result;
    do { result = waitpid((pid_t)pid, &status, 0); } while (result < 0 && errno == EINTR);
    if (result < 0) return 1;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 1;
}
static int vlsh_read(int fd, void *buffer, size_t size) {
    ssize_t count;
    do { count = read(fd, buffer, size); } while (count < 0 && errno == EINTR);
    return (int)count;
}
#endif
