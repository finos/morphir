/**
 * IR Checker constants - schema versions and sample data
 */

import type { SchemaVersion, SchemaVersionValue, ValidationModeInfo } from './types';

export const schemaVersions: SchemaVersion[] = [
  { value: 'v1', label: 'v1', file: 'morphir-ir-v1.json', status: 'Legacy' },
  { value: 'v2', label: 'v2', file: 'morphir-ir-v2.json', status: 'Legacy' },
  { value: 'v3', label: 'v3', file: 'morphir-ir-v3.json', status: 'Stable' },
  { value: 'v4', label: 'v4', file: 'morphir-ir-v4.json', status: 'Draft' },
];

export const validationModes: ValidationModeInfo[] = [
  { value: 'fast', label: 'Fast', description: 'Stop at first error (recommended)' },
  { value: 'thorough', label: 'Thorough', description: 'Find all errors (slower for large files)' },
];

// Inline minimal samples for each version (used for "Empty Library" option)
export const sampleJson: Record<SchemaVersionValue, string> = {
  v4: `{
  "formatVersion": 4,
  "distribution": {
    "Library": {
      "packageName": "my-org/my-package",
      "dependencies": {},
      "def": {
        "modules": {}
      }
    }
  }
}`,
  v3: `{
  "formatVersion": 3,
  "distribution": [
    "Library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
  v2: `{
  "formatVersion": 2,
  "distribution": [
    "Library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
  v1: `{
  "formatVersion": 1,
  "distribution": [
    "library",
    [[["my"], ["org"]], [["my"], ["package"]]],
    [],
    { "modules": [] }
  ]
}`,
};

// Additional example files are dynamically loaded from /ir/examples/<version>/index.json

// Morphir IR node types for special highlighting
export const morphirNodeTypes: readonly string[] = [
  'Library', 'Specs', 'Application', 'Reference', 'Variable', 'Literal',
  'Apply', 'Lambda', 'IfThenElse', 'PatternMatch', 'Constructor',
  'Tuple', 'List', 'Record', 'Field', 'Unit', 'Let', 'LetDefinition',
  'LetRecursion', 'Destructure', 'UpdateRecord'
];
