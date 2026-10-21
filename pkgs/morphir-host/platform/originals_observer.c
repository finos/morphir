/* Private opt-in installed-consumer observations. No public RPC, authority,
 * cases or verdicts are produced here. Normal process() remains independent. */
#include "originals_observer.h"
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <limits.h>
#include <errno.h>

#if defined(__APPLE__) && defined(__aarch64__)
#include <mach/mach_time.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>

#define OP_VERSION "0.1.0-draft.1"
#define OP_FRAME_LIMIT 262144
#define OP_HORIZON UINT64_C(6148914691236517166)
#define OP_OUTPUT_LIMIT 16777216

typedef enum { READ_COMPLETE, READ_SHORT, READ_FAILED, READ_NOT_READ } read_kind;
typedef enum { READ_SEEK, READ_SIZE, READ_READ } read_operation;
typedef enum { NR_WAIT, NR_REFUSED, NR_SIZE, NR_SEEK } not_read_reason;
typedef struct {
  int created;
  read_kind kind;
  read_operation operation;
  not_read_reason reason;
  size_t count;
  int error;
  int close_error;
} output_observation;
typedef enum { HELPER_NOT_ATTEMPTED, HELPER_PREPARATION_FAILED,
  HELPER_FORK_FAILED, HELPER_STARTED } helper_kind;
typedef struct {
  helper_kind kind;
  int waited;
  int status;
  int wait_error;
  output_observation out, err;
} helper_observation;

struct morphir_originals_observer {
  int fd, helper_fd;
  int poisoned;
  unsigned int sequence, attempted, started, retained, seen;
  uint64_t previous, end;
  helper_observation helper;
#ifdef MORPHIR_OBSERVER_TEST_DIAGNOSTICS
  const char *first_fault;
  int first_errno;
#endif
};

static void op_fault(morphir_originals_observer *o, const char *cause) {
#ifdef MORPHIR_OBSERVER_TEST_DIAGNOSTICS
  if (!o->poisoned) { o->first_fault = cause; o->first_errno = errno; }
#else
  (void)cause;
#endif
  o->poisoned = 1;
}

/* The selected ABI fixes the exact timebase. Checked arithmetic precedes the
 * product; integer nanoseconds never pass through a floating representation. */
static int op_ticks_ns(uint64_t ticks, uint64_t *ns) {
  if (ticks > UINT64_MAX / 125) return 0;
  *ns = ticks * 125 / 3;
  return *ns <= OP_HORIZON;
}
static int op_clock(morphir_originals_observer *o) {
  uint64_t now;
  if (o->poisoned) return 0;
  if (!op_ticks_ns(mach_continuous_time(), &now) ||
      now < o->previous || now >= o->end) {
    op_fault(o, "continuous-clock"); return 0;
  }
  o->previous = now;
  return 1;
}
static int op_decimal(const char *s, uint64_t limit, uint64_t *value) {
  uint64_t n = 0;
  if (!s || !*s || (*s == '0' && s[1])) return 0;
  for (; *s; ++s) {
    if (*s < '0' || *s > '9' || n > (limit - (unsigned)(*s - '0')) / 10) return 0;
    n = n * 10 + (unsigned)(*s - '0');
  }
  *value = n; return 1;
}
static int op_selector(const char *name, uint64_t limit, uint64_t *value) {
  return op_decimal(getenv(name), limit, value);
}
static int op_text(const char *name, const char *expected) {
  const char *value = getenv(name);
  return value && !strcmp(value, expected);
}
/* Endpoint is a genuine nonblocking stream socket. SO_NOSIGPIPE is local to
 * this transferred endpoint; no process-wide signal disposition is changed. */
static int op_endpoint(int fd) {
  int flags = fcntl(fd, F_GETFL), kind = 0, yes = 1;
  socklen_t size = sizeof(kind);
  if (flags < 0 || !(flags & O_NONBLOCK) ||
      getsockopt(fd, SOL_SOCKET, SO_TYPE, &kind, &size) || kind != SOCK_STREAM) return 0;
  int result = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#ifdef MORPHIR_OBSERVER_TEST_DIAGNOSTICS
  if (result) fprintf(stderr, "endpoint fd=%d flags=%d type=%d SO_NOSIGPIPE errno=%d\n", fd, flags, kind, errno);
#endif
  return !result;
}
static int op_transfer(morphir_originals_observer *o, void *data, size_t length, int writing) {
  size_t offset = 0;
  while (offset < length) {
    if (!op_clock(o)) return 0;
    ssize_t n = writing ? write(o->fd, (char *)data + offset, length - offset)
                        : read(o->fd, (char *)data + offset, length - offset);
    if (n > 0) { offset += (size_t)n; continue; }
    if (n < 0 && errno == EINTR) continue;
    if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
      struct pollfd fd = { o->fd, writing ? POLLOUT : POLLIN, 0 };
      /* Poll is only a bounded readiness hint. The SAME absolute continuous
       * end is rechecked before every subsequent read/write, including EINTR. */
      int ready = poll(&fd, 1, 1);
      if (ready >= 0 || errno == EINTR) continue;
    }
    op_fault(o, writing ? "write" : "read"); return 0;
  }
  return 1;
}
static void op_be(unsigned char *p, size_t n) {
  p[0] = (unsigned char)(n >> 24); p[1] = (unsigned char)(n >> 16);
  p[2] = (unsigned char)(n >> 8); p[3] = (unsigned char)n;
}
static int op_emit(morphir_originals_observer *o, const char *literal, int business) {
  if (!o || o->poisoned) return 0;
  if (!literal || !op_clock(o)) { op_fault(o, "prewrite"); return 0; }
  size_t length = strlen(literal);
  if (length > OP_FRAME_LIMIT) { op_fault(o, "local-frame-cap"); return 0; }
  unsigned char header[4], got_header[4];
  op_be(header, length);
  if (business) ++o->started;
  if (!op_transfer(o, header, 4, 1) || !op_transfer(o, (void *)literal, length, 1)) return 0;
  char expected[128], got[128];
  int ack_length = snprintf(expected, sizeof(expected),
      "{\"kind\":\"retained\",\"version\":\"" OP_VERSION "\",\"sequence\":%u}", o->sequence);
  if (ack_length < 0 || (size_t)ack_length >= sizeof(expected) ||
      !op_transfer(o, got_header, 4, 0)) { op_fault(o, "ack-header"); return 0; }
  op_be(header, (size_t)ack_length);
  if (memcmp(header, got_header, 4) || !op_transfer(o, got, (size_t)ack_length, 0) ||
      memcmp(expected, got, (size_t)ack_length)) { op_fault(o, "ack-literal"); return 0; }
  /* A complete read is not acceptance: the caller can be descheduled after
   * that syscall. Accept Retained only while the SAME fixed end still holds. */
  if (!op_clock(o)) return 0;
  if (business) ++o->retained;
  ++o->sequence;
  return 1;
}

/* Bounded literal builder. OS operands are byte-preserving lowercase hex,
 * including invalid UTF8; no filesystem input becomes a JSON string escape. */
typedef struct { char *data; size_t used, capacity; int failed; } op_builder;
static void op_add(op_builder *b, const char *s) {
  size_t n = strlen(s);
  if (b->failed || n >= b->capacity - b->used) { b->failed = 1; return; }
  memcpy(b->data + b->used, s, n + 1); b->used += n;
}
static void op_number(op_builder *b, const char *format, unsigned long long n) {
  char text[64]; snprintf(text, sizeof(text), format, n); op_add(b, text);
}
static void op_operand(op_builder *b, const char *s) {
  static const char digits[] = "0123456789abcdef";
  size_t n = strlen(s);
  op_add(b, "{\"kind\":\"unix-bytes\",\"bytes\":{\"kind\":\"hex\",\"hex\":\"");
  if (n > 131072 || b->failed || n > (b->capacity - b->used - 1) / 2) { b->failed = 1; return; }
  for (size_t i = 0; i < n; ++i) {
    unsigned char c = (unsigned char)s[i];
    b->data[b->used++] = digits[c >> 4]; b->data[b->used++] = digits[c & 15];
  }
  b->data[b->used] = 0; op_add(b, "\"}}");
}
static void op_prefix(op_builder *b, const char *kind, unsigned int sequence) {
  op_add(b, "{\"kind\":\""); op_add(b, kind);
  op_add(b, "\",\"version\":\"" OP_VERSION "\",\"sequence\":");
  op_number(b, "%llu", sequence);
}
static void op_built(morphir_originals_observer *o, op_builder *b, int business) {
  if (b->failed) o->poisoned = 1;
  else op_emit(o, b->data, business);
}
morphir_originals_observer *morphir_originals_observer_start(void) {
  /* Only the canonical publish caller invokes start. Invalid metadata cannot
   * cause observation to raise or suppress the original application path. */
  if (!getenv("MORPHIR_PRIVATE_CONSUMER_OUTER_FD")) return NULL;
  uint64_t fd, helper, at, end, numer, denom;
  if (!op_text("MORPHIR_PRIVATE_CONSUMER_VERSION", OP_VERSION) ||
      !op_text("MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION", OP_VERSION) ||
      !op_text("MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN", "darwin-mach-continuous-nanoseconds") ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_OUTER_FD", INT_MAX, &fd) || fd < 3 ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_HELPER_FD", INT_MAX, &helper) || helper < 3 || helper == fd ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS", OP_HORIZON, &at) ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_END_NS", OP_HORIZON, &end) || at >= end ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER", UINT32_MAX, &numer) || numer != 125 ||
      !op_selector("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM", UINT32_MAX, &denom) || denom != 3) return NULL;
  mach_timebase_info_data_t timebase;
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.numer != numer || timebase.denom != denom) return NULL;
  /* Validate BOTH descriptors before adopting either number. An invalid
   * descriptor may later be reused by tmpfile(): it must never reach the
   * observed launcher's close/transfer effects as an alleged endpoint owner. */
  if (!op_endpoint((int)fd) || !op_endpoint((int)helper)) return NULL;
  morphir_originals_observer *o = calloc(1, sizeof(*o));
  if (!o) return NULL;
  o->fd = (int)fd; o->helper_fd = (int)helper; o->previous = at; o->end = end;
  op_emit(o, "{\"kind\":\"open\",\"version\":\"" OP_VERSION "\",\"sequence\":0}", 0);
  return o;
}
static void op_fact(morphir_originals_observer *o, const char *path, int returned, int cleanup) {
  if (!o) return;
  ++o->attempted;
  if (!op_clock(o)) return;
  unsigned int bit = cleanup ? 2 : 1;
  if ((o->seen & bit) || o->attempted > 2) { o->poisoned = 1; return; }
  o->seen |= bit;
  char *data = malloc(OP_FRAME_LIMIT + 1);
  if (!data) { o->poisoned = 1; return; }
  op_builder b = { data, 0, OP_FRAME_LIMIT + 1, 0 }; data[0] = 0;
  op_prefix(&b, "fact", o->sequence);
  op_add(&b, cleanup ? ",\"fact\":{\"kind\":\"scratch-cleanup-finished\",\"path\":" :
      ",\"fact\":{\"kind\":\"destination-commit-finished\",\"path\":");
  op_operand(&b, path);
  if (!cleanup) op_add(&b, ",\"policy\":\"create\"");
  op_add(&b, returned ? ",\"outcome\":\"returned\"}}" : ",\"outcome\":\"raised\"}}");
  op_built(o, &b, 1); free(data);
}
void morphir_originals_observer_commit(morphir_originals_observer *o, const char *path, int returned) {
  op_fact(o, path, returned, 0);
}
void morphir_originals_observer_cleanup(morphir_originals_observer *o, const char *path, int returned) {
  op_fact(o, path, returned, 1);
}
static void op_error(op_builder *b, int error) {
  if (error > 0) {
    op_add(b, "{\"kind\":\"errno\",\"code\":\""); op_number(b, "%llu", (unsigned)error); op_add(b, "\"}");
  } else op_add(b, "{\"kind\":\"unavailable\"}");
}
static void op_output(op_builder *b, output_observation *o) {
  if (!o->created) { op_add(b, "{\"kind\":\"not-created\"}"); return; }
  op_add(b, "{\"kind\":\"owned\",\"read\":{\"kind\":\"");
  if (o->kind == READ_NOT_READ) {
    const char *reasons[] = { "wait-incomplete", "size-refused", "size-failed", "seek-failed" };
    op_add(b, "not-read\",\"reason\":\""); op_add(b, reasons[o->reason]); op_add(b, "\"}");
  } else {
    op_add(b, o->kind == READ_COMPLETE ? "complete" : o->kind == READ_SHORT ? "short-read" : "failed");
    if (o->kind == READ_FAILED) {
      const char *operations[] = { "seek", "size", "read" };
      op_add(b, "\",\"operation\":\""); op_add(b, operations[o->operation]);
    }
    op_add(b, "\",\"byteLength\":\""); op_number(b, "%llu", o->count); op_add(b, "\"");
    if (o->kind == READ_FAILED) { op_add(b, ",\"error\":"); op_error(b, o->error); }
    op_add(b, "}");
  }
  if (o->close_error) {
    op_add(b, ",\"disposal\":{\"kind\":\"failed\",\"operation\":\"close\",\"errorCode\":\"");
    op_number(b, "%llu", (unsigned)o->close_error); op_add(b, "\"}}");
  } else op_add(b, ",\"disposal\":{\"kind\":\"disposed\"}}");
}
static void op_helper(op_builder *b, helper_observation *h) {
  if (h->kind == HELPER_NOT_ATTEMPTED) { op_add(b, "{\"kind\":\"not-attempted\"}"); return; }
  if (h->kind == HELPER_STARTED) {
    op_add(b, "{\"kind\":\"started\",\"wait\":{");
    if (h->waited) {
      char status[64]; snprintf(status, sizeof(status), "\"kind\":\"waited\",\"rawStatus\":\"%d\"}", h->status); op_add(b, status);
    } else {
      op_add(b, "\"kind\":\"failed\",\"errorCode\":\""); op_number(b, "%llu", (unsigned)h->wait_error); op_add(b, "\"}");
    }
  } else {
    op_add(b, "{\"kind\":\"launch-failed\",\"stage\":\"");
    op_add(b, h->kind == HELPER_FORK_FAILED ? "fork" : "preparation"); op_add(b, "\"");
  }
  op_add(b, ",\"stdout\":"); op_output(b, &h->out);
  op_add(b, ",\"stderr\":"); op_output(b, &h->err); op_add(b, "}");
}
void morphir_originals_observer_finish(morphir_originals_observer *o) {
  if (!o) return;
  if (o->helper.out.close_error < 0 || o->helper.err.close_error < 0 ||
      (o->helper.kind == HELPER_STARTED && !o->helper.waited && o->helper.wait_error <= 0)) o->poisoned = 1;
  if (!o->poisoned) {
    char data[2048] = {0}; op_builder b = { data, 0, sizeof(data), 0 };
    op_prefix(&b, "close", o->sequence);
    op_add(&b, ",\"attemptedHooks\":"); op_number(&b, "%llu", o->attempted);
    op_add(&b, ",\"startedFactFrames\":"); op_number(&b, "%llu", o->started);
    op_add(&b, ",\"retainedBusinessFacts\":"); op_number(&b, "%llu", o->retained);
    op_add(&b, ",\"helper\":"); op_helper(&b, &o->helper); op_add(&b, "}");
    op_built(o, &b, 0);
  }
  /* close is never retried: EINTR may already have consumed the descriptor. */
  if (o->helper_fd >= 0) close(o->helper_fd);
  close(o->fd); free(o);
}

extern int morphir_host_interruption_requested(void);
extern int morphir_host_interruption_active(void);
extern moonbit_bytes_t morphir_host_process(const char *, const char *, int, const char *, const char *, int);
static void op_word(unsigned char *p, int value) {
  unsigned int n = (unsigned)value;
  for (int i = 0; i < 4; ++i) p[i] = (unsigned char)(n >> (8 * i));
}
static moonbit_bytes_t op_process_error(const char *text) {
  size_t length = strlen(text);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)length + 8);
  op_word(result, -1); op_word(result + 4, 0); memcpy(result + 8, text, length); return result;
}
static void op_dispose(FILE *file, output_observation *output) {
  if (!file) return;
  errno = 0;
  /* The wire has no unavailable-errno disposal variant. Keep unavailable
   * distinct locally; finish must fault rather than invent an error number. */
  if (fclose(file)) output->close_error = errno > 0 ? errno : -1;
}
static int op_size(FILE *file, output_observation *output, long *length) {
  errno = 0;
  if (fseek(file, 0, SEEK_END)) { output->kind = READ_FAILED; output->operation = READ_SEEK; output->error = errno; return 0; }
  errno = 0; *length = ftell(file);
  if (*length < 0) { output->kind = READ_FAILED; output->operation = READ_SIZE; output->error = errno; return 0; }
  return 1;
}
static int op_read(FILE *file, output_observation *output, unsigned char *dest, size_t length) {
  errno = 0;
  if (fseek(file, 0, SEEK_SET)) { output->kind = READ_FAILED; output->operation = READ_SEEK; output->error = errno; return 0; }
  errno = 0; output->count = fread(dest, 1, length, file);
  if (ferror(file)) { output->kind = READ_FAILED; output->operation = READ_READ; output->error = errno; return 0; }
  if (output->count != length) {
    if (feof(file)) output->kind = READ_SHORT;
    else { output->kind = READ_FAILED; output->operation = READ_READ; output->error = errno; }
    return 0;
  }
  output->kind = READ_COMPLETE; return 1;
}
static void op_helper_started(morphir_originals_observer *o, const char *program, char **argv, int count, const char *cwd) {
  if (o->poisoned) return;
  char *data = malloc(OP_FRAME_LIMIT + 1);
  if (!data) { o->poisoned = 1; return; }
  data[0] = 0; op_builder b = { data, 0, OP_FRAME_LIMIT + 1, 0 };
  op_prefix(&b, "helper-started", o->sequence); op_add(&b, ",\"launch\":{\"program\":"); op_operand(&b, program);
  op_add(&b, ",\"arguments\":[");
  for (int i = 0; i < count; ++i) { if (i) op_add(&b, ","); op_operand(&b, argv[i + 1]); }
  op_add(&b, "],\"directory\":"); op_operand(&b, cwd); op_add(&b, "}}");
  op_built(o, &b, 0); free(data);
}
static int op_process_clock(uint64_t *milliseconds) {
  struct timespec sample;
  if (clock_gettime(CLOCK_MONOTONIC, &sample) || sample.tv_sec < 0 ||
      (uint64_t)sample.tv_sec > UINT64_MAX / 1000) return 0;
  *milliseconds = (uint64_t)sample.tv_sec * 1000 + (uint64_t)sample.tv_nsec / 1000000;
  return 1;
}
moonbit_bytes_t morphir_originals_observer_process(morphir_originals_observer *o,
    const char *program, const char *packed, int count, const char *cwd, const char *home, int timeout) {
  if (!o) return morphir_host_process(program, packed, count, cwd, home, timeout);
  if (o->helper.kind != HELPER_NOT_ATTEMPTED) { o->poisoned = 1; return op_process_error("Observed helper already attempted"); }
  helper_observation *h = &o->helper;
  h->kind = HELPER_PREPARATION_FAILED;
  h->out.kind = h->err.kind = READ_NOT_READ;
  h->out.reason = h->err.reason = NR_WAIT;
  if (count < 0 || count > 1024 || timeout < 1) return op_process_error("Invalid process arguments or timeout");
  char **argv = calloc((size_t)count + 2, sizeof(char *));
  if (!argv) return op_process_error("Cannot allocate process arguments");
  argv[0] = (char *)program;
  const char *next = packed;
  for (int i = 0; i < count; ++i) { argv[i + 1] = (char *)next; next += strlen(next) + 1; }
  FILE *out = tmpfile(), *err = tmpfile();
  h->out.created = out != NULL; h->err.created = err != NULL;
  if (!out || !err) {
    op_dispose(out, &h->out); op_dispose(err, &h->err); free(argv);
    return op_process_error("Cannot create process output files");
  }
  uint64_t process_start = 0;
  int process_clock_available = op_process_clock(&process_start);
  pid_t pid = fork();
  if (!pid) {
    /* Failure to dispose the child's Outer copy cannot become a delegated
     * helper. Child setup failure is still observed as a genuine Started. */
    if (close(o->fd)) _exit(126);
    int flags = fcntl(o->helper_fd, F_GETFD);
    if (flags < 0 || fcntl(o->helper_fd, F_SETFD, flags & ~FD_CLOEXEC)) _exit(126);
    setpgid(0, 0);
    if (dup2(fileno(out), STDOUT_FILENO) < 0 || dup2(fileno(err), STDERR_FILENO) < 0) _exit(126);
    if (fileno(out) != STDOUT_FILENO && fileno(out) != STDERR_FILENO) close(fileno(out));
    if (fileno(err) != STDOUT_FILENO && fileno(err) != STDERR_FILENO) close(fileno(err));
    if (chdir(cwd)) { perror("chdir"); _exit(126); }
    if (*home) {
      const char *path = getenv("PATH"); size_t length = strlen(home) + (path ? strlen(path) : 0) + 8;
      char *child_path = malloc(length);
      if (!child_path) _exit(126);
      snprintf(child_path, length, "%s/bin:%s", home, path ? path : "");
      if (setenv("MOON_HOME", home, 1) || setenv("PATH", child_path, 1)) _exit(126);
      free(child_path);
    }
    execvp(program, argv); perror("execvp"); _exit(127);
  }
  if (pid < 0) {
    h->kind = HELPER_FORK_FAILED; op_dispose(out, &h->out); op_dispose(err, &h->err); free(argv);
    if (close(o->helper_fd)) o->poisoned = 1;
    o->helper_fd = -1; return op_process_error("Cannot start child process");
  }
  h->kind = HELPER_STARTED;
  if (close(o->helper_fd)) o->poisoned = 1;
  o->helper_fd = -1; /* Parent relinquishes helper immediately. */
  int group_owned = setpgid(pid, pid) == 0 || getpgid(pid) == pid;
  op_helper_started(o, program, argv, count, cwd); /* Faults do not stop actual monitoring. */
  free(argv);
  int elapsed = 0, timed_out = 0, oversized = 0, interrupt_forwarded = 0;
  struct timespec interval = {0, 10000000};
  for (;;) {
    pid_t waited = waitpid(pid, &h->status, WNOHANG);
    if (waited == pid) { h->waited = 1; break; }
    if (waited < 0) {
      if (errno == EINTR) continue;
      h->wait_error = errno; break;
    }
    if (!interrupt_forwarded && morphir_host_interruption_active() && morphir_host_interruption_requested()) {
      kill(pid, SIGINT); interrupt_forwarded = 1;
    }
    struct stat a, b;
    if (!fstat(fileno(out), &a) && !fstat(fileno(err), &b) &&
        (a.st_size > OP_OUTPUT_LIMIT || b.st_size > OP_OUTPUT_LIMIT || a.st_size + b.st_size > OP_OUTPUT_LIMIT)) oversized = 1;
    uint64_t process_now;
    int deadline_elapsed = elapsed >= timeout;
    if (process_clock_available && op_process_clock(&process_now) && process_now >= process_start)
      deadline_elapsed = process_now - process_start >= (uint64_t)timeout;
    if (deadline_elapsed || oversized) {
      if (group_owned) kill(-pid, SIGTERM);
      kill(pid, SIGTERM);
      for (int grace = 0; grace < 50; ++grace) {
        pid_t done = waitpid(pid, &h->status, WNOHANG);
        if (done == pid) { h->waited = 1; break; }
        if (done < 0 && errno != EINTR) { h->wait_error = errno; break; }
        nanosleep(&interval, NULL);
      }
      /* A successful grace wait consumes the child exactly once. Never signal
       * or wait its PID again; process-group authority is a separate fact. */
      if (!h->waited && !h->wait_error) {
        if (group_owned) kill(-pid, SIGKILL);
        kill(pid, SIGKILL);
        pid_t done;
        do { done = waitpid(pid, &h->status, 0); } while (done < 0 && errno == EINTR);
        if (done == pid) h->waited = 1; else h->wait_error = errno;
      }
      timed_out = !oversized; break;
    }
    nanosleep(&interval, NULL); elapsed += 10;
  }
  if (!h->waited) {
    op_dispose(out, &h->out); op_dispose(err, &h->err);
    return op_process_error("Cannot wait for helper process");
  }
  long out_length = 0, err_length = 0;
  int out_size_ok = op_size(out, &h->out, &out_length), err_size_ok = op_size(err, &h->err, &err_length);
  if (!out_size_ok || !err_size_ok || oversized || out_length > OP_OUTPUT_LIMIT || err_length > OP_OUTPUT_LIMIT ||
      out_length + err_length > OP_OUTPUT_LIMIT) {
    if (out_size_ok) { h->out.kind = READ_NOT_READ; h->out.reason = err_size_ok ? NR_REFUSED : h->err.operation == READ_SEEK ? NR_SEEK : NR_SIZE; }
    if (err_size_ok) { h->err.kind = READ_NOT_READ; h->err.reason = out_size_ok ? NR_REFUSED : h->out.operation == READ_SEEK ? NR_SEEK : NR_SIZE; }
    op_dispose(out, &h->out); op_dispose(err, &h->err); return op_process_error("Process output unavailable or exceeds 16 MiB");
  }
  int code = timed_out ? 124 : WIFEXITED(h->status) ? WEXITSTATUS(h->status) : WIFSIGNALED(h->status) ? 128 + WTERMSIG(h->status) : -1;
  const char *message = timed_out ? "\nProcess timed out" : "";
  size_t message_length = strlen(message);
  moonbit_bytes_t result = moonbit_make_bytes_raw((int32_t)(8 + out_length + err_length + message_length));
  op_word(result, code); op_word(result + 4, (int)out_length);
  int out_ok = op_read(out, &h->out, result + 8, (size_t)out_length);
  int err_ok = op_read(err, &h->err, result + 8 + out_length, (size_t)err_length);
  memcpy(result + 8 + out_length + err_length, message, message_length);
  op_dispose(out, &h->out); op_dispose(err, &h->err);
  if (!out_ok || !err_ok || h->out.close_error || h->err.close_error) {
    moonbit_decref(result); return op_process_error("Cannot read or dispose helper output");
  }
  return result;
}
#else
struct morphir_originals_observer { int unused; };
morphir_originals_observer *morphir_originals_observer_start(void) { return NULL; }
void morphir_originals_observer_commit(morphir_originals_observer *o, const char *p, int returned) { (void)o; (void)p; (void)returned; }
void morphir_originals_observer_cleanup(morphir_originals_observer *o, const char *p, int returned) { (void)o; (void)p; (void)returned; }
void morphir_originals_observer_finish(morphir_originals_observer *o) { (void)o; }
extern moonbit_bytes_t morphir_host_process(const char *, const char *, int, const char *, const char *, int);
moonbit_bytes_t morphir_originals_observer_process(morphir_originals_observer *o, const char *p, const char *a, int n,
    const char *cwd, const char *home, int timeout) {
  (void)o; return morphir_host_process(p, a, n, cwd, home, timeout);
}
#endif
