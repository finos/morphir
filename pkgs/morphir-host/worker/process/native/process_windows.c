// Process workers on Windows (PROC-1).
//
// Each worker gets its own job object with kill-on-close. The worker joins
// the job before it runs any code: through PROC_THREAD_ATTRIBUTE_JOB_LIST
// where the system has it, otherwise by starting suspended and assigning the
// process before it resumes. The worker inherits only its three pipe ends.
// The host stops the worker by terminating the job, and confirms that the job
// has no active process. If the host exits, the job handle closes and the
// system terminates the job.

#ifdef _WIN32

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <moonbit.h>

#define MORPHIR_ARTIFACT_SYMBOLIC_LINK 1
#define MORPHIR_ARTIFACT_NOT_REGULAR 2
#define MORPHIR_ARTIFACT_TOO_LARGE 3
#define MORPHIR_ARTIFACT_UNREADABLE 4

// Reads a regular file without following a reparse point. `path` is
// NUL-terminated UTF-16. See process_unix.c for the contract.
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
  HANDLE file = CreateFileW(
    (LPCWSTR)path,
    GENERIC_READ,
    FILE_SHARE_READ,
    NULL,
    OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN,
    NULL
  );
  if (file == INVALID_HANDLE_VALUE) {
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = (int32_t)GetLastError();
    return moonbit_make_bytes(0, 0);
  }
  BY_HANDLE_FILE_INFORMATION info;
  if (!GetFileInformationByHandle(file, &info)) {
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = (int32_t)GetLastError();
    CloseHandle(file);
    return moonbit_make_bytes(0, 0);
  }
  if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) {
    problem[0] = MORPHIR_ARTIFACT_SYMBOLIC_LINK;
    CloseHandle(file);
    return moonbit_make_bytes(0, 0);
  }
  if ((info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) ||
      GetFileType(file) != FILE_TYPE_DISK) {
    problem[0] = MORPHIR_ARTIFACT_NOT_REGULAR;
    CloseHandle(file);
    return moonbit_make_bytes(0, 0);
  }
  int64_t size = ((int64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
  if (size > limit) {
    problem[0] = MORPHIR_ARTIFACT_TOO_LARGE;
    CloseHandle(file);
    return moonbit_make_bytes(0, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)size, 0);
  int32_t done = 0;
  while (done < (int32_t)size) {
    DWORD n = 0;
    if (!ReadFile(file, bytes + done, (DWORD)((int32_t)size - done), &n, NULL) ||
        n == 0) {
      problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
      problem[1] = (int32_t)GetLastError();
      CloseHandle(file);
      moonbit_decref(bytes);
      return moonbit_make_bytes(0, 0);
    }
    done += (int32_t)n;
  }
  char extra;
  DWORD more = 0;
  BOOL tail = ReadFile(file, &extra, 1, &more, NULL);
  CloseHandle(file);
  if (!tail || more != 0) {
    problem[0] = MORPHIR_ARTIFACT_UNREADABLE;
    problem[1] = ERROR_FILE_INVALID;
    moonbit_decref(bytes);
    return moonbit_make_bytes(0, 0);
  }
  return bytes;
}

struct morphir_win_worker {
  HANDLE job;
  HANDLE process;
  // The host's ends of stdin, stdout and stderr, until streams own them.
  HANDLE ends[3];
  DWORD pid;
};

static void morphir_close(HANDLE *handle) {
  if (*handle && *handle != INVALID_HANDLE_VALUE) {
    CloseHandle(*handle);
  }
  *handle = NULL;
}

// The only documented variable: SystemRoot, which system libraries such as
// Winsock need. Everything else in the host's environment stays out.
static LPWSTR morphir_environment(void) {
  WCHAR root[MAX_PATH];
  DWORD length = GetEnvironmentVariableW(L"SystemRoot", root, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    LPWSTR empty = (LPWSTR)calloc(2, sizeof(WCHAR));
    return empty;
  }
  const WCHAR prefix[] = L"SystemRoot=";
  size_t prefix_length = sizeof(prefix) / sizeof(WCHAR) - 1;
  LPWSTR block = (LPWSTR)calloc(prefix_length + length + 2, sizeof(WCHAR));
  if (!block) {
    return NULL;
  }
  memcpy(block, prefix, prefix_length * sizeof(WCHAR));
  memcpy(block + prefix_length, root, length * sizeof(WCHAR));
  return block;
}

// Starts `path` with the quoted `command` line (both NUL-terminated UTF-16)
// in `cwd`, inside a new job. Returns the worker, or NULL with the Windows
// error in `error`.
MOONBIT_FFI_EXPORT
struct morphir_win_worker *morphir_worker_win_spawn(
  moonbit_bytes_t path,
  moonbit_bytes_t command,
  moonbit_bytes_t cwd,
  int32_t *error
) {
  *error = 0;
  struct morphir_win_worker *worker =
    (struct morphir_win_worker *)calloc(1, sizeof(struct morphir_win_worker));
  if (!worker) {
    *error = ERROR_NOT_ENOUGH_MEMORY;
    return NULL;
  }
  HANDLE child[3] = {NULL, NULL, NULL};
  HANDLE thread = NULL;
  LPWSTR environment = NULL;
  LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
  BOOL assigned = FALSE;

  worker->job = CreateJobObjectW(NULL, NULL);
  if (!worker->job) {
    goto fail;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
  memset(&limits, 0, sizeof(limits));
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(
        worker->job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)
      )) {
    goto fail;
  }

  // Anonymous pipes are synchronous, so the worker can use them as ordinary
  // standard streams. The host's ends are never inheritable.
  if (!CreatePipe(&child[0], &worker->ends[0], NULL, 0) ||
      !CreatePipe(&worker->ends[1], &child[1], NULL, 0) ||
      !CreatePipe(&worker->ends[2], &child[2], NULL, 0)) {
    goto fail;
  }

  environment = morphir_environment();
  if (!environment) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    goto fail;
  }

  SIZE_T size = 0;
  InitializeProcThreadAttributeList(NULL, 2, 0, &size);
  attributes = (LPPROC_THREAD_ATTRIBUTE_LIST)malloc(size);
  if (!attributes || !InitializeProcThreadAttributeList(attributes, 2, 0, &size)) {
    goto fail;
  }
  if (!UpdateProcThreadAttribute(
        attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST, child,
        sizeof(child), NULL, NULL
      )) {
    goto fail;
  }
  DWORD flags = CREATE_UNICODE_ENVIRONMENT | EXTENDED_STARTUPINFO_PRESENT |
                CREATE_NO_WINDOW;
#ifdef PROC_THREAD_ATTRIBUTE_JOB_LIST
  if (UpdateProcThreadAttribute(
        attributes, 0, PROC_THREAD_ATTRIBUTE_JOB_LIST, &worker->job,
        sizeof(HANDLE), NULL, NULL
      )) {
    assigned = TRUE;
  } else {
    flags |= CREATE_SUSPENDED;
  }
#else
  flags |= CREATE_SUSPENDED;
#endif

  STARTUPINFOEXW startup;
  memset(&startup, 0, sizeof(startup));
  startup.StartupInfo.cb = sizeof(startup);
  startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
  startup.StartupInfo.hStdInput = child[0];
  startup.StartupInfo.hStdOutput = child[1];
  startup.StartupInfo.hStdError = child[2];
  startup.lpAttributeList = attributes;

  // CreateProcessW passes a handle in the handle list only if it is
  // inheritable. From here until the handles close after CreateProcessW,
  // another thread's CreateProcess with bInheritHandles and no handle list
  // can inherit the worker's ends too. That program then holds the worker's
  // stdin or stdout open: the worker reads end of file later, and the host's
  // read of stdout ends at the worker's exit (see channel.mbt), not at end of
  // file. The window is kept to these few calls.
  for (int i = 0; i < 3; ++i) {
    if (!SetHandleInformation(child[i], HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT)) {
      goto fail;
    }
  }
  PROCESS_INFORMATION process;
  memset(&process, 0, sizeof(process));
  if (!CreateProcessW(
        (LPCWSTR)path, (LPWSTR)command, NULL, NULL, TRUE, flags, environment,
        (LPCWSTR)cwd, (LPSTARTUPINFOW)&startup, &process
      )) {
    goto fail;
  }
  worker->process = process.hProcess;
  worker->pid = process.dwProcessId;
  thread = process.hThread;
  if (!assigned) {
    // Still suspended: it has run no code and cannot have children.
    if (!AssignProcessToJobObject(worker->job, worker->process)) {
      DWORD cause = GetLastError();
      TerminateProcess(worker->process, 1);
      WaitForSingleObject(worker->process, 1000);
      SetLastError(cause);
      goto fail;
    }
    if (ResumeThread(thread) == (DWORD)-1) {
      DWORD cause = GetLastError();
      TerminateJobObject(worker->job, 1);
      SetLastError(cause);
      goto fail;
    }
  }
  morphir_close(&thread);
  for (int i = 0; i < 3; ++i) {
    morphir_close(&child[i]);
  }
  DeleteProcThreadAttributeList(attributes);
  free(attributes);
  free(environment);
  return worker;

fail:
  *error = (int32_t)GetLastError();
  if (*error == 0) {
    *error = ERROR_GEN_FAILURE;
  }
  morphir_close(&thread);
  for (int i = 0; i < 3; ++i) {
    morphir_close(&child[i]);
  }
  if (attributes) {
    DeleteProcThreadAttributeList(attributes);
    free(attributes);
  }
  free(environment);
  for (int i = 0; i < 3; ++i) {
    morphir_close(&worker->ends[i]);
  }
  morphir_close(&worker->process);
  morphir_close(&worker->job);
  free(worker);
  return NULL;
}

MOONBIT_FFI_EXPORT
int32_t morphir_worker_win_pid(struct morphir_win_worker *worker) {
  return (int32_t)worker->pid;
}

// The host's end of stdin (0), stdout (1) or stderr (2). It stays the
// worker's until morphir_worker_win_hand_over.
MOONBIT_FFI_EXPORT
HANDLE morphir_worker_win_end(struct morphir_win_worker *worker, int32_t index) {
  return index >= 0 && index < 3 ? worker->ends[index] : NULL;
}

// The first `streams` ends now belong to streams, which close them. The
// others are closed at once. morphir_worker_win_release closes any end that
// was never handed over.
MOONBIT_FFI_EXPORT
void morphir_worker_win_hand_over(
  struct morphir_win_worker *worker,
  int32_t streams
) {
  for (int i = 0; i < 3; ++i) {
    if (i < streams) {
      worker->ends[i] = NULL;
    } else {
      morphir_close(&worker->ends[i]);
    }
  }
}

// Terminates every process in the job. Returns 0 or a Windows error.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_win_terminate(struct morphir_win_worker *worker) {
  if (!worker->job) {
    return ERROR_INVALID_HANDLE;
  }
  return TerminateJobObject(worker->job, 1) ? 0 : (int32_t)GetLastError();
}

// The number of active processes in the job, or a negative Windows error.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_win_active(struct morphir_win_worker *worker) {
  if (!worker->job) {
    return -ERROR_INVALID_HANDLE;
  }
  JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
  if (!QueryInformationJobObject(
        worker->job, JobObjectBasicAccountingInformation, &accounting,
        sizeof(accounting), NULL
      )) {
    return -(int32_t)GetLastError();
  }
  return (int32_t)accounting.ActiveProcesses;
}

// The IDs of the processes in the job, at most `capacity` of them, in
// `pids`. Returns their number, or a negative Windows error.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_win_processes(
  struct morphir_win_worker *worker,
  int32_t *pids,
  int32_t capacity
) {
  if (!worker->job) {
    return -ERROR_INVALID_HANDLE;
  }
  if (capacity < 1) {
    return 0;
  }
  size_t size = sizeof(JOBOBJECT_BASIC_PROCESS_ID_LIST) +
                (size_t)capacity * sizeof(ULONG_PTR);
  JOBOBJECT_BASIC_PROCESS_ID_LIST *list =
    (JOBOBJECT_BASIC_PROCESS_ID_LIST *)calloc(1, size);
  if (!list) {
    return -ERROR_NOT_ENOUGH_MEMORY;
  }
  if (!QueryInformationJobObject(
        worker->job, JobObjectBasicProcessIdList, list, (DWORD)size, NULL
      ) &&
      GetLastError() != ERROR_MORE_DATA) {
    int32_t error = -(int32_t)GetLastError();
    free(list);
    return error;
  }
  int32_t count = (int32_t)list->NumberOfProcessIdsInList;
  if (count > capacity) {
    count = capacity;
  }
  for (int32_t i = 0; i < count; ++i) {
    pids[i] = (int32_t)list->ProcessIdList[i];
  }
  free(list);
  return count;
}

// Closes the job (which kills anything left in it), the process handle and
// any end that was never handed over.
MOONBIT_FFI_EXPORT
void morphir_worker_win_release(struct morphir_win_worker *worker) {
  for (int i = 0; i < 3; ++i) {
    morphir_close(&worker->ends[i]);
  }
  morphir_close(&worker->job);
  morphir_close(&worker->process);
  free(worker);
}

// For tests: opens `path` (NUL-terminated UTF-16), and creates it if it does
// not exist, with no sharing. While the handle is open, no other handle can
// open or delete the file. Writes the handle to `file[0]`. Returns 0 or a
// Windows error.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_win_open_unshared(moonbit_bytes_t path, uint64_t *file) {
  HANDLE handle = CreateFileW(
    (LPCWSTR)path, GENERIC_READ | GENERIC_WRITE, 0, NULL, OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, NULL
  );
  if (handle == INVALID_HANDLE_VALUE) {
    file[0] = 0;
    return (int32_t)GetLastError();
  }
  file[0] = (uint64_t)(uintptr_t)handle;
  return 0;
}

// For tests: closes a handle from morphir_worker_win_open_unshared.
MOONBIT_FFI_EXPORT
void morphir_worker_win_close_file(uint64_t file) {
  if (file) {
    CloseHandle((HANDLE)(uintptr_t)file);
  }
}

// Whether a process runs.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_process_alive(int32_t pid) {
  HANDLE process =
    OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (!process) {
    return GetLastError() == ERROR_ACCESS_DENIED ? 1 : 0;
  }
  DWORD code = 0;
  BOOL ok = GetExitCodeProcess(process, &code);
  CloseHandle(process);
  return ok && code == STILL_ACTIVE ? 1 : 0;
}

// The operating system and the architecture of this host as an index:
// 5 aarch64 Windows, 6 x86_64 Windows, or 0.
MOONBIT_FFI_EXPORT
int32_t morphir_worker_host_machine(void) {
#if defined(_M_ARM64) || defined(__aarch64__)
  return 5;
#elif defined(_M_X64) || defined(__x86_64__)
  return 6;
#else
  return 0;
#endif
}

#endif
