// Test-only observation/fault injection. This file is never a packaged asset.
// Observe the real Node process without adding production launcher controls.
const { isMainThread } = require('node:worker_threads') as typeof import('node:worker_threads');
if (isMainThread && process.env.MORPHIR_MOONX_TEST_CONFIG) {
  const fs = require('node:fs') as typeof import('node:fs');
  const config = JSON.parse(fs.readFileSync(process.env.MORPHIR_MOONX_TEST_CONFIG, 'utf8'));
  if (!['observe', 'transport', 'unresponsive'].includes(config.mode)) {
    throw new Error('Unknown Moonx qualification preload mode');
  }
  const record = (event: string, details: object = {}) => fs.appendFileSync(config.events, JSON.stringify({
    profile: 'morphir/moonx-test-observation', contractVersion: '0.1.0',
    event, pid: process.pid, ...details,
  }) + '\n');
  const entry = process.argv[1];
  if (!entry) throw new Error('Moonx qualification preload requires an entry');
  record('node-started', {
    mode: config.mode, node: process.version, entry, entryCanonical: fs.realpathSync(entry),
    arguments: process.argv.slice(2), cwd: process.cwd(),
  });
  process.on('exit', code => record('node-exit', { code }));
  if (config.mode === 'transport') {
    // This explicit boundary fixture exits before executing application code.
    // Its receipt must remain separate from real Morphir acceptance evidence.
    const deadline = Date.now() + 15000;
    const wait = () => {
      if (Date.now() > deadline) throw new Error('Transport fixture timed out');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2);
    };
    const writeAll = (fd: number, bytes: Buffer) => {
      let offset = 0;
      while (offset < bytes.length) {
        try {
          const count = fs.writeSync(fd, bytes, offset, Math.min(8192, bytes.length - offset));
          if (count === 0) wait(); else offset += count;
        } catch (error) {
          if (retryable(error)) wait(); else throw error;
        }
      }
    };
    let total = 0;
    const buffer = Buffer.alloc(16384);
    for (;;) {
      let count;
      try { count = fs.readSync(0, buffer); }
      catch (error) {
        if (retryable(error)) { wait(); continue; }
        throw error;
      }
      if (count === 0) break;
      total += count;
      if (total > 2097152) throw new Error('Transport fixture input exceeded 2 MiB');
      writeAll(1, buffer.subarray(0, count));
    }
    const diagnostics = Buffer.from(Array.from({ length: 1792 }, (_, index) => 255 - index % 256));
    writeAll(2, diagnostics);
    record('transport-completed', { inputBytes: total, stderrBytes: diagnostics.length, childStatus: 23 });
    process.exit(23);
  } else if (config.mode === 'unresponsive') {
    // Deliberately withhold the application and its event loop. Registered Node
    // signal handlers prevent default termination but cannot make progress.
    for (const signal of process.platform === 'win32' ? ['SIGINT', 'SIGTERM', 'SIGBREAK'] : ['SIGINT', 'SIGTERM']) {
      process.on(signal, () => {});
    }
    record('unresponsive-ready');
    for (;;) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1000);
  } else {
    let observed = false;
    const ready = (fd: unknown) => {
      if (fd !== 0 || observed) return;
      observed = true;
      record('stdin-read-starting', {
        sigintListeners: process.listenerCount('SIGINT'),
        sigtermListeners: process.listenerCount('SIGTERM'),
        sigbreakListeners: process.listenerCount('SIGBREAK'),
      });
    };
    const read = fs.readSync;
    fs.readSync = function (this: unknown, ...args: unknown[]) { ready(args[0]); return Reflect.apply(read, this, args); };
    const readFile = fs.readFileSync;
    fs.readFileSync = function (this: unknown, ...args: unknown[]) { ready(args[0]); return Reflect.apply(readFile, this, args); };
    // The installed Morphir terminal owner reads asynchronously while its
    // worker waits on shared buffers. Observe the existing bounded request.
    // Accessing process.stdin eagerly can change fd 0 to nonblocking mode and
    // break a synchronous reader. Wrap only when the application opens it.
    const stdin = Object.getOwnPropertyDescriptor(process, 'stdin');
    const wrapped = new WeakSet();
    const observeStream = (stream: NodeJS.ReadStream) => {
      if (wrapped.has(stream)) return stream;
      wrapped.add(stream);
      const streamRead = stream.read;
      stream.read = function (this: unknown, ...args: unknown[]) {
        if (typeof args[0] === 'number' && args[0] > 0) ready(0);
        return Reflect.apply(streamRead, this, args);
      };
      return stream;
    };
    const getStdin = stdin?.get;
    if (typeof getStdin === 'function') {
      Object.defineProperty(process, 'stdin', { ...stdin, get() {
        return observeStream(Reflect.apply(getStdin, this, []));
      } });
    } else if (stdin?.value) observeStream(stdin.value);
    const emit = process.emit;
    process.emit = function (event: string | symbol, ...args: unknown[]) {
      if (typeof event === 'string' && ['SIGINT', 'SIGTERM', 'SIGQUIT', 'SIGBREAK'].includes(event)) {
        record('node-signal', { signal: event });
      }
      return Reflect.apply(emit, this, [event, ...args]);
    };
    require('node:module').syncBuiltinESMExports();
  }
}

function retryable(error: unknown): boolean {
  return error instanceof Error && 'code' in error &&
    (error.code === 'EAGAIN' || error.code === 'EWOULDBLOCK');
}
