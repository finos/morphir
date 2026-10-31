// The path of the running executable, as UTF-8 bytes. On Linux it is
// /proc/self/exe, which the host reads through. On macOS it is the real
// path of _NSGetExecutablePath; on Windows, GetModuleFileNameW. An empty
// result means the path is not known.
#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static moonbit_bytes_t morphir_wasm_bytes(const char *text, size_t length) {
  moonbit_bytes_t result = moonbit_make_bytes((int32_t)length, 0);
  memcpy(result, text, length);
  return result;
}

#if defined(__APPLE__)
#include <limits.h>
#include <mach-o/dyld.h>

MOONBIT_FFI_EXPORT moonbit_bytes_t morphir_wasm_worker_executable_path(void) {
  char path[PATH_MAX];
  uint32_t size = sizeof(path);
  if (_NSGetExecutablePath(path, &size) != 0) {
    return morphir_wasm_bytes("", 0);
  }
  char real[PATH_MAX];
  if (realpath(path, real) == NULL) {
    return morphir_wasm_bytes("", 0);
  }
  return morphir_wasm_bytes(real, strlen(real));
}
#elif defined(_WIN32)
#include <windows.h>

MOONBIT_FFI_EXPORT moonbit_bytes_t morphir_wasm_worker_executable_path(void) {
  wchar_t path[32768];
  DWORD length = GetModuleFileNameW(NULL, path, 32768);
  if (length == 0 || length >= 32768) {
    return morphir_wasm_bytes("", 0);
  }
  int bytes = WideCharToMultiByte(CP_UTF8, 0, path, (int)length, NULL, 0, NULL, NULL);
  if (bytes <= 0) {
    return morphir_wasm_bytes("", 0);
  }
  moonbit_bytes_t result = moonbit_make_bytes(bytes, 0);
  WideCharToMultiByte(CP_UTF8, 0, path, (int)length, (char *)result, bytes, NULL, NULL);
  return result;
}
#else
MOONBIT_FFI_EXPORT moonbit_bytes_t morphir_wasm_worker_executable_path(void) {
  static const char path[] = "/proc/self/exe";
  return morphir_wasm_bytes(path, sizeof(path) - 1);
}
#endif
