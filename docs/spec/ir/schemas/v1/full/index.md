---
title: "Full Schema"
linkTitle: "Full Schema"
weight: 20
description: "Complete Morphir IR JSON Schema for format version 1"
---

# Morphir IR Schema Version 1 - Complete Schema

This page contains the complete JSON schema definition for Morphir IR format version 1.

## Download

You can download the schema file directly:
- YAML: [morphir-ir-v1.yaml](/schemas/morphir-ir-v1.yaml)
- JSON: [morphir-ir-v1.json](/schemas/morphir-ir-v1.json)

## Interactive Viewer

For an interactive browsing experience, see the [Interactive Schema Viewer](./schema-viewer/).

## Usage

This schema can be used to validate Morphir IR JSON files in format version 1:

```bash
# Using Python jsonschema (recommended for YAML schemas)
pip install jsonschema pyyaml requests
python -c "import json, yaml, jsonschema, requests; \
  schema = yaml.safe_load(requests.get('https://morphir.finos.org/schemas/morphir-ir-v1.yaml').text); \
  data = json.load(open('your-morphir-ir.json')); \
  jsonschema.validate(data, schema); \
  print('✓ Valid Morphir IR v1')"
```

## References

- [Schema Version 1 Documentation](../)
- [Morphir IR Specification](../../../morphir-ir-specification/)

---

## Appendix: Complete Schema Definition

```yaml {linenos=true}
# JSON Schema for Morphir IR Format Version 1
# This schema defines the structure of a Morphir IR distribution in version 1 format.
# Format version 1 uses lowercase tag names and different structure for modules.

$schema: "http://json-schema.org/draft-07/schema#"
$id: "https://morphir.finos.org/schemas/morphir-ir-v1.yaml"
title: "Morphir IR Distribution (Version 1)"
description: |
  A Morphir IR distribution represents a complete, self-contained package of business logic
  with all its dependencies. It captures the semantics of functional programs in a
  language-independent, platform-agnostic format.
  
  This is format version 1, which uses lowercase tags and a different module structure.

type: object
required:
  - formatVersion
  - distribution
properties:
  formatVersion:
    type: integer
    const: 1
    description: "The version of the IR format. Must be 1 for this schema."
  
  distribution:
    description: "The distribution data, currently only Library distributions are supported."
    type: array
    minItems: 4
    maxItems: 4
    items:
      - type: string
        const: "library"
        description: "Distribution type (lowercase in v1)."
      - $ref: "#/definitions/PackageName"
      - $ref: "#/definitions/Dependencies"
      - $ref: "#/definitions/PackageDefinition"

definitions:
  # ===== Basic Building Blocks =====
  
  Name:
    type: array
    items:
      type: string
      pattern: "^[a-z][a-z0-9]*$"
    minItems: 1
    description: |
      A Name is a list of lowercase words that represents a human-readable identifier.
      Example: ["value", "in", "u", "s", "d"] can be rendered as valueInUSD or value_in_USD.
  
  Path:
    type: array
    items:
      $ref: "#/definitions/Name"
    minItems: 1
    description: |
      A Path is a list of Names representing a hierarchical location in the IR structure.
      Used for package names and module names.
  
  PackageName:
    $ref: "#/definitions/Path"
    description: "Globally unique identifier for a package."
  
  ModuleName:
    $ref: "#/definitions/Path"
    description: "Unique identifier for a module within a package."
  
  FQName:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - $ref: "#/definitions/PackageName"
      - $ref: "#/definitions/ModuleName"
      - $ref: "#/definitions/Name"
    description: |
      Fully-Qualified Name that provides a globally unique identifier for any type or value.
      Consists of [packagePath, modulePath, localName].
  
  # ===== Attributes =====
  
  Attributes:
    type: object
    description: |
      Attributes can be attached to various nodes in the IR for extensibility.
      When no additional information is needed, an empty object {} is used.
  
  # ===== Access Control (V1 format) =====
  
  AccessLevel:
    type: string
    enum: ["public", "private"]
    description: "Controls visibility of types and values (lowercase in v1)."
  
  # Note: Documented is not a separate schema definition because it's encoded conditionally.
  # When documentation exists, the JSON has both "doc" and "value" fields.
  # When documentation is absent, the JSON contains only the documented element directly (no wrapper).
  # This is handled inline in the definitions that use Documented.
  
  # ===== Distribution Structure =====
  
  Dependencies:
    type: array
    items:
      type: array
      minItems: 2
      maxItems: 2
      items:
        - $ref: "#/definitions/PackageName"
        - $ref: "#/definitions/PackageSpecification"
    description: "Dictionary of package dependencies, contains only type signatures."
  
  PackageDefinition:
    type: object
    required: ["modules"]
    properties:
      modules:
        type: array
        items:
          $ref: "#/definitions/ModuleEntry"
        description: "All modules in the package (public and private)."
    description: "Complete implementation of a package with all details."
  
  ModuleEntry:
    type: object
    required: ["name", "def"]
    properties:
      name:
        $ref: "#/definitions/ModuleName"
        description: "The module name/path."
      def:
        type: array
        minItems: 2
        maxItems: 2
        items:
          - $ref: "#/definitions/AccessLevel"
          - $ref: "#/definitions/ModuleDefinition"
        description: "Access-controlled module definition [accessLevel, definition]."
    description: "Module entry with name and access-controlled definition (v1 format)."
  
  PackageSpecification:
    type: object
    required: ["modules"]
    properties:
      modules:
        type: array
        items:
          type: object
          required: ["name", "spec"]
          properties:
            name:
              $ref: "#/definitions/ModuleName"
              description: "The module name/path."
            spec:
              $ref: "#/definitions/ModuleSpecification"
              description: "The module specification."
        description: "Public modules only."
    description: "Public interface of a package, contains only type signatures."
  
  # ===== Module Structure =====
  
  ModuleDefinition:
    type: object
    required: ["types", "values"]
    properties:
      types:
        type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - type: array
              minItems: 2
              maxItems: 2
              items:
                - $ref: "#/definitions/AccessLevel"
                - oneOf:
                    - type: object
                      required: ["doc", "value"]
                      properties:
                        doc:
                          type: string
                        value:
                          $ref: "#/definitions/TypeDefinition"
                    - $ref: "#/definitions/TypeDefinition"
        description: "All type definitions (public and private)."
      values:
        type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - type: array
              minItems: 2
              maxItems: 2
              items:
                - $ref: "#/definitions/AccessLevel"
                - oneOf:
                    - type: object
                      required: ["doc", "value"]
                      properties:
                        doc:
                          type: string
                        value:
                          $ref: "#/definitions/ValueDefinition"
                    - $ref: "#/definitions/ValueDefinition"
        description: "All value definitions (public and private)."
      doc:
        type: string
        description: "Optional documentation for the module."
    description: "Complete implementation of a module."
  
  ModuleSpecification:
    type: object
    required: ["types", "values"]
    properties:
      types:
        type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - oneOf:
                - type: object
                  required: ["doc", "value"]
                  properties:
                    doc:
                      type: string
                    value:
                      $ref: "#/definitions/TypeSpecification"
                - $ref: "#/definitions/TypeSpecification"
        description: "Public type specifications only."
      values:
        type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - oneOf:
                - type: object
                  required: ["doc", "value"]
                  properties:
                    doc:
                      type: string
                    value:
                      $ref: "#/definitions/ValueSpecification"
                - $ref: "#/definitions/ValueSpecification"
        description: "Public value specifications only."
      doc:
        type: string
        description: "Optional documentation for the module."
    description: "Public interface of a module."
  
  # ===== Type System =====
  # All type tags are lowercase in v1
  
  Type:
    description: |
      A Type is a recursive tree structure representing type expressions.
      Tags are lowercase in format version 1.
    oneOf:
      - $ref: "#/definitions/VariableType"
      - $ref: "#/definitions/ReferenceType"
      - $ref: "#/definitions/TupleType"
      - $ref: "#/definitions/RecordType"
      - $ref: "#/definitions/ExtensibleRecordType"
      - $ref: "#/definitions/FunctionType"
      - $ref: "#/definitions/UnitType"
  
  VariableType:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "variable"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Name"
    description: "Represents a type variable (generic parameter)."
  
  ReferenceType:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "reference"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/FQName"
      - type: array
        items:
          $ref: "#/definitions/Type"
        description: "Type arguments for generic types."
    description: "Reference to another type or type alias."
  
  TupleType:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "tuple"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          $ref: "#/definitions/Type"
        description: "Element types in order."
    description: "A composition of multiple types in a fixed order (product type)."
  
  RecordType:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "record"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          $ref: "#/definitions/Field"
        description: "List of field definitions."
    description: "A composition of named fields with their types."
  
  ExtensibleRecordType:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "extensible_record"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Name"
      - type: array
        items:
          $ref: "#/definitions/Field"
        description: "Known fields."
    description: "A record type that can be extended with additional fields."
  
  FunctionType:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "function"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Type"
      - $ref: "#/definitions/Type"
    description: |
      Represents a function type. Multi-argument functions are represented via currying.
      Items: [tag, attributes, argumentType, returnType]
  
  UnitType:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "unit"
      - $ref: "#/definitions/Attributes"
    description: "The type with exactly one value (similar to void in some languages)."
  
  Field:
    type: object
    required: ["name", "tpe"]
    properties:
      name:
        $ref: "#/definitions/Name"
        description: "Field name."
      tpe:
        $ref: "#/definitions/Type"
        description: "Field type."
    description: "A field in a record type."
  
  # ===== Type Specifications =====
  # All type specification tags are lowercase with underscores in v1
  
  TypeSpecification:
    description: "Defines the interface of a type without implementation details."
    oneOf:
      - $ref: "#/definitions/TypeAliasSpecification"
      - $ref: "#/definitions/OpaqueTypeSpecification"
      - $ref: "#/definitions/CustomTypeSpecification"
      - $ref: "#/definitions/DerivedTypeSpecification"
  
  TypeAliasSpecification:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "type_alias_specification"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
      - $ref: "#/definitions/Type"
    description: "An alias for another type."
  
  OpaqueTypeSpecification:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "opaque_type_specification"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
    description: |
      A type with unknown structure. The implementation is hidden from consumers.
  
  CustomTypeSpecification:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "custom_type_specification"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
      - $ref: "#/definitions/Constructors"
    description: "A tagged union type (sum type)."
  
  DerivedTypeSpecification:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "derived_type_specification"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
      - type: object
        required: ["baseType", "fromBaseType", "toBaseType"]
        properties:
          baseType:
            $ref: "#/definitions/Type"
            description: "The type used for serialization."
          fromBaseType:
            $ref: "#/definitions/FQName"
            description: "Function to convert from base type."
          toBaseType:
            $ref: "#/definitions/FQName"
            description: "Function to convert to base type."
        description: "Details for derived type."
    description: |
      A type with platform-specific representation but known serialization.
  
  # ===== Type Definitions =====
  # All type definition tags are lowercase with underscores in v1
  
  TypeDefinition:
    description: "Provides the complete implementation of a type."
    oneOf:
      - $ref: "#/definitions/TypeAliasDefinition"
      - $ref: "#/definitions/CustomTypeDefinition"
  
  TypeAliasDefinition:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "type_alias_definition"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
      - $ref: "#/definitions/Type"
    description: "Complete definition of a type alias."
  
  CustomTypeDefinition:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "custom_type_definition"
      - type: array
        items:
          $ref: "#/definitions/Name"
        description: "Type parameters."
      - type: array
        minItems: 2
        maxItems: 2
        items:
          - $ref: "#/definitions/AccessLevel"
          - $ref: "#/definitions/Constructors"
    description: |
      Complete definition of a custom type. If constructors are private, 
      the specification becomes opaque_type_specification.
  
  Constructors:
    type: array
    items:
      type: array
      minItems: 2
      maxItems: 2
      items:
        - $ref: "#/definitions/Name"
        - type: array
          items:
            type: array
            minItems: 2
            maxItems: 2
            items:
              - $ref: "#/definitions/Name"
              - $ref: "#/definitions/Type"
          description: "Constructor arguments as (name, type) pairs."
    description: "Dictionary of constructor names to their typed arguments."
  
  # ===== Value System =====
  # Value expressions use lowercase tags with underscores in v1
  
  Value:
    description: |
      A Value is a recursive tree structure representing computations.
      All data and logic in Morphir are represented as value expressions.
      Note: Value tags are lowercase with underscores in format version 1.
    oneOf:
      - $ref: "#/definitions/LiteralValue"
      - $ref: "#/definitions/ConstructorValue"
      - $ref: "#/definitions/TupleValue"
      - $ref: "#/definitions/ListValue"
      - $ref: "#/definitions/RecordValue"
      - $ref: "#/definitions/VariableValue"
      - $ref: "#/definitions/ReferenceValue"
      - $ref: "#/definitions/FieldValue"
      - $ref: "#/definitions/FieldFunctionValue"
      - $ref: "#/definitions/ApplyValue"
      - $ref: "#/definitions/LambdaValue"
      - $ref: "#/definitions/LetDefinitionValue"
      - $ref: "#/definitions/LetRecursionValue"
      - $ref: "#/definitions/DestructureValue"
      - $ref: "#/definitions/IfThenElseValue"
      - $ref: "#/definitions/PatternMatchValue"
      - $ref: "#/definitions/UpdateRecordValue"
      - $ref: "#/definitions/UnitValue"
  
  LiteralValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "literal"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Literal"
    description: "A literal constant value."
  
  ConstructorValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "constructor"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/FQName"
    description: "Reference to a custom type constructor."
  
  TupleValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "tuple"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          $ref: "#/definitions/Value"
        description: "Element values in order."
    description: "A tuple value with multiple elements."
  
  ListValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "list"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          $ref: "#/definitions/Value"
        description: "List elements."
    description: "A list of values."
  
  RecordValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "record"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - $ref: "#/definitions/Value"
        description: "Dictionary mapping field names to values."
    description: "A record value with named fields."
  
  VariableValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "variable"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Name"
    description: "Reference to a variable in scope."
  
  ReferenceValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "reference"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/FQName"
    description: "Reference to a defined value (function or constant)."
  
  FieldValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "field"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Value"
      - $ref: "#/definitions/Name"
    description: "Field access on a record. Items: [tag, attributes, recordExpr, fieldName]"
  
  FieldFunctionValue:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "field_function"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Name"
    description: "A function that extracts a field (e.g., .firstName)."
  
  ApplyValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "apply"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Value"
      - $ref: "#/definitions/Value"
    description: |
      Function application. Items: [tag, attributes, function, argument].
      Multi-argument calls are represented via currying (nested Apply nodes).
  
  LambdaValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "lambda"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Pattern"
      - $ref: "#/definitions/Value"
    description: |
      Anonymous function (lambda abstraction).
      Items: [tag, attributes, argumentPattern, body]
  
  LetDefinitionValue:
    type: array
    minItems: 5
    maxItems: 5
    items:
      - const: "let_definition"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Name"
      - $ref: "#/definitions/ValueDefinition"
      - $ref: "#/definitions/Value"
    description: |
      A let binding introducing a single value.
      Items: [tag, attributes, bindingName, definition, inExpr]
  
  LetRecursionValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "let_recursion"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - $ref: "#/definitions/ValueDefinition"
        description: "Multiple bindings that can reference each other."
      - $ref: "#/definitions/Value"
    description: "Mutually recursive let bindings."
  
  DestructureValue:
    type: array
    minItems: 5
    maxItems: 5
    items:
      - const: "destructure"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Pattern"
      - $ref: "#/definitions/Value"
      - $ref: "#/definitions/Value"
    description: |
      Pattern-based destructuring.
      Items: [tag, attributes, pattern, valueToDestructure, inExpr]
  
  IfThenElseValue:
    type: array
    minItems: 5
    maxItems: 5
    items:
      - const: "if_then_else"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Value"
      - $ref: "#/definitions/Value"
      - $ref: "#/definitions/Value"
    description: |
      Conditional expression.
      Items: [tag, attributes, condition, thenBranch, elseBranch]
  
  PatternMatchValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "pattern_match"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Value"
      - type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Pattern"
            - $ref: "#/definitions/Value"
        description: "List of pattern-branch pairs."
    description: "Pattern matching with multiple cases."
  
  UpdateRecordValue:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "update_record"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Value"
      - type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - $ref: "#/definitions/Value"
        description: "Fields to update with new values."
    description: |
      Record update expression (immutable copy-on-update).
      Items: [tag, attributes, recordToUpdate, fieldsToUpdate]
  
  UnitValue:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "unit"
      - $ref: "#/definitions/Attributes"
    description: "The unit value (the single value of the Unit type)."
  
  # ===== Literals =====
  # All literal tags are lowercase with underscores in v1
  
  Literal:
    description: "Represents literal constant values."
    oneOf:
      - $ref: "#/definitions/BoolLiteral"
      - $ref: "#/definitions/CharLiteral"
      - $ref: "#/definitions/StringLiteral"
      - $ref: "#/definitions/WholeNumberLiteral"
      - $ref: "#/definitions/FloatLiteral"
      - $ref: "#/definitions/DecimalLiteral"
  
  BoolLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "bool_literal"
      - type: boolean
    description: "Boolean literal (true or false)."
  
  CharLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "char_literal"
      - type: string
        minLength: 1
        maxLength: 1
    description: "Single character literal."
  
  StringLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "string_literal"
      - type: string
    description: "Text string literal."
  
  WholeNumberLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "whole_number_literal"
      - type: integer
    description: "Integer literal."
  
  FloatLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "float_literal"
      - type: number
    description: "Floating-point number literal."
  
  DecimalLiteral:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "decimal_literal"
      - type: string
        pattern: "^-?[0-9]+(\\.[0-9]+)?$"
    description: "Arbitrary-precision decimal literal (stored as string)."
  
  # ===== Patterns =====
  # All pattern tags are lowercase with underscores in v1
  
  Pattern:
    description: |
      Patterns are used for destructuring and filtering values.
      They appear in lambda, let destructure, and pattern match expressions.
      Pattern tags are lowercase with underscores in format version 1.
    oneOf:
      - $ref: "#/definitions/WildcardPattern"
      - $ref: "#/definitions/AsPattern"
      - $ref: "#/definitions/TuplePattern"
      - $ref: "#/definitions/ConstructorPattern"
      - $ref: "#/definitions/EmptyListPattern"
      - $ref: "#/definitions/HeadTailPattern"
      - $ref: "#/definitions/LiteralPattern"
      - $ref: "#/definitions/UnitPattern"
  
  WildcardPattern:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "wildcard_pattern"
      - $ref: "#/definitions/Attributes"
    description: "Matches any value without binding (the _ pattern)."
  
  AsPattern:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "as_pattern"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Pattern"
      - $ref: "#/definitions/Name"
    description: |
      Binds a name to a value matched by a nested pattern.
      Simple variable binding is AsPattern with WildcardPattern nested.
      Items: [tag, attributes, nestedPattern, variableName]
  
  TuplePattern:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "tuple_pattern"
      - $ref: "#/definitions/Attributes"
      - type: array
        items:
          $ref: "#/definitions/Pattern"
        description: "Patterns for each tuple element."
    description: "Matches a tuple by matching each element."
  
  ConstructorPattern:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "constructor_pattern"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/FQName"
      - type: array
        items:
          $ref: "#/definitions/Pattern"
        description: "Patterns for constructor arguments."
    description: "Matches a specific type constructor and its arguments."
  
  EmptyListPattern:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "empty_list_pattern"
      - $ref: "#/definitions/Attributes"
    description: "Matches an empty list (the [] pattern)."
  
  HeadTailPattern:
    type: array
    minItems: 4
    maxItems: 4
    items:
      - const: "head_tail_pattern"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Pattern"
      - $ref: "#/definitions/Pattern"
    description: |
      Matches a non-empty list by head and tail (the x :: xs pattern).
      Items: [tag, attributes, headPattern, tailPattern]
  
  LiteralPattern:
    type: array
    minItems: 3
    maxItems: 3
    items:
      - const: "literal_pattern"
      - $ref: "#/definitions/Attributes"
      - $ref: "#/definitions/Literal"
    description: "Matches an exact literal value."
  
  UnitPattern:
    type: array
    minItems: 2
    maxItems: 2
    items:
      - const: "unit_pattern"
      - $ref: "#/definitions/Attributes"
    description: "Matches the unit value."
  
  # ===== Value Specifications and Definitions =====
  
  ValueSpecification:
    type: object
    required: ["inputs", "output"]
    properties:
      inputs:
        type: array
        items:
          type: array
          minItems: 2
          maxItems: 2
          items:
            - $ref: "#/definitions/Name"
            - $ref: "#/definitions/Type"
        description: "Function parameters as (name, type) pairs."
      output:
        $ref: "#/definitions/Type"
        description: "The return type."
    description: |
      The type signature of a value or function.
      Contains only type information, no implementation.
  
  ValueDefinition:
    type: object
    required: ["inputTypes", "outputType", "body"]
    properties:
      inputTypes:
        type: array
        items:
          type: array
          minItems: 3
          maxItems: 3
          items:
            - $ref: "#/definitions/Name"
            - $ref: "#/definitions/Attributes"
            - $ref: "#/definitions/Type"
        description: "Function parameters as (name, attributes, type) tuples."
      outputType:
        $ref: "#/definitions/Type"
        description: "The return type."
      body:
        $ref: "#/definitions/Value"
        description: "The value expression implementing the logic."
    description: |
      The complete implementation of a value or function.
      Contains both type information and implementation.
```
