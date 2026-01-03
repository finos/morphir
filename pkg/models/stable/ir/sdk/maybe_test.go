package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestMaybeModuleName(t *testing.T) {
	name := MaybeModuleName()
	expected := ir.PathFromString("Maybe")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestMaybeModuleSpec(t *testing.T) {
	spec := MaybeModuleSpec()

	// Check that we have the Maybe type
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Maybe type
	if types[0].Name().ToCamelCase() != "maybe" {
		t.Errorf("Expected type 'maybe', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Maybe type is a custom type with Just and Nothing constructors
	typeSpec := types[0].Spec().Value()
	if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
		// Check type parameters
		params := customSpec.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected Maybe type to have 1 type parameter, got %d", len(params))
		}
		if len(params) > 0 && params[0].ToCamelCase() != "a" {
			t.Errorf("Expected type parameter 'a', got %s", params[0].ToCamelCase())
		}

		// Check constructors
		ctors := customSpec.Constructors()
		if len(ctors) != 2 {
			t.Errorf("Expected Maybe type to have 2 constructors, got %d", len(ctors))
		}

		// Verify constructor names
		ctorNames := make(map[string]bool)
		for _, ctor := range ctors {
			ctorNames[ctor.Name().ToTitleCase()] = true
		}

		for _, expectedName := range []string{"Just", "Nothing"} {
			if !ctorNames[expectedName] {
				t.Errorf("Expected constructor %s not found in Maybe type", expectedName)
			}
		}

		// Verify Just constructor has one argument
		for _, ctor := range ctors {
			if ctor.Name().ToTitleCase() == "Just" {
				args := ctor.Args()
				if len(args) != 1 {
					t.Errorf("Expected Just constructor to have 1 argument, got %d", len(args))
				}
				if len(args) > 0 {
					// Argument should be type variable 'a'
					if typeVar, ok := args[0].Type().(ir.TypeVariable[ir.Unit]); ok {
						if typeVar.Name().ToCamelCase() != "a" {
							t.Errorf("Expected Just argument to be type 'a', got %s", typeVar.Name().ToCamelCase())
						}
					} else {
						t.Error("Expected Just argument to be a type variable")
					}
				}
			}
		}

		// Verify Nothing constructor has no arguments
		for _, ctor := range ctors {
			if ctor.Name().ToTitleCase() == "Nothing" {
				args := ctor.Args()
				if len(args) != 0 {
					t.Errorf("Expected Nothing constructor to have 0 arguments, got %d", len(args))
				}
			}
		}
	} else {
		t.Error("Maybe type should be a CustomTypeSpecification")
	}

	// Check that we have value specifications
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
		"withDefault", "hasValue",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestMaybeTypeReference(t *testing.T) {
	// Test MaybeType helper
	valueType := TVar("a")
	maybeT := MaybeType(valueType)

	if ref, ok := maybeT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(MaybeModuleName(), "Maybe")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Check type parameters
		params := ref.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected 1 type parameter, got %d", len(params))
		}
	} else {
		t.Error("MaybeType() should return a TypeReference")
	}
}

func TestMaybeMapFunction(t *testing.T) {
	spec := MaybeModuleSpec()
	values := spec.Values()

	// Find the "map" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "map" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'map' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be a function (a -> b)
			if len(inputs) > 0 {
				firstInput := inputs[0]
				if firstInput.Name().ToCamelCase() != "f" {
					t.Errorf("Expected first parameter name 'f', got %s", firstInput.Name().ToCamelCase())
				}

				// Should be a function type
				if _, ok := firstInput.Type().(ir.TypeFunction[ir.Unit]); !ok {
					t.Error("Expected first parameter to be a function type")
				}
			}

			// Second input should be Maybe a
			if len(inputs) > 1 {
				secondInput := inputs[1]
				if secondInput.Name().ToCamelCase() != "maybe" {
					t.Errorf("Expected second parameter name 'maybe', got %s", secondInput.Name().ToCamelCase())
				}

				// Should be a type reference to Maybe
				if typeRef, ok := secondInput.Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "maybe" {
						t.Errorf("Expected type 'Maybe', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Expected second parameter to be a TypeReference to Maybe")
				}
			}

			// Output should be Maybe b
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "maybe" {
					t.Errorf("Expected output type 'Maybe', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Expected output to be a TypeReference to Maybe")
			}

			return
		}
	}

	t.Error("'map' function not found in Maybe module")
}

func TestMaybeWithDefaultFunction(t *testing.T) {
	spec := MaybeModuleSpec()
	values := spec.Values()

	// Find the "withDefault" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "withDefault" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'withDefault' to have 2 inputs, got %d", len(inputs))
			}

			// Verify parameter names
			expectedNames := []string{"default", "maybe"}
			for i, expectedName := range expectedNames {
				if i < len(inputs) {
					actualName := inputs[i].Name().ToCamelCase()
					if actualName != expectedName {
						t.Errorf("Expected parameter %d to be named '%s', got '%s'", i, expectedName, actualName)
					}
				}
			}

			// Output should be type 'a' (not Maybe a)
			output := valueSpec.Output()
			if typeVar, ok := output.(ir.TypeVariable[ir.Unit]); ok {
				if typeVar.Name().ToCamelCase() != "a" {
					t.Errorf("Expected output to be type variable 'a', got %s", typeVar.Name().ToCamelCase())
				}
			} else {
				t.Error("Expected output to be a TypeVariable")
			}

			return
		}
	}

	t.Error("'withDefault' function not found in Maybe module")
}
