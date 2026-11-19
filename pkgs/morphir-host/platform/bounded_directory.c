#include "moonbit.h"
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__) || defined(__linux__)
#include <dirent.h>
#include <dirent.h>
#include <fcntl.h>
#include <time.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#ifdef __APPLE__
#include <sys/acl.h>
#endif
#ifdef __linux__
#include <sys/syscall.h>
#endif

static int same_identity(const struct stat *a, const struct stat *b) {
  return a->st_dev == b->st_dev && a->st_ino == b->st_ino;
}

#ifdef __APPLE__
#define MTIME(st) ((st)->st_mtimespec)
#define CTIME(st) ((st)->st_ctimespec)
#else
#define MTIME(st) ((st)->st_mtim)
#define CTIME(st) ((st)->st_ctim)
#endif

static int same_version(const struct stat *a, const struct stat *b) {
  return same_identity(a, b) && a->st_mode == b->st_mode &&
    a->st_nlink == b->st_nlink && a->st_size == b->st_size &&
    MTIME(a).tv_sec == MTIME(b).tv_sec && MTIME(a).tv_nsec == MTIME(b).tv_nsec &&
    CTIME(a).tv_sec == CTIME(b).tv_sec && CTIME(a).tv_nsec == CTIME(b).tv_nsec;
}

static int owned_directory(int fd, struct stat *st) {
  if (fstat(fd, st) || !S_ISDIR(st->st_mode) ||
      st->st_uid != geteuid() || (st->st_mode & 0022)) return 0;
#ifdef __APPLE__
  /* Darwin ACLs can grant writes independently of the POSIX mode bits. */
  acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
  if (!acl) return errno == ENOENT || errno == EOPNOTSUPP;
  acl_free(acl);
  return 0;
#else
  return 1;
#endif
}
#endif

static moonbit_bytes_t packet(int code, const void *data, size_t size) {
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)(size + 1));
  result[0] = (uint8_t)code;
  if (size) memcpy(result + 1, data, size);
  return result;
}

int morphir_bounded_directory_open(int parent, const char *path) {
#if defined(__APPLE__) || defined(__linux__)
  int flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC;
  return parent < 0 ? open(path, flags) : openat(parent, path, flags);
#else
  return -1;
#endif
}

moonbit_bytes_t morphir_bounded_directory_stamp(int fd, const char *name) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat st;
  if (*name ? fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) : fstat(fd, &st))
    return packet(1, NULL, 0);
  char text[256];
  char kind = S_ISDIR(st.st_mode) ? 'd' : S_ISREG(st.st_mode) ? 'f' : 'x';
  int length = snprintf(text, sizeof(text), "%c:%llu:%llu:%llu:%llu:%lld:%lld:%ld:%lld:%ld",
    kind, (unsigned long long)st.st_dev, (unsigned long long)st.st_ino,
    (unsigned long long)st.st_mode, (unsigned long long)st.st_nlink,
    (long long)st.st_size, (long long)MTIME(&st).tv_sec, MTIME(&st).tv_nsec,
    (long long)CTIME(&st).tv_sec, CTIME(&st).tv_nsec);
  if (length > 0 && (size_t)length < sizeof(text)) return packet(0, text, (size_t)length);
#endif
  return packet(1, NULL, 0);
}

moonbit_bytes_t morphir_bounded_directory_read(int parent, const char *name, int limit) {
#if defined(__APPLE__) || defined(__linux__)
  if (limit < 0 || limit > 1048576) return packet(2, NULL, 0);
  int fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return packet(1, NULL, 0);
  struct stat before, after, entry;
  int code = 1;
  char *bytes = NULL;
  size_t size = 0, offset = 0;
  if (fstat(fd, &before) || !S_ISREG(before.st_mode) || before.st_nlink != 1) goto end;
  if (before.st_size < 0 || before.st_size > limit) { code = 2; goto end; }
  size = (size_t)before.st_size;
  bytes = malloc(size + 1);
  if (!bytes) goto end;
  while (offset <= size) {
    size_t count = size + 1 - offset;
    ssize_t n = read(fd, bytes + offset, count > 65536 ? 65536 : count);
    if (n < 0 && errno == EINTR) continue;
    if (n < 0) goto end;
    if (!n) break;
    offset += (size_t)n;
  }
  if (offset != size || fstat(fd, &after) || !same_version(&before, &after) ||
      fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) ||
      !same_version(&before, &entry)) { code = 3; goto end; }
  code = 0;
end:
  close(fd);
  moonbit_bytes_t result = packet(code, bytes, code ? 0 : size);
  free(bytes);
  return result;
#else
  return packet(1, NULL, 0);
#endif
}

int morphir_bounded_directory_owned(int fd) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat st;
  return owned_directory(fd, &st);
#else
  return 0;
#endif
}

int morphir_bounded_directory_mkdir(int parent, const char *name) {
#if defined(__APPLE__) || defined(__linux__)
  return mkdirat(parent, name, 0700);
#else
  return -1;
#endif
}

int morphir_bounded_directory_remove(int parent, const char *name, int directory) {
#if defined(__APPLE__) || defined(__linux__)
  return unlinkat(parent, name, directory ? AT_REMOVEDIR : 0);
#else
  return -1;
#endif
}

int morphir_bounded_directory_write(int parent, const char *name, int offset,
    int create, const unsigned char *bytes, int length) {
#if defined(__APPLE__) || defined(__linux__)
  if (offset < 0 || length < 0 || length > 1048576) return -1;
  int flags = O_WRONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
  if (create) flags |= O_CREAT | O_EXCL;
  int fd = openat(parent, name, flags, 0600);
  if (fd < 0) return -1;
  struct stat st;
  int result = -1;
  if (!fstat(fd, &st) && S_ISREG(st.st_mode) && st.st_nlink == 1 && st.st_size == offset) {
    int written = 0;
    while (written < length) {
      ssize_t n = pwrite(fd, bytes + written, (size_t)(length - written), (off_t)offset + written);
      if (n < 0 && errno == EINTR) continue;
      if (n <= 0) break;
      written += (int)n;
    }
    if (written == length) result = 0;
  }
  return close(fd) ? -1 : result;
#else
  return -1;
#endif
}

int morphir_bounded_directory_publish(int parent, const char *parent_path,
    int stage, const char *from, const char *to) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat owner, current, source, entry;
  if (!owned_directory(parent, &owner) || !owned_directory(stage, &source)) return -1;
  int now = morphir_bounded_directory_open(-1, parent_path);
  if (now < 0) return -1;
  int unchanged = owned_directory(now, &current) && same_identity(&owner, &current);
  close(now);
  if (!unchanged || fstatat(parent, from, &entry, AT_SYMLINK_NOFOLLOW) ||
      !same_identity(&source, &entry)) return -1;
#ifdef __APPLE__
  return renameatx_np(parent, from, parent, to, RENAME_EXCL);
#elif defined(SYS_renameat2)
  return syscall(SYS_renameat2, parent, from, parent, to, 1U) ? -1 : 0;
#endif
#endif
  return -1;
}

#if defined(__APPLE__) || defined(__linux__)
/* The worker can leave unreported entries in an operation-owned directory.
 * Walk from the pinned descriptor, refuse mounts or replaced directories,
 * and unlink non-directories without following links. */
static int clear_owned_directory(int fd, dev_t device, int depth, int *remaining) {
  if (depth > 32) return -2;
  int scan = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (scan < 0) return -1;
  DIR *directory = fdopendir(scan);
  if (!directory) { close(scan); return -1; }
  int result = 0;
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(directory);
    if (!entry) { if (errno) result = -1; break; }
    const char *name = entry->d_name;
    if (!strcmp(name, ".") || !strcmp(name, "..")) continue;
    if (*remaining == 0) { result = -2; break; }
    --*remaining;
    struct stat named, pinned, current;
    if (fstatat(fd, name, &named, AT_SYMLINK_NOFOLLOW) || named.st_dev != device) {
      result = -1;
      break;
    }
    if (!S_ISDIR(named.st_mode)) {
      if (unlinkat(fd, name, 0)) { result = -1; break; }
      continue;
    }
    int child = morphir_bounded_directory_open(fd, name);
    if (child < 0) { result = -1; break; }
    if (!owned_directory(child, &pinned) || !same_identity(&named, &pinned)) result = -1;
    else result = clear_owned_directory(child, device, depth + 1, remaining);
    if (!result && (fstatat(fd, name, &current, AT_SYMLINK_NOFOLLOW) ||
        !same_identity(&pinned, &current) || unlinkat(fd, name, AT_REMOVEDIR)))
      result = -1;
    close(child);
    if (result) break;
  }
  if (closedir(directory) && !result) result = -1;
  return result;
}
#endif

int morphir_bounded_directory_discard(int parent, int stage, const char *name, int limit) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat owner, source, entry;
  if (!owned_directory(parent, &owner) || !owned_directory(stage, &source) ||
      fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) ||
      !same_identity(&source, &entry) || owner.st_dev != source.st_dev) return -1;
  if (limit < 0) return -2;
  int remaining = limit;
  int result = clear_owned_directory(stage, source.st_dev, 0, &remaining);
  if (result) return result;
  if (fstatat(parent, name, &entry, AT_SYMLINK_NOFOLLOW) ||
      !same_identity(&source, &entry)) return -1;
  return unlinkat(parent, name, AT_REMOVEDIR);
#else
  return -1;
#endif
}

int morphir_bounded_directory_outside(int fd, int source) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat root;
  if (fstat(source, &root)) return 0;
  int current = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (current < 0) return 0;
  int outside = 0;
  for (int depth = 0; depth < 128; depth++) {
    struct stat here, above;
    if (fstat(current, &here) || same_identity(&root, &here)) break;
    int parent = openat(current, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (parent < 0) break;
    close(current);
    current = parent;
    if (fstat(current, &above)) break;
    if (same_identity(&above, &here)) { outside = 1; break; }
  }
  close(current);
  return outside;
#else
  return 0;
#endif
}

int morphir_bounded_file_open(int parent, const char *name, int limit) {
#if defined(__APPLE__) || defined(__linux__)
  if (limit < 0 || limit > 16777216) return -1;
  int fd = openat(parent, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
  if (fd < 0) return -1;
  struct stat st;
  if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_nlink != 1 ||
      st.st_size < 0 || st.st_size > limit) {
    close(fd);
    return -1;
  }
  return fd;
#else
  return -1;
#endif
}

/* POSIX side of the existing schema-1 producer task lock. The caller opens an
 * persistent lock file without replacing its inode. Writers may create an
 * absent lock. Closing the descriptor releases either mode. */
int morphir_bounded_try_task_lease(int parent, const char *name, int exclusive) {
#if defined(__APPLE__) || defined(__linux__)
  int flags = O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC;
  flags |= exclusive ? O_RDWR | O_CREAT : O_RDONLY;
  int fd = openat(parent, name, flags, 0644);
  if (fd < 0) return -1;
  struct stat pinned, named;
  if (fstat(fd, &pinned) || !S_ISREG(pinned.st_mode) || pinned.st_nlink != 1 ||
      pinned.st_size != 0 || pinned.st_uid != geteuid() || (pinned.st_mode & 0022)) {
    close(fd);
    return -1;
  }
  if (flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB)) {
    int result = errno == EWOULDBLOCK || errno == EAGAIN ? -2 : -1;
    close(fd);
    return result;
  }
  if (fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) ||
      !same_version(&pinned, &named)) {
    close(fd);
    return -1;
  }
  return fd;
#else
  return -1;
#endif
}

int morphir_bounded_task_lease_matches(int fd, int parent, const char *name) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat pinned, named;
  return !fstat(fd, &pinned) && pinned.st_nlink == 1 &&
    !fstatat(parent, name, &named, AT_SYMLINK_NOFOLLOW) && same_version(&pinned, &named);
#else
  return 0;
#endif
}

void morphir_bounded_task_lock_pause(void) {
#if defined(__APPLE__) || defined(__linux__)
  struct timespec delay = {0, 20000000};
  nanosleep(&delay, NULL);
#endif
}

moonbit_bytes_t morphir_bounded_task_timestamp(void) {
#if defined(__APPLE__) || defined(__linux__)
  char timestamp[21];
  time_t now = time(NULL);
  struct tm utc;
  if (gmtime_r(&now, &utc) &&
      strftime(timestamp, sizeof(timestamp), "%Y-%m-%dT%H:%M:%SZ", &utc) == 20) {
    moonbit_bytes_t result = moonbit_make_bytes(20, 0);
    memcpy(result, timestamp, 20);
    return result;
  }
#endif
  return moonbit_make_bytes(0, 0);
}

int morphir_bounded_replace_file(int parent, const char *staged, const char *name) {
#if defined(__APPLE__) || defined(__linux__)
  return renameat(parent, staged, parent, name);
#else
  return -1;
#endif
}

int morphir_bounded_same_directory(int first, int second) {
#if defined(__APPLE__) || defined(__linux__)
  struct stat a, b;
  return !fstat(first, &a) && !fstat(second, &b) && same_identity(&a, &b);
#else
  return 0;
#endif
}
