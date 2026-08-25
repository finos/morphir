#!/usr/bin/env node
/**
 * Fails when morphir-rust's embedded copy of the configuration schema
 * differs from the generated schema in this repository.
 *
 * The parent repository is the source of truth (static/schemas/*.yaml,
 * converted by yaml-to-json-schemas.js). morphir-rust embeds the JSON so the
 * loader can validate offline. This check runs in the parent's CI, where both
 * files exist thanks to the submodule.
 *
 * Usage: node scripts/check-config-schema-sync.js
 */

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const source = path.join(repoRoot, 'website', 'static', 'schemas', 'morphir-config-v1.json');
const copy = path.join(repoRoot, 'ecosystem', 'morphir-rust', 'crates', 'morphir-common', 'schemas', 'morphir-config-v1.json');

function read(file) {
  if (!fs.existsSync(file)) {
    console.error(`Missing: ${path.relative(repoRoot, file)}`);
    if (file === copy) {
      console.error('The embedded copy in morphir-rust has not been created yet.');
      console.error(`Create ${path.relative(repoRoot, copy)} by copying the generated`);
      console.error(`${path.relative(repoRoot, source)} over it, then bump the submodule.`);
    }
    process.exit(1);
  }
  return fs.readFileSync(file, 'utf8').replace(/\r\n/g, '\n');
}

const sourceText = read(source);
const copyText = read(copy);

if (sourceText !== copyText) {
  console.error('morphir-rust embeds an out-of-date morphir-config-v1.json.');
  console.error(`  source: ${path.relative(repoRoot, source)}`);
  console.error(`  copy:   ${path.relative(repoRoot, copy)}`);
  console.error('Copy the source over the embedded file in morphir-rust and bump the submodule.');
  process.exit(1);
}

console.log('morphir-config-v1.json is in sync with morphir-rust.');
