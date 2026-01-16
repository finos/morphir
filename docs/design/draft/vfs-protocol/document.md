---
title: Document Type
sidebar_label: Document
sidebar_position: 9
---

# Document Type

The Document type provides a first-class, schema-less JSON-like data structure within the Morphir IR for representing untyped or dynamically-typed data.

## Design Principles

- **Value-Level Concern**: Document is a Literal variant, not a Type variant
- **SDK Type**: The type is `morphir/sdk:document#document` - a built-in reference
- **Platform Native**: Operations are specs-only; backends implement natively
- **JSON-Compatible**: Structure maps directly to JSON for easy interop

## Use Cases

| Use Case | Description |
|----------|-------------|
| External APIs | Responses where schema is unknown or varies |
| Configuration | Settings that don't need strict compile-time typing |
| Forwarding | Pass-through opaque data without interpretation |
| Metadata | Context-dependent annotations |
| Interop | Bridge to JSON-based systems |

## Gleam Type Definitions

### Document Value

```gleam
// === document.gleam ===

/// Recursive document value structure
/// Represents JSON-like schema-less data
pub type DocumentValue {
  /// JSON null
  DocNull

  /// JSON boolean
  DocBool(value: Bool)

  /// JSON number (integer)
  DocInt(value: Int)

  /// JSON number (floating point)
  DocFloat(value: Float)

  /// JSON string
  DocString(value: String)

  /// JSON array (ordered list)
  DocArray(elements: List(DocumentValue))

  /// JSON object (string-keyed map)
  DocObject(fields: Dict(String, DocumentValue))
}
```

### Literal Extension

The `DocumentLiteral` variant is added to the existing `Literal` type:

```gleam
// In values.gleam - extended Literal type

pub type Literal {
  // Existing literals...
  StringLiteral(value: String)
  IntLiteral(value: Int)
  FloatLiteral(value: Float)
  BoolLiteral(value: Bool)
  CharLiteral(value: String)
  WholeNumberLiteral(value: Int)
  DecimalLiteral(value: String)

  /// Document literal - schema-less JSON-like tree
  DocumentLiteral(value: DocumentValue)
}
```

### Type Reference

Document values have the type `morphir/sdk:document#document`:

```gleam
// The Document type is a simple opaque type in the SDK
// No new Type variant needed - it's just a Reference

fn document_type() -> Type(a) {
  Reference(
    attributes: default_attributes(),
    fqname: fqname_from_string("morphir/sdk:document#document"),
    args: [],
  )
}
```

## JSON Serialization

### DocumentValue Encoding

```json
// DocNull
{ "DocNull": {} }

// DocBool
{ "DocBool": true }

// DocInt
{ "DocInt": 42 }

// DocFloat
{ "DocFloat": 3.14 }

// DocString
{ "DocString": "hello" }

// DocArray
{ "DocArray": [
    { "DocInt": 1 },
    { "DocInt": 2 },
    { "DocInt": 3 }
  ]
}

// DocObject
{ "DocObject": {
    "name": { "DocString": "Alice" },
    "age": { "DocInt": 30 },
    "active": { "DocBool": true }
  }
}
```

### Shorthand Encoding

For compact representation, Document values can use JSON directly when unambiguous:

```json
// Shorthand (when context is clear)
{
  "DocumentLiteral": {
    "name": "Alice",
    "age": 30,
    "tags": ["admin", "user"],
    "metadata": null
  }
}

// Canonical (explicit wrappers)
{
  "DocumentLiteral": {
    "DocObject": {
      "name": { "DocString": "Alice" },
      "age": { "DocInt": 30 },
      "tags": { "DocArray": [
        { "DocString": "admin" },
        { "DocString": "user" }
      ]},
      "metadata": { "DocNull": {} }
    }
  }
}
```

### Decoding Rules

| JSON Value | DocumentValue |
|------------|---------------|
| `null` | `DocNull` |
| `true`/`false` | `DocBool` |
| Integer number | `DocInt` |
| Floating number | `DocFloat` |
| String | `DocString` |
| Array | `DocArray` |
| Object | `DocObject` |

## SDK Specification

The Document SDK provides operations as specifications (native implementation per platform).

### Type Definition

```elm
module Morphir.SDK.Document exposing
    ( Document
    , null, bool, int, float, string, array, object
    , asBool, asInt, asFloat, asString, asArray, asObject
    , get, getPath
    , isNull, isBool, isInt, isFloat, isString, isArray, isObject
    , encode, decoder
    )

{-| Schema-less document type for representing JSON-like data.

@docs Document

## Construction
@docs null, bool, int, float, string, array, object

## Extraction
@docs asBool, asInt, asFloat, asString, asArray, asObject

## Navigation
@docs get, getPath

## Predicates
@docs isNull, isBool, isInt, isFloat, isString, isArray, isObject

## Encoding/Decoding
@docs encode, decoder

-}
```

### Construction Functions

```elm
{-| The null document value. -}
null : Document

{-| Create a document from a boolean. -}
bool : Bool -> Document

{-| Create a document from an integer. -}
int : Int -> Document

{-| Create a document from a float. -}
float : Float -> Document

{-| Create a document from a string. -}
string : String -> Document

{-| Create a document from a list of documents. -}
array : List Document -> Document

{-| Create a document from key-value pairs. -}
object : List ( String, Document ) -> Document
```

### Extraction Functions

```elm
{-| Extract a boolean, if the document is a boolean. -}
asBool : Document -> Maybe Bool

{-| Extract an integer, if the document is an integer. -}
asInt : Document -> Maybe Int

{-| Extract a float, if the document is a number.
    Integers are coerced to floats.
-}
asFloat : Document -> Maybe Float

{-| Extract a string, if the document is a string. -}
asString : Document -> Maybe String

{-| Extract an array, if the document is an array. -}
asArray : Document -> Maybe (List Document)

{-| Extract an object as a dictionary, if the document is an object. -}
asObject : Document -> Maybe (Dict String Document)
```

### Navigation Functions

```elm
{-| Get a field from a document object by key.
    Returns Nothing if not an object or key doesn't exist.

    get "name" (object [("name", string "Alice")]) == Just (string "Alice")
    get "age" (string "hello") == Nothing
-}
get : String -> Document -> Maybe Document

{-| Get a nested value by path.

    doc = object
        [ ("user", object
            [ ("profile", object
                [ ("name", string "Alice") ]
                )
            ]
          )
        ]

    getPath ["user", "profile", "name"] doc == Just (string "Alice")
    getPath ["user", "missing"] doc == Nothing
-}
getPath : List String -> Document -> Maybe Document
```

### Predicate Functions

```elm
{-| Check if document is null. -}
isNull : Document -> Bool

{-| Check if document is a boolean. -}
isBool : Document -> Bool

{-| Check if document is an integer. -}
isInt : Document -> Bool

{-| Check if document is a float (non-integer number). -}
isFloat : Document -> Bool

{-| Check if document is a string. -}
isString : Document -> Bool

{-| Check if document is an array. -}
isArray : Document -> Bool

{-| Check if document is an object. -}
isObject : Document -> Bool
```

## Code Generation

### TypeScript/JavaScript

```typescript
// Document maps to `unknown` or a branded type
type Document = unknown;

// Or with runtime type info
type Document =
  | null
  | boolean
  | number
  | string
  | Document[]
  | { [key: string]: Document };

// SDK functions
const Document = {
  null: null,
  bool: (b: boolean): Document => b,
  int: (n: number): Document => n,
  string: (s: string): Document => s,
  array: (arr: Document[]): Document => arr,
  object: (entries: [string, Document][]): Document =>
    Object.fromEntries(entries),

  asString: (doc: Document): string | undefined =>
    typeof doc === 'string' ? doc : undefined,

  get: (key: string, doc: Document): Document | undefined =>
    typeof doc === 'object' && doc !== null && !Array.isArray(doc)
      ? (doc as Record<string, Document>)[key]
      : undefined,
};
```

### Scala

```scala
// Document as a sealed trait or type alias
sealed trait Document
case object DocNull extends Document
case class DocBool(value: Boolean) extends Document
case class DocInt(value: Long) extends Document
case class DocFloat(value: Double) extends Document
case class DocString(value: String) extends Document
case class DocArray(elements: List[Document]) extends Document
case class DocObject(fields: Map[String, Document]) extends Document

// Or use existing JSON library
import io.circe.Json
type Document = Json
```

### Go

```go
// Document as interface{} or any
type Document = any

// Or with explicit types
type Document interface {
    isDocument()
}

type DocNull struct{}
type DocBool struct{ Value bool }
type DocInt struct{ Value int64 }
type DocFloat struct{ Value float64 }
type DocString struct{ Value string }
type DocArray struct{ Elements []Document }
type DocObject struct{ Fields map[string]Document }
```

### Java

```java
// Using sealed interfaces (Java 17+)
public sealed interface Document permits
    DocNull, DocBool, DocInt, DocFloat, DocString, DocArray, DocObject {}

public record DocNull() implements Document {}
public record DocBool(boolean value) implements Document {}
public record DocInt(long value) implements Document {}
public record DocFloat(double value) implements Document {}
public record DocString(String value) implements Document {}
public record DocArray(List<Document> elements) implements Document {}
public record DocObject(Map<String, Document> fields) implements Document {}
```

## VFS File Example

### Value Definition Using Document

File: `.morphir-dist/pkg/my-org/api/values/parse-response.value.json`

```json
{
  "formatVersion": "4.0.0",
  "name": "parse-response",
  "def": {
    "access": "Public",
    "value": {
      "ExpressionBody": {
        "inputTypes": {
          "response": "morphir/sdk:document#document"
        },
        "outputType": ["morphir/sdk:maybe#maybe", "my-org/api:types#user"],
        "body": {
          "Apply": {
            "function": { "Reference": { "fqname": "morphir/sdk:maybe#and-then" } },
            "args": [
              {
                "Apply": {
                  "function": { "Reference": { "fqname": "morphir/sdk:document#get" } },
                  "args": [
                    { "Literal": { "StringLiteral": "data" } },
                    { "Variable": { "name": "response" } }
                  ]
                }
              }
            ]
          }
        }
      }
    }
  }
}
```

### Document Literal in IR

```json
{
  "Literal": {
    "DocumentLiteral": {
      "type": "user",
      "attributes": {
        "id": 12345,
        "roles": ["admin", "editor"],
        "settings": {
          "theme": "dark",
          "notifications": true
        }
      }
    }
  }
}
```

## Comparison with Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **Document (this design)** | Clean, JSON-native, simple | No compile-time structure checking |
| **Type variant** | Type-level operations | Complicates Type sum type |
| **Extensible records** | Some structure | Still needs known fields |
| **Any/Dynamic** | Maximum flexibility | No structure at all |

## Open Considerations

### Optional Extensions

These are not part of the core design but could be added later:

1. **Binary data**: `DocBinary(bytes: BitArray)` for base64-encoded blobs
2. **Timestamps**: `DocTimestamp(value: String)` for ISO 8601 dates
3. **Big numbers**: `DocDecimal(value: String)` for arbitrary precision
4. **IR references**: `DocReference(fqname: FQName)` for linking to IR nodes

### Schema Validation

Runtime schema validation could be provided via decorations:

```json
{
  "my-org/api:handlers#response": {
    "schema": {
      "type": "object",
      "properties": {
        "data": { "type": "object" },
        "error": { "type": "string" }
      }
    }
  }
}
```

### Merge Semantics

For combining documents (e.g., in configuration):

```elm
{-| Merge two documents. Objects are deep-merged, other types use the second value. -}
merge : Document -> Document -> Document
```
