// Test-only process observation and bounded failure recovery.
import assert from 'node:assert/strict';
import {spawn, type ChildProcessWithoutNullStreams} from 'node:child_process';
import {existsSync,readFileSync,lstatSync} from 'node:fs';
import {basename,dirname,isAbsolute,relative,sep} from 'node:path';
export type Observation = { event: string; pid: number; entry?: string; entryCanonical?: string; arguments?: string[]; cwd?: string; signal?: string; code?: number; sigintListeners?: number; sigtermListeners?: number; sigbreakListeners?: number };
export type Exit = { code: number | null; signal: NodeJS.Signals | null; error?: Error };
export type Running = { child: ChildProcessWithoutNullStreams; stdout: Buffer[]; stderr: Buffer[]; closed: Promise<Exit>; deadline: Promise<Exit>; settled(): boolean; cancelWatchdog(): void; emergency(): void };
export const recoveryProblems: string[] = [];
export const sleep = (ms: number) => new Promise<void>(done => setTimeout(done, ms));
export function gone(pid: number): boolean {
  try { process.kill(pid, 0); return false; }
  catch (error) { if ((error as NodeJS.ErrnoException).code === 'ESRCH') return true; throw error; }
}
export function observations(path: string): Observation[] {
  if (!existsSync(path)) return [];
  const text = readFileSync(path, 'utf8');
  return text.slice(0, text.lastIndexOf('\n') + 1).split('\n').filter(Boolean).map(line => JSON.parse(line));
}
function inside(root: string, path: string): boolean {
  const part = relative(root, path);
  return part !== '' && part !== '..' && !part.startsWith(`..${sep}`) && !isAbsolute(part);
}
export function start(program: string, args: string[], cwd: string, env: NodeJS.ProcessEnv, events?: string, deadlineMilliseconds = 30000): Running {
  assert.ok(Number.isSafeInteger(deadlineMilliseconds) && deadlineMilliseconds > 0);
  const child = spawn(program, args, { cwd, env, stdio: ['pipe', 'pipe', 'pipe'] });
  const stdout: Buffer[] = [], stderr: Buffer[] = [];
  let failure: Error | undefined;
  let settled = false;
  const capture = (chunks: Buffer[]) => {
    let size = 0;
    return (bytes: Buffer) => {
      size += bytes.length;
      if (size > 16 * 1024 * 1024) { failure ??= new Error('Launcher output exceeded 16 MiB'); child.kill('SIGKILL'); }
      else chunks.push(bytes);
    };
  };
  child.stdout.on('data', capture(stdout)); child.stderr.on('data', capture(stderr));
  // Child startup/cancellation may close stdin while a caller still owns it.
  child.stdin.on('error', error => { if ((error as NodeJS.ErrnoException).code !== 'EPIPE') failure ??= error; });
  const closed = new Promise<Exit>(done => {
    child.once('error', error => { failure = error; });
    child.once('close', (code, signal) => { settled = true; done({ code, signal, error: failure }); });
  });
  const emergency = () => {
    try {
      const pids = events ? observations(events).filter(row => row.event === 'node-started').map(row => row.pid) : [];
      for (const line of Buffer.concat(stdout).toString().split('\n')) {
        if (/^CONSOLE_PID=\d+$/.test(line)) pids.push(Number(line.slice('CONSOLE_PID='.length)));
      }
      // Descendants inherit the pipes. Terminate them before waiting for close.
      for (const pid of pids) if (!gone(pid)) {
        try { process.kill(pid, 'SIGKILL'); } catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ESRCH') throw error; }
      }
    } catch (error) { recoveryProblems.push(`Known descendant cleanup failed: ${String(error)}`); }
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  };
  let expire!: (result: Exit) => void;
  const deadline = new Promise<Exit>(done => { expire = done; });
  const watchdog = setTimeout(() => {
    if (!settled) {
      failure ??= new Error(`Launcher qualification exceeded ${deadlineMilliseconds} milliseconds`);
      emergency();
      // Do not depend on descendant-owned pipes closing to report timeout.
      expire({ code: null, signal: null, error: failure });
    }
  }, deadlineMilliseconds);
  return { child, stdout, stderr, closed, deadline, settled: () => settled, emergency, cancelWatchdog: () => clearTimeout(watchdog) };
}
export async function finish(run: Running): Promise<Exit> {
  const result = await Promise.race([run.closed, run.deadline]);
  run.cancelWatchdog();
  if (result.error) throw result.error;
  return result;
}
export async function cleanup(run: Running) {
  run.cancelWatchdog();
  // Successful reaping/payload assertions happen before this emergency path.
  if (!run.settled()) run.emergency();
  const closed = await new Promise<boolean>(done => {
    const timer = setTimeout(() => done(false), 3000);
    run.closed.then(() => { clearTimeout(timer); done(true); });
  });
  if (!closed) {
    recoveryProblems.push('Process pipes did not close within the three-second recovery bound');
    run.child.stdin.destroy(); run.child.stdout.destroy(); run.child.stderr.destroy(); run.child.unref();
  }
  // Recovery failures stay separate so they cannot replace the original error.
}
export async function waitObservation(run: Running, events: string, event: string) {
  const deadline = Date.now() + 20000;
  for (;;) {
    const found = observations(events).find(row => row.event === event);
    if (found) return found;
    assert.ok(run.child.exitCode === null && run.child.signalCode === null, Buffer.concat(run.stderr).toString());
    assert.ok(Date.now() < deadline, `No ${event} readiness: ${Buffer.concat(run.stderr).toString()}`);
    await sleep(10);
  }
}
export async function waitControlLine(run: Running, prefix: string) {
  const deadline = Date.now() + 20000;
  for (;;) {
    const text = Buffer.concat(run.stdout).toString();
    const line = text.slice(0, text.lastIndexOf('\n') + 1).split('\n').find(value => value.startsWith(prefix));
    if (line) return line.slice(prefix.length);
    assert.ok(run.child.exitCode === null && run.child.signalCode === null, Buffer.concat(run.stderr).toString());
    assert.ok(Date.now() < deadline, `No ${prefix} control record`);
    await sleep(10);
  }
}
export function proveCleanup(events: string, temporary: string) {
  const child = observations(events).find(row => row.event === 'node-started');
  assert.ok(child?.entry);
  assert.equal(basename(child.entry), 'morphir.js');
  assert.ok(child.entryCanonical, 'Observe the existing physical payload path before cleanup');
  const payload = dirname(dirname(child.entryCanonical));
  assert.ok(inside(temporary, payload), 'The actual payload must belong to this invocation');
  let present = true;
  try { lstatSync(payload); } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') present = false; else throw error;
  }
  assert.equal(present, false, 'Launcher removed its payload before success');
  assert.ok(gone(child.pid), 'Actual Node child was reaped before success');
  return { nodePid: child.pid, payload, childReaped: true, payloadRemoved: true };
}
