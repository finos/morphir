#!/usr/bin/env node
/**
 * Fails when morphir-rust's embedded copy of the configuration schema
 * differs from the generated schema in this repository.
 *
 * The parent repository is the source of truth (static/schemas/*.yaml,
 * converted by yaml-to-json-schemas.js). morphir-rust embeds the JSON so the
 * loader can validate offline. The comparison is byte for byte after
 * normalising line endings, so the copy must be the formatted output of
 * `mise run website:build-schemas`, not merely an equivalent schema.
 *
 * `mise run check:config-schema-sync` runs this, `mise run check` depends on
 * that task, and the docs job in .github/workflows/ci.yml runs it as its own
 * step (CI initializes the submodule through `mise run init -- --ci`).
 *
 * When the morphir-rust submodule is not checked out, the check is reported
 * and skipped, the way tools/check-vendored-fixture.ts skips its copy.
 *
 * Usage (from the repository root): node website/scripts/check-config-schema-sync.js
 */

const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..', '..');
const submodule = path.join(repoRoot, 'ecosystem', 'morphir-rust');
const source = path.join(repoRoot, 'website', 'static', 'schemas', 'morphir-config-v1.json');
const copy = path.join(submodule, 'crates', 'morphir-common', 'schemas', 'morphir-config-v1.json');

if (!fs.existsSync(path.join(submodule, 'Cargo.toml'))) {
  console.log(`${path.relative(repoRoot, submodule)} is not checked out; skipping the configuration schema sync check`);
  process.exit(0);
}

function read(file) {
  if (!fs.existsSync(file)) {
    console.error(`Missing: ${path.relative(repoRoot, file)}`);
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
  console.error('Change the YAML source here, run `mise run website:build-schemas`, copy the');
  console.error('generated JSON over the embedded file in morphir-rust, and bump the submodule.');
  process.exit(1);
}

console.log('morphir-config-v1.json is in sync with morphir-rust.');
