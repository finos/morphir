#!/usr/bin/env node
/**
 * Converts YAML schema files to JSON format.
 * This ensures the JSON schemas stay in sync with the YAML source of truth.
 *
 * Usage: node scripts/yaml-to-json-schemas.js
 *
 * The script:
 * 1. Finds all .yaml schema files in static/schemas/
 * 2. Parses them and writes corresponding .json files
 * 3. Preserves the $id field but updates the extension to .json
 */

const fs = require('fs');
const path = require('path');

// Simple YAML parser for JSON Schema files
// We use a lightweight approach to avoid adding dependencies
// This handles the subset of YAML used in our schema files

function parseYaml(content) {
  // Use js-yaml if available, otherwise fall back to a simple parser
  try {
    const yaml = require('js-yaml');
    return yaml.load(content);
  } catch (e) {
    // js-yaml not available, try to parse manually
    throw new Error('js-yaml is required. Run: npm install js-yaml --save-dev');
  }
}

function convertSchemas() {
  const schemasDir = path.resolve(__dirname, '..', 'static', 'schemas');

  if (!fs.existsSync(schemasDir)) {
    console.error('Schemas directory not found:', schemasDir);
    process.exit(1);
  }

  const files = fs.readdirSync(schemasDir);
  const yamlFiles = files.filter(f => f.endsWith('.yaml') && f.startsWith('morphir-ir-'));

  if (yamlFiles.length === 0) {
    console.log('No morphir-ir-*.yaml files found in', schemasDir);
    return;
  }

  let converted = 0;
  let errors = 0;

  for (const yamlFile of yamlFiles) {
    const yamlPath = path.join(schemasDir, yamlFile);
    const jsonFile = yamlFile.replace('.yaml', '.json');
    const jsonPath = path.join(schemasDir, jsonFile);

    try {
      console.log(`Converting ${yamlFile} -> ${jsonFile}`);

      const yamlContent = fs.readFileSync(yamlPath, 'utf8');
      const schema = parseYaml(yamlContent);

      // Update $id to use .json extension if present
      if (schema.$id && schema.$id.endsWith('.yaml')) {
        schema.$id = schema.$id.replace('.yaml', '.json');
      }

      // Write JSON with 2-space indentation
      const jsonContent = JSON.stringify(schema, null, 2);
      fs.writeFileSync(jsonPath, jsonContent + '\n');

      converted++;
      console.log(`  ✓ Wrote ${jsonPath}`);
    } catch (err) {
      errors++;
      console.error(`  ✗ Error converting ${yamlFile}:`, err.message);
    }
  }

  console.log(`\nConverted ${converted} schema(s), ${errors} error(s)`);

  if (errors > 0) {
    process.exit(1);
  }
}

convertSchemas();
