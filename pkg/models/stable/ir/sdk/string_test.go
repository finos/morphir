package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestStringModuleName(t *testing.T) {
	name := StringModuleName()
	expected := ir.PathFromString("String")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestStringModuleSpec(t *testing.T) {
	spec := StringModuleSpec()

	// Check that we have the String type
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify String type
	if types[0].Name().ToCamelCase() != "string" {
		t.Errorf("Expected type 'string', got %s", types[0].Name().ToCamelCase())
	}

	// Check that String type is opaque
	typeSpec := types[0].Spec().Value()
	if _, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); !ok {
		t.Error("String type should be an OpaqueTypeSpecification")
	}

	// Check value specifications
	values := spec.Values()
	if len(values) == 0 {
		t.Error("Expected some value specifications, got none")
	}

	// Should have ~42 functions
	if len(values) < 40 {
		t.Errorf("Expected at least 40 functions, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"isEmpty", "length", "reverse", "repeat", "replace",
		"append", "concat", "split", "join", "words", "lines",
		"slice", "left", "right", "dropLeft", "dropRight",
		"contains", "startsWith", "endsWith", "indexes", "indices",
		"toInt", "fromInt", "toFloat", "fromFloat", "fromChar",
		"cons", "uncons", "toList", "fromList",
		"toUpper", "toLower",
		"pad", "padLeft", "padRight", "trim", "trimLeft", "trimRight",
		"map", "filter", "foldl", "foldr", "any", "all",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestStringTypeReference(t *testing.T) {
	// Test StringType helper
	stringT := StringType()

	if ref, ok := stringT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(StringModuleName(), "String")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// String type should have no type parameters
		params := ref.TypeParams()
		if len(params) != 0 {
			t.Errorf("Expected 0 type parameters, got %d", len(params))
		}
	} else {
		t.Error("StringType() should return a TypeReference")
	}
}

func TestStringConcatFunction(t *testing.T) {
	spec := StringModuleSpec()
	values := spec.Values()

	// Find the "concat" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "concat" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'concat' to have 1 input, got %d", len(inputs))
			}

			// Input should be List String
			if len(inputs) > 0 {
				firstInput := inputs[0]
				if typeRef, ok := firstInput.Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "list" {
						t.Errorf("Expected input type 'List', got %s", fqn.LocalName().ToCamelCase())
					}

					// List should be parameterized by String
					params := typeRef.TypeParams()
					if len(params) != 1 {
						t.Errorf("Expected List to have 1 type parameter, got %d", len(params))
					}
				}
			}

			// Output should be String
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "string" {
					t.Errorf("Expected output type 'String', got %s", fqn.LocalName().ToCamelCase())
				}
			}

			return
		}
	}

	t.Error("'concat' function not found in String module")
}
