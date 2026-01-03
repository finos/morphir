package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestNumberModuleName(t *testing.T) {
	name := NumberModuleName()
	expected := ir.PathFromString("Number")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestNumberModuleSpec(t *testing.T) {
	spec := NumberModuleSpec()

	// Check value specifications (should have 21 functions)
	values := spec.Values()
	if len(values) != 21 {
		t.Errorf("Expected 21 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"zero", "one", "fromInt",
		"equal", "notEqual", "lessThan", "lessThanOrEqual", "greaterThan", "greaterThanOrEqual",
		"add", "subtract", "multiply", "divide", "abs", "negate", "reciprocal",
		"toDecimal", "coerceToDecimal", "toFractionalString",
		"simplify", "isSimplified",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}
