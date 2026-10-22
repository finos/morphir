import { isMainThread, parentPort, Worker, workerData } from 'node:worker_threads';

const globals = globalThis as typeof globalThis & {
  __morphirInterrupt?: Int32Array;
  __morphirStdinRead?: (buffer: Uint8Array, length: number) => number;
};

/** Run synchronous CLI evaluation in one owned worker. The parent receives
 * SIGINT and reads stdin asynchronously, one requested 64 KiB chunk at a time. */
export function terminalWorker(entry: URL, args: string[]): boolean {
  if (!isMainThread) {
    if (workerData?.morphirInterrupt instanceof SharedArrayBuffer &&
        workerData?.morphirInputState instanceof SharedArrayBuffer &&
        workerData?.morphirInputBytes instanceof SharedArrayBuffer) {
      const interrupted = new Int32Array(workerData.morphirInterrupt);
      const state = new Int32Array(workerData.morphirInputState);
      const bytes = new Uint8Array(workerData.morphirInputBytes);
      globals.__morphirInterrupt = interrupted;
      globals.__morphirStdinRead = (buffer, length) => {
        if (length < 1 || length > bytes.length || Atomics.load(interrupted, 0)) return -1;
        Atomics.store(state, 0, 0);
        parentPort!.postMessage({ type: 'morphir:stdin', length });
        while (Atomics.load(state, 0) === 0) {
          if (Atomics.load(interrupted, 0)) return -1;
          Atomics.wait(state, 0, 0, 100);
        }
        if (Atomics.load(interrupted, 0)) return -1;
        const status = Atomics.load(state, 0);
        if (status === 2) return 0;
        if (status !== 1) return -1;
        const count = Atomics.load(state, 1);
        if (count < 1 || count > length) return -1;
        buffer.set(bytes.subarray(0, count));
        return count;
      };
    }
    return false;
  }
  const command = args.find(arg => !['--json', '--json-lines', '--help', '-h', '--no-banner'].includes(arg));
  if (command !== 'worksheet' && command !== 'eval' && command !== 'connected' && command !== 'model' && command !== 'generate' && command !== 'mck') return false;
  const interrupted = new Int32Array(new SharedArrayBuffer(4));
  const state = new Int32Array(new SharedArrayBuffer(8));
  const bytes = new Uint8Array(new SharedArrayBuffer(65536));
  const worker = new Worker(entry, {
    argv: process.argv.slice(2),
    workerData: { morphirInterrupt: interrupted.buffer, morphirInputState: state.buffer, morphirInputBytes: bytes.buffer },
  });
  let requested = 0;
  let inputFailed = false;
  let inputActive = false;
  let workerFailed = false;
  const respond = (status: number, length = 0) => {
    requested = 0;
    Atomics.store(state, 1, length);
    Atomics.store(state, 0, status);
    Atomics.notify(state, 0);
  };
  const pump = () => {
    if (!requested) return;
    if (inputFailed) return respond(3);
    try {
      const chunk = process.stdin.read(requested) as Buffer | null;
      if (chunk) {
        bytes.set(chunk);
        respond(1, chunk.length);
      } else if (process.stdin.readableEnded) respond(2);
    } catch {
      inputFailed = true;
      respond(3);
    }
  };
  const inputError = () => { inputFailed = true; pump(); };
  const inputRequest = (message: unknown) => {
    const request = message as { type?: unknown; length?: unknown };
    if (request?.type !== 'morphir:stdin') return;
    if (requested || !Number.isInteger(request.length) || (request.length as number) < 1 || (request.length as number) > bytes.length) {
      inputFailed = true;
      respond(3);
      return;
    }
    if (!inputActive) {
      inputActive = true;
      process.stdin.on('readable', pump);
      process.stdin.on('end', pump);
      process.stdin.on('error', inputError);
    }
    requested = request.length as number;
    pump();
  };
  const interrupt = () => { Atomics.store(interrupted, 0, 1); Atomics.notify(state, 0); };
  process.on('SIGINT', interrupt);
  worker.on('message', inputRequest);
  worker.once('error', error => { workerFailed = true; console.error(error.message); });
  worker.once('exit', code => {
    process.off('SIGINT', interrupt);
    if (inputActive) {
      process.stdin.off('readable', pump);
      process.stdin.off('end', pump);
      process.stdin.off('error', inputError);
      process.stdin.pause();
      // A caller may keep its pipe open indefinitely. Release our event-loop
      // reference without closing the caller's stream or waiting for EOF.
      (process.stdin as typeof process.stdin & { unref?: () => void }).unref?.();
    }
    worker.off('message', inputRequest);
    process.exitCode = workerFailed ? 2 : code;
  });
  return true;
}

/** The bounded bridge uses this only from its synchronous worker. */
export function terminalStdinRead(buffer: Uint8Array, length: number): number | undefined {
  return globals.__morphirStdinRead?.(buffer, length);
}
