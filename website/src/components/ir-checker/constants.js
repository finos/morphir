/**
 * IR Checker constants - schema versions and sample data
 */

export const schemaVersions = [
  { value: 'v1', label: 'v1', file: 'morphir-ir-v1.json', status: 'Legacy' },
  { value: 'v2', label: 'v2', file: 'morphir-ir-v2.json', status: 'Legacy' },
  { value: 'v3', label: 'v3', file: 'morphir-ir-v3.json', status: 'Stable' },
  { value: 'v4', label: 'v4', file: 'morphir-ir-v4.json', status: 'Draft' },
];

export const sampleJson = {
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

// Morphir IR node types for special highlighting
export const morphirNodeTypes = [
  'Library', 'Specs', 'Application', 'Reference', 'Variable', 'Literal',
  'Apply', 'Lambda', 'IfThenElse', 'PatternMatch', 'Constructor',
  'Tuple', 'List', 'Record', 'Field', 'Unit', 'Let', 'LetDefinition',
  'LetRecursion', 'Destructure', 'UpdateRecord'
];
