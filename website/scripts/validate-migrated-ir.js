#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const Ajv = require('ajv');
const addFormats = require('ajv-formats');

const input = process.argv[2];
if (!input) {
  console.error('Usage: node scripts/validate-migrated-ir.js <morphir-ir-v4.json>');
  process.exit(2);
}

const websiteRoot = path.resolve(__dirname, '..');
const schema = JSON.parse(
  fs.readFileSync(path.join(websiteRoot, 'static', 'schemas', 'morphir-ir-v4.json'), 'utf8'),
);
const document = JSON.parse(fs.readFileSync(path.resolve(input), 'utf8'));
const ajv = new Ajv({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);

if (!validate(document)) {
  for (const error of validate.errors || []) {
    console.error(`${error.instancePath || '/'} ${error.message}`);
  }
  process.exit(1);
}

console.log(`${input} conforms to morphir-ir-v4.json`);
