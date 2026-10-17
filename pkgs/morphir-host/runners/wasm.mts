#!/usr/bin/env node
import { workbenchError } from '../../../types/data.ts';
import * as fs from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';

// Explicit runner for the CLI's WASI and WASM-GC artifacts.
const [artifact, ...args] = process.argv.slice(2);
if (!artifact) throw new Error('Usage: node wasm.mjs <artifact.wasm> [arguments]');
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
      case 'kind': {
        try { const s = fs.lstatSync(a); return s.isSymbolicLink() ? 3 : s.isDirectory() ? 2 : s.isFile() ? 1 : 4; }
        catch(cause) {const e=workbenchError(cause); if (e.code === 'ENOENT' || e.code === 'ENOTDIR') return 0; throw e; }
      }
      case 'mkdir': return fs.mkdirSync(a);
      case 'remove_file': return fs.unlinkSync(a);
      case 'remove_dir': return fs.rmdirSync(a);
      case 'rename': return fs.renameSync(a, b);
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
    spectest: { print_char: (c: number) => process.stdout.write(String.fromCharCode(c)) },
    // MoonBit core (argparse) declares a WASM-GC exit import; the CLI never calls it.
    __moonbit_sys_unstable: { exit: (code: number) => process.exit(code) },
  });
  const start = instance.exports._start;
  if (typeof start !== 'function') throw new Error('Missing WASM entry');
  start();
}
