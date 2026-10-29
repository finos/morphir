#ifndef MORPHIR_HOST_PROCESS_H
#define MORPHIR_HOST_PROCESS_H
#include "moonbit.h"

/* The callback borrows the owning hosted lifetime for this synchronous wait.
 * 0 continues, 1 forwards SIGINT, 2 allows cooperative cancel-file cleanup. */
moonbit_bytes_t morphir_host_process(const char *, const char *, int,
    const char *, const char *, int, int (*interrupted)(void));
#endif
