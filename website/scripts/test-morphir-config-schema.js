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
];

// Cases validated against a single definition rather than the root schema.
const definitionCases = [
  ['secretValue', 'plain string', 'ghp_abc', true],
  ['secretValue', 'env reference', { env: 'GITHUB_TOKEN' }, true],
  ['secretValue', 'file reference', { file: '~/.config/morphir/token' }, true],
  ['secretValue', 'env and file together', { env: 'A', file: 'b' }, false],
  ['secretValue', 'env with extra key', { env: 'A', extra: true }, false],
  ['secretValue', 'non-string env', { env: 1 }, false],
  ['secretValue', 'empty object', {}, false],
  ['secretValue', 'number', 42, false],
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
