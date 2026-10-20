#!/usr/bin/env node

import { fileURLToPath } from 'node:url';
import { terminalWorker } from '../../../pkgs/morphir-host/runners/terminal-worker.mts';

process.env.MORPHIR_CONNECTED_HELPER ??= fileURLToPath(new URL('../build-provider/connected.mjs', import.meta.url));
process.env.MORPHIR_TRANSFER_HELPER ??= fileURLToPath(new URL('../build-provider/transfers.mjs', import.meta.url));
process.env.MORPHIR_ORIGINALS_HELPER ??= fileURLToPath(new URL('../build-provider/originals.mjs', import.meta.url));

if (!terminalWorker(new URL(import.meta.url), process.argv.slice(2))) {
  await import('../dist/morphir.js');
}
