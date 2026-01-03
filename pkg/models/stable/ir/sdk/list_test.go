package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestListModuleName(t *testing.T) {
	name := ListModuleName()
	expected := ir.PathFromString("List")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestListModuleSpec(t *testing.T) {
	spec := ListModuleSpec()

	// Check that we have the List type
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify List type
	if types[0].Name().ToCamelCase() != "list" {
		t.Errorf("Expected type 'list', got %s", types[0].Name().ToCamelCase())
	}

	// Check that List type is opaque with one type parameter
	typeSpec := types[0].Spec().Value()
	if opaqueSpec, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); ok {
		params := opaqueSpec.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected List type to have 1 type parameter, got %d", len(params))
		}
		if len(params) > 0 && params[0].ToCamelCase() != "a" {
			t.Errorf("Expected type parameter 'a', got %s", params[0].ToCamelCase())
		}
	} else {
		t.Error("List type should be an OpaqueTypeSpecification")
	}

	// Check that we have value specifications
	values := spec.Values()
	if len(values) == 0 {
		t.Error("Expected some value specifications, got none")
	}

	// Verify some key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"singleton", "repeat", "range", "cons",
		"map", "filter", "foldl", "foldr",
		"length", "reverse", "member",
		"all", "any", "maximum", "minimum",
		"sum", "product", "append", "concat",
		"head", "tail", "take", "drop",
		"sort", "sortBy", "sortWith",
		"isEmpty", "partition", "unzip",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestListTypeReference(t *testing.T) {
	// Test ListType helper
	elemType := TVar("a")
	listT := ListType(elemType)

	if ref, ok := listT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(ListModuleName(), "List")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Check type parameters
		params := ref.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected 1 type parameter, got %d", len(params))
		}
	} else {
		t.Error("ListType() should return a TypeReference")
	}
}

func TestListMapFunction(t *testing.T) {
	spec := ListModuleSpec()
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

			// Second input should be List a
			if len(inputs) > 1 {
				secondInput := inputs[1]
				if secondInput.Name().ToCamelCase() != "list" {
					t.Errorf("Expected second parameter name 'list', got %s", secondInput.Name().ToCamelCase())
				}

				// Should be a type reference to List
				if typeRef, ok := secondInput.Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "list" {
						t.Errorf("Expected type 'List', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Expected second parameter to be a TypeReference to List")
				}
			}

			// Output should be List b
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "list" {
					t.Errorf("Expected output type 'List', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Expected output to be a TypeReference to List")
			}

			return
		}
	}

	t.Error("'map' function not found in List module")
}

func TestListFoldlFunction(t *testing.T) {
	spec := ListModuleSpec()
	values := spec.Values()

	// Find the "foldl" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "foldl" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 3 {
				t.Errorf("Expected 'foldl' to have 3 inputs, got %d", len(inputs))
			}

			// Verify parameter names
			expectedNames := []string{"f", "acc", "list"}
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

	t.Error("'foldl' function not found in List module")
}
