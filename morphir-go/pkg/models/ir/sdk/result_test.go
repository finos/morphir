package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestResultModuleName(t *testing.T) {
	name := ResultModuleName()
	expected := ir.PathFromString("Result")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestResultModuleSpec(t *testing.T) {
	spec := ResultModuleSpec()

	// Check that we have the Result type
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Result type
	if types[0].Name().ToCamelCase() != "result" {
		t.Errorf("Expected type 'result', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Result type is a custom type with Ok and Err constructors
	typeSpec := types[0].Spec().Value()
	if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
		// Check type parameters (should have 2: error and value)
		params := customSpec.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected Result type to have 2 type parameters, got %d", len(params))
		}
		if len(params) >= 2 {
			if params[0].ToCamelCase() != "e" {
				t.Errorf("Expected first type parameter 'e', got %s", params[0].ToCamelCase())
			}
			if params[1].ToCamelCase() != "a" {
				t.Errorf("Expected second type parameter 'a', got %s", params[1].ToCamelCase())
			}
		}

		// Check constructors
		ctors := customSpec.Constructors()
		if len(ctors) != 2 {
			t.Errorf("Expected Result type to have 2 constructors, got %d", len(ctors))
		}

		// Verify constructor names
		ctorNames := make(map[string]bool)
		for _, ctor := range ctors {
			ctorNames[ctor.Name().ToTitleCase()] = true
		}

		for _, expectedName := range []string{"Ok", "Err"} {
			if !ctorNames[expectedName] {
				t.Errorf("Expected constructor %s not found in Result type", expectedName)
			}
		}

		// Verify Ok constructor has one argument of type 'a'
		for _, ctor := range ctors {
			if ctor.Name().ToTitleCase() == "Ok" {
				args := ctor.Args()
				if len(args) != 1 {
					t.Errorf("Expected Ok constructor to have 1 argument, got %d", len(args))
				}
				if len(args) > 0 {
					if typeVar, ok := args[0].Type().(ir.TypeVariable[ir.Unit]); ok {
						if typeVar.Name().ToCamelCase() != "a" {
							t.Errorf("Expected Ok argument to be type 'a', got %s", typeVar.Name().ToCamelCase())
						}
					}
				}
			}
		}

		// Verify Err constructor has one argument of type 'e'
		for _, ctor := range ctors {
			if ctor.Name().ToTitleCase() == "Err" {
				args := ctor.Args()
				if len(args) != 1 {
					t.Errorf("Expected Err constructor to have 1 argument, got %d", len(args))
				}
				if len(args) > 0 {
					if typeVar, ok := args[0].Type().(ir.TypeVariable[ir.Unit]); ok {
						if typeVar.Name().ToCamelCase() != "e" {
							t.Errorf("Expected Err argument to be type 'e', got %s", typeVar.Name().ToCamelCase())
						}
					}
				}
			}
		}
	} else {
		t.Error("Result type should be a CustomTypeSpecification")
	}

	// Check value specifications
	values := spec.Values()
	if len(values) == 0 {
		t.Error("Expected some value specifications, got none")
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"andThen", "map", "map2", "map3", "map4", "map5",
		"mapError", "withDefault", "toMaybe", "fromMaybe",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestResultTypeReference(t *testing.T) {
	// Test ResultType helper
	errorType := TVar("e")
	valueType := TVar("a")
	resultT := ResultType(errorType, valueType)

	if ref, ok := resultT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(ResultModuleName(), "Result")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Check type parameters (should have 2)
		params := ref.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("ResultType() should return a TypeReference")
	}
}

func TestResultMapFunction(t *testing.T) {
	spec := ResultModuleSpec()
	values := spec.Values()

	// Find the "map" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "map" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'map' to have 2 inputs, got %d", len(inputs))
			}

			// Verify parameter names
			expectedNames := []string{"f", "result"}
			for i, expectedName := range expectedNames {
				if i < len(inputs) {
					actualName := inputs[i].Name().ToCamelCase()
					if actualName != expectedName {
						t.Errorf("Expected parameter %d to be named '%s', got '%s'", i, expectedName, actualName)
					}
				}
			}

			return
		}
	}

	t.Error("'map' function not found in Result module")
}

func TestResultMapErrorFunction(t *testing.T) {
	spec := ResultModuleSpec()
	values := spec.Values()

	// Find the "mapError" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "mapError" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'mapError' to have 2 inputs, got %d", len(inputs))
			}

			// Output should be Result y a (error type changed)
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				params := typeRef.TypeParams()
				if len(params) != 2 {
					t.Errorf("Expected output to have 2 type parameters, got %d", len(params))
				}
				// First param should be 'y', second should be 'a'
				if len(params) >= 2 {
					if typeVar, ok := params[0].(ir.TypeVariable[ir.Unit]); ok {
						if typeVar.Name().ToCamelCase() != "y" {
							t.Errorf("Expected first type parameter 'y', got %s", typeVar.Name().ToCamelCase())
						}
					}
					if typeVar, ok := params[1].(ir.TypeVariable[ir.Unit]); ok {
						if typeVar.Name().ToCamelCase() != "a" {
							t.Errorf("Expected second type parameter 'a', got %s", typeVar.Name().ToCamelCase())
						}
					}
				}
			}

			return
		}
	}

	t.Error("'mapError' function not found in Result module")
}
