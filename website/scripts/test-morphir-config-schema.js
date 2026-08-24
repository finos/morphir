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

const schemaFiles = ['morphir-config-v1.yaml', 'morphir-config-v1.json'];
const failures = schemaFiles.flatMap(schemaFile => {
  const schemaPath = path.join(schemasDirectory, schemaFile);
  const schema = schemaFile.endsWith('.yaml')
    ? yaml.load(fs.readFileSync(schemaPath, 'utf8'))
    : JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
  const validate = new Ajv({ allErrors: true, strict: false }).compile(schema);

  return cases.flatMap(([name, value, expected]) => {
    const actual = validate(value);
    return actual === expected
      ? []
      : [`${schemaFile}, ${name}: expected ${expected}, received ${actual}\n${JSON.stringify(validate.errors, null, 2)}`];
  });
});

if (failures.length > 0) {
  console.error(failures.join('\n\n'));
  process.exit(1);
}

console.log(`Validated ${cases.length} task cases against ${schemaFiles.length} Morphir configuration schemas.`);
