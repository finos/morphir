#include <stdint.h>
#if defined(__APPLE__)
#include <libproc.h>
#include <sys/proc_info.h>
#include <time.h>
#include <unistd.h>
#elif defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <psapi.h>
#else
#include <stdio.h>
#include <time.h>
#include <unistd.h>
#endif

int32_t morphir_worker_platform(void) {
#if defined(__APPLE__) || defined(__linux__)
  return 1;
#else
  /* Windows needs independent native worker lifecycle qualification. */
  return 0;
#endif
}

int32_t morphir_worker_desktop(void) {
#if defined(__APPLE__) && (defined(__aarch64__) || defined(__arm64__))
  return 1;
#else
  /* Other packaged GUI lanes remain a separate qualification task. */
  return 0;
#endif
}

double morphir_worker_now(void) {
#if defined(_WIN32)
  LARGE_INTEGER value, frequency;
  QueryPerformanceCounter(&value);
  QueryPerformanceFrequency(&frequency);
  return (double)value.QuadPart * 1000.0 / (double)frequency.QuadPart;
#else
  struct timespec value;
  if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return -1;
  return value.tv_sec * 1000.0 + value.tv_nsec / 1000000.0;
#endif
}

double morphir_worker_rss(int32_t pid) {
#if defined(__APPLE__)
  struct proc_taskinfo info;
  if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, sizeof(info)) != sizeof(info)) return -1;
  return (double)info.pti_resident_size;
#elif defined(_WIN32)
  HANDLE child = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, (DWORD)pid);
  if (!child) return -1;
  PROCESS_MEMORY_COUNTERS info;
  BOOL ok = K32GetProcessMemoryInfo(child, &info, sizeof(info));
  CloseHandle(child);
  return ok ? (double)info.WorkingSetSize : -1;
#elif defined(__linux__)
  char path[64];
  snprintf(path, sizeof(path), "/proc/%d/statm", pid);
  FILE *file = fopen(path, "r");
  if (!file) return -1;
  unsigned long total, resident;
  int ok = fscanf(file, "%lu %lu", &total, &resident);
  fclose(file);
  return ok == 2 ? (double)resident * sysconf(_SC_PAGESIZE) : -1;
#else
  return -1;
#endif
}

int32_t morphir_worker_pid(void) {
#if defined(_WIN32)
  return (int32_t)GetCurrentProcessId();
#else
  return (int32_t)getpid();
#endif
}
