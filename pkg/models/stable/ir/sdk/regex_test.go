package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestRegexModuleName(t *testing.T) {
	name := RegexModuleName()
	expected := ir.PathFromString("Regex")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestRegexModuleSpec(t *testing.T) {
	spec := RegexModuleSpec()

	// Check value specifications (should have 10 functions)
	values := spec.Values()
	if len(values) != 10 {
		t.Errorf("Expected 10 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"fromString", "fromStringWith", "never",
		"contains", "find", "findAtMost",
		"replace", "replaceAtMost",
		"split", "splitAtMost",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}
