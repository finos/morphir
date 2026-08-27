#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const Ajv = require('ajv');
const yaml = require('js-yaml');

const schemasDirectory = path.resolve(__dirname, '..', 'static', 'schemas');

const cases = [
  ['empty configuration', {}, true],
  ['intrinsic task with omitted kind', { tasks: { build: { action: 'morphir.pipeline.compile' } } }, true],
  ['explicit intrinsic task', { tasks: { build: { kind: 'intrinsic', action: 'morphir.pipeline.compile' } } }, true],
  ['command task', { tasks: { build: { kind: 'command', cmd: ['echo', 'hello'] } } }, true],
  ['task extension property', { tasks: { build: { action: 'compile', extension_setting: true } } }, true],
  ['unknown task kind', { tasks: { build: { kind: 'bogus' } } }, false],
  ['command with string cmd', { tasks: { build: { kind: 'command', cmd: 'echo hello' } } }, false],
  ['command kind omitted', { tasks: { build: { cmd: ['echo', 'hello'] } } }, false],
  ['intrinsic task with cmd', { tasks: { build: { kind: 'intrinsic', cmd: ['echo', 'hello'] } } }, false],
  ['command task with action', { tasks: { build: { kind: 'command', action: 'compile' } } }, false],
  ['task string shorthand', { tasks: { build: 'cargo build' } }, true],
  ['task with run and depends', { tasks: { build: { description: 'Build', run: 'cargo build', depends: ['fmt'], cwd: 'crates/x', env: { CI: 'true' } } } }, true],
  ['task depends alt spelling accepted alone', { tasks: { build: { kind: 'command', cmd: ['echo'], depends: ['fmt'] } } }, true],
  ['task depends and depends_on together', { tasks: { build: { kind: 'command', cmd: ['echo'], depends: ['fmt'], depends_on: ['lint'] } } }, false],
  ['task run alone implies command shorthand', { tasks: { build: { run: 'cargo build' } } }, true],
  ['task run and cmd together', { tasks: { build: { kind: 'command', cmd: ['echo'], run: 'echo hi' } } }, false],
  ['task run and action together', { tasks: { build: { kind: 'intrinsic', action: 'x', run: 'echo hi' } } }, false],
  ['task action alone without run', { tasks: { build: { kind: 'intrinsic', action: 'compile' } } }, true],
  ['frontend section', { frontend: { language: 'elm', emit_parse_stage: true, emit_parse_stage_fatal: false } }, true],
  ['frontend with wrong type', { frontend: { emit_parse_stage: 'yes' } }, false],
  ['project extras', { project: { name: 'acme/orders', description: 'Orders', authors: ['Alice'], license: 'Apache-2.0', repository: 'https://example.com/r', output_directory: '.morphir/out' } }, true],
  ['ir mode and morphir extras', { ir: { mode: 'vfs' }, morphir: { min_cli_version: '0.2.0', dev_mode: true } }, true],
  ['ir mode wrong type', { ir: { mode: 4 } }, false],
  ['dependencies string and detailed', { dependencies: { 'finos/morphir-sdk': '1.0.0', local: { path: '../local', workspace: true } }, 'dev-dependencies': { git: { git: 'https://example.com/r.git', tag: 'v1' } } }, true],
  ['dependency detailed with wrong path type', { dependencies: { local: { path: 3 } } }, false],
  ['extensions and sources', { extensions: { gleam: { path: 'ext/gleam.wasm', enabled: true, args: ['--x'], config: { a: 1 } } }, sources: { enabled: true, allow: ['https://github.com/*'], cache: { maxSizeMb: 100 } } }, true],
  ['project.authors wrong element type', { project: { authors: [123] } }, false],
  ['extensions enabled wrong type', { extensions: { gleam: { enabled: 'yes' } } }, false],
  ['morphir.dev_mode wrong type', { morphir: { dev_mode: 'yes' } }, false],
];

// Cases validated against a single definition rather than the root schema.
const definitionCases = [
  ['secretValue', 'plain string', 'ghp_abc', true],
  ['secretValue', 'env reference', { env: 'GITHUB_TOKEN' }, true],
  ['secretValue', 'file reference', { file: '~/.config/morphir/token' }, true],
  ['secretValue', 'command reference', { command: ['gh', 'auth', 'token'] }, true],
  ['secretValue', 'keyring reference', { keyring: { service: 'github.com', account: 'damre' } }, true],
  ['secretValue', 'empty command', { command: [] }, false],
  ['secretValue', 'command with non-string argument', { command: ['gh', 1] }, false],
  ['secretValue', 'keyring without service', { keyring: { account: 'damre' } }, false],
  ['secretValue', 'keyring without account', { keyring: { service: 'github.com' } }, false],
  ['secretValue', 'keyring with empty service', { keyring: { service: '', account: 'damre' } }, false],
  ['secretValue', 'keyring with extra key', { keyring: { service: 'github.com', account: 'damre', extra: true } }, false],
  ['secretValue', 'command mixed with env', { command: ['gh'], env: 'TOKEN' }, false],
  ['secretValue', 'empty env', { env: '' }, false],
  ['secretValue', 'empty file', { file: '' }, false],
  ['secretValue', 'env and file together', { env: 'A', file: 'b' }, false],
  ['secretValue', 'env with extra key', { env: 'A', extra: true }, false],
  ['secretValue', 'non-string env', { env: 1 }, false],
  ['secretValue', 'empty object', {}, false],
  ['secretValue', 'number', 42, false],
  ['secretValue', 'file with extra key', { file: 'p', extra: true }, false],
  ['secretValue', 'non-string file', { file: 1 }, false],
];

const schemaFiles = ['morphir-config-v1.yaml', 'morphir-config-v1.json'];

function loadSchema(schemaFile) {
  const schemaPath = path.join(schemasDirectory, schemaFile);
  return schemaFile.endsWith('.yaml')
    ? yaml.load(fs.readFileSync(schemaPath, 'utf8'))
    : JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
}

function definitionSchema(schema, name) {
  return { $schema: schema.$schema, definitions: schema.definitions, $ref: `#/definitions/${name}` };
}

const failures = schemaFiles.flatMap(schemaFile => {
  const schema = loadSchema(schemaFile);
  const ajv = new Ajv({ allErrors: true, strict: false });
  const validate = ajv.compile(schema);

  const rootFailures = cases.flatMap(([name, value, expected]) => {
    const actual = validate(value);
    return actual === expected
      ? []
      : [`${schemaFile}, ${name}: expected ${expected}, received ${actual}\n${JSON.stringify(validate.errors, null, 2)}`];
  });

  const definitionFailures = definitionCases.flatMap(([definition, name, value, expected]) => {
    const validateDefinition = new Ajv({ allErrors: true, strict: false }).compile(definitionSchema(schema, definition));
    const actual = validateDefinition(value);
    return actual === expected
      ? []
      : [`${schemaFile}, ${definition} ${name}: expected ${expected}, received ${actual}\n${JSON.stringify(validateDefinition.errors, null, 2)}`];
  });

  return [...rootFailures, ...definitionFailures];
});

if (failures.length > 0) {
  console.error(failures.join('\n\n'));
  process.exit(1);
}

console.log(`Validated ${cases.length} root cases and ${definitionCases.length} definition cases against ${schemaFiles.length} Morphir configuration schemas.`);
