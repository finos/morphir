package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestIntModuleName(t *testing.T) {
	name := IntModuleName()
	expected := ir.PathFromString("Int")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestIntModuleSpec(t *testing.T) {
	spec := IntModuleSpec()

	// Check that we have 4 types (Int8, Int16, Int32, Int64)
	types := spec.Types()
	if len(types) != 4 {
		t.Errorf("Expected 4 types, got %d", len(types))
	}

	// Verify all types exist
	typeNames := make(map[string]bool)
	for _, typ := range types {
		typeNames[typ.Name().ToCamelCase()] = true
	}

	expectedTypes := []string{"int8", "int16", "int32", "int64"}
	for _, expected := range expectedTypes {
		if !typeNames[expected] {
			t.Errorf("Expected type %s not found", expected)
		}
	}

	// Check value specifications (should have 8 functions: from/to for each type)
	values := spec.Values()
	if len(values) != 8 {
		t.Errorf("Expected 8 value specifications, got %d", len(values))
	}

	// Verify all conversion functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"fromInt8", "toInt8",
		"fromInt16", "toInt16",
		"fromInt32", "toInt32",
		"fromInt64", "toInt64",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestIntTypeReferences(t *testing.T) {
	// Test all Int type helpers
	types := map[string]ir.Type[ir.Unit]{
		"Int8":  Int8Type(),
		"Int16": Int16Type(),
		"Int32": Int32Type(),
		"Int64": Int64Type(),
	}

	for name, typ := range types {
		if ref, ok := typ.(ir.TypeReference[ir.Unit]); ok {
			fqn := ref.FullyQualifiedName()
			expectedFQN := ToFQName(IntModuleName(), name)
			if !fqn.Equal(expectedFQN) {
				t.Errorf("Expected FQName %v for %s, got %v", expectedFQN, name, fqn)
			}
		} else {
			t.Errorf("%sType() should return a TypeReference", name)
		}
	}
}

func TestIntConversionFunctions(t *testing.T) {
	spec := IntModuleSpec()
	values := spec.Values()

	// Test fromInt8 function
	for _, val := range values {
		if val.Name().ToCamelCase() == "fromInt8" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'fromInt8' to have 1 input, got %d", len(inputs))
			}

			// Output should be Int
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "int" {
					t.Errorf("Expected output type 'Int', got %s", fqn.LocalName().ToCamelCase())
				}
			}
			break
		}
	}

	// Test toInt8 function
	for _, val := range values {
		if val.Name().ToCamelCase() == "toInt8" {
			valueSpec := val.Spec().Value()

			// Output should be Maybe Int8
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "maybe" {
					t.Errorf("Expected output type 'Maybe', got %s", fqn.LocalName().ToCamelCase())
				}

				// Check that it's parameterized by Int8
				params := typeRef.TypeParams()
				if len(params) != 1 {
					t.Errorf("Expected Maybe to have 1 type parameter, got %d", len(params))
				}
			}
			return
		}
	}
}
