# Morphir Models (Go)

This module provides the Go representation of the Morphir Intermediate
Representation (IR). It includes core IR types, JSON codecs, schema helpers,
and a small SDK expressed in IR for standard library modeling.

## What lives here

- `ir` holds the core data structures for Morphir IR.
- `ir/codec/json` provides JSON encoding/decoding for IR values.
- `ir/schema` embeds versioned IR JSON schemas.
- `ir/sdk` provides IR definitions for common standard library concepts.

## Quick start

Use the IR package as the primary entry point:

```go
package main

import (
	"fmt"

	"github.com/finos/morphir/pkg/models/ir"
)

func main() {
	name := ir.NameFromString("Order")
	path := ir.Path{ir.NameFromString("Domain")}
	qname := ir.QualifiedName{Path: path, Name: name}

	fmt.Println(qname)
}
```

For JSON codecs:

```go
package main

import (
	"encoding/json"
	"fmt"

	"github.com/finos/morphir/pkg/models/ir"
	jsoncodec "github.com/finos/morphir/pkg/models/ir/codec/json"
)

func main() {
	value := ir.Value{
		Attributes: ir.EmptyAttributes{},
		Value: ir.LiteralValue{
			Attributes: ir.EmptyAttributes{},
			Value:      ir.StringLiteral("hello"),
		},
	}

	encoded, err := jsoncodec.EncodeValue(value, jsoncodec.EncodeOptions{})
	if err != nil {
		panic(err)
	}

	payload, err := json.MarshalIndent(encoded, "", "  ")
	if err != nil {
		panic(err)
	}

	fmt.Println(string(payload))
}
```

## IR package overview

The `ir` package models the Morphir IR specification and is organized around
these concepts:

- Names and paths: `Name`, `Path`, `QualifiedName`, `FullyQualifiedName`.
- Packages and modules: `PackageName`, `PackageDefinition`, `ModuleName`.
- Types: `Type`, `TypeSpecification`, `TypeDefinition`.
- Values and patterns: `Value`, `Pattern`, `Literal`.
- Access control and documentation: `AccessControlled`, `Documented`.

The API is designed to favor immutable data and functional composition.

## JSON codecs

The JSON codec layer allows round-tripping Morphir IR values to the official
JSON format used by other Morphir tooling. Use the `Encode*` and `Decode*`
functions in `ir/codec/json` when interoperability is required.

## Schemas

The `ir/schema` package embeds Morphir IR schema files (v1, v2, v3) and exposes
helpers for loading them. These can be used to validate external IR payloads
before decoding.

## SDK helpers

The `ir/sdk` package provides reusable IR definitions that represent common
standard library constructs (list, maybe, result, dict, time, etc.). These
helpers are useful when emitting IR from other tools.

## Versioning

This module is released independently with tags like `pkg/models/vX.Y.Z`. To
install a specific version:

```bash
go get github.com/finos/morphir/pkg/models@vX.Y.Z
```

## Documentation

- Package docs: `go doc github.com/finos/morphir/pkg/models`
- IR docs: `go doc github.com/finos/morphir/pkg/models/ir`
- Codec docs: `go doc github.com/finos/morphir/pkg/models/ir/codec/json`

## Contributing

When contributing changes to the models module, keep the Morphir IR
specification in mind and verify any structural changes against the JSON
schemas in `ir/schema`.
