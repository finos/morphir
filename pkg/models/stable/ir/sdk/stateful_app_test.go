package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestStatefulAppModuleName(t *testing.T) {
	name := StatefulAppModuleName()
	expected := ir.PathFromString("StatefulApp")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestStatefulAppModuleSpec(t *testing.T) {
	spec := StatefulAppModuleSpec()

	// Check that we have 1 type (StatefulApp)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify StatefulApp type
	if types[0].Name().ToCamelCase() != "statefulApp" {
		t.Errorf("Expected type 'statefulApp', got %s", types[0].Name().ToCamelCase())
	}

	// Check that StatefulApp is a custom type with 4 type parameters
	typeSpec := types[0].Spec().Value()
	if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
		params := customSpec.TypeParams()
		if len(params) != 4 {
			t.Errorf("Expected StatefulApp to have 4 type parameters, got %d", len(params))
		}

		// Verify type parameter names (k, c, s, e)
		expectedParams := []string{"k", "c", "s", "e"}
		for i, expected := range expectedParams {
			if i >= len(params) {
				break
			}
			actualName := params[i].ToCamelCase()
			if actualName != expected {
				t.Errorf("Expected type parameter %s at position %d, got %s", expected, i, actualName)
			}
		}

		// Check constructor
		constructors := customSpec.Constructors()
		if len(constructors) != 1 {
			t.Errorf("Expected StatefulApp to have 1 constructor, got %d", len(constructors))
		}

		if len(constructors) > 0 {
			// Verify constructor name
			if constructors[0].Name().ToCamelCase() != "statefulApp" {
				t.Errorf("Expected constructor name 'statefulApp', got %s", constructors[0].Name().ToCamelCase())
			}

			// Verify constructor has one argument (the logic function)
			args := constructors[0].Args()
			if len(args) != 1 {
				t.Errorf("Expected StatefulApp constructor to have 1 argument, got %d", len(args))
			}

			if len(args) > 0 {
				// Verify argument name
				if args[0].Name().ToCamelCase() != "logic" {
					t.Errorf("Expected argument name 'logic', got %s", args[0].Name().ToCamelCase())
				}

				// Verify argument type is a function
				if _, ok := args[0].Type().(ir.TypeFunction[ir.Unit]); !ok {
					t.Error("logic argument should be a TypeFunction")
				}
			}
		}
	} else {
		t.Error("StatefulApp type should be a CustomTypeSpecification")
	}

	// Check value specifications (should have 0 functions)
	values := spec.Values()
	if len(values) != 0 {
		t.Errorf("Expected 0 value specifications, got %d", len(values))
	}
}

func TestStatefulAppTypeReference(t *testing.T) {
	// Test StatefulAppType helper with String, Int, Float, Bool
	appT := StatefulAppType(StringType(), intType(), floatType(), boolType())

	if ref, ok := appT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(StatefulAppModuleName(), "StatefulApp")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// StatefulApp should have 4 type parameters
		params := ref.TypeParams()
		if len(params) != 4 {
			t.Errorf("Expected 4 type parameters, got %d", len(params))
		}

		// Verify type parameters are in the correct order
		expectedTypes := []string{"string", "int", "float", "bool"}
		for i, expected := range expectedTypes {
			if i >= len(params) {
				break
			}
			if typeRef, ok := params[i].(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != expected {
					t.Errorf("Expected type parameter %d to be %s, got %s", i, expected, fqn.LocalName().ToCamelCase())
				}
			}
		}
	} else {
		t.Error("StatefulAppType() should return a TypeReference")
	}
}
