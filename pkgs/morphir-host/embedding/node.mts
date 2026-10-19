import type { EventEmitter } from "node:events";
import type { Compiler, Options } from "./api.mjs";
import {Worker} from "node:worker_threads";
import {createRequire} from "node:module";
import {createEmbeddedToolchain, createWorkerToolchain} from "./index.mjs";
export {createDirectoryArtifactStore, readDirectoryArtifact} from './node-artifacts.mjs';
export {loadNodeMepAdapter} from './node-mep-adapter.mjs';
export {runMepExtension} from './node-mep-stdio.mjs';

const require = createRequire(import.meta.url);
export function createCompiler(): Compiler {
  // The upstream compiler retains diagnostics globally. Each build needs isolation.
  const path = require.resolve("@moonbit/moonc-worker");
  delete require.cache[path];
  const events: EventEmitter = process;
  const listeners = new Map(events.eventNames().map(event => [event, new Set(events.listeners(event))]));
  try { return require(path); }
  finally {
    // Compiler initialization installs process-level exception handlers. Embedding
    // must preserve the application's handlers and avoid retaining old compilers.
    for (const event of events.eventNames()) {
      for (const listener of events.listeners(event)) {
        if (!listeners.get(event)?.has(listener)) events.removeListener(event, listener as (...args: unknown[]) => void);
      }
    }
  }
}

export function createInProcessToolchain(options?: Options) {
  return createEmbeddedToolchain(createCompiler, options);
}

export function createNodeToolchain() {
  return createWorkerToolchain(new Worker(new URL("./node-worker.mjs", import.meta.url),
    {execArgv: []}));
}
