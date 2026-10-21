#!/usr/bin/env node
import { workbenchError } from '../../../types/data.ts';
import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { terminalStdinRead, terminalWorker } from './terminal-worker.mts';

// Explicit runner for the CLI's WASI and WASM-GC artifacts.
if (!terminalWorker(new URL(import.meta.url), process.argv.slice(3))) {
const interrupted = (globalThis as typeof globalThis & { __morphirInterrupt?: Int32Array }).__morphirInterrupt;
const [artifact, ...args] = process.argv.slice(2);
if (!artifact) throw new Error('Usage: node wasm.mjs <artifact.wasm> [arguments]');
// MoonBit prints UTF-16 code units. Keep an astral pair in one UTF-8 write;
// writing each surrogate separately would replace both halves with U+FFFD.
let pendingHigh: number | undefined;
const printChar = (code: number) => {
  if (pendingHigh !== undefined) {
    const high = pendingHigh;
    pendingHigh = undefined;
    if (code >= 0xdc00 && code <= 0xdfff) {
      process.stdout.write(String.fromCharCode(high, code));
      return;
    }
    process.stdout.write(String.fromCharCode(high));
  }
  if (code >= 0xd800 && code <= 0xdbff) pendingHigh = code;
  else process.stdout.write(String.fromCodePoint(code));
};
const module = await WebAssembly.compile(fs.readFileSync(artifact));
const imports = WebAssembly.Module.imports(module);
if (!imports.some(i => i.module === 'morphir_host_v1')) {
  const { WASI } = await import("node:wasi");
  const wasi = new WASI({version: 'preview1', args: ['morphir', ...args], env: process.env,
    preopens: {'.': process.cwd()}, returnOnExit: true});
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject() as WebAssembly.Imports);
  process.exitCode = wasi.start(instance);
} else {
  const dispatch = (op: string, a: string, b: string) => {
    switch (op) {
      case 'bytes_supported': return true;
      case 'interruption_supported': return !!interrupted;
      case 'interruption_requested': return !!interrupted && Atomics.load(interrupted, 0) !== 0;
      case 'monotonic_seconds': return Number(process.hrtime.bigint()) / 1e9;
      case 'read_input': {
        const limit = Number(b);
        if (!Number.isInteger(limit) || limit < 1 || limit > 16777216) throw new Error('input.invalid_limit');
        let fd = 0;
        if (a !== '-') {
          if (!fs.lstatSync(a).isFile()) throw new Error('input.regular_file_required');
          fd = fs.openSync(a, fs.constants.O_RDONLY | (fs.constants.O_NONBLOCK || 0) | (fs.constants.O_NOFOLLOW || 0));
        }
        try {
          if (a !== '-' && (!fs.fstatSync(fd).isFile() || fs.fstatSync(fd).size > limit)) throw new Error('input.limit');
          const chunks: Buffer[] = [];
          let total = 0;
          for (;;) {
            if (interrupted && Atomics.load(interrupted, 0) !== 0) throw new Error('Cancelled');
            const buffer = Buffer.alloc(Math.min(65536, limit - total + 1));
            const count = a === '-'
              ? terminalStdinRead(buffer, buffer.length) ?? fs.readSync(fd, buffer, 0, buffer.length, null)
              : fs.readSync(fd, buffer, 0, buffer.length, null);
            if (count < 0) throw new Error(interrupted && Atomics.load(interrupted, 0) ? 'Cancelled' : 'input.read_failed');
            if (!count) break;
            total += count;
            if (total > limit) throw new Error('input.limit');
            chunks.push(buffer.subarray(0, count));
          }
          return Array.from(Buffer.concat(chunks, total));
        } finally { if (a !== '-') fs.closeSync(fd); }
      }
      case 'args': return ['morphir', ...args];
      case 'environment': return process.env;
      case 'system_type': return process.platform === 'darwin' ? 'macos' : process.platform === 'win32' ? 'windows' : 'linux';
      case 'cwd': return process.cwd();
      case 'architecture': return process.arch;
      case 'process_supported': return true;
      case 'temporary': return fs.mkdtempSync(tmpdir() + '/morphir-toolchain-');
      case 'process': {
        const request = JSON.parse(a);
        const env = {...process.env};
        if (request.home) {
          env.MOON_HOME = request.home;
          env.PATH = request.home + '/bin' + (process.platform === 'win32' ? ';' : ':') + (env.PATH || '');
        }
        const result = spawnSync(request.program, request.args, {cwd: request.cwd, env,
          encoding:'utf8', timeout: request.timeout, maxBuffer:16777216, windowsHide:true});
        return {exitCode:result.error ? (workbenchError(result.error).code === 'ETIMEDOUT' ? 124 : -1) : (result.status ?? -1),
          stdout:result.stdout || '', stderr:(result.stderr || '') + (result.error ? result.error.message : '')};
      }
      case 'read': { if (fs.statSync(a).size > 16777216) throw new Error('File exceeds 16 MiB'); return new TextDecoder('utf-8', {fatal:true}).decode(fs.readFileSync(a)); }
      case 'write': return fs.writeFileSync(a, b);
      case 'read_bytes': { if (fs.statSync(a).size > 16777216) throw new Error('File exceeds 16 MiB'); return Array.from(fs.readFileSync(a)); }
      case 'write_bytes': { const bytes = JSON.parse(b); if (!Array.isArray(bytes) || bytes.some(n => !Number.isInteger(n) || n < 0 || n > 255)) throw new Error('Invalid host bytes'); return fs.writeFileSync(a, Buffer.from(bytes)); }
      case 'list': return fs.readdirSync(a);
      case 'list_bounded': {
        const limit = Number(b);
        if (!Number.isInteger(limit) || limit < 0 || limit > 65536 || a.includes('\0')) throw new Error('directory.invalid_request');
        if (!fs.lstatSync(a).isDirectory()) throw new Error('directory.open_failed');
        // Node returns Buffer names for 'buffer'; @types/node's Dir currently
        // declares only decoded names. Keep that raw host binding explicit.
        const openBytes = fs.opendirSync as unknown as (path: string, options: {encoding: 'buffer'; bufferSize: number}) => {
          readSync(): {name: Uint8Array} | null;
          closeSync(): void;
        };
        const directory = openBytes(a, {encoding: 'buffer', bufferSize: 1});
        const names: string[] = [];
        let units = 0;
        try {
          for (;;) {
            if (interrupted && Atomics.load(interrupted, 0)) throw new Error('Cancelled');
            const entry = directory.readSync();
            if (!entry) break;
            if (names.length >= limit) throw new Error('directory.entry_limit');
            const name = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(entry.name);
            if (name.length > 4096 || name.length > 1048576 - units) throw new Error('directory.name_limit');
            units += name.length;
            names.push(name);
          }
        } finally { directory.closeSync(); }
        return names;
      }
      case 'kind': {
        try { const s = fs.lstatSync(a); return s.isSymbolicLink() ? 3 : s.isDirectory() ? 2 : s.isFile() ? 1 : 4; }
        catch(cause) {const e=workbenchError(cause); if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return 0; throw e; }
      }
      case 'mkdir': return fs.mkdirSync(a);
      case 'remove_file': return fs.unlinkSync(a);
      case 'remove_dir': return fs.rmdirSync(a);
      case 'rename': return fs.renameSync(a, b);
      case 'link_file_new': return fs.linkSync(a, b);
      case 'stderr': return void process.stderr.write(a);
      case 'exit': return void (process.exitCode = Number(a));
      default: throw new Error(`Unsupported host operation: ${op}`);
    }
  };
  const instance = await WebAssembly.instantiate(module, {
    morphir_host_v1: {
      begin: () => ({text: ''}), append: (s: {text: string}, c: number) => { s.text += String.fromCharCode(c); },
      length: (s: {text: string}) => s.text.length, at: (s: {text: string}, i: number) => s.text.charCodeAt(i),
      request: (op: {text: string}, a: {text: string}, b: {text: string}) => {
        try { return {text: JSON.stringify({value: dispatch(op.text, a.text, b.text) ?? null})}; }
        catch(cause) {const e=workbenchError(cause); return {text: JSON.stringify({error: e.message})}; }
      },
    },
    spectest: { print_char: printChar },
    // MoonBit core (argparse) declares a WASM-GC exit import; the CLI never calls it.
    __moonbit_sys_unstable: { exit: (code: number) => process.exit(code) },
  });
  const start = instance.exports._start;
  if (typeof start !== 'function') throw new Error('Missing WASM entry');
  start();
}

}
