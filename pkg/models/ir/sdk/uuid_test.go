package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestUUIDModuleName(t *testing.T) {
	name := UUIDModuleName()
	expected := ir.PathFromString("UUID")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestUUIDModuleSpec(t *testing.T) {
	spec := UUIDModuleSpec()

	// Check that we have 2 types (UUID and Error)
	types := spec.Types()
	if len(types) != 2 {
		t.Errorf("Expected 2 types, got %d", len(types))
	}

	// Check value specifications (should have 12 functions)
	values := spec.Values()
	if len(values) != 12 {
		t.Errorf("Expected 12 value specifications, got %d", len(values))
	}
}

func TestUUIDTypeReference(t *testing.T) {
	uuidT := UUIDType()

	if ref, ok := uuidT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(UUIDModuleName(), "UUID")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}
	} else {
		t.Error("UUIDType() should return a TypeReference")
	}
}
