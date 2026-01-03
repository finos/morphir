package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestKeyModuleName(t *testing.T) {
	name := KeyModuleName()
	expected := ir.PathFromString("Key")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestKeyModuleSpec(t *testing.T) {
	spec := KeyModuleSpec()

	// Check that we have no types (using type aliases)
	types := spec.Types()
	if len(types) != 0 {
		t.Errorf("Expected 0 types, got %d", len(types))
	}

	// Check value specifications (should have 17 functions: noKey, key0, key2..key16)
	values := spec.Values()
	if len(values) != 17 {
		t.Errorf("Expected 17 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{"noKey", "key0", "key2", "key3", "key4", "key5", "key6", "key7", "key8", "key9", "key10", "key11", "key12", "key13", "key14", "key15", "key16"}
	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}
