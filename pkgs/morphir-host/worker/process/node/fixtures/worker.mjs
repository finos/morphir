// Fixture worker for the process launcher conformance suite. It speaks
// Content-Length framed JSON-RPC on stdin and stdout. The protocol is in
// pkgs/morphir-host/worker/process/conformance/README.md.
import { spawn } from 'node:child_process';
import { fstatSync, readdirSync, statSync } from 'node:fs';

const args = process.argv.slice(2);
const ignoresExit = args.includes('--ignore-exit');
const ignoresStdin = args.includes('--ignore-stdin');
const floodsOnExit = args.includes('--flood-on-exit');
// A worker that ignores exit also outlives the end of its stdin.
if (ignoresExit) setInterval(() => {}, 1000);
let grandchild = null;
if (args.includes('--grandchild')) {
  // The grandchild stays in the worker's process group and tree.
  grandchild = spawn(process.execPath, ['-e', 'setInterval(() => {}, 1000)'], {
    stdio: 'ignore',
    windowsHide: true,
  });
}

function send(message) {
  const body = Buffer.from(JSON.stringify(message), 'utf8');
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function reply(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function stop() {
  if (ignoresExit) return;
  // 1 MiB on stdout after the end of the input: more than a pipe holds.
  if (floodsOnExit) process.stdout.write(Buffer.alloc(1 << 20, 'x'), () => process.exit(0));
  else process.exit(0);
}

// The identity (`device:inode`) of an open descriptor, or null when it is closed.
function identity(fd) {
  try {
    const stat = fstatSync(fd, { bigint: true });
    return `${stat.dev}:${stat.ino}`;
  } catch {
    return null;
  }
}

// The open descriptors, from /dev/fd. Windows has no such list.
function descriptors() {
  if (process.platform === 'win32') return null;
  const listed = readdirSync('/dev/fd').map(Number).sort((a, b) => a - b);
  // The listing's own descriptor is closed by now and has no identity.
  return listed.map((fd) => ({ fd, id: identity(fd) })).filter((entry) => entry.id !== null);
}

function handle(message) {
  const { id, method, params } = message;
  if (id === undefined) {
    if (method === 'exit') stop();
    return;
  }
  switch (method) {
    case 'echo':
      return reply(id, params ?? null);
    case 'argv':
      return reply(id, { args });
    case 'env':
      return reply(id, { names: Object.keys(process.env).sort() });
    case 'cwd': {
      const entries = readdirSync(process.cwd()).length;
      if (process.platform === 'win32') return reply(id, { entries, mode: null, ownedByWorker: null });
      const stat = statSync(process.cwd());
      return reply(id, { entries, mode: stat.mode & 0o777, ownedByWorker: stat.uid === process.getuid() });
    }
    case 'fds':
      return reply(id, { descriptors: descriptors() });
    case 'console':
      console.log('x');
      return;
    case 'pids':
      return reply(id, { worker: process.pid, grandchild: grandchild?.pid ?? null });
    case 'hang':
      return;
    case 'stderr': {
      const size = params?.bytes ?? 0;
      const chunk = Buffer.alloc(65536, 'e');
      let left = size;
      const next = () => {
        while (left > 0) {
          const part = left >= chunk.length ? chunk : chunk.subarray(0, left);
          left -= part.length;
          if (!process.stderr.write(part)) return process.stderr.once('drain', next);
        }
        process.stderr.write('\nstderr end\n', () => reply(id, { written: size }));
      };
      return next();
    }
    case 'log':
      process.stdout.write('worker log line\r\n\r\n');
      return;
    case 'oversized':
      process.stdout.write('Content-Length: 16777217\r\n\r\n');
      return;
    case 'crash':
      process.exit(3);
      return;
    default:
      return send({ jsonrpc: '2.0', id, error: { code: -32601, message: `unknown method ${method}` } });
  }
}

let input = Buffer.alloc(0);
// A worker that ignores stdin never reads it, so the host's writes fill the pipe.
if (!ignoresStdin) process.stdin.on('data', (chunk) => {
  input = Buffer.concat([input, chunk]);
  for (;;) {
    const end = input.indexOf('\r\n\r\n');
    if (end < 0) return;
    const header = input.subarray(0, end).toString('utf8');
    const match = /^Content-Length: *(\d+)$/im.exec(header);
    if (!match) process.exit(2);
    const length = Number(match[1]);
    if (input.length < end + 4 + length) return;
    const body = input.subarray(end + 4, end + 4 + length).toString('utf8');
    input = input.subarray(end + 4 + length);
    handle(JSON.parse(body));
  }
});
if (!ignoresStdin) process.stdin.on('end', stop);
else setInterval(() => {}, 1000);
