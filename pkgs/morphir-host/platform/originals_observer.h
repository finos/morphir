#ifndef MORPHIR_ORIGINALS_OBSERVER_H
#define MORPHIR_ORIGINALS_OBSERVER_H
#include "moonbit.h"

/* A single command owns this pointer. It is borrowed exclusively by process,
 * then by the outer commit/cleanup hooks; finish consumes it. Selectors are
 * launch metadata, never permission to enter the observed publish path. */
typedef struct morphir_originals_observer morphir_originals_observer;
morphir_originals_observer *morphir_originals_observer_start(void);
void morphir_originals_observer_commit(morphir_originals_observer *, const char *, int);
void morphir_originals_observer_cleanup(morphir_originals_observer *, const char *, int);
void morphir_originals_observer_finish(morphir_originals_observer *);
moonbit_bytes_t morphir_originals_observer_process(morphir_originals_observer *,
    const char *, const char *, int, const char *, const char *, int);
#endif
