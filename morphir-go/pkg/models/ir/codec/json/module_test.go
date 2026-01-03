package json

import (
	"encoding/json"
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestModuleSpecificationRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	// Create a module specification with a type and a value
	typeName := ir.NameFromParts([]string{"my", "type"})
	valueName := ir.NameFromParts([]string{"my", "value"})

	// Type specification: type alias
	typeSpec := ir.NewTypeAliasSpecification(
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	// Value specification: a function from Int to String
	valueSpec := ir.NewValueSpecification(
		[]ir.ValueSpecificationInput[unitAttr]{
			ir.ValueSpecificationInputFromParts(
				ir.NameFromParts([]string{"x"}),
				ir.NewTypeUnit[unitAttr](unitAttr{}),
			),
		},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	modSpec := ir.NewModuleSpecification(
		[]ir.ModuleSpecificationType[unitAttr]{
			ir.ModuleSpecificationTypeFromParts[unitAttr](
				typeName,
				ir.NewDocumented("Type documentation", typeSpec),
			),
		},
		[]ir.ModuleSpecificationValue[unitAttr]{
			ir.ModuleSpecificationValueFromParts[unitAttr](
				valueName,
				ir.NewDocumented("Value documentation", valueSpec),
			),
		},
		nil,
	)

	data, err := EncodeModuleSpecification(opts, encodeUnitAttr, modSpec)
	if err != nil {
		t.Fatalf("EncodeModuleSpecification: %v", err)
	}

	decoded, err := DecodeModuleSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeModuleSpecification: %v", err)
	}

	// Verify types
	if len(decoded.Types()) != 1 {
		t.Fatalf("expected 1 type, got %d", len(decoded.Types()))
	}
	if !decoded.Types()[0].Name().Equal(typeName) {
		t.Fatalf("type name mismatch")
	}
	if decoded.Types()[0].Spec().Doc() != "Type documentation" {
		t.Fatalf("type doc mismatch")
	}

	// Verify values
	if len(decoded.Values()) != 1 {
		t.Fatalf("expected 1 value, got %d", len(decoded.Values()))
	}
	if !decoded.Values()[0].Name().Equal(valueName) {
		t.Fatalf("value name mismatch")
	}
	if decoded.Values()[0].Spec().Doc() != "Value documentation" {
		t.Fatalf("value doc mismatch")
	}
}

func TestModuleDefinitionRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	typeName := ir.NameFromParts([]string{"my", "type"})
	valueName := ir.NameFromParts([]string{"my", "value"})

	// Type definition: type alias
	typeDef := ir.NewTypeAliasDefinition(
		[]ir.Name{ir.NameFromParts([]string{"a"})},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	// Value definition: simple unit value
	valueDef := ir.NewValueDefinition[unitAttr, unitAttr](
		[]ir.ValueDefinitionInput[unitAttr, unitAttr]{},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
		ir.NewUnitValue[unitAttr, unitAttr](unitAttr{}),
	)

	modDef := ir.NewModuleDefinition(
		[]ir.ModuleDefinitionType[unitAttr]{
			ir.ModuleDefinitionTypeFromParts[unitAttr](
				typeName,
				ir.Public(ir.NewDocumented("Type documentation", typeDef)),
			),
		},
		[]ir.ModuleDefinitionValue[unitAttr, unitAttr]{
			ir.ModuleDefinitionValueFromParts[unitAttr, unitAttr](
				valueName,
				ir.Private(ir.NewDocumented("Value documentation", valueDef)),
			),
		},
		nil,
	)

	data, err := EncodeModuleDefinition(opts, encodeUnitAttr, encodeValueUnitAttr, modDef)
	if err != nil {
		t.Fatalf("EncodeModuleDefinition: %v", err)
	}

	decoded, err := DecodeModuleDefinition(opts, decodeUnitAttr, decodeValueUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeModuleDefinition: %v", err)
	}

	// Verify types
	if len(decoded.Types()) != 1 {
		t.Fatalf("expected 1 type, got %d", len(decoded.Types()))
	}
	if !decoded.Types()[0].Name().Equal(typeName) {
		t.Fatalf("type name mismatch")
	}
	if decoded.Types()[0].Definition().Access() != ir.AccessPublic {
		t.Fatalf("type access mismatch: expected Public")
	}
	if decoded.Types()[0].Definition().Value().Doc() != "Type documentation" {
		t.Fatalf("type doc mismatch")
	}

	// Verify values
	if len(decoded.Values()) != 1 {
		t.Fatalf("expected 1 value, got %d", len(decoded.Values()))
	}
	if !decoded.Values()[0].Name().Equal(valueName) {
		t.Fatalf("value name mismatch")
	}
	if decoded.Values()[0].Definition().Access() != ir.AccessPrivate {
		t.Fatalf("value access mismatch: expected Private")
	}
	if decoded.Values()[0].Definition().Value().Doc() != "Value documentation" {
		t.Fatalf("value doc mismatch")
	}
}

func TestModuleSpecificationWithDoc(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	doc := "Module level documentation"
	modSpec := ir.NewModuleSpecification[unitAttr](nil, nil, &doc)

	data, err := EncodeModuleSpecification(opts, encodeUnitAttr, modSpec)
	if err != nil {
		t.Fatalf("EncodeModuleSpecification: %v", err)
	}

	decoded, err := DecodeModuleSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeModuleSpecification: %v", err)
	}

	if decoded.Doc() == nil {
		t.Fatalf("expected doc to be present")
	}
	if *decoded.Doc() != doc {
		t.Fatalf("doc mismatch: expected %q, got %q", doc, *decoded.Doc())
	}
}

func TestValueSpecificationRoundTripV3(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	// Create a value specification with inputs
	spec := ir.NewValueSpecification(
		[]ir.ValueSpecificationInput[unitAttr]{
			ir.ValueSpecificationInputFromParts(
				ir.NameFromParts([]string{"x"}),
				ir.NewTypeUnit[unitAttr](unitAttr{}),
			),
			ir.ValueSpecificationInputFromParts(
				ir.NameFromParts([]string{"y"}),
				ir.NewTypeUnit[unitAttr](unitAttr{}),
			),
		},
		ir.NewTypeUnit[unitAttr](unitAttr{}),
	)

	data, err := EncodeValueSpecification(opts, encodeUnitAttr, spec)
	if err != nil {
		t.Fatalf("EncodeValueSpecification: %v", err)
	}

	decoded, err := DecodeValueSpecification(opts, decodeUnitAttr, data)
	if err != nil {
		t.Fatalf("DecodeValueSpecification: %v", err)
	}

	if !ir.EqualValueSpecification(
		func(unitAttr, unitAttr) bool { return true },
		spec, decoded,
	) {
		t.Fatalf("expected structural equality after roundtrip")
	}
}

func TestDocumentedRoundTrip(t *testing.T) {
	opts := Options{FormatVersion: FormatV3}

	doc := ir.NewDocumented("Documentation string", ir.NewTypeUnit[unitAttr](unitAttr{}))

	encodeType := func(tpe ir.Type[unitAttr]) (json.RawMessage, error) {
		return EncodeType(opts, encodeUnitAttr, tpe)
	}

	data, err := EncodeDocumented(opts, encodeType, doc)
	if err != nil {
		t.Fatalf("EncodeDocumented: %v", err)
	}

	decodeType := func(raw json.RawMessage) (ir.Type[unitAttr], error) {
		return DecodeType(opts, decodeUnitAttr, raw)
	}

	decoded, err := DecodeDocumented(opts, decodeType, data)
	if err != nil {
		t.Fatalf("DecodeDocumented: %v", err)
	}

	if decoded.Doc() != "Documentation string" {
		t.Fatalf("doc mismatch: expected %q, got %q", "Documentation string", decoded.Doc())
	}
}
