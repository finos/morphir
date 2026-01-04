package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestDictModuleName(t *testing.T) {
	name := DictModuleName()
	expected := ir.PathFromString("Dict")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestDictModuleSpec(t *testing.T) {
	spec := DictModuleSpec()

	// Check that we have 1 type (Dict)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Dict type
	if types[0].Name().ToCamelCase() != "dict" {
		t.Errorf("Expected type 'dict', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Dict type is opaque with 2 type parameters
	typeSpec := types[0].Spec().Value()
	if opaqueSpec, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); ok {
		params := opaqueSpec.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected Dict to have 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("Dict type should be an OpaqueTypeSpecification")
	}

	// Check value specifications (should have 22 functions)
	values := spec.Values()
	if len(values) != 22 {
		t.Errorf("Expected 22 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		// Construction
		"empty", "singleton", "insert", "update", "remove",
		// Query
		"isEmpty", "member", "get", "size",
		// Lists
		"keys", "values", "toList", "fromList",
		// Transform
		"map", "foldl", "foldr", "filter", "partition",
		// Combine
		"union", "intersect", "diff", "merge",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestDictTypeReference(t *testing.T) {
	// Test DictType helper with String keys and Int values
	dictT := DictType(StringType(), intType())

	if ref, ok := dictT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(DictModuleName(), "Dict")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Dict should have 2 type parameters
		params := ref.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected 2 type parameters, got %d", len(params))
		}

		// First param should be String
		if len(params) > 0 {
			if typeRef, ok := params[0].(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "string" {
					t.Errorf("Expected first type parameter to be String, got %s", fqn.LocalName().ToCamelCase())
				}
			}
		}

		// Second param should be Int
		if len(params) > 1 {
			if typeRef, ok := params[1].(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "int" {
					t.Errorf("Expected second type parameter to be Int, got %s", fqn.LocalName().ToCamelCase())
				}
			}
		}
	} else {
		t.Error("DictType() should return a TypeReference")
	}
}

func TestDictEmptyFunction(t *testing.T) {
	spec := DictModuleSpec()
	values := spec.Values()

	// Find the "empty" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "empty" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 0 {
				t.Errorf("Expected 'empty' to have 0 inputs, got %d", len(inputs))
			}

			// Output should be Dict k v
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "dict" {
					t.Errorf("Expected output type 'Dict', got %s", fqn.LocalName().ToCamelCase())
				}

				// Should have 2 type parameters
				params := typeRef.TypeParams()
				if len(params) != 2 {
					t.Errorf("Expected Dict to have 2 type parameters, got %d", len(params))
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'empty' function not found in Dict module")
}

func TestDictGetFunction(t *testing.T) {
	spec := DictModuleSpec()
	values := spec.Values()

	// Find the "get" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "get" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'get' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be key of type k
			if len(inputs) > 0 {
				if typeVar, ok := inputs[0].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "k" {
						t.Errorf("Expected first input to be type variable 'k', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("First input should be a TypeVariable")
				}
			}

			// Second input should be Dict k v
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "dict" {
						t.Errorf("Expected second input type 'Dict', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeReference")
				}
			}

			// Output should be Maybe v
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "maybe" {
					t.Errorf("Expected output type 'Maybe', got %s", fqn.LocalName().ToCamelCase())
				}

				// Maybe should be parameterized by v
				params := typeRef.TypeParams()
				if len(params) != 1 {
					t.Errorf("Expected Maybe to have 1 type parameter, got %d", len(params))
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'get' function not found in Dict module")
}

func TestDictMapFunction(t *testing.T) {
	spec := DictModuleSpec()
	values := spec.Values()

	// Find the "map" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "map" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'map' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be function from (k, a) to b
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					// Verify it has argument and result
					if funcType.Argument() == nil {
						t.Error("Map function should have an argument type")
					}
					if funcType.Result() == nil {
						t.Error("Map function should have a result type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Second input should be Dict k a
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "dict" {
						t.Errorf("Expected second input type 'Dict', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeReference")
				}
			}

			// Output should be Dict k b
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "dict" {
					t.Errorf("Expected output type 'Dict', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'map' function not found in Dict module")
}

func TestDictMergeFunction(t *testing.T) {
	spec := DictModuleSpec()
	values := spec.Values()

	// Find the "merge" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "merge" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			// merge has 6 parameters
			if len(inputs) != 6 {
				t.Errorf("Expected 'merge' to have 6 inputs, got %d", len(inputs))
			}

			// First input should be leftOnly function
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("leftOnly function should have an argument type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Second input should be both function
			if len(inputs) > 1 {
				if funcType, ok := inputs[1].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("both function should have an argument type")
					}
				} else {
					t.Error("Second input should be a TypeFunction")
				}
			}

			// Third input should be rightOnly function
			if len(inputs) > 2 {
				if funcType, ok := inputs[2].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("rightOnly function should have an argument type")
					}
				} else {
					t.Error("Third input should be a TypeFunction")
				}
			}

			// Output should be result type variable
			output := valueSpec.Output()
			if typeVar, ok := output.(ir.TypeVariable[ir.Unit]); ok {
				if typeVar.Name().ToCamelCase() != "result" {
					t.Errorf("Expected output to be type variable 'result', got %s", typeVar.Name().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeVariable")
			}

			return
		}
	}

	t.Error("'merge' function not found in Dict module")
}
