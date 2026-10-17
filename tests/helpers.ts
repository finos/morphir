/** A controllable asynchronous boundary for cancellation and ordering tests. */
export function deferred<T = unknown>() {
  let resolve: (value?: T) => void = () => { throw new Error('Deferred promise is not initialized'); };
  let reject: (cause: unknown) => void = () => { throw new Error('Deferred promise is not initialized'); };
  const promise = new Promise<T>((done, failed) => {
    resolve = value => done(value as T);
    reject = failed;
  });
  return { promise, resolve, reject };
}

/** Deliberately violate a static contract to exercise its runtime rejection. */
export function malformed<T>(value: unknown): T { return value as T; }
