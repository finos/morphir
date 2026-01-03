package json

import (
	"encoding/json"
	"fmt"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// EncodePackageSpecification encodes a package specification to JSON.
func EncodePackageSpecification[TA any](
	opts Options,
	encodeTA func(TA) (json.RawMessage, error),
	spec ir.PackageSpecification[TA],
) (json.RawMessage, error) {
	modules := spec.Modules()
	moduleEntries := make([]json.RawMessage, 0, len(modules))

	for _, mod := range modules {
		nameJSON, err := EncodePath(opts, mod.Name())
		if err != nil {
			return nil, fmt.Errorf("encode module name: %w", err)
		}

		specJSON, err := EncodeModuleSpecification(opts, encodeTA, mod.Spec())
		if err != nil {
			return nil, fmt.Errorf("encode module spec: %w", err)
		}

		entry, err := json.Marshal([]json.RawMessage{nameJSON, specJSON})
		if err != nil {
			return nil, fmt.Errorf("encode module entry: %w", err)
		}
		moduleEntries = append(moduleEntries, entry)
	}

	result := map[string]interface{}{
		"modules": moduleEntries,
	}

	return json.Marshal(result)
}

// DecodePackageSpecification decodes a package specification from JSON.
func DecodePackageSpecification[TA any](
	opts Options,
	decodeTA func(json.RawMessage) (TA, error),
	data json.RawMessage,
) (ir.PackageSpecification[TA], error) {
	var raw struct {
		Modules []json.RawMessage `json:"modules"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return ir.EmptyPackageSpecification[TA](), fmt.Errorf("unmarshal package specification: %w", err)
	}

	modules := make([]ir.PackageSpecificationModule[TA], 0, len(raw.Modules))

	for i, entry := range raw.Modules {
		var pair []json.RawMessage
		if err := json.Unmarshal(entry, &pair); err != nil {
			return ir.EmptyPackageSpecification[TA](), fmt.Errorf("unmarshal module entry %d: %w", i, err)
		}
		if len(pair) != 2 {
			return ir.EmptyPackageSpecification[TA](), fmt.Errorf("module entry %d: expected 2 elements, got %d", i, len(pair))
		}

		name, err := DecodePath(opts, pair[0])
		if err != nil {
			return ir.EmptyPackageSpecification[TA](), fmt.Errorf("decode module name %d: %w", i, err)
		}

		spec, err := DecodeModuleSpecification(opts, decodeTA, pair[1])
		if err != nil {
			return ir.EmptyPackageSpecification[TA](), fmt.Errorf("decode module spec %d: %w", i, err)
		}

		modules = append(modules, ir.PackageSpecificationModuleFromParts(name, spec))
	}

	return ir.NewPackageSpecification(modules), nil
}

// EncodePackageDefinition encodes a package definition to JSON.
func EncodePackageDefinition[TA any, VA any](
	opts Options,
	encodeTA func(TA) (json.RawMessage, error),
	encodeVA func(VA) (json.RawMessage, error),
	def ir.PackageDefinition[TA, VA],
) (json.RawMessage, error) {
	modules := def.Modules()
	moduleEntries := make([]json.RawMessage, 0, len(modules))

	for _, mod := range modules {
		nameJSON, err := EncodePath(opts, mod.Name())
		if err != nil {
			return nil, fmt.Errorf("encode module name: %w", err)
		}

		// Encode module definition
		modDefJSON, err := EncodeModuleDefinition(opts, encodeTA, encodeVA, mod.Definition().Value())
		if err != nil {
			return nil, fmt.Errorf("encode module definition: %w", err)
		}

		// Wrap in access controlled
		acJSON, err := EncodeAccessControlled(opts, func(m ir.ModuleDefinition[TA, VA]) (json.RawMessage, error) {
			return modDefJSON, nil
		}, mod.Definition())
		if err != nil {
			return nil, fmt.Errorf("encode access controlled module: %w", err)
		}

		entry, err := json.Marshal([]json.RawMessage{nameJSON, acJSON})
		if err != nil {
			return nil, fmt.Errorf("encode module entry: %w", err)
		}
		moduleEntries = append(moduleEntries, entry)
	}

	result := map[string]interface{}{
		"modules": moduleEntries,
	}

	return json.Marshal(result)
}

// DecodePackageDefinition decodes a package definition from JSON.
func DecodePackageDefinition[TA any, VA any](
	opts Options,
	decodeTA func(json.RawMessage) (TA, error),
	decodeVA func(json.RawMessage) (VA, error),
	data json.RawMessage,
) (ir.PackageDefinition[TA, VA], error) {
	var raw struct {
		Modules []json.RawMessage `json:"modules"`
	}
	if err := json.Unmarshal(data, &raw); err != nil {
		return ir.EmptyPackageDefinition[TA, VA](), fmt.Errorf("unmarshal package definition: %w", err)
	}

	modules := make([]ir.PackageDefinitionModule[TA, VA], 0, len(raw.Modules))

	for i, entry := range raw.Modules {
		var pair []json.RawMessage
		if err := json.Unmarshal(entry, &pair); err != nil {
			return ir.EmptyPackageDefinition[TA, VA](), fmt.Errorf("unmarshal module entry %d: %w", i, err)
		}
		if len(pair) != 2 {
			return ir.EmptyPackageDefinition[TA, VA](), fmt.Errorf("module entry %d: expected 2 elements, got %d", i, len(pair))
		}

		name, err := DecodePath(opts, pair[0])
		if err != nil {
			return ir.EmptyPackageDefinition[TA, VA](), fmt.Errorf("decode module name %d: %w", i, err)
		}

		decodeModDef := func(raw json.RawMessage) (ir.ModuleDefinition[TA, VA], error) {
			return DecodeModuleDefinition(opts, decodeTA, decodeVA, raw)
		}

		ac, err := DecodeAccessControlled(opts, decodeModDef, pair[1])
		if err != nil {
			return ir.EmptyPackageDefinition[TA, VA](), fmt.Errorf("decode access controlled module %d: %w", i, err)
		}

		modules = append(modules, ir.PackageDefinitionModuleFromParts[TA, VA](name, ac))
	}

	return ir.NewPackageDefinition(modules), nil
}
