#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/stat.h>
#include <string.h>
#include "process.h"
#ifndef _WIN32
#include <unistd.h>
#include <dirent.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <poll.h>
#endif
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
static wchar_t *wide_path(const char *text) {
  int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (!size) return NULL;
  wchar_t *result = malloc((size_t)size * sizeof(wchar_t));
  if (!result) return NULL;
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, size)) {
    free(result); return NULL;
  }
  return result;
}
#endif
int morphir_host_kind(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return -1;
  DWORD a = GetFileAttributesW(wide);
  DWORD e = GetLastError();
  free(wide);
  if (a == INVALID_FILE_ATTRIBUTES)
    return (e == ERROR_FILE_NOT_FOUND || e == ERROR_PATH_NOT_FOUND) ? 0 : -1;
  if (a & FILE_ATTRIBUTE_REPARSE_POINT) return 3;
  return (a & FILE_ATTRIBUTE_DIRECTORY) ? 2 : 1;
#else
  struct stat st;
  if (lstat(path, &st)) return (errno == ENOENT || errno == ENOTDIR) ? 0 : -1;
  if (S_ISLNK(st.st_mode)) return 3;
  if (S_ISDIR(st.st_mode)) return 2;
  if (S_ISREG(st.st_mode)) return 1;
  return 4;
#endif
}
int morphir_host_size(const char *path) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return -1;
  struct _stat64 st;
  int result = _wstat64(wide, &st);
  free(wide);
  if (result) return -1;
#else
  struct stat st;
  if (stat(path, &st)) return -1;
#endif
  return st.st_size > 16777216 ? 16777217 : (int)st.st_size;
}
/* Publish the complete directory tree a at the previously absent path b.
 * 0: published. 1: b exists or cannot be reserved (destination_unavailable).
 * 2: the rename failed and b stays absent (create_failed). 3: a reservation
 * could not be removed (reservation_cleanup_failed). Nothing is replaced. */
int morphir_host_rename_directory_new(const char *a, const char *b) {
#ifdef _WIN32
  /* MoveFileExW without MOVEFILE_REPLACE_EXISTING refuses any existing b in
   * the same call that renames, so no reservation and no check-then-rename
   * race exist. Without MOVEFILE_COPY_ALLOWED it never falls back to a copy:
   * a move to another volume fails, so publication stays one atomic rename. */
  wchar_t *source = wide_path(a), *target = wide_path(b);
  if (!source || !target) { int code = source ? 1 : 2; free(source); free(target); return code; }
  int result = 0;
  /* POSIX rename refuses a file or a symbolic link as the source of a
   * directory publication. The caller owns the staging source. */
  DWORD attributes = GetFileAttributesW(source);
  if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
      (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) result = 2;
  else if (!MoveFileExW(source, target, 0)) {
    DWORD error = GetLastError();
    /* Classify only; the failed call changed nothing. As with mkdir on POSIX,
     * an existing b or a missing parent of b (the source was found above)
     * means the destination is unavailable. Other errors, such as another
     * volume or an open handle in the source tree, leave b absent. */
    result = error == ERROR_ALREADY_EXISTS || error == ERROR_FILE_EXISTS ||
        error == ERROR_PATH_NOT_FOUND ||
        GetFileAttributesW(target) != INVALID_FILE_ATTRIBUTES ? 1 : 2;
  }
  free(source); free(target);
  return result;
#else
  struct stat owned, current;
  if (mkdir(b, 0700)) return 1;
  if (lstat(b, &owned)) return 3;
  if (!rename(a, b)) return 0;
  if (lstat(b, &current) || !S_ISDIR(current.st_mode) ||
      current.st_dev != owned.st_dev || current.st_ino != owned.st_ino) return 3;
  return rmdir(b) ? 3 : 2;
#endif
}
int morphir_host_rename(const char *a, const char *b) {
#ifdef _WIN32
  wchar_t *first = wide_path(a), *second = wide_path(b);
  if (!first || !second) { free(first); free(second); return EINVAL; }
  int result = _wrename(first, second) ? errno : 0;
  free(first); free(second);
  return result;
#else
  return rename(a, b) ? errno : 0;
#endif
}
int morphir_host_link_file_new(const char *a, const char *b) {
#ifdef _WIN32
  wchar_t *first = wide_path(a), *second = wide_path(b);
  if (!first || !second) { free(first); free(second); return EINVAL; }
  int result = CreateHardLinkW(second, first, NULL) ? 0 : (int)GetLastError();
  free(first); free(second);
  return result;
#else
  return link(a, b) ? errno : 0;
#endif
}
void morphir_host_stderr(const char *text, int length) { fwrite(text, 1, (size_t)length, stderr); }
void morphir_host_stdout(const char *text, int length) { fwrite(text, 1, (size_t)length, stdout); }
void morphir_host_exit(int code) { exit(code); }
int morphir_host_system(void) {
#ifdef __APPLE__
  return 0;
#elif defined(_WIN32)
  return 1;
#else
  return 2;
#endif
}

int morphir_host_architecture(void) {
#if defined(__aarch64__) || defined(_M_ARM64)
  return 0;
#elif defined(__x86_64__) || defined(_M_X64)
  return 1;
#else
  return 2;
#endif
}

moonbit_bytes_t morphir_host_temporary(void) {
#ifdef _WIN32
  return moonbit_make_bytes(0, 0);
#else
  const char *base = getenv("TMPDIR");
  if (!base || !*base) base = "/tmp";
  size_t length = strlen(base) + 40;
  char *path = malloc(length);
  if (!path) return moonbit_make_bytes(0, 0);
  snprintf(path, length, "%s/morphir-toolchain-XXXXXX", base);
  if (!mkdtemp(path)) { free(path); return moonbit_make_bytes(0, 0); }
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)strlen(path));
  memcpy(result, path, strlen(path)); free(path); return result;
#endif
}

static void put_word(unsigned char *data, int value) {
  unsigned int word = (unsigned int)value;
  for (int i = 0; i < 4; i++) data[i] = (unsigned char)(word >> (i * 8));
}

static moonbit_bytes_t process_error(const char *message) {
  int length = (int)strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw(length + 8);
  put_word(result, -1); put_word(result + 4, 0);
  memcpy(result + 8, message, (size_t)length); return result;
}

int morphir_host_interruption_requested(void);
int morphir_host_interruption_active(void);

moonbit_bytes_t morphir_host_process(const char *program, const char *packed,
    int count, const char *cwd, const char *home, int timeout, int (*interrupted)(void)) {
#ifdef _WIN32
  return process_error("Native Windows process adapter unavailable; use the Node host");
#else
  if (count < 0 || count > 1024 || timeout < 1)
    return process_error("Invalid process arguments or timeout");
  char **argv = calloc((size_t)count + 2, sizeof(char *));
  if (!argv) return process_error("Cannot allocate process arguments");
  argv[0] = (char *)program;
  const char *next = packed;
  for (int i = 0; i < count; i++) { argv[i + 1] = (char *)next; next += strlen(next) + 1; }
  FILE *out = tmpfile(), *err = tmpfile();
  if (!out || !err) {
    if (out) fclose(out); if (err) fclose(err); free(argv);
    return process_error("Cannot create process output files");
  }
  pid_t pid = fork();
  if (pid == 0) {
    setpgid(0, 0);
    if (dup2(fileno(out), STDOUT_FILENO) < 0 || dup2(fileno(err), STDERR_FILENO) < 0) _exit(126);
    if (chdir(cwd)) { perror("chdir"); _exit(126); }
    if (*home) {
      const char *path = getenv("PATH");
      size_t length = strlen(home) + (path ? strlen(path) : 0) + 8;
      char *child_path = malloc(length);
      if (!child_path) _exit(126);
      snprintf(child_path, length, "%s/bin:%s", home, path ? path : "");
      setenv("MOON_HOME", home, 1); setenv("PATH", child_path, 1);
      free(child_path);
    }
    execvp(program, argv); perror("execvp"); _exit(127);
  }
  free(argv);
  if (pid < 0) { fclose(out); fclose(err); return process_error("Cannot start child process"); }
  setpgid(pid, pid);
  int status = 0, elapsed = 0, timed_out = 0, oversized = 0, interrupt_forwarded = 0;
  int interrupt_deadline = -1;
  struct timespec interval = {0, 10000000};
  for (;;) {
    pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid) break;
    if (waited < 0 && errno != EINTR) { status = 127 << 8; break; }
    if (!interrupt_forwarded) {
      int delivery = interrupted();
      if (delivery) {
        // A cooperative helper already has its cancel file. Preserve the same
        // five-second cleanup budget before escalating its owned process tree.
        if (delivery == 1) kill(pid, SIGINT);
        interrupt_forwarded = 1;
        interrupt_deadline = elapsed + 5000;
      }
    }
    struct stat out_stat, err_stat;
    if (!fstat(fileno(out), &out_stat) && !fstat(fileno(err), &err_stat) &&
        out_stat.st_size + err_stat.st_size > 16777216) oversized = 1;
    if (elapsed >= timeout || oversized || (interrupt_deadline >= 0 && elapsed >= interrupt_deadline)) {
      // Give protocol helpers time to reclaim their separately owned child groups.
      kill(-pid, SIGTERM); kill(pid, SIGTERM);
      for (int grace = 0; grace < 50; grace++) {
        if (waitpid(pid, &status, WNOHANG) == pid) break;
        nanosleep(&interval, NULL);
      }
      kill(-pid, SIGKILL); kill(pid, SIGKILL);
      while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
      timed_out = !oversized && interrupt_deadline < 0; break;
    }
    nanosleep(&interval, NULL); elapsed += 10;
  }
  long out_length, err_length;
  fseek(out, 0, SEEK_END); out_length = ftell(out);
  fseek(err, 0, SEEK_END); err_length = ftell(err);
  if (oversized || out_length < 0 || err_length < 0 || out_length + err_length > 16777216) {
    fclose(out); fclose(err); return process_error("Process output exceeds 16 MiB");
  }
  int code = timed_out ? 124 : WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
  const char *message = timed_out ? "\nProcess timed out" : "";
  size_t message_length = strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)(8 + out_length + err_length + message_length));
  put_word(result, code); put_word(result + 4, (int)out_length);
  rewind(out); rewind(err);
  fread(result + 8, 1, (size_t)out_length, out);
  fread(result + 8 + out_length, 1, (size_t)err_length, err);
  memcpy(result + 8 + out_length + err_length, message, message_length);
  fclose(out); fclose(err); return result;
#endif
}

double morphir_monotonic_seconds(void) {
#ifdef _WIN32
  LARGE_INTEGER count, frequency;
  QueryPerformanceCounter(&count); QueryPerformanceFrequency(&frequency);
  return (double)count.QuadPart / (double)frequency.QuadPart;
#else
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
#endif
}
double morphir_wall_seconds(void) {
#ifdef _WIN32
  FILETIME value; ULARGE_INTEGER ticks;
  GetSystemTimeAsFileTime(&value); ticks.LowPart=value.dwLowDateTime; ticks.HighPart=value.dwHighDateTime;
  return (double)(ticks.QuadPart - 116444736000000000ULL) / 1e7;
#else
  struct timespec value;
  clock_gettime(CLOCK_REALTIME, &value);
  return (double)value.tv_sec + (double)value.tv_nsec / 1e9;
#endif
}
uint64_t morphir_observation_nonce(void) {
  uint64_t value = 0;
#ifdef _WIN32
  /* RtlGenRandom is available without an additional link dependency. */
  typedef BOOLEAN (WINAPI *gen_random)(PVOID, ULONG);
  HMODULE module = LoadLibraryA("advapi32.dll");
  gen_random generate = module ? (gen_random)GetProcAddress(module,"SystemFunction036") : NULL;
  int ok = generate && generate(&value, sizeof(value));
  if(module)FreeLibrary(module);
  if(ok)return value;
#else
  FILE *source=fopen("/dev/urandom","rb");
  if(source) { size_t count=fread(&value,1,sizeof(value),source);fclose(source);if(count==sizeof(value))return value; }
#endif
  /* Correlation only, never a credential. Preserve uniqueness if entropy is unavailable. */
  static uint64_t counter=0;
  return (uint64_t)(morphir_monotonic_seconds()*1e9) ^ ++counter;
}

#ifndef _WIN32
#include <fcntl.h>
static int regular_file(const char *path) {
  struct stat st;
  if (lstat(path, &st)) return errno == ENOENT ? 0 : -1;
  return S_ISREG(st.st_mode) ? 1 : -1;
}
static int write_log(const char *path, const unsigned char *data, int length) {
  size_t size = strlen(path) + 16;
  char *old = malloc(size), *dest = malloc(size);
  if (!old || !dest) { free(old); free(dest); return -1; }
  int result = 0;
  for (int i = 3; i >= 1; i--) {
    if (i == 1) snprintf(old, size, "%s", path);
    else snprintf(old, size, "%s.%d", path, i - 1);
    snprintf(dest, size, "%s.%d", path, i);
    int source = regular_file(old), target = regular_file(dest);
    if (source < 0 || target < 0) { result = -1; break; }
    if (source && ((target && unlink(dest)) || rename(old, dest))) { result = -1; break; }
  }
  free(old); free(dest);
  if (result) return result;
  int fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NONBLOCK, 0600);
  if (fd < 0) return -1;
  int offset = 0;
  while (offset < length) {
    ssize_t written = write(fd, data + offset, (size_t)(length - offset));
    if (written < 0 && errno == EINTR) continue;
    if (written <= 0) { result = -1; break; }
    offset += (int)written;
  }
  if (close(fd)) result = -1;
  return result;
}
static int default_log_dirs(const char *root) {
  struct stat st;
  if (lstat(root, &st) || !S_ISDIR(st.st_mode)) return -1;
  size_t length = strlen(root);
  char *path = malloc(length + 16);
  if (!path) return -1;
  const char *suffixes[] = {"/.morphir", "/.morphir/logs"};
  int result = 0;
  for (int i = 0; i < 2; i++) {
    snprintf(path, length + 16, "%s%s", root, suffixes[i]);
    if (mkdir(path, 0700) && errno != EEXIST) { result = -1; break; }
    if (lstat(path, &st) || !S_ISDIR(st.st_mode)) { result = -1; break; }
  }
  free(path);
  return result;
}
#else
/* The worker never borrows Moon-managed storage. A timed-out filesystem call
   may resist cancellation, so retain its snapshot until it actually returns
   and refuse further drains while it is outstanding. Never terminate a thread
   that may own CRT/allocator locks or a pending Windows I/O buffer. */
static volatile LONG log_worker_active = 0;
typedef struct {
  volatile LONG references;
  volatile LONG cancelled;
  wchar_t *path;
  wchar_t *root;
  unsigned char *data;
  int length;
  HANDLE stderr_handle;
} log_work;

static void release_log_work(log_work *work) {
  if (InterlockedDecrement(&work->references) == 0) {
    if (work->stderr_handle != INVALID_HANDLE_VALUE) CloseHandle(work->stderr_handle);
    free(work->path); free(work->root); free(work->data); free(work);
  }
}

static int log_cancelled(log_work *work) {
  return InterlockedCompareExchange(&work->cancelled, 0, 0) != 0;
}

static int regular_log_file(const wchar_t *path) {
  DWORD attributes = GetFileAttributesW(path);
  if (attributes == INVALID_FILE_ATTRIBUTES) {
    DWORD error = GetLastError();
    return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND ? 0 : -1;
  }
  return attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DEVICE) ? -1 : 1;
}

static int log_directory(const wchar_t *path) {
  DWORD attributes = GetFileAttributesW(path);
  return attributes != INVALID_FILE_ATTRIBUTES &&
    (attributes & FILE_ATTRIBUTE_DIRECTORY) && !(attributes & FILE_ATTRIBUTE_REPARSE_POINT);
}

static int default_log_dirs(log_work *work) {
  if (log_cancelled(work) || !log_directory(work->root)) return -1;
  size_t length = wcslen(work->root);
  wchar_t *path = malloc((length + 16) * sizeof(wchar_t));
  if (!path) return -1;
  const wchar_t *suffixes[] = {L"/.morphir", L"/.morphir/logs"};
  int result = 0;
  for (int i = 0; i < 2; i++) {
    wcscpy(path, work->root); wcscat(path, suffixes[i]);
    if (log_cancelled(work) ||
        (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) ||
        !log_directory(path)) { result = -1; break; }
  }
  free(path);
  return result;
}

static int write_log_bytes(log_work *work, HANDLE file) {
  int offset = 0;
  while (offset < work->length) {
    DWORD written = 0;
    if (log_cancelled(work) ||
        !WriteFile(file, work->data + offset, (DWORD)(work->length - offset), &written, NULL) ||
        written == 0) return -1;
    offset += (int)written;
  }
  return log_cancelled(work) ? -1 : 0;
}

static int write_log(log_work *work) {
  size_t length = wcslen(work->path);
  wchar_t *old = malloc((length + 3) * sizeof(wchar_t));
  wchar_t *dest = malloc((length + 3) * sizeof(wchar_t));
  if (!old || !dest) { free(old); free(dest); return -1; }
  int result = 0;
  for (int i = 3; i >= 1; i--) {
    wcscpy(old, work->path); wcscpy(dest, work->path);
    if (i != 1) { old[length] = L'.'; old[length + 1] = (wchar_t)(L'0' + i - 1); old[length + 2] = 0; }
    dest[length] = L'.'; dest[length + 1] = (wchar_t)(L'0' + i); dest[length + 2] = 0;
    if (log_cancelled(work)) { result = -1; break; }
    int source = regular_log_file(old), target = regular_log_file(dest);
    if (source < 0 || target < 0) { result = -1; break; }
    if (source && (log_cancelled(work) || (target && !DeleteFileW(dest)) ||
        log_cancelled(work) || !MoveFileW(old, dest))) { result = -1; break; }
  }
  free(old); free(dest);
  if (result || log_cancelled(work)) return -1;
  HANDLE file = CreateFileW(work->path, GENERIC_WRITE, 0, NULL, CREATE_NEW,
    FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, NULL);
  if (file == INVALID_HANDLE_VALUE) return -1;
  BY_HANDLE_FILE_INFORMATION info;
  if (GetFileType(file) != FILE_TYPE_DISK || !GetFileInformationByHandle(file, &info) ||
      (info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT))) result = -1;
  else result = write_log_bytes(work, file);
  if (!CloseHandle(file)) result = -1;
  return result;
}

static DWORD WINAPI log_worker(void *argument) {
  log_work *work = argument;
  int result = -1;
  if (!log_cancelled(work)) {
    if (work->stderr_handle != INVALID_HANDLE_VALUE)
      result = write_log_bytes(work, work->stderr_handle);
    else if (!*work->root || !default_log_dirs(work)) result = write_log(work);
  }
  release_log_work(work);
  InterlockedExchange(&log_worker_active, 0);
  return result == 0 ? 0 : 1;
}
#endif
int morphir_flush_file(const char *path, const unsigned char *data, int length, int timeout, const char *root) {
#ifdef _WIN32
  if (length < 0 || length > 4194304 || timeout < 1 || timeout > 5000 ||
      strlen(path) > 131068 || strlen(root) > 131068) return -1;
  if (InterlockedCompareExchange(&log_worker_active, 1, 0) != 0) return -1;
  log_work *work = calloc(1, sizeof(log_work));
  if (!work) { InterlockedExchange(&log_worker_active, 0); return -1; }
  work->references = 1;
  work->stderr_handle = INVALID_HANDLE_VALUE;
  work->path = wide_path(path); work->root = wide_path(root);
  work->data = malloc(length ? (size_t)length : 1);
  work->length = length;
  if (!work->path || !work->root || !work->data ||
      wcslen(work->path) >= 32767 || wcslen(work->root) >= 32767) {
    release_log_work(work); InterlockedExchange(&log_worker_active, 0); return -1;
  }
  memcpy(work->data, data, (size_t)length);
  if (!strcmp(path, "@stderr") && !DuplicateHandle(GetCurrentProcess(),
      GetStdHandle(STD_ERROR_HANDLE), GetCurrentProcess(), &work->stderr_handle,
      0, FALSE, DUPLICATE_SAME_ACCESS)) {
    work->stderr_handle = INVALID_HANDLE_VALUE;
    release_log_work(work); InterlockedExchange(&log_worker_active, 0); return -1;
  }
  InterlockedIncrement(&work->references);
  HANDLE worker = CreateThread(NULL, 0, log_worker, work, 0, NULL);
  if (!worker) {
    release_log_work(work); release_log_work(work);
    InterlockedExchange(&log_worker_active, 0); return -1;
  }
  int result = -1;
  if (WaitForSingleObject(worker, (DWORD)timeout) == WAIT_OBJECT_0) {
    DWORD code;
    if (GetExitCodeThread(worker, &code) && code == 0) result = 0;
  } else {
    InterlockedExchange(&work->cancelled, 1);
    CancelSynchronousIo(worker);
    // As with the POSIX worker, shutdown has a separate 20-ms allowance.
    // Cancellation is a request, not evidence that a pending write was undone.
    WaitForSingleObject(worker, 20);
  }
  CloseHandle(worker);
  release_log_work(work);
  return result;
#else
  if (length < 0 || length > 4194304 || timeout < 1 || timeout > 5000) return -1;
  pid_t pid = fork();
  if (pid < 0) return -1;
  if (pid == 0) {
    if (!strcmp(path, "@stderr")) {
      int offset = 0;
      while (offset < length) {
        ssize_t written = write(STDERR_FILENO, data + offset, (size_t)(length - offset));
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) _exit(1);
        offset += (int)written;
      }
      _exit(0);
    }
    if (*root && default_log_dirs(root)) _exit(1);
    _exit(write_log(path, data, length) ? 1 : 0);
  }
  struct timespec interval = {0, 1000000};
  double deadline = morphir_monotonic_seconds() + (double)timeout / 1000.0;
  int status = 0;
  for (;;) {
    pid_t waited = waitpid(pid, &status, WNOHANG);
    if (waited == pid) return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
    if (waited < 0 && errno != EINTR) return -1;
    if (morphir_monotonic_seconds() >= deadline) break;
    nanosleep(&interval, NULL);
  }
  kill(pid, SIGKILL);
  // Keep shutdown bounded even if a host filesystem is stuck in kernel I/O.
  for (int i = 0; i < 20; i++) {
    if (waitpid(pid, &status, WNOHANG) == pid) break;
    nanosleep(&interval, NULL);
  }
  return -1;
#endif
}

/* Bounded descriptor reads for executable pins, independent of model buffers. */
#include <fcntl.h>
#ifdef _WIN32
#include <io.h>
#endif
int morphir_host_file_open(const char *path, int limit) {
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  if (!wide) return -1;
  int fd = _wopen(wide, _O_RDONLY | _O_BINARY | _O_NOINHERIT);
  free(wide);
  if (fd < 0) return -1;
  struct _stat64 st;
  if (_fstat64(fd, &st) || (st.st_mode & _S_IFMT) != _S_IFREG || st.st_size < 0 || st.st_size > limit) {
    _close(fd); return -1;
  }
#else
  int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) return -1;
  struct stat st;
  if (fstat(fd, &st) || !S_ISREG(st.st_mode) || st.st_size < 0 || st.st_size > limit) {
    close(fd); return -1;
  }
#endif
  return fd;
}
int morphir_host_file_read(int fd, unsigned char *buffer, int length) {
#ifdef _WIN32
  return _read(fd, buffer, (unsigned int)length);
#else
  ssize_t result;
  do { result = read(fd, buffer, (size_t)length); } while (result < 0 && errno == EINTR);
  return (int)result;
#endif
}
int morphir_host_file_close(int fd) {
#ifdef _WIN32
  return _close(fd);
#else
  return close(fd);
#endif
}

/* Command-owned cooperative interruption. The signal handler only sets a flag. */
static volatile sig_atomic_t morphir_interrupted = 0;
static int morphir_interrupt_active = 0;
#ifdef _WIN32
static void (*morphir_previous_interrupt)(int) = SIG_DFL;
#else
static struct sigaction morphir_previous_interrupt;
#endif
static void morphir_interrupt_handler(int signal_number) {
  (void)signal_number;
  morphir_interrupted = 1;
}
void morphir_host_interruption_start(void) {
  if (morphir_interrupt_active) return;
  morphir_interrupted = 0;
#ifdef _WIN32
  morphir_previous_interrupt = signal(SIGINT, morphir_interrupt_handler);
  morphir_interrupt_active = morphir_previous_interrupt != SIG_ERR;
#else
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = morphir_interrupt_handler;
  sigemptyset(&action.sa_mask);
  morphir_interrupt_active = sigaction(SIGINT, &action, &morphir_previous_interrupt) == 0;
#endif
}
void morphir_host_interruption_stop(void) {
  if (!morphir_interrupt_active) return;
#ifdef _WIN32
  signal(SIGINT, morphir_previous_interrupt);
#else
  sigaction(SIGINT, &morphir_previous_interrupt, NULL);
#endif
  morphir_interrupt_active = 0;
}
int morphir_host_interruption_requested(void) { return morphir_interrupted != 0; }
int morphir_host_interruption_active(void) { return morphir_interrupt_active; }
int morphir_host_stdin_read(unsigned char *buffer, int length, int (*interrupted)(void)) {
  if (length < 1 || length > 65536 || interrupted()) return -1;
#ifdef _WIN32
  int previous_mode = _setmode(0, _O_BINARY);
  HANDLE input = (HANDLE)_get_osfhandle(0);
  int result;
  if (GetFileType(input) == FILE_TYPE_PIPE) {
    for (;;) {
      if (interrupted()) { result = -1; break; }
      DWORD available = 0;
      if (!PeekNamedPipe(input, NULL, 0, NULL, &available, NULL)) {
        DWORD error = GetLastError();
        result = error == ERROR_BROKEN_PIPE || error == ERROR_PIPE_NOT_CONNECTED ? 0 : -1;
        break;
      }
      if (available) {
        unsigned int count = available < (DWORD)length ? (unsigned int)available : (unsigned int)length;
        result = _read(0, buffer, count);
        break;
      }
      Sleep(10);
    }
  } else result = _read(0, buffer, (unsigned int)length);
  if (previous_mode >= 0) _setmode(0, previous_mode);
  return result;
#else
  // Polling lets a hosted cancel file stop a read even without an OS signal.
  struct pollfd input = {0, POLLIN, 0};
  for (;;) {
    if (interrupted()) return -1;
    int ready = poll(&input, 1, 10);
    if (ready < 0) { if (errno == EINTR) continue; return -1; }
    if (!ready) continue;
    ssize_t result = read(0, buffer, (size_t)length);
    if (result < 0 && errno == EINTR) continue;
    return (int)result;
  }
#endif
}

/* A bounded packed result: status byte followed by NUL-terminated UTF-8 names.
 * Only one OS entry is observed at a time. No unbounded readdir collection is
 * created, even for limit zero or when the first over-budget entry is found. */
static int directory_append(unsigned char **data, size_t *used, size_t *capacity,
    int *count, int limit, const char *name) {
  if (!strcmp(name, ".") || !strcmp(name, "..")) return 0;
  if (*count >= limit) return 1;
  size_t length = strlen(name);
  if (length > 16384 || length + 1 > 4194304 - *used) return 2;
  size_t needed = *used + length + 1;
  if (needed > *capacity) {
    size_t next = *capacity;
    while (next < needed) next = next > 2097152 ? 4194304 : next * 2;
    unsigned char *grown = realloc(*data, next);
    if (!grown) return 3;
    *data = grown; *capacity = next;
  }
  memcpy(*data + *used, name, length + 1);
  *used = needed; ++*count;
  return 0;
}

moonbit_bytes_t morphir_host_list_bounded(const char *path, int limit, int (*interrupted)(void)) {
  size_t used = 1, capacity = 64;
  unsigned char *data = malloc(capacity);
  int status = 0, count = 0;
  if (!data || limit < 0 || limit > 65536) {
    free(data); return moonbit_make_bytes(1, 5);
  }
#ifdef _WIN32
  wchar_t *wide = wide_path(path);
  HANDLE directory = INVALID_HANDLE_VALUE;
  if (!wide || morphir_host_kind(path) != 2) status = 5;
  if (!status) {
    size_t length = wcslen(wide);
    wchar_t *pattern = malloc((length + 3) * sizeof(wchar_t));
    if (!pattern) status = 5;
    else {
      memcpy(pattern, wide, length * sizeof(wchar_t));
      pattern[length] = L'/'; pattern[length + 1] = L'*'; pattern[length + 2] = 0;
      WIN32_FIND_DATAW entry;
      directory = FindFirstFileW(pattern, &entry);
      DWORD open_error = GetLastError();
      free(pattern);
      if (directory == INVALID_HANDLE_VALUE) {
        if (open_error != ERROR_FILE_NOT_FOUND) status = 5;
      } else for (;;) {
        if (interrupted()) { status = 6; break; }
        char name[16385];
        int length = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS,
            entry.cFileName, -1, name, sizeof(name), NULL, NULL);
        if (!length) { status = 3; break; }
        status = directory_append(&data, &used, &capacity, &count, limit, name);
        if (status) break;
        if (!FindNextFileW(directory, &entry)) {
          if (GetLastError() != ERROR_NO_MORE_FILES) status = 3;
          break;
        }
      }
    }
  }
  free(wide);
  if (directory != INVALID_HANDLE_VALUE && !FindClose(directory)) status = 4;
#else
  DIR *directory = NULL;
  /* Existing Mount confinement checks every component. Refuse a final symlink
   * here as well; the portable host assumes caller-owned parents stay stable. */
  int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (fd < 0) status = 5;
  else {
    directory = fdopendir(fd);
    if (!directory) { status = 5; if (close(fd)) status = 4; }
  }
  if (directory) {
    for (;;) {
      if (interrupted()) { status = 6; break; }
      errno = 0;
      struct dirent *entry = readdir(directory);
      if (!entry) { if (errno) status = 3; break; }
      status = directory_append(&data, &used, &capacity, &count, limit, entry->d_name);
      if (status) break;
    }
    if (closedir(directory)) status = 4;
  }
#endif
  moonbit_bytes_t result = moonbit_make_bytes_raw(status ? 1 : (int32_t)used);
  result[0] = (unsigned char)status;
  if (!status && used > 1) memcpy(result + 1, data + 1, used - 1);
  free(data);
  return result;
}
