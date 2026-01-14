---
title: "Morphir IR Specification"
linkTitle: "IR Specification"
weight: 1
description: "Complete specification of the Morphir Intermediate Representation (IR)"
---

# Morphir IR Specification

## Overview

The Morphir Intermediate Representation (IR) is a language-independent, platform-agnostic representation of business logic and domain models. It serves as a universal format that captures the semantics of functional programs, enabling them to be transformed, analyzed, and executed across different platforms and languages.

### Purpose

The Morphir IR specification defines:

- **Building blocks**: Core concepts and data structures that form the IR
- **Relationships**: How different components of the IR relate to and reference each other
- **Semantics**: The meaning and behavior of each construct

This specification is designed to:

- Guide implementers building tools that generate, consume, or transform Morphir IR
- Provide context for Large Language Models (LLMs) working with Morphir
- Serve as the authoritative reference for the Morphir IR structure

### Design Principles

The Morphir IR follows these key principles:

- **Functional**: All logic is expressed as pure functions without side effects
- **Type-safe**: Complete type information is preserved throughout the IR
- **Hierarchical**: Code is organized in a hierarchical namespace (Package → Module → Type/Value)
- **Naming-agnostic**: Names are stored in a canonical format independent of any specific naming convention
- **Explicit**: All references are fully-qualified to eliminate ambiguity

## Core Concepts

### Naming

Morphir uses a sophisticated naming system that is independent of any specific naming convention (camelCase, snake_case, etc.). This allows the same IR to be rendered in different conventions for different platforms.

#### Name

A **Name** represents a human-readable identifier made up of one or more words.

- Structure: A list of lowercase word strings
- Purpose: Serves as the atomic unit for all identifiers
- Example: `["value", "in", "u", "s", "d"]` can be rendered as:
  - `valueInUSD` (camelCase)
  - `ValueInUSD` (TitleCase)
  - `value_in_USD` (snake_case)

#### Path

A **Path** represents a hierarchical location in the IR structure.

- Structure: A list of Names
- Purpose: Identifies packages and modules within the hierarchy
- Example: `[["morphir"], ["s", "d", "k"], ["string"]]` represents the path to the String module

#### Qualified Name (QName)

A **Qualified Name** uniquely identifies a type or value within a package.

- Structure: A tuple of (module path, local name)
- Components:
  - Module path: The Path to the module
  - Local name: The Name of the type or value within that module
- Purpose: Identifies items relative to a package

#### Fully-Qualified Name (FQName)

A **Fully-Qualified Name** provides a globally unique identifier for any type or value.

- Structure: A tuple of (package path, module path, local name)
- Components:
  - Package path: The Path to the package
  - Module path: The Path to the module within the package
  - Local name: The Name of the type or value
- Purpose: Enables unambiguous references across package boundaries

### Attributes and Annotations

The IR supports extensibility through attributes that can be attached to various nodes:

- **Type attributes (ta)**: Extra information attached to type nodes (e.g., source location, type inference results)
- **Value attributes (va)**: Extra information attached to value nodes (e.g., source location, inferred types)

When no additional information is needed, the unit type `()` is used as a placeholder.

### Access Control

#### AccessControlled

An **AccessControlled** wrapper manages visibility of types and values.

- Structure: `{ access, value }`
- Access levels:
  - **Public**: Visible to external consumers of the package
  - **Private**: Only visible within the package
- Purpose: Controls what parts of a package are exposed in its public API

#### Documented

A **Documented** wrapper associates documentation with IR elements.

- Structure: `{ doc, value }`
- Components:
  - doc: A string containing documentation text
  - value: The documented element
- Purpose: Preserves documentation for types and values

## Distribution

A **Distribution** represents a complete, self-contained package of Morphir code with all its dependencies.

### Structure

Currently, Morphir supports a single distribution type: **Library**

A Library distribution contains:

- **Package name**: The globally unique identifier for the package (like NPM package name or Maven GroupId:ArtifactId)
- **Dependencies**: A dictionary mapping package names to their specifications
  - Dependencies only contain type signatures (specifications), not implementations
- **Package definition**: The complete implementation of the package
  - Contains all module definitions, including private modules
  - Includes both type signatures and implementations

### Purpose

A distribution is:

- The output of the Morphir compilation process (e.g., `morphir-elm make`)
- A complete unit that can be executed, analyzed, or transformed
- Self-contained with all dependency information included

## Package

A **Package** is a collection of modules that are versioned and distributed together. It corresponds to what package managers like NPM, NuGet, Maven, or pip consider a package.

### Package Specification

A **Package Specification** provides the public interface of a package.

Structure:
- **modules**: A dictionary mapping module names (Paths) to Module Specifications

Characteristics:
- Contains only publicly exposed modules
- Types are only included if they are public
- Values are only included if they are public
- No implementation details are included

### Package Definition

A **Package Definition** provides the complete implementation of a package.

Structure:
- **modules**: A dictionary mapping module names (Paths) to AccessControlled Module Definitions

Characteristics:
- Contains all modules (both public and private)
- All types are included (both public and private)
- All values are included with their implementations
- Each module is wrapped in AccessControlled to indicate its visibility

### Package Name

A **Package Name** is the globally unique identifier for a package.

- Structure: A Path (list of Names)
- Examples: `[["morphir"], ["s", "d", "k"]]`, `[["my"], ["company"], ["models"]]`
- Purpose: Uniquely identifies a package across all Morphir systems

## Module

A **Module** groups related types and values together, similar to packages in Java or namespaces in other languages.

### Module Specification

A **Module Specification** provides the public interface of a module.

Structure:
- **types**: Dictionary of type names to Documented Type Specifications
- **values**: Dictionary of value names to Documented Value Specifications  
- **doc**: Optional documentation string for the module

Characteristics:
- Only includes publicly exposed types and values
- Contains type signatures but no implementations
- Documentation is preserved from the source

### Module Definition

A **Module Definition** provides the complete implementation of a module.

Structure:
- **types**: Dictionary of type names to AccessControlled, Documented Type Definitions
- **values**: Dictionary of value names to AccessControlled, Documented Value Definitions
- **doc**: Optional documentation string for the module

Characteristics:
- Includes all types and values (public and private)
- Contains complete implementations
- Each type and value is wrapped in AccessControlled to indicate visibility
- Documentation is preserved from the source

### Module Name

A **Module Name** uniquely identifies a module within a package.

- Structure: A Path (list of Names)
- Examples: `[["morphir"], ["i", "r"], ["type"]]`, `[["my"], ["module"]]`

### Qualified Module Name

A **Qualified Module Name** provides a globally unique module identifier.

- Structure: A tuple of (package path, module path)
- Purpose: Enables unambiguous module references across packages

## Type System

The Morphir type system is based on functional programming principles, similar to languages like Elm, Haskell, or ML.

### Type Expressions

A **Type** is a recursive tree structure representing type expressions. Each node can have type attributes attached.

#### Variable

Represents a type variable (generic parameter).

- Structure: `Variable a Name`
- Components:
  - a: Type attribute
  - Name: The variable name
- Example: The `a` in `List a`
- Purpose: Enables generic/polymorphic types

#### Reference

A reference to another type or type alias.

- Structure: `Reference a FQName (List Type)`
- Components:
  - a: Type attribute
  - FQName: Fully-qualified name of the referenced type
  - List Type: Type arguments (for generic types)
- Examples:
  - `String` → `Reference a (["morphir"], ["s", "d", "k"], ["string"]) []`
  - `List Int` → `Reference a (["morphir"], ["s", "d", "k"], ["list"]) [intType]`
- Purpose: Refers to built-in types, custom types, or type aliases

#### Tuple

A composition of multiple types in a fixed order.

- Structure: `Tuple a (List Type)`
- Components:
  - a: Type attribute
  - List Type: Element types in order
- Examples:
  - `(Int, String)` → `Tuple a [intType, stringType]`
  - `(Int, Int, Bool)` → `Tuple a [intType, intType, boolType]`
- Notes:
  - Zero-element tuple is equivalent to Unit
  - Single-element tuple is equivalent to the element type itself
- Purpose: Represents product types with positional access

#### Record

A composition of named fields with their types.

- Structure: `Record a (List Field)`
- Components:
  - a: Type attribute
  - List Field: List of field definitions
- Field structure: `{ name: Name, tpe: Type }`
- Example: `{ firstName: String, age: Int }`
- Notes:
  - Field order is preserved but not semantically significant
  - All fields are required (no optional fields)
- Purpose: Represents product types with named field access

#### ExtensibleRecord

A record type that can be extended with additional fields.

- Structure: `ExtensibleRecord a Name (List Field)`
- Components:
  - a: Type attribute
  - Name: Type variable representing the extension
  - List Field: Known fields
- Example: `{ a | firstName: String, age: Int }` means "type `a` with at least these fields"
- Purpose: Enables flexible record types that can be extended

#### Function

Represents a function type.

- Structure: `Function a Type Type`
- Components:
  - a: Type attribute
  - First Type: Argument type
  - Second Type: Return type
- Examples:
  - `Int -> String` → `Function a intType stringType`
  - `Int -> Int -> Bool` → `Function a intType (Function a intType boolType)`
- Notes:
  - Multi-argument functions are represented via currying (nested Function types)
- Purpose: Represents the type of functions and lambdas

#### Unit

The type with exactly one value.

- Structure: `Unit a`
- Components:
  - a: Type attribute
- Purpose: Placeholder where a type is needed but the value is unused
- Corresponds to `void` in some languages

### Type Specifications

A **Type Specification** defines the interface of a type without implementation details.

#### TypeAliasSpecification

An alias for another type.

- Structure: `TypeAliasSpecification (List Name) Type`
- Components:
  - List Name: Type parameters
  - Type: The aliased type expression
- Example: `type alias UserId = String`
- Purpose: Provides a meaningful name for a type expression

#### OpaqueTypeSpecification

A type with unknown structure.

- Structure: `OpaqueTypeSpecification (List Name)`
- Components:
  - List Name: Type parameters
- Characteristics:
  - Structure is hidden from consumers
  - Cannot be automatically serialized
  - Values can only be created and manipulated via provided functions
- Purpose: Encapsulates implementation details

#### CustomTypeSpecification

A tagged union type (sum type).

- Structure: `CustomTypeSpecification (List Name) Constructors`
- Components:
  - List Name: Type parameters
  - Constructors: Dictionary of constructor names to their arguments
- Constructor arguments: `List (Name, Type)` - list of named, typed arguments
- Example: `type Result e a = Ok a | Err e`
- Purpose: Represents choice between multiple alternatives

#### DerivedTypeSpecification

A type with platform-specific representation but known serialization.

- Structure: `DerivedTypeSpecification (List Name) Details`
- Details contain:
  - **baseType**: The type used for serialization
  - **fromBaseType**: FQName of function to convert from base type
  - **toBaseType**: FQName of function to convert to base type
- Example: A `LocalDate` might serialize to/from String with conversion functions
- Purpose: Enables platform-specific types while maintaining serialization capability

### Type Definitions

A **Type Definition** provides the complete implementation of a type.

#### TypeAliasDefinition

Complete definition of a type alias.

- Structure: `TypeAliasDefinition (List Name) Type`
- Components:
  - List Name: Type parameters
  - Type: The complete type expression being aliased
- Same as specification (aliases have no hidden implementation)

#### CustomTypeDefinition

Complete definition of a custom type.

- Structure: `CustomTypeDefinition (List Name) (AccessControlled Constructors)`
- Components:
  - List Name: Type parameters
  - AccessControlled Constructors: Constructor definitions with visibility control
- If constructors are Private → specification becomes OpaqueTypeSpecification
- If constructors are Public → specification becomes CustomTypeSpecification
- Purpose: Allows hiding constructors while exposing the type

## Value System

Values represent both data and logic in Morphir. All computations are expressed as value expressions.

### Value Expressions

A **Value** is a recursive tree structure representing computations. Each node can have type and value attributes.

#### Literal

A literal constant value.

- Structure: `Literal va Literal`
- Components:
  - va: Value attribute
  - Literal: The literal value
- Supported literal types:
  - **BoolLiteral**: Boolean values (`True`, `False`)
  - **CharLiteral**: Single characters (`'a'`, `'Z'`)
  - **StringLiteral**: Text strings (`"hello"`)
  - **WholeNumberLiteral**: Integers (`42`, `-17`)
  - **FloatLiteral**: Floating-point numbers (`3.14`, `-0.5`)
  - **DecimalLiteral**: Arbitrary-precision decimals
- Purpose: Represents constant data

#### Constructor

Reference to a custom type constructor.

- Structure: `Constructor va FQName`
- Components:
  - va: Value attribute
  - FQName: Fully-qualified name of the constructor
- If the constructor has arguments, it will be wrapped in Apply nodes
- Example: `Just` in `Maybe a`, `Ok` in `Result e a`
- Purpose: Creates tagged union values

#### Tuple

A tuple value with multiple elements.

- Structure: `Tuple va (List Value)`
- Components:
  - va: Value attribute
  - List Value: Element values in order
- Example: `(42, "hello", True)`
- Purpose: Groups multiple values together with positional access

#### List

A list of values.

- Structure: `List va (List Value)`
- Components:
  - va: Value attribute
  - List Value: List elements
- Example: `[1, 2, 3, 4]`
- Purpose: Represents homogeneous sequences

#### Record

A record value with named fields.

- Structure: `Record va (Dict Name Value)`
- Components:
  - va: Value attribute
  - Dict Name Value: Dictionary mapping field names to values
- Example: `{ firstName = "John", age = 30 }`
- Purpose: Represents structured data with named field access

#### Variable

Reference to a variable in scope.

- Structure: `Variable va Name`
- Components:
  - va: Value attribute
  - Name: Variable name
- Example: References to function parameters or let-bound variables
- Purpose: Accesses values bound in the current scope

#### Reference

Reference to a defined value (function or constant).

- Structure: `Reference va FQName`
- Components:
  - va: Value attribute
  - FQName: Fully-qualified name of the referenced value
- Example: `Morphir.SDK.List.map`, `Basics.add`
- Purpose: Invokes or references defined functions and constants

#### Field

Field access on a record.

- Structure: `Field va Value Name`
- Components:
  - va: Value attribute
  - Value: The record expression
  - Name: Field name to access
- Example: `user.firstName` → `Field va (Variable va ["user"]) ["first", "name"]`
- Purpose: Extracts a specific field from a record

#### FieldFunction

A function that extracts a field.

- Structure: `FieldFunction va Name`
- Components:
  - va: Value attribute
  - Name: Field name
- Example: `.firstName` creates a function `\r -> r.firstName`
- Purpose: Creates a field accessor function

#### Apply

Function application.

- Structure: `Apply va Value Value`
- Components:
  - va: Value attribute
  - First Value: The function
  - Second Value: The argument
- Multi-argument calls are represented via currying (nested Apply nodes)
- Example: `add 1 2` → `Apply va (Apply va (Reference va add) (Literal va 1)) (Literal va 2)`
- Purpose: Invokes functions with arguments

#### Lambda

Anonymous function (lambda abstraction).

- Structure: `Lambda va Pattern Value`
- Components:
  - va: Value attribute
  - Pattern: Pattern matching the input
  - Value: Function body
- Example: `\x -> x + 1` → `Lambda va (AsPattern va (WildcardPattern va) ["x"]) (body)`
- Purpose: Creates inline functions

#### LetDefinition

A let binding introducing a single value.

- Structure: `LetDefinition va Name Definition Value`
- Components:
  - va: Value attribute
  - Name: Binding name
  - Definition: Value definition being bound
  - Value: Expression where the binding is in scope
- Example: `let x = 5 in x + x`
- Purpose: Introduces local bindings

#### LetRecursion

Mutually recursive let bindings.

- Structure: `LetRecursion va (Dict Name Definition) Value`
- Components:
  - va: Value attribute
  - Dict Name Definition: Multiple bindings that can reference each other
  - Value: Expression where the bindings are in scope
- Purpose: Enables mutual recursion between bindings

#### Destructure

Pattern-based destructuring.

- Structure: `Destructure va Pattern Value Value`
- Components:
  - va: Value attribute
  - Pattern: Pattern to match
  - First Value: Expression to destructure
  - Second Value: Expression where extracted variables are in scope
- Example: `let (x, y) = point in ...`
- Purpose: Extracts values from structured data

#### IfThenElse

Conditional expression.

- Structure: `IfThenElse va Value Value Value`
- Components:
  - va: Value attribute
  - First Value: Condition
  - Second Value: Then branch
  - Third Value: Else branch
- Example: `if x > 0 then "positive" else "non-positive"`
- Purpose: Conditional logic

#### PatternMatch

Pattern matching with multiple cases.

- Structure: `PatternMatch va Value (List (Pattern, Value))`
- Components:
  - va: Value attribute
  - Value: Expression to match against
  - List (Pattern, Value): List of pattern-branch pairs
- Example: `case maybeValue of Just x -> x; Nothing -> 0`
- Purpose: Conditional logic based on structure

#### UpdateRecord

Record update expression.

- Structure: `UpdateRecord va Value (Dict Name Value)`
- Components:
  - va: Value attribute
  - Value: The record to update
  - Dict Name Value: Fields to update with new values
- Example: `{ user | age = 31 }`
- Notes: This is copy-on-update (immutable)
- Purpose: Creates a modified copy of a record

#### Unit

The unit value.

- Structure: `Unit va`
- Components:
  - va: Value attribute
- Purpose: Represents the single value of the Unit type

### Patterns

**Patterns** are used for destructuring and filtering values. They appear in lambda, let destructure, and pattern match expressions.

#### WildcardPattern

Matches any value without binding.

- Structure: `WildcardPattern a`
- Syntax: `_` in source languages
- Purpose: Ignores a value

#### AsPattern

Binds a name to a value matched by a nested pattern.

- Structure: `AsPattern a Pattern Name`
- Components:
  - a: Pattern attribute
  - Pattern: Nested pattern
  - Name: Variable name to bind
- Syntax: `pattern as name` in source languages
- Special case: Simple variable binding is `AsPattern a (WildcardPattern a) name`
- Purpose: Captures matched values

#### TuplePattern

Matches a tuple by matching each element.

- Structure: `TuplePattern a (List Pattern)`
- Components:
  - a: Pattern attribute
  - List Pattern: Patterns for each tuple element
- Example: `(x, y)` matches a 2-tuple
- Purpose: Destructures tuples

#### ConstructorPattern

Matches a specific type constructor and its arguments.

- Structure: `ConstructorPattern a FQName (List Pattern)`
- Components:
  - a: Pattern attribute
  - FQName: Fully-qualified constructor name
  - List Pattern: Patterns for constructor arguments
- Example: `Just x` matches `Just` with pattern `x`
- Purpose: Destructures and filters tagged unions

#### EmptyListPattern

Matches an empty list.

- Structure: `EmptyListPattern a`
- Syntax: `[]` in source languages
- Purpose: Detects empty lists

#### HeadTailPattern

Matches a non-empty list by head and tail.

- Structure: `HeadTailPattern a Pattern Pattern`
- Components:
  - a: Pattern attribute
  - First Pattern: Matches the head element
  - Second Pattern: Matches the tail (remaining list)
- Syntax: `x :: xs` in source languages
- Purpose: Destructures lists recursively

#### LiteralPattern

Matches an exact literal value.

- Structure: `LiteralPattern a Literal`
- Components:
  - a: Pattern attribute
  - Literal: The exact value to match
- Example: `42`, `"hello"`, `True`
- Purpose: Filters by exact value

#### UnitPattern

Matches the unit value.

- Structure: `UnitPattern a`
- Purpose: Matches the Unit value

### Value Specifications

A **Value Specification** defines the type signature of a value or function.

Structure:
- **inputs**: List of (Name, Type) pairs representing function parameters
- **output**: The return type

Characteristics:
- Contains only type information, no implementation
- Multi-argument functions list all parameters
- Zero-argument values (constants) have empty inputs list

Example: `add : Int -> Int -> Int` becomes:
```
{ inputs = [("a", Int), ("b", Int)]
, output = Int
}
```

### Value Definitions

A **Value Definition** provides the complete implementation of a value or function.

Structure:
- **inputTypes**: List of (Name, va, Type) tuples for function parameters
  - Name: Parameter name
  - va: Value attribute for the parameter
  - Type: Parameter type
- **outputType**: The return type
- **body**: The value expression implementing the logic

Characteristics:
- Contains both type information and implementation
- Parameters are extracted from nested lambdas when possible
- Body contains the actual computation

## Relationships Between Concepts

### Hierarchical Structure

```
Distribution
  └─ Package (with dependencies)
      └─ Module
          ├─ Types
          │   └─ Type Definition/Specification
          └─ Values
              └─ Value Definition/Specification
```

### Specifications vs Definitions

- **Specifications**: Public interface only
  - Used for dependencies
  - Contain type signatures only
  - Expose only public items
  
- **Definitions**: Complete implementation
  - Used for the package being compiled
  - Contain all details
  - Include both public and private items

### Conversion Flow

```
Definition → Specification
  - Package Definition → Package Specification
  - Module Definition → Module Specification  
  - Type Definition → Type Specification
  - Value Definition → Value Specification
```

Specifications can be created with or without private items:
- **definitionToSpecification**: Public items only
- **definitionToSpecificationWithPrivate**: All items included

### Reference Resolution

References in the IR are always fully-qualified:

1. **Within expressions**: References use FQName (package, module, local name)
2. **Within modules**: Items use local Names (looked up in module context)
3. **Within packages**: Modules use Paths (looked up in package context)

This eliminates ambiguity and enables:
- Easy dependency tracking
- Cross-package linking
- Independent processing of modules

## Semantics

### Type System Semantics

- **Type Safety**: All values have types; type checking ensures correctness
- **Polymorphism**: Type variables enable generic programming
- **Structural Typing**: Records and tuples are compared structurally
- **Nominal Typing**: Custom types are compared by name
- **Immutability**: All values are immutable; updates create new values

### Value Evaluation Semantics

- **Pure Functions**: All functions are pure (no side effects)
- **Eager Evaluation**: Arguments are evaluated before function application
- **Pattern Matching**: Patterns are tested in order; first match wins
- **Scope Rules**:
  - Lambda parameters are in scope in the lambda body
  - Let bindings are in scope in the let expression body
  - Pattern variables are in scope in the associated branch
  
### Access Control Semantics

- **Public**: Visible in package specifications; accessible to consumers
- **Private**: Only visible within package definition; not exposed
- **Custom type constructors**: Can be public (pattern matching allowed) or private (opaque type)

## Usage Guidelines for Tool Implementers

### Generating IR

When generating Morphir IR from source code:

1. **Preserve names in canonical form**: Convert all identifiers to lowercase word lists
2. **Use fully-qualified references**: Always include package and module paths
3. **Maintain access control**: Mark public vs private appropriately
4. **Extract lambdas into function parameters**: Use the inputTypes field instead of nested lambdas where possible
5. **Preserve documentation**: Include doc strings from source

### Consuming IR

When consuming Morphir IR:

1. **Respect access control**: Only access public items from dependencies
2. **Resolve references**: Use the distribution to look up type and value definitions
3. **Handle attributes**: Be prepared for different attribute types or use unit type
4. **Follow naming conventions**: Use Name conversion utilities for target platform
5. **Process hierarchically**: Start from Distribution → Package → Module → Types/Values

### Transforming IR

When transforming Morphir IR:

1. **Preserve structure**: Maintain the hierarchical organization
2. **Update references consistently**: If you rename items, update all references
3. **Maintain type correctness**: Ensure transformations preserve type safety
4. **Handle both specifications and definitions**: Transform both forms consistently
5. **Preserve attributes**: Carry forward attributes unless explicitly changing them

## JSON Schema Specifications

To support tooling, validation, and interoperability, formal JSON schemas are provided for all supported format versions of the Morphir IR. These schemas are defined in YAML format for readability and include comprehensive documentation.

### Available Schemas

- **[Format Version 3 (Current)](/schemas/morphir-ir-v3.yaml)**: The latest format version, which uses capitalized constructor tags (e.g., `"Library"`, `"Public"`, `"Variable"`).

- **[Format Version 2](/schemas/morphir-ir-v2.yaml)**: Uses capitalized distribution and type tags (e.g., `"Library"`, `"Public"`, `"Variable"`) but lowercase value and pattern tags (e.g., `"apply"`, `"lambda"`, `"as_pattern"`).

- **[Format Version 1](/schemas/morphir-ir-v1.yaml)**: The original format version, which uses lowercase tags throughout (e.g., `"library"`, `"public"`) and a different module structure where modules have `name` and `def` fields.

### Key Differences Between Versions

#### Format Version 1 → 2
- **Distribution tag**: Changed from `"library"` to `"Library"`
- **Access control**: Changed from `"public"/"private"` to `"Public"/"Private"`
- **Module structure**: Changed from `{"name": ..., "def": ...}` to array-based `[modulePath, accessControlled]`
- **Type tags**: Changed to capitalized forms (e.g., `"variable"` → `"Variable"`)

#### Format Version 2 → 3
- **Value expression tags**: Changed from lowercase to capitalized (e.g., `"apply"` → `"Apply"`)
- **Pattern tags**: Changed from lowercase with underscores to capitalized (e.g., `"as_pattern"` → `"AsPattern"`)
- **Literal tags**: Changed from lowercase with underscores to capitalized (e.g., `"bool_literal"` → `"BoolLiteral"`)

### Using the Schemas

The JSON schemas can be used for:

1. **Validation**: Validate Morphir IR JSON files against the appropriate version schema
2. **Documentation**: Understand the structure and constraints of the IR format
3. **Code Generation**: Generate parsers, serializers, and type definitions for various languages
4. **Tooling**: Build editors, linters, and other tools that work with Morphir IR

Example validation using a JSON schema validator:

```bash
# Using Python jsonschema (recommended for YAML schemas)
pip install jsonschema pyyaml requests
python -c "import json, yaml, jsonschema, requests; \
  schema = yaml.safe_load(requests.get('https://morphir.finos.org/schemas/morphir-ir-v3.yaml').text); \
  data = json.load(open('morphir-ir.json')); \
  jsonschema.validate(data, schema); \
  print('✓ Valid Morphir IR')"

# Using ajv-cli (Node.js) - requires converting YAML to JSON first
npm install -g ajv-cli
curl -o morphir-ir-v3.yaml https://morphir.finos.org/schemas/morphir-ir-v3.yaml
python -c "import yaml, json; \
  json.dump(yaml.safe_load(open('morphir-ir-v3.yaml')), \
  open('morphir-ir-v3.json', 'w'))"
ajv validate -s morphir-ir-v3.json -d morphir-ir.json

# Using sourcemeta/jsonschema CLI (fast, cross-platform C++ validator)
# Install via: npm install -g @sourcemeta/jsonschema
#          or: brew install sourcemeta/apps/jsonschema
#          or: pip install jsonschema-cli
curl -o morphir-ir-v3.json https://morphir.finos.org/schemas/morphir-ir-v3.json
jsonschema validate morphir-ir-v3.json morphir-ir.json
```

### Schema Location

Schemas are available in both YAML and JSON formats:

| Version | YAML | JSON |
|---------|------|------|
| v3 (Current) | https://morphir.finos.org/schemas/morphir-ir-v3.yaml | https://morphir.finos.org/schemas/morphir-ir-v3.json |
| v2 | https://morphir.finos.org/schemas/morphir-ir-v2.yaml | https://morphir.finos.org/schemas/morphir-ir-v2.json |
| v1 | https://morphir.finos.org/schemas/morphir-ir-v1.yaml | https://morphir.finos.org/schemas/morphir-ir-v1.json |

Use YAML for better readability or JSON for maximum tool compatibility.

## Conclusion

The Morphir IR provides a comprehensive, type-safe representation of functional business logic. Its design enables:

- **Portability**: Same logic can target multiple platforms
- **Analysis**: Logic can be analyzed for correctness and properties
- **Transformation**: Logic can be optimized and adapted
- **Tooling**: Rich development tools can be built on a standard format
- **Interoperability**: Different languages can share logic via IR

This specification defines the structure and semantics necessary for building a robust ecosystem of Morphir tools and ensuring consistent interpretation across implementations. The accompanying JSON schemas provide formal, machine-readable definitions that can be used for validation, code generation, and tooling support.
