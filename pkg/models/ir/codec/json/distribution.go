package json

import (
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// encodeUnit encodes a unit value to JSON (empty array).
func encodeUnit(ir.Unit) (json.RawMessage, error) {
	return json.RawMessage("[]"), nil
}

// decodeUnit decodes a unit value from JSON (empty array).
func decodeUnit(raw json.RawMessage) (ir.Unit, error) {
	var items []any
	if err := json.Unmarshal(raw, &items); err != nil {
		return ir.Unit{}, err
	}
	if len(items) != 0 {
		return ir.Unit{}, fmt.Errorf("expected empty array for unit, got %d elements", len(items))
	}
	return ir.Unit{}, nil
}

// EncodeDistribution encodes a distribution to JSON.
func EncodeDistribution(opts Options, dist ir.Distribution) (json.RawMessage, error) {
	switch d := dist.(type) {
	case ir.Library:
		return encodeLibrary(opts, d)
	default:
		return nil, fmt.Errorf("unknown distribution type: %T", dist)
	}
}

// encodeLibrary encodes a library distribution to JSON.
func encodeLibrary(opts Options, lib ir.Library) (json.RawMessage, error) {
	// Encode package name
	pkgNameJSON, err := EncodePath(opts, lib.PackageName())
	if err != nil {
		return nil, fmt.Errorf("encode package name: %w", err)
	}

	// Encode dependencies as list of [name, spec] tuples
	deps := lib.Dependencies()
	depEntries := make([]json.RawMessage, 0, len(deps))
	for _, dep := range deps {
		nameJSON, err := EncodePath(opts, dep.Name())
		if err != nil {
			return nil, fmt.Errorf("encode dependency name: %w", err)
		}

		specJSON, err := EncodePackageSpecification(opts, encodeUnit, dep.Spec())
		if err != nil {
			return nil, fmt.Errorf("encode dependency spec: %w", err)
		}

		entry, err := json.Marshal([]json.RawMessage{nameJSON, specJSON})
		if err != nil {
			return nil, fmt.Errorf("encode dependency entry: %w", err)
		}
		depEntries = append(depEntries, entry)
	}

	depsJSON, err := json.Marshal(depEntries)
	if err != nil {
		return nil, fmt.Errorf("encode dependencies: %w", err)
	}

	// Encode definition with unit for TA and Type[Unit] for VA
	defJSON, err := encodeLibraryDefinition(opts, lib.Definition())
	if err != nil {
		return nil, fmt.Errorf("encode definition: %w", err)
	}

	// Build the Library tuple: ["Library", packageName, dependencies, definition]
	result := []json.RawMessage{
		json.RawMessage(`"Library"`),
		pkgNameJSON,
		depsJSON,
		defJSON,
	}

	return json.Marshal(result)
}

// encodeLibraryDefinition encodes a library's package definition.
func encodeLibraryDefinition(opts Options, def ir.PackageDefinition[ir.Unit, ir.Type[ir.Unit]]) (json.RawMessage, error) {
	encodeVA := func(t ir.Type[ir.Unit]) (json.RawMessage, error) {
		return EncodeType(opts, encodeUnit, t)
	}
	return EncodePackageDefinition(opts, encodeUnit, encodeVA, def)
}

// DecodeDistribution decodes a distribution from JSON.
func DecodeDistribution(opts Options, data json.RawMessage) (ir.Distribution, error) {
	var tuple []json.RawMessage
	if err := json.Unmarshal(data, &tuple); err != nil {
		return nil, fmt.Errorf("unmarshal distribution tuple: %w", err)
	}

	if len(tuple) < 1 {
		return nil, fmt.Errorf("distribution tuple too short")
	}

	var tag string
	if err := json.Unmarshal(tuple[0], &tag); err != nil {
		return nil, fmt.Errorf("unmarshal distribution tag: %w", err)
	}

	switch tag {
	case "Library", "library":
		return decodeLibrary(opts, tuple)
	default:
		return nil, fmt.Errorf("unknown distribution tag: %s", tag)
	}
}

// decodeLibrary decodes a library distribution from JSON.
func decodeLibrary(opts Options, tuple []json.RawMessage) (ir.Library, error) {
	if len(tuple) != 4 {
		return ir.Library{}, fmt.Errorf("library tuple: expected 4 elements, got %d", len(tuple))
	}

	// Decode package name
	pkgName, err := DecodePath(opts, tuple[1])
	if err != nil {
		return ir.Library{}, fmt.Errorf("decode package name: %w", err)
	}

	// Decode dependencies
	var depEntries []json.RawMessage
	if err := json.Unmarshal(tuple[2], &depEntries); err != nil {
		return ir.Library{}, fmt.Errorf("unmarshal dependencies: %w", err)
	}

	deps := make([]ir.LibraryDependency, 0, len(depEntries))
	for i, entry := range depEntries {
		var pair []json.RawMessage
		if err := json.Unmarshal(entry, &pair); err != nil {
			return ir.Library{}, fmt.Errorf("unmarshal dependency %d: %w", i, err)
		}
		if len(pair) != 2 {
			return ir.Library{}, fmt.Errorf("dependency %d: expected 2 elements, got %d", i, len(pair))
		}

		name, err := DecodePath(opts, pair[0])
		if err != nil {
			return ir.Library{}, fmt.Errorf("decode dependency name %d: %w", i, err)
		}

		spec, err := DecodePackageSpecification(opts, decodeUnit, pair[1])
		if err != nil {
			return ir.Library{}, fmt.Errorf("decode dependency spec %d: %w", i, err)
		}

		deps = append(deps, ir.LibraryDependencyFromParts(name, spec))
	}

	// Decode definition
	def, err := decodeLibraryDefinition(opts, tuple[3])
	if err != nil {
		return ir.Library{}, fmt.Errorf("decode definition: %w", err)
	}

	return ir.NewLibrary(pkgName, deps, def), nil
}

// decodeLibraryDefinition decodes a library's package definition.
func decodeLibraryDefinition(opts Options, data json.RawMessage) (ir.PackageDefinition[ir.Unit, ir.Type[ir.Unit]], error) {
	decodeVA := func(raw json.RawMessage) (ir.Type[ir.Unit], error) {
		return DecodeType(opts, decodeUnit, raw)
	}
	return DecodePackageDefinition(opts, decodeUnit, decodeVA, data)
}
