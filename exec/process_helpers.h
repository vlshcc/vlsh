#ifndef VLSH_PROCESS_HELPERS_H
#define VLSH_PROCESS_HELPERS_H
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* Close-on-exec prevents later stages from retaining other stages' pipe ends. */
static int vlsh_pipe(int *fds) {
    if (pipe(fds) < 0) return -1;
    if (fcntl(fds[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(fds[1], F_SETFD, FD_CLOEXEC) < 0) {
        close(fds[0]);
        close(fds[1]);
        return -1;
    }
    return 0;
}

static int vlsh_open(const char *path, int output, int append) {
    int flags = output ? O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC) : O_RDONLY;
    return open(path, flags | O_CLOEXEC, 0666);
}

/* All argv storage is prepared by the parent. Only async signal safe calls
   are used between fork and exec; this matters when plugins use threads. */
static int vlsh_spawn(const char *path, char *const argv[], int input, int output, int merge) {
    pid_t pid = fork();
    if (pid != 0) return (int)pid;
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    if ((input >= 0 && dup2(input, STDIN_FILENO) < 0) ||
        (output >= 0 && dup2(output, STDOUT_FILENO) < 0) ||
        (merge && dup2(STDOUT_FILENO, STDERR_FILENO) < 0)) {
        _exit(126);
    }
    execv(path, argv);
    int code = errno == ENOENT ? 127 : 126;
    const char message[] = "vlsh: cannot execute command\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
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
