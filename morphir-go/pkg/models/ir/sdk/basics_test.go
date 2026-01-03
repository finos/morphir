package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestBasicsModuleName(t *testing.T) {
	name := BasicsModuleName()
	expected := ir.PathFromString("Basics")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestBasicsModuleSpec(t *testing.T) {
	spec := BasicsModuleSpec()

	// Check that we have types
	types := spec.Types()
	if len(types) != 5 {
		t.Errorf("Expected 5 types, got %d", len(types))
	}

	// Check that Int, Float, Bool, Order, Never types are present
	typeNames := make(map[string]bool)
	for _, typ := range types {
		typeNames[typ.Name().ToCamelCase()] = true
	}

	expectedTypes := []string{"int", "float", "bool", "order", "never"}
	for _, expected := range expectedTypes {
		if !typeNames[expected] {
			t.Errorf("Expected type %s not found", expected)
		}
	}

	// Check Order type has 3 constructors (LT, EQ, GT)
	for _, typ := range types {
		if typ.Name().ToCamelCase() == "order" {
			typeSpec := typ.Spec().Value()
			if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
				ctors := customSpec.Constructors()
				if len(ctors) != 3 {
					t.Errorf("Expected Order type to have 3 constructors, got %d", len(ctors))
				}

				// Verify constructor names
				ctorNames := make(map[string]bool)
				for _, ctor := range ctors {
					ctorNames[ctor.Name().ToTitleCase()] = true
				}

				for _, expectedName := range []string{"LT", "EQ", "GT"} {
					if !ctorNames[expectedName] {
						t.Errorf("Expected constructor %s not found in Order type", expectedName)
					}
				}
			} else {
				t.Error("Order type should be a CustomTypeSpecification")
			}
		}
	}

	// Check that we have values (functions)
	values := spec.Values()
	if len(values) == 0 {
		t.Error("Expected some value specifications, got none")
	}

	// Verify some key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{"add", "subtract", "multiply", "equal", "lessThan", "and", "or", "not"}
	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestBasicsTypeReferences(t *testing.T) {
	// Test intType
	intT := intType()
	if ref, ok := intT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(BasicsModuleName(), "Int")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}
	} else {
		t.Error("intType() should return a TypeReference")
	}

	// Test floatType
	floatT := floatType()
	if ref, ok := floatT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(BasicsModuleName(), "Float")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}
	} else {
		t.Error("floatType() should return a TypeReference")
	}

	// Test boolType
	boolT := boolType()
	if ref, ok := boolT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(BasicsModuleName(), "Bool")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}
	} else {
		t.Error("boolType() should return a TypeReference")
	}
}

func TestValueSpecificationStructure(t *testing.T) {
	spec := BasicsModuleSpec()
	values := spec.Values()

	// Find the "add" function and verify its structure
	for _, val := range values {
		if val.Name().ToCamelCase() == "add" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'add' to have 2 inputs, got %d", len(inputs))
			}

			// Both inputs should be type variable "number"
			for i, input := range inputs {
				if typeVar, ok := input.Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "number" {
						t.Errorf("Expected input %d to be type variable 'number', got %s", i, typeVar.Name().ToCamelCase())
					}
				} else {
					t.Errorf("Expected input %d to be a TypeVariable", i)
				}
			}

			// Output should also be type variable "number"
			output := valueSpec.Output()
			if typeVar, ok := output.(ir.TypeVariable[ir.Unit]); ok {
				if typeVar.Name().ToCamelCase() != "number" {
					t.Errorf("Expected output to be type variable 'number', got %s", typeVar.Name().ToCamelCase())
				}
			} else {
				t.Error("Expected output to be a TypeVariable")
			}

			return
		}
	}

	t.Error("'add' function not found in Basics module")
}
