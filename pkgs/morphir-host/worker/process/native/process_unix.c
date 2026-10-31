// Process workers on Linux and macOS (PROC-1).
//
// A worker starts with posix_spawn as the leader of a new process group, with
// three pipes as its standard streams, no other descriptor, an empty
// environment and a private working directory. The host stops the whole group
// with killpg and confirms that no live member remains.

#ifndef _WIN32

#ifdef __linux__
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#endif

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <moonbit.h>

#ifdef __APPLE__
#include <Availability.h>
#include <libproc.h>
#include <sys/proc.h>
#include <sys/proc_info.h>
#if defined(__MAC_OS_X_VERSION_MIN_REQUIRED) &&                               \
  __MAC_OS_X_VERSION_MIN_REQUIRED >= 260000
#define morphir_addchdir posix_spawn_file_actions_addchdir
#else
#define morphir_addchdir posix_spawn_file_actions_addchdir_np
#endif
#else
#define morphir_addchdir posix_spawn_file_actions_addchdir_np
#endif

#if defined(__GLIBC__) &&                                                      \
  (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 34))
#define MORPHIR_HAVE_CLOSEFROM 1
#endif

// Problems that an artifact read reports. They match `ArtifactProblem`.
#define MORPHIR_ARTIFACT_SYMBOLIC_LINK 1
#define MORPHIR_ARTIFACT_NOT_REGULAR 2
#define MORPHIR_ARTIFACT_TOO_LARGE 3
#define MORPHIR_ARTIFACT_UNREADABLE 4

// Reads a regular file through a descriptor that does not follow a final
// symbolic link. The bytes returned are the bytes that the host hashes and
// copies. `limit` bounds the size; `problem[0]` gets a problem code and
// `problem[1]` an errno, and the result is then empty.
MOONBIT_FFI_EXPORT
moonbit_bytes_t morphir_worker_read_artifact(
  moonbit_bytes_t path,
  int64_t limit,
  int32_t *problem
) {
  problem[0] = 0;
  problem[1] = 0;
  // The bytes go into one MoonBit byte array, whose length is an int32_t.
  if (limit > INT32_MAX) {
    limit = INT32_MAX;
  }
  // O_NONBLOCK: opening a FIFO without a writer must not block. The type
  // check below refuses it, and regular files then read in blocking mode.
  int fd = open(
    (const char *)path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK
  );
  if (fd < 0) {
    problem[0] = errno == ELOOP ? MORPHIR_ARTIFACT_SYMBOLIC_LINK
                                : MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = errno;
    return moonbit_make_bytes(0, 0);
  }
  struct stat info;
  if (fstat(fd, &info) != 0) {
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = errno;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  if (!S_ISREG(info.st_mode)) {
    problem[0] = MORPHIR_ARTIFACT_NOT_REGULAR;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0 || fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0) {
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = errno;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  if ((int64_t)info.st_size > limit) {
    problem[0] = MORPHIR_ARTIFACT_TOO_LARGE;
    close(fd);
    return moonbit_make_bytes(0, 0);
  }
  int32_t size = (int32_t)info.st_size;
  moonbit_bytes_t bytes = moonbit_make_bytes(size, 0);
  int32_t done = 0;
  while (done < size) {
    ssize_t n = read(fd, bytes + done, (size_t)(size - done));
    if (n < 0 && errno == EINTR) {
      continue;
    }
    if (n <= 0) {
      // A file that shrinks while it is read is refused, never half copied.
      problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
      problem[1] = n < 0 ? errno : EIO;
      close(fd);
      moonbit_decref(bytes);
      return moonbit_make_bytes(0, 0);
    }
    done += (int32_t)n;
  }
  char extra;
  ssize_t more = read(fd, &extra, 1);
  close(fd);
  if (more != 0) {
    // The file grew after fstat: the bytes read are not the whole artifact.
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = EIO;
    moonbit_decref(bytes);
    return moonbit_make_bytes(0, 0);
  }
  return bytes;
}

static int morphir_blocking(int fd) {
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) {
    return errno;
  }
  if ((flags & O_NONBLOCK) && fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) < 0) {
    return errno;
  }
  return 0;
}

// Adds a close action for every open descriptor from 3 that is not
// close-on-exec, where the platform has no "close every other" action.
static int morphir_close_others(posix_spawn_file_actions_t *actions) {
#if defined(MORPHIR_HAVE_CLOSEFROM)
  return posix_spawn_file_actions_addclosefrom_np(actions, 3);
#elif defined(__APPLE__)
  (void)actions;
  return 0; // POSIX_SPAWN_CLOEXEC_DEFAULT closes them.
#else
  long max = sysconf(_SC_OPEN_MAX);
  if (max < 0 || max > 65536) {
    max = 65536;
  }
  for (int fd = 3; fd < max; ++fd) {
    int flags = fcntl(fd, F_GETFD);
    if (flags >= 0 && !(flags & FD_CLOEXEC)) {
      int err = posix_spawn_file_actions_addclose(actions, fd);
      if (err) {
        return err;
      }
    }
  }
  return 0;
#endif
}

// Starts `path` with `args` (each a NUL-terminated UTF-8 string, `args[0]`
// included) in the new process group whose ID is its PID. `stdio` holds the
// worker's ends of the three pipes. Returns 0 and the PID in `pid`, or an
// errno.
static int32_t morphir_spawn_with(
  moonbit_bytes_t path,
  moonbit_bytes_t *args,
  int32_t count,
  moonbit_bytes_t cwd,
  int32_t *stdio,
  int32_t *pid
) {
  int fds[3];
  int lifted[3] = {-1, -1, -1};
  int err = 0;
  for (int i = 0; i < 3; ++i) {
    fds[i] = stdio[i];
    // dup2 onto itself keeps close-on-exec set, so lift low descriptors.
    if (fds[i] < 3) {
      lifted[i] = fcntl(fds[i], F_DUPFD_CLOEXEC, 3);
      if (lifted[i] < 0) {
        err = errno;
        goto lifted_exit;
      }
      fds[i] = lifted[i];
    }
    // The worker reads and writes in blocking mode. Each pipe end is its own
    // open file description, so the host's ends stay non-blocking.
    err = morphir_blocking(fds[i]);
    if (err) {
      goto lifted_exit;
    }
  }

  char **argv = (char **)calloc((size_t)count + 1, sizeof(char *));
  if (!argv) {
    err = ENOMEM;
    goto lifted_exit;
  }
  for (int32_t i = 0; i < count; ++i) {
    argv[i] = (char *)args[i];
  }
  char *envp[] = {NULL};

  posix_spawnattr_t attr;
  posix_spawn_file_actions_t actions;
  err = posix_spawnattr_init(&attr);
  if (err) {
    goto argv_exit;
  }
  err = posix_spawn_file_actions_init(&actions);
  if (err) {
    goto attr_exit;
  }

  short flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK |
                POSIX_SPAWN_SETSIGDEF;
#ifdef __APPLE__
  flags |= POSIX_SPAWN_CLOEXEC_DEFAULT;
#endif
  sigset_t none, all;
  sigemptyset(&none);
  sigfillset(&all);
  if ((err = posix_spawnattr_setflags(&attr, flags)) ||
      (err = posix_spawnattr_setpgroup(&attr, 0)) ||
      (err = posix_spawnattr_setsigmask(&attr, &none)) ||
      (err = posix_spawnattr_setsigdefault(&attr, &all))) {
    goto actions_exit;
  }
  for (int i = 0; i < 3; ++i) {
    err = posix_spawn_file_actions_adddup2(&actions, fds[i], i);
    if (err) {
      goto actions_exit;
    }
  }
  if ((err = morphir_close_others(&actions)) ||
      (err = morphir_addchdir(&actions, (const char *)cwd))) {
    goto actions_exit;
  }

  pid_t child = 0;
  err = posix_spawn(&child, (const char *)path, &actions, &attr, argv, envp);
  if (!err) {
    *pid = (int32_t)child;
  }

actions_exit:
  posix_spawn_file_actions_destroy(&actions);
attr_exit:
  posix_spawnattr_destroy(&attr);
argv_exit:
  free(argv);
lifted_exit:
  for (int i = 0; i < 3; ++i) {
    if (lifted[i] >= 0) {
      close(lifted[i]);
    }
  }
  return err;
}

// Makes a pipe whose ends are both close-on-exec. On Linux, pipe2 sets the
// flag atomically. Other systems have no pipe2 with O_CLOEXEC, so the flag is
// set after pipe(): until then, a program that another thread starts through
// an API that does not close other descriptors (for example @process.spawn in
// moonbitlang/async, in a thread-pool thread) can inherit an end. The
// worker's own spawn closes every descriptor that it does not name
// (POSIX_SPAWN_CLOEXEC_DEFAULT). On an error, no end stays open and both
// entries of `fds` are -1.
static int morphir_pipe(int fds[2]) {
#if defined(__linux__)
  if (pipe2(fds, O_CLOEXEC) != 0) {
    int err = errno;
    fds[0] = -1;
    fds[1] = -1;
    return err;
  }
  return 0;
#else
  if (pipe(fds) != 0) {
    int err = errno;
    fds[0] = -1;
    fds[1] = -1;
    return err;
  }
  for (int i = 0; i < 2; ++i) {
    if (fcntl(fds[i], F_SETFD, FD_CLOEXEC) != 0) {
      int err = errno;
      close(fds[0]);
      close(fds[1]);
      fds[0] = -1;
      fds[1] = -1;
      return err;
    }
  }
  return 0;
#endif
}

// Creates the worker's three pipes and starts it with morphir_spawn_with.
// The host's ends (stdin write end, stdout and stderr read ends) go to
// `host`, in non-blocking mode, and the device and inode of each to
// `identity`. Each pipe end is its own open file description, so the
// worker's ends stay blocking. The worker's ends are never registered with
// the host's event loop, and the host closes them as soon as posix_spawn
// returns: an event loop registration of an end that the worker shares
// would outlive the host's copy. No step can fail after posix_spawn starts
// the worker. Returns 0, or an errno with no descriptor left open and no
// process started.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_spawn(
  moonbit_bytes_t path,
  moonbit_bytes_t *args,
  int32_t count,
  moonbit_bytes_t cwd,
  int32_t *host,
  int64_t *identity,
  int32_t *pid
) {
  int in[2] = {-1, -1}, out[2] = {-1, -1}, err[2] = {-1, -1};
  int32_t result = morphir_pipe(in);
  if (!result) {
    result = morphir_pipe(out);
  }
  if (!result) {
    result = morphir_pipe(err);
  }
  int mine[3] = {in[1], out[0], err[0]};
  for (int i = 0; i < 3 && !result; ++i) {
    struct stat info;
    int flags = fcntl(mine[i], F_GETFL);
    if (flags < 0 || fcntl(mine[i], F_SETFL, flags | O_NONBLOCK) < 0 ||
        fstat(mine[i], &info) != 0) {
      result = errno;
    } else {
      identity[2 * i] = (int64_t)info.st_dev;
      identity[2 * i + 1] = (int64_t)info.st_ino;
    }
  }
  if (!result) {
    int32_t child[3] = {in[0], out[1], err[1]};
    result = morphir_spawn_with(path, args, count, cwd, child, pid);
  }
  int ends[3] = {in[0], out[1], err[1]};
  for (int i = 0; i < 3; ++i) {
    if (ends[i] >= 0) {
      close(ends[i]);
    }
  }
  if (result) {
    for (int i = 0; i < 3; ++i) {
      if (mine[i] >= 0) {
        close(mine[i]);
      }
    }
    return result;
  }
  for (int i = 0; i < 3; ++i) {
    host[i] = mine[i];
  }
  return 0;
}

// Whether `fd` is still the pipe end with this device and inode.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_is_end(int32_t fd, int64_t device, int64_t inode) {
  struct stat info;
  if (fd < 0 || fstat(fd, &info) != 0 || !S_ISFIFO(info.st_mode)) {
    return 0;
  }
  return (int64_t)info.st_dev == device && (int64_t)info.st_ino == inode;
}

// Closes `fd` if it is still the pipe end with this device and inode. A wrap
// that failed may have closed the end already, and its number may then
// belong to another file. No other code holds a copy of the end, so its
// number cannot change hands between the check and the close.
MOONBIT_FFI_EXPORT
void morphir_worker_close_end(int32_t fd, int64_t device, int64_t inode) {
  if (morphir_worker_is_end(fd, device, inode)) {
    close(fd);
  }
}

// Signals every process of the group. Returns 0, or an errno; ESRCH means
// the group has no member left.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_signal_group(int32_t pgid, int32_t terminate) {
  if (pgid <= 1) {
    return EINVAL;
  }
  return killpg((pid_t)pgid, terminate ? SIGTERM : SIGKILL) == 0 ? 0 : errno;
}

#ifdef __linux__
// Reads the state and the process group of a process from /proc. Returns 0,
// or -1 when the process has gone.
static int morphir_proc_stat(const char *pid, char *state, long *group) {
  char name[288];
  snprintf(name, sizeof(name), "/proc/%s/stat", pid);
  int fd = open(name, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return -1;
  }
  char text[512];
  ssize_t n = read(fd, text, sizeof(text) - 1);
  close(fd);
  if (n <= 0) {
    return -1;
  }
  text[n] = 0;
  // "pid (comm) state ppid pgrp ...": comm may hold spaces and parentheses.
  char *end = strrchr(text, ')');
  long ppid = 0;
  if (!end || sscanf(end + 1, " %c %ld %ld", state, &ppid, group) != 3) {
    return -1;
  }
  return 0;
}
#endif

// Counts the group's members that are not zombies. A zombie has no running
// code and no open files; its parent or init reaps it. Returns -1 when the
// platform cannot list members.
static int32_t morphir_live_members(pid_t pgid) {
#if defined(__APPLE__)
  int capacity = 64;
  for (;;) {
    pid_t *pids = (pid_t *)calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) {
      return -1;
    }
    int bytes = proc_listpids(
      PROC_PGRP_ONLY, (uint32_t)pgid, pids, capacity * (int)sizeof(pid_t)
    );
    if (bytes < 0) {
      free(pids);
      return -1;
    }
    int n = bytes / (int)sizeof(pid_t);
    if (n >= capacity) {
      free(pids);
      capacity *= 4;
      continue;
    }
    int32_t live = 0;
    for (int i = 0; i < n; ++i) {
      if (pids[i] <= 0) {
        continue;
      }
      struct proc_bsdinfo info;
      int got = proc_pidinfo(pids[i], PROC_PIDTBSDINFO, 0, &info, sizeof(info));
      if (got == (int)sizeof(info) && info.pbi_status == SZOMB) {
        continue;
      }
      if (got <= 0 && errno == ESRCH) {
        continue;
      }
      ++live;
    }
    free(pids);
    return live;
  }
#elif defined(__linux__)
  DIR *proc = opendir("/proc");
  if (!proc) {
    return -1;
  }
  int32_t live = 0;
  struct dirent *entry;
  while ((entry = readdir(proc))) {
    if (entry->d_name[0] < '0' || entry->d_name[0] > '9') {
      continue;
    }
    char state = 0;
    long group = 0;
    if (morphir_proc_stat(entry->d_name, &state, &group) != 0) {
      continue;
    }
    if (group == (long)pgid && state != 'Z' && state != 'X') {
      ++live;
    }
  }
  closedir(proc);
  return live;
#else
  (void)pgid;
  return -1;
#endif
}

// The state of a group: 0 when it has no member, 1 when only zombies remain,
// 2 while a live member remains, or a negative errno.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_group_state(int32_t pgid) {
  if (pgid <= 1) {
    return -EINVAL;
  }
  if (killpg((pid_t)pgid, 0) != 0) {
    return errno == ESRCH ? 0 : -errno;
  }
  int32_t live = morphir_live_members((pid_t)pgid);
  if (live == 0) {
    return 1;
  }
  return 2;
}

// Whether a process runs: it exists and is not a zombie.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_process_alive(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  if (kill((pid_t)pid, 0) != 0 && errno == ESRCH) {
    return 0;
  }
#if defined(__APPLE__)
  struct proc_bsdinfo info;
  int got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
  if (got == (int)sizeof(info) && info.pbi_status == SZOMB) {
    return 0;
  }
  if (got <= 0 && errno == ESRCH) {
    return 0;
  }
#elif defined(__linux__)
  char text[24];
  snprintf(text, sizeof(text), "%d", (int)pid);
  char state = 0;
  long group = 0;
  if (morphir_proc_stat(text, &state, &group) != 0 || state == 'Z' ||
      state == 'X') {
    return 0;
  }
#endif
  return 1;
}

// The host's target triple as an index: 1 aarch64-apple-darwin,
// 2 x86_64-apple-darwin, 3 aarch64-unknown-linux-gnu, 4 x86_64-unknown-linux-gnu,
// 5 aarch64-unknown-linux-musl, 6 x86_64-unknown-linux-musl, or 0.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_host_platform(void) {
#if defined(__APPLE__) && defined(__aarch64__)
  return 1;
#elif defined(__APPLE__) && defined(__x86_64__)
  return 2;
#elif defined(__linux__) && defined(__GLIBC__) && defined(__aarch64__)
  return 3;
#elif defined(__linux__) && defined(__GLIBC__) && defined(__x86_64__)
  return 4;
#elif defined(__linux__) && defined(__aarch64__)
  return 5;
#elif defined(__linux__) && defined(__x86_64__)
  return 6;
#else
  return 0;
#endif
}

#endif
