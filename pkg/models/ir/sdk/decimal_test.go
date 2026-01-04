package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestDecimalModuleName(t *testing.T) {
	name := DecimalModuleName()
	expected := ir.PathFromString("Decimal")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestDecimalModuleSpec(t *testing.T) {
	spec := DecimalModuleSpec()

	// Check that we have 1 type (Decimal)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Decimal type
	if types[0].Name().ToCamelCase() != "decimal" {
		t.Errorf("Expected type 'decimal', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Decimal type is opaque
	typeSpec := types[0].Spec().Value()
	if _, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); !ok {
		t.Error("Decimal type should be an OpaqueTypeSpecification")
	}

	// Check value specifications (should have 34 functions)
	values := spec.Values()
	if len(values) != 34 {
		t.Errorf("Expected 34 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		// Constants
		"zero", "one", "minusOne",
		// Constructors
		"fromInt", "fromFloat", "fromString",
		// Scale helpers
		"hundred", "thousand", "million", "tenth", "hundredth", "thousandth", "millionth", "bps",
		// Conversions
		"toString", "toFloat",
		// Arithmetic
		"add", "sub", "mul", "div", "divWithDefault", "negate", "abs",
		// Rounding
		"truncate", "round",
		// Comparison
		"gt", "gte", "eq", "neq", "lt", "lte", "compare",
		// Manipulation
		"shiftDecimalLeft", "shiftDecimalRight",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestDecimalTypeReference(t *testing.T) {
	// Test DecimalType helper
	decT := DecimalType()

	if ref, ok := decT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(DecimalModuleName(), "Decimal")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Decimal should have no type parameters
		params := ref.TypeParams()
		if len(params) != 0 {
			t.Errorf("Expected 0 type parameters, got %d", len(params))
		}
	} else {
		t.Error("DecimalType() should return a TypeReference")
	}
}
