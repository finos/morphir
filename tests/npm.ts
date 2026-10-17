import { existsSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

// Bun sets npm_execpath to Bun. These are explicitly npm compatibility tests,
// including on Windows where execFile cannot launch npm.cmd without a shell.
const directory = dirname(process.execPath);
const candidates = [process.env.npm_execpath,
  resolve(directory, '../lib/node_modules/npm/bin/npm-cli.js'),
  resolve(directory, 'node_modules/npm/bin/npm-cli.js'),
  resolve(directory, '../node_modules/npm/bin/npm-cli.js')];
const selected = candidates.find((path): path is string => !!path && path.endsWith('npm-cli.js') && existsSync(path));
if (!selected) throw new Error('The Node installation must include npm for installed-package compatibility tests');
export const npmCli = selected;
