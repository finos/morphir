/* Focused actual Darwin C owner tests. Compile directly with the platform
 * include path; no runner verdict or full-profile assertion is made here. */
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <time.h>
#include <mach/mach_time.h>

static int op_ticks_ns(uint64_t, uint64_t *);
static int paused_read_fd = -1;
static size_t paused_read_remaining;
static uint64_t paused_read_end;
static unsigned int observer_reads, observer_allocations;
static ssize_t audited_read(int fd, void *data, size_t length) {
  ++observer_reads;
  ssize_t result = read(fd, data, length);
  if (fd == paused_read_fd && result > 0) {
    assert((size_t)result <= paused_read_remaining);
    paused_read_remaining -= (size_t)result;
    if (!paused_read_remaining) {
      /* Actual read completed. Model scheduling out before the caller resumes,
       * crossing its original fixed end; no clock or ACK bytes are invented. */
      uint64_t now;
      struct timespec interval = {0, 1000000};
      do { nanosleep(&interval, NULL); assert(op_ticks_ns(mach_continuous_time(), &now)); } while (now <= paused_read_end);
      paused_read_fd = -1;
    }
  }
  return result;
}
static void *audited_malloc(size_t size) { ++observer_allocations; return malloc(size); }

static pid_t consumed_pid = -1;
static int after_reap_wait, after_reap_signal;
static const char *control_name = "startup";
static pid_t audited_waitpid(pid_t pid, int *status, int flags) {
  if (pid == consumed_pid) ++after_reap_wait;
  pid_t result = waitpid(pid, status, flags);
  if (result == pid && pid > 0) consumed_pid = pid;
  return result;
}
static int audited_kill(pid_t pid, int signal_number) {
  if (pid == consumed_pid || pid == -consumed_pid) ++after_reap_signal;
  return kill(pid, signal_number);
}
#define waitpid audited_waitpid
#define kill audited_kill
#define read audited_read
#define malloc audited_malloc
#define MORPHIR_OBSERVER_TEST_DIAGNOSTICS
#include "../originals_observer.c"
#undef waitpid
#undef kill
#undef read
#undef malloc
#include "../platform.c"

/* Minimal allocation ABI used by this focused C executable only. */
moonbit_bytes_t moonbit_make_bytes_raw(int32_t size) { return calloc((size_t)size, 1); }
moonbit_bytes_t moonbit_make_bytes(int32_t size, int value) {
  moonbit_bytes_t result = malloc((size_t)size); memset(result, value, (size_t)size); return result;
}
void moonbit_decref(void *p) { free(p); }

static void read_exact(int fd, void *p, size_t size) {
  size_t at = 0;
  while (at < size) {
    ssize_t n = read(fd, (char *)p + at, size - at);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) fprintf(stderr, "%s collector read: n=%zd errno=%d received=%zu wanted=%zu\n", control_name, n, errno, at, size);
    assert(n > 0); at += (size_t)n;
  }
}
static size_t receive_frame(int fd, char *data) {
  unsigned char head[4]; read_exact(fd, head, 4);
  size_t n = (size_t)head[0] << 24 | (size_t)head[1] << 16 | (size_t)head[2] << 8 | head[3];
  assert(n <= OP_FRAME_LIMIT); read_exact(fd, data, n); data[n] = 0; return n;
}
static void ack_frame(int fd, unsigned int sequence) {
  char data[128]; unsigned char head[4];
  int n = snprintf(data, sizeof(data), "{\"kind\":\"retained\",\"version\":\"" OP_VERSION "\",\"sequence\":%u}", sequence);
  op_be(head, (size_t)n);
  /* Actual ACK fragmented across separate writes, never relying on records. */
  for (int i = 0; i < 4; ++i) assert(write(fd, head + i, 1) == 1);
  for (int i = 0; i < n; ++i) assert(write(fd, data + i, 1) == 1);
}
static void selector(const char *key, uint64_t value) {
  char text[32]; snprintf(text, sizeof(text), "%llu", (unsigned long long)value); assert(!setenv(key, text, 1));
}
typedef struct { int outer[2], helper[2]; uint64_t now; } endpoints;
static endpoints setup(int milliseconds) {
  endpoints e;
  assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, e.outer)); assert(!socketpair(AF_UNIX, SOCK_STREAM, 0, e.helper));
  assert(!fcntl(e.outer[0], F_SETFL, O_NONBLOCK)); assert(!fcntl(e.helper[0], F_SETFL, O_NONBLOCK));
  assert(op_ticks_ns(mach_continuous_time(), &e.now));
  selector("MORPHIR_PRIVATE_CONSUMER_OUTER_FD", (uint64_t)e.outer[0]);
  selector("MORPHIR_PRIVATE_CONSUMER_HELPER_FD", (uint64_t)e.helper[0]);
  selector("MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS", e.now);
  selector("MORPHIR_PRIVATE_CONSUMER_END_NS", e.now + (uint64_t)milliseconds * 1000000);
  selector("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_NUMER", 125);
  selector("MORPHIR_PRIVATE_CONSUMER_TIMEBASE_DENOM", 3);
  assert(!setenv("MORPHIR_PRIVATE_CONSUMER_VERSION", OP_VERSION, 1));
  assert(!setenv("MORPHIR_PRIVATE_CONSUMER_CLOCK_VERSION", OP_VERSION, 1));
  assert(!setenv("MORPHIR_PRIVATE_CONSUMER_CLOCK_DOMAIN", "darwin-mach-continuous-nanoseconds", 1));
  return e;
}
static void collect(int fd, int count, int helper_started) {
  char *data = malloc(OP_FRAME_LIMIT + 1); assert(data);
  for (int i = 0; i < count; ++i) {
    receive_frame(fd, data);
    char expected[32]; snprintf(expected, sizeof(expected), "\"sequence\":%d", i); assert(strstr(data, expected));
    if (i == 0) assert(strstr(data, "\"kind\":\"open\""));
    if (helper_started && i == 1) assert(strstr(data, "\"kind\":\"helper-started\""));
    if (i == count - 1) assert(strstr(data, "\"kind\":\"close\""));
    ack_frame(fd, (unsigned)i);
  }
  char byte; assert(read(fd, &byte, 1) == 0); free(data); close(fd); _exit(0);
}
static void child_ok(pid_t child) { int status; assert(waitpid(child, &status, 0) == child); assert(WIFEXITED(status) && WEXITSTATUS(status) == 0); }
static int word(unsigned char *p) { return (int)((unsigned)p[0] | (unsigned)p[1] << 8 | (unsigned)p[2] << 16 | (unsigned)p[3] << 24); }
static void diagnose(morphir_originals_observer *o, endpoints *e) {
  if (!o || o->poisoned) {
    uint64_t now = 0; op_ticks_ns(mach_continuous_time(), &now);
    fprintf(stderr, "owner diagnostic: pointer=%p outer=%d helper=%d errno=%d now=%llu at=%llu end=%s cause=%s first_errno=%d previous=%llu sequence=%u\n",
        (void *)o, e->outer[0], e->helper[0], errno, (unsigned long long)now, (unsigned long long)e->now,
        getenv("MORPHIR_PRIVATE_CONSUMER_END_NS"), o && o->first_fault ? o->first_fault : "metadata-or-timebase",
        o ? o->first_errno : 0, o ? (unsigned long long)o->previous : 0, o ? o->sequence : 0);
  }
}

static void healthy_facts(void) {
  endpoints e = setup(2000); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) { close(e.outer[0]); close(e.helper[0]); collect(e.outer[1], 4, 0); }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); diagnose(o, &e); assert(o && !o->poisoned);
  morphir_originals_observer_commit(o, "/tmp/raw-\xff-\"", 1);
  morphir_originals_observer_cleanup(o, "/tmp/scratch", 0);
  assert(o->attempted == 2 && o->started == 2 && o->retained == 2 && o->sequence == 3);
  morphir_originals_observer_finish(o); child_ok(collector);
}
static void ack_completed_after_fixed_end(void) {
  endpoints e = setup(500); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) {
    close(e.outer[0]); close(e.helper[0]);
    char *data = malloc(OP_FRAME_LIMIT + 1); assert(data);
    receive_frame(e.outer[1], data); ack_frame(e.outer[1], 0);
    receive_frame(e.outer[1], data); assert(strstr(data, "\"kind\":\"destination-commit-finished\"")); ack_frame(e.outer[1], 1);
    char byte; assert(read(e.outer[1], &byte, 1) == 0); free(data); close(e.outer[1]); _exit(0);
  }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); diagnose(o, &e); assert(o && !o->poisoned);
  const char ack[] = "{\"kind\":\"retained\",\"version\":\"" OP_VERSION "\",\"sequence\":1}";
  paused_read_fd = o->fd; paused_read_remaining = 4 + strlen(ack); paused_read_end = o->end;
  morphir_originals_observer_commit(o, "/tmp/published", 1);
  assert(!paused_read_remaining && paused_read_fd == -1);
  assert(o->poisoned && o->attempted == 1 && o->started == 1 && o->retained == 0 && o->sequence == 1);
  unsigned int reads = observer_reads, allocations = observer_allocations;
  morphir_originals_observer_cleanup(o, "/tmp/scratch", 1);
  assert(o->attempted == 2 && observer_reads == reads && observer_allocations == allocations);
  morphir_originals_observer_finish(o); child_ok(collector);
}
static void expired_fact_allocates_nothing(void) {
  morphir_originals_observer o = {0};
  uint64_t now; assert(op_ticks_ns(mach_continuous_time(), &now));
  o.fd = o.helper_fd = -1; o.previous = now; o.end = now;
  unsigned int reads = observer_reads, allocations = observer_allocations;
  morphir_originals_observer_commit(&o, "/tmp/expired", 1);
  assert(o.poisoned && o.attempted == 1 && o.started == 0 && o.retained == 0);
  assert(observer_reads == reads && observer_allocations == allocations);
}
static void grace_wait_consumed_once(void) {
  endpoints e = setup(3000); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) { close(e.outer[0]); close(e.helper[0]); collect(e.outer[1], 3, 1); }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); diagnose(o, &e); assert(o && !o->poisoned);
  consumed_pid = -1; after_reap_signal = after_reap_wait = 0;
  const char args[] = "-c\0trap 'printf done; exit 0' TERM; while :; do sleep 0.01; done\0";
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/sh", args, 2, "/tmp", "", 500);
  assert(word(result) == 124); assert(o->helper.waited && WIFEXITED(o->helper.status) && WEXITSTATUS(o->helper.status) == 0);
  assert(after_reap_signal == 0 && after_reap_wait == 0);
  assert(o->helper.out.kind == READ_COMPLETE && o->helper.out.count == 4);
  assert(o->helper.out.close_error == 0 && o->helper.err.close_error == 0);
  moonbit_decref(result); morphir_originals_observer_finish(o); child_ok(collector);
}
static void preexec_is_started(void) {
  endpoints e = setup(2000); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) { close(e.outer[0]); close(e.helper[0]); collect(e.outer[1], 3, 1); }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(o);
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/echo", "", 0, "/nonexistent-morphir-owner-fixture", "", 200);
  assert(word(result) == 126 && o->helper.kind == HELPER_STARTED && o->helper.waited);
  assert(WEXITSTATUS(o->helper.status) == 126); moonbit_decref(result);
  morphir_originals_observer_finish(o); child_ok(collector);
}
static void output_layout_and_limit(int oversized) {
  endpoints e = setup(3000); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) { close(e.outer[0]); close(e.helper[0]); collect(e.outer[1], 3, 1); }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(o);
  const char small[] = "-c\0printf out; printf err >&2; exit 9\0";
  const char large[] = "-c\0/usr/bin/head -c 16777217 /dev/zero\0";
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/sh", oversized ? large : small, 2, "/tmp", "", 2000);
  assert(o->helper.waited);
  if (oversized) {
    assert(word(result) == -1 && word(result + 4) == 0);
    assert(o->helper.out.kind == READ_NOT_READ && o->helper.out.reason == NR_REFUSED);
    assert(o->helper.out.close_error == 0 && o->helper.err.close_error == 0);
  } else {
    assert(word(result) == 9 && word(result + 4) == 3 && !memcmp(result + 8, "outerr", 6));
    assert(o->helper.out.count == 3 && o->helper.err.count == 3);
  }
  moonbit_decref(result); morphir_originals_observer_finish(o); child_ok(collector);
}
static void eof_and_kernel_errors(void) {
  unsigned char data[8]; output_observation observation = {0};
  FILE *file = tmpfile(); assert(file); assert(fwrite("abc", 1, 3, file) == 3);
  assert(!op_read(file, &observation, data, 8)); assert(observation.kind == READ_SHORT && observation.count == 3 && observation.error == 0);
  op_dispose(file, &observation); assert(!observation.close_error);
  int pipes[2]; assert(!pipe(pipes)); close(pipes[1]); file = fdopen(pipes[0], "r"); assert(file);
  long length; memset(&observation, 0, sizeof(observation));
  assert(!op_size(file, &observation, &length)); assert(observation.operation == READ_SEEK && observation.error == ESPIPE && observation.count == 0);
  op_dispose(file, &observation);
  char path[] = "/tmp/morphir-c-read-XXXXXX"; int fd = mkstemp(path); assert(fd >= 0); close(fd);
  fd = open(path, O_WRONLY); assert(fd >= 0); file = fdopen(fd, "w"); assert(file);
  memset(&observation, 0, sizeof(observation)); assert(!op_read(file, &observation, data, 1));
  assert(observation.kind == READ_FAILED && observation.operation == READ_READ && observation.error == EBADF && observation.count == 0);
  op_dispose(file, &observation); unlink(path);
  file = tmpfile(); assert(file); assert(!close(fileno(file)));
  memset(&observation, 0, sizeof(observation)); op_dispose(file, &observation);
  assert(observation.close_error == EBADF);
}
static void lost_ack_poison_preserves_monitoring(void) {
  endpoints e = setup(300); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) {
    close(e.outer[0]); close(e.helper[0]);
    char *data = malloc(OP_FRAME_LIMIT + 1); receive_frame(e.outer[1], data); ack_frame(e.outer[1], 0);
    receive_frame(e.outer[1], data); /* Genuine HelperStarted retained but ACK withheld. */
    usleep(450000); char byte; assert(read(e.outer[1], &byte, 1) == 0); close(e.outer[1]); free(data); _exit(0);
  }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(o);
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/sh", "-c\0printf ok; exit 7\0", 2, "/tmp", "", 1000);
  assert(word(result) == 7 && o->helper.waited && WEXITSTATUS(o->helper.status) == 7);
  assert(o->poisoned); unsigned int sequence = o->sequence;
  morphir_originals_observer_commit(o, "/tmp/commit", 1); morphir_originals_observer_cleanup(o, "/tmp/scratch", 1);
  assert(o->sequence == sequence && o->attempted == 2 && o->started == 0);
  moonbit_decref(result); morphir_originals_observer_finish(o); child_ok(collector);
}
static void peer_close_no_sigpipe(void) {
  endpoints e = setup(100); close(e.outer[1]); close(e.helper[1]);
  struct sigaction before, after; assert(!sigaction(SIGPIPE, NULL, &before));
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(!o);
  assert(!sigaction(SIGPIPE, NULL, &after));
  assert(before.sa_handler == after.sa_handler);
  /* An invalid-adoption path owns no descriptor numbers. The actual ordinary
   * application still executes, rather than closing reused output owners. */
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/sh", "-c\0printf legacy; exit 11\0", 2, "/tmp", "", 1000);
  assert(word(result) == 11 && word(result + 4) == 6 && !memcmp(result + 8, "legacy", 6));
  moonbit_decref(result); morphir_originals_observer_finish(o);
  close(e.outer[0]); close(e.helper[0]);
}
static void invalid_adoption_preserves_application(void) {
  endpoints e = setup(2000);
  /* Closed launch descriptor is genuinely reused by the ordinary process's
   * tmpfile. An alleged poisoned owner must not close that output in child. */
  close(e.outer[0]);
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(!o);
  moonbit_bytes_t result = morphir_originals_observer_process(o, "/bin/sh", "-c\0printf reused; printf stderr >&2; exit 12\0", 2, "/tmp", "", 1000);
  assert(word(result) == 12 && word(result + 4) == 6 && !memcmp(result + 8, "reusedstderr", 12));
  moonbit_decref(result); close(e.outer[1]); close(e.helper[0]); close(e.helper[1]);
  e = setup(2000);
  assert(!setenv("MORPHIR_PRIVATE_CONSUMER_OUTER_FD", "03", 1));
  o = morphir_originals_observer_start(); assert(!o);
  result = morphir_originals_observer_process(o, "/bin/sh", "-c\0printf metadata; exit 13\0", 2, "/tmp", "", 1000);
  assert(word(result) == 13 && word(result + 4) == 8 && !memcmp(result + 8, "metadata", 8));
  moonbit_decref(result); close(e.outer[0]); close(e.outer[1]); close(e.helper[0]); close(e.helper[1]);
}
static void integer_bounds(void) {
  uint64_t result; assert(op_ticks_ns(UINT64_MAX / 125, &result)); assert(!op_ticks_ns(UINT64_MAX / 125 + 1, &result));
  assert(op_decimal("18446744073709551615", UINT64_MAX, &result) && result == UINT64_MAX);
  assert(!op_decimal("18446744073709551616", UINT64_MAX, &result));
  assert(!op_decimal("01", UINT64_MAX, &result)); assert(!op_decimal("-1", UINT64_MAX, &result));
}
static void helper_image(void) {
  uint64_t outer, helper, at, end;
  assert(op_selector("MORPHIR_PRIVATE_CONSUMER_OUTER_FD", INT_MAX, &outer));
  assert(op_selector("MORPHIR_PRIVATE_CONSUMER_HELPER_FD", INT_MAX, &helper));
  assert(fcntl((int)outer, F_GETFD) == -1 && errno == EBADF);
  assert(fcntl((int)helper, F_GETFD) >= 0 && !(fcntl((int)helper, F_GETFD) & FD_CLOEXEC));
  assert(op_selector("MORPHIR_PRIVATE_CONSUMER_CLOCK_AT_NS", OP_HORIZON, &at));
  assert(op_selector("MORPHIR_PRIVATE_CONSUMER_END_NS", OP_HORIZON, &end));
  morphir_originals_observer o = {0}; o.fd = (int)helper; o.previous = at; o.end = end;
  assert(op_emit(&o, "{\"kind\":\"open\",\"version\":\"" OP_VERSION "\",\"sequence\":0}", 0));
  assert(op_emit(&o, "{\"kind\":\"close\",\"version\":\"" OP_VERSION "\",\"sequence\":1,\"attemptedHooks\":0,\"startedFactFrames\":0,\"retainedBusinessFacts\":0,\"helper\":{\"kind\":\"not-applicable\"}}", 0));
  close((int)helper); puts("actual-helper");
}
static void actual_endpoint_transfer(const char *program) {
  endpoints e = setup(3000); pid_t collector = fork(); assert(collector >= 0);
  if (!collector) {
    close(e.outer[0]); close(e.helper[0]);
    char *data = malloc(OP_FRAME_LIMIT + 1); assert(data);
    receive_frame(e.outer[1], data); assert(strstr(data, "\"kind\":\"open\"")); ack_frame(e.outer[1], 0);
    receive_frame(e.outer[1], data); assert(strstr(data, "\"kind\":\"helper-started\"")); ack_frame(e.outer[1], 1);
    receive_frame(e.helper[1], data); assert(strstr(data, "\"kind\":\"open\"")); ack_frame(e.helper[1], 0);
    receive_frame(e.helper[1], data); assert(strstr(data, "\"helper\":{\"kind\":\"not-applicable\"}")); ack_frame(e.helper[1], 1);
    char byte; assert(read(e.helper[1], &byte, 1) == 0);
    receive_frame(e.outer[1], data); assert(strstr(data, "\"kind\":\"started\",\"wait\":{\"kind\":\"waited\",\"rawStatus\":\"0\"}")); ack_frame(e.outer[1], 2);
    assert(read(e.outer[1], &byte, 1) == 0); close(e.outer[1]); close(e.helper[1]); free(data); _exit(0);
  }
  close(e.outer[1]); close(e.helper[1]);
  morphir_originals_observer *o = morphir_originals_observer_start(); assert(o);
  moonbit_bytes_t result = morphir_originals_observer_process(o, program, "helper-image\0", 1, "/tmp", "", 2000);
  assert(word(result) == 0 && word(result + 4) == 14);
  assert(!memcmp(result + 8, "actual-helper\n", 14));
  assert(o->helper_fd == -1 && o->helper.waited && o->helper.status == 0);
  moonbit_decref(result); morphir_originals_observer_finish(o); child_ok(collector);
}
int main(int argc, char **argv) {
  if (argc == 2 && !strcmp(argv[1], "helper-image")) { helper_image(); return 0; }
  if (argc == 2 && !strcmp(argv[1], "expired-fact-only")) { expired_fact_allocates_nothing(); return 0; }
  /* The exercised launcher genuinely changes cwd to /tmp. Resolve this test
   * binary before that operation, just as the admitted Node path is absolute. */
  char *program = realpath(argv[0], NULL); assert(program);
  control_name = "integer-bounds"; integer_bounds();
  control_name = "healthy-facts"; healthy_facts();
  control_name = "post-read-deadline"; ack_completed_after_fixed_end();
  control_name = "expired-fact-allocation"; expired_fact_allocates_nothing();
  control_name = "grace-wait"; grace_wait_consumed_once();
  control_name = "preexec"; preexec_is_started();
  control_name = "EOF/kernel-errors"; eof_and_kernel_errors();
  control_name = "lost-ACK"; lost_ack_poison_preserves_monitoring();
  control_name = "peer-close"; peer_close_no_sigpipe();
  control_name = "invalid-adoption"; invalid_adoption_preserves_application();
  control_name = "endpoint-transfer"; actual_endpoint_transfer(program);
  control_name = "output-layout"; output_layout_and_limit(0);
  control_name = "output-limit"; output_layout_and_limit(1);
  free(program);
  puts("originals observer: 13 focused actual C controls PASS"); return 0;
}
