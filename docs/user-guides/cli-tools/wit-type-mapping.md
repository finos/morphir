---
id: wit-type-mapping
title: WIT Type Mapping
sidebar_position: 11
---

# WIT Type Mapping

This document describes how WebAssembly Interface Types (WIT) map to and from Morphir's Intermediate Representation (IR).

## Overview

Morphir's WIT integration provides bidirectional type mapping:

- **WIT -> IR (make)**: Converts WIT source to Morphir's domain types
- **IR -> WIT (gen)**: Converts Morphir domain types back to WIT source

The mapping preserves semantic meaning while adapting to each representation's conventions.

## Primitive Types

WIT primitive types map directly to Morphir primitive types:

| WIT Type | Morphir Type | Description |
|----------|--------------|-------------|
| `bool` | `Bool` | Boolean value |
| `u8` | `U8` | Unsigned 8-bit integer |
| `u16` | `U16` | Unsigned 16-bit integer |
| `u32` | `U32` | Unsigned 32-bit integer |
| `u64` | `U64` | Unsigned 64-bit integer |
| `s8` | `S8` | Signed 8-bit integer |
| `s16` | `S16` | Signed 16-bit integer |
| `s32` | `S32` | Signed 32-bit integer |
| `s64` | `S64` | Signed 64-bit integer |
| `f32` | `F32` | 32-bit floating point |
| `f64` | `F64` | 64-bit floating point |
| `char` | `Char` | Unicode character |
| `string` | `String` | UTF-8 string |

**Example:**

```wit
interface primitives {
    type age = u8;
    type name = string;
    type active = bool;
}
```

## Container Types

### List

WIT lists map to Morphir list types:

| WIT | Morphir |
|-----|---------|
| `list<T>` | `ListType{Element: T}` |

**Example:**

```wit
interface collections {
    type numbers = list<u32>;
    type names = list<string>;
}
```

### Option

WIT options map to Morphir option types:

| WIT | Morphir |
|-----|---------|
| `option<T>` | `OptionType{Inner: T}` |

**Example:**

```wit
interface nullable {
    type maybe-name = option<string>;
    type maybe-age = option<u32>;
}
```

### Result

WIT results map to Morphir result types:

| WIT | Morphir |
|-----|---------|
| `result` | `ResultType{Ok: nil, Err: nil}` |
| `result<T>` | `ResultType{Ok: T, Err: nil}` |
| `result<T, E>` | `ResultType{Ok: T, Err: E}` |
| `result<_, E>` | `ResultType{Ok: nil, Err: E}` |

**Example:**

```wit
interface errors {
    type error-code = u32;
    type parse-result = result<string, error-code>;
    type void-result = result<_, error-code>;
}
```

### Tuple

WIT tuples map to Morphir tuple types:

| WIT | Morphir |
|-----|---------|
| `tuple<T1, T2, ...>` | `TupleType{Types: [T1, T2, ...]}` |

**Example:**

```wit
interface pairs {
    type point = tuple<f32, f32>;
    type named-value = tuple<string, u32, bool>;
}
```

## Composite Types

### Record

WIT records map to Morphir record definitions:

**WIT:**
```wit
record user {
    id: string,
    name: string,
    age: u32,
    active: bool,
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "user",
    Kind: RecordDef{
        Fields: []Field{
            {Name: "id", Type: PrimitiveType{String}},
            {Name: "name", Type: PrimitiveType{String}},
            {Name: "age", Type: PrimitiveType{U32}},
            {Name: "active", Type: PrimitiveType{Bool}},
        },
    },
}
```

### Variant

WIT variants map to Morphir variant definitions:

**WIT:**
```wit
variant status {
    pending,
    active(string),
    completed(u32),
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "status",
    Kind: VariantDef{
        Cases: []VariantCase{
            {Name: "pending", Payload: nil},
            {Name: "active", Payload: &PrimitiveType{String}},
            {Name: "completed", Payload: &PrimitiveType{U32}},
        },
    },
}
```

### Enum

WIT enums map to Morphir enum definitions:

**WIT:**
```wit
enum color {
    red,
    green,
    blue,
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "color",
    Kind: EnumDef{
        Cases: []Identifier{"red", "green", "blue"},
    },
}
```

### Flags

WIT flags map to Morphir flags definitions:

**WIT:**
```wit
flags permissions {
    read,
    write,
    execute,
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "permissions",
    Kind: FlagsDef{
        Flags: []Identifier{"read", "write", "execute"},
    },
}
```

### Type Alias

WIT type aliases map to Morphir type alias definitions:

**WIT:**
```wit
type user-id = string;
type timestamp = u64;
```

**Morphir Domain:**
```go
TypeDef{
    Name: "user-id",
    Kind: TypeAliasDef{
        Target: PrimitiveType{String},
    },
}
```

## Resource Types

WIT resources and handles map to Morphir resource and handle types:

### Resource Definition

**WIT:**
```wit
resource file {
    constructor(path: string);
    read: func() -> result<list<u8>, error-code>;
    write: func(data: list<u8>) -> result<_, error-code>;
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "file",
    Kind: ResourceDef{
        Constructor: &Constructor{
            Params: []Param{{Name: "path", Type: PrimitiveType{String}}},
        },
        Methods: []ResourceMethod{
            {Name: "read", Function: ...},
            {Name: "write", Function: ...},
        },
    },
}
```

### Handle Types

| WIT | Morphir |
|-----|---------|
| `own<resource>` | `HandleType{Resource: "resource", IsBorrow: false}` |
| `borrow<resource>` | `HandleType{Resource: "resource", IsBorrow: true}` |

**Example:**

```wit
interface files {
    resource file;

    open: func(path: string) -> own<file>;
    read: func(f: borrow<file>) -> list<u8>;
}
```

## Functions

WIT functions map to Morphir function definitions:

**WIT:**
```wit
interface math {
    add: func(a: s32, b: s32) -> s32;
    divide: func(a: s32, b: s32) -> result<s32, string>;
    log: func(message: string);
}
```

**Morphir Domain:**
```go
Function{
    Name: "add",
    Params: []Param{
        {Name: "a", Type: PrimitiveType{S32}},
        {Name: "b", Type: PrimitiveType{S32}},
    },
    Results: []Type{PrimitiveType{S32}},
}
```

### Multiple Return Values

Functions with multiple return values use tuple-style results:

**WIT:**
```wit
interface multi {
    get-pair: func() -> (string, u32);
}
```

## Packages and Interfaces

### Package Structure

WIT packages map to Morphir package structures:

**WIT:**
```wit
package example:http@1.0.0;

interface types {
    type url = string;
}

interface client {
    use types.{url};
    get: func(u: url) -> result<string, string>;
}
```

**Morphir Domain:**
```go
Package{
    Namespace: "example",
    Name: "http",
    Version: semver("1.0.0"),
    Interfaces: []Interface{
        {Name: "types", Types: [...]},
        {Name: "client", Functions: [...]},
    },
}
```

### Worlds

WIT worlds map to Morphir world definitions:

**WIT:**
```wit
world http-server {
    import types;
    export handler;
}
```

## Naming Conventions

WIT uses kebab-case for all identifiers. The mapping preserves these conventions:

| WIT | Morphir Identifier |
|-----|-------------------|
| `user-id` | `user-id` |
| `http-client` | `http-client` |
| `get-user-by-id` | `get-user-by-id` |

### Escaped Identifiers

WIT supports escaped identifiers using `%` prefix for reserved words:

```wit
interface reserved {
    type %type = string;
    %import: func();
}
```

## Documentation

WIT documentation comments (`///`) are preserved in Morphir:

**WIT:**
```wit
/// A user in the system
/// with unique identifier
record user {
    /// The unique user ID
    id: string,
    /// Display name
    name: string,
}
```

**Morphir Domain:**
```go
TypeDef{
    Name: "user",
    Docs: Documentation{Lines: ["A user in the system", "with unique identifier"]},
    Kind: RecordDef{
        Fields: []Field{
            {Name: "id", Docs: Documentation{Lines: ["The unique user ID"]}},
            {Name: "name", Docs: Documentation{Lines: ["Display name"]}},
        },
    },
}
```

## Future Types (WASI Preview 3)

The following types are planned for WASI Preview 3 and have preliminary support:

### Future

| WIT | Morphir |
|-----|---------|
| `future` | `FutureType{Inner: nil}` |
| `future<T>` | `FutureType{Inner: T}` |

### Stream

| WIT | Morphir |
|-----|---------|
| `stream` | `StreamType{Element: nil}` |
| `stream<T>` | `StreamType{Element: T}` |

## Unsupported Features

Some WIT features are not yet fully supported:

- Complex `use` paths with versioning
- Resource methods (constructor, methods, statics) - basic support only
- World imports/exports - structural only
- Inline interface definitions in worlds

These features are tracked for future implementation.

## Round-Trip Validation

When using `morphir wit build`, the system validates that:

1. WIT source parses correctly
2. Morphir IR is generated successfully
3. Generated WIT is semantically equivalent to original

A successful round-trip indicates the type mapping preserved all semantic information.

## See Also

- [WIT Commands](./wit-commands.md) - CLI command reference
- [Morphir IR Specification](../../morphir-ir-specification.md) - IR format details
