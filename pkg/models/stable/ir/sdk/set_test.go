package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestSetModuleName(t *testing.T) {
	name := SetModuleName()
	expected := ir.PathFromString("Set")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestSetModuleSpec(t *testing.T) {
	spec := SetModuleSpec()

	// Check that we have 1 type (Set)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Set type
	if types[0].Name().ToCamelCase() != "set" {
		t.Errorf("Expected type 'set', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Set type is opaque with 1 type parameter
	typeSpec := types[0].Spec().Value()
	if opaqueSpec, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); ok {
		params := opaqueSpec.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected Set to have 1 type parameter, got %d", len(params))
		}
	} else {
		t.Error("Set type should be an OpaqueTypeSpecification")
	}

	// Check value specifications (should have 17 functions)
	values := spec.Values()
	if len(values) != 17 {
		t.Errorf("Expected 17 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		// Construction
		"empty", "singleton", "insert", "remove",
		// Query
		"isEmpty", "member", "size",
		// Combine
		"union", "intersect", "diff",
		// Lists
		"toList", "fromList",
		// Transform
		"map", "foldl", "foldr", "filter", "partition",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestSetTypeReference(t *testing.T) {
	// Test SetType helper with Int
	setT := SetType(intType())

	if ref, ok := setT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(SetModuleName(), "Set")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Set should have 1 type parameter
		params := ref.TypeParams()
		if len(params) != 1 {
			t.Errorf("Expected 1 type parameter, got %d", len(params))
		}

		// Param should be Int
		if len(params) > 0 {
			if typeRef, ok := params[0].(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "int" {
					t.Errorf("Expected type parameter to be Int, got %s", fqn.LocalName().ToCamelCase())
				}
			}
		}
	} else {
		t.Error("SetType() should return a TypeReference")
	}
}

func TestSetEmptyFunction(t *testing.T) {
	spec := SetModuleSpec()
	values := spec.Values()

	// Find the "empty" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "empty" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 0 {
				t.Errorf("Expected 'empty' to have 0 inputs, got %d", len(inputs))
			}

			// Output should be Set t
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "set" {
					t.Errorf("Expected output type 'Set', got %s", fqn.LocalName().ToCamelCase())
				}

				// Should have 1 type parameter
				params := typeRef.TypeParams()
				if len(params) != 1 {
					t.Errorf("Expected Set to have 1 type parameter, got %d", len(params))
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'empty' function not found in Set module")
}

func TestSetMemberFunction(t *testing.T) {
	spec := SetModuleSpec()
	values := spec.Values()

	// Find the "member" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "member" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'member' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be value of type t
			if len(inputs) > 0 {
				if typeVar, ok := inputs[0].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "t" {
						t.Errorf("Expected first input to be type variable 't', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("First input should be a TypeVariable")
				}
			}

			// Second input should be Set t
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "set" {
						t.Errorf("Expected second input type 'Set', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeReference")
				}
			}

			// Output should be Bool
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "bool" {
					t.Errorf("Expected output type 'Bool', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'member' function not found in Set module")
}

func TestSetMapFunction(t *testing.T) {
	spec := SetModuleSpec()
	values := spec.Values()

	// Find the "map" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "map" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'map' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be function from a to b
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

			// Second input should be Set a
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "set" {
						t.Errorf("Expected second input type 'Set', got %s", fqn.LocalName().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeReference")
				}
			}

			// Output should be Set b
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "set" {
					t.Errorf("Expected output type 'Set', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'map' function not found in Set module")
}

func TestSetPartitionFunction(t *testing.T) {
	spec := SetModuleSpec()
	values := spec.Values()

	// Find the "partition" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "partition" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'partition' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be predicate function
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("Predicate function should have an argument type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Output should be a tuple of (Set t, Set t)
			output := valueSpec.Output()
			if tuple, ok := output.(ir.TypeTuple[ir.Unit]); ok {
				elements := tuple.Elements()
				if len(elements) != 2 {
					t.Errorf("Expected output to be a 2-tuple, got %d elements", len(elements))
				}

				// Both elements should be Set types
				for i, elem := range elements {
					if typeRef, ok := elem.(ir.TypeReference[ir.Unit]); ok {
						fqn := typeRef.FullyQualifiedName()
						if fqn.LocalName().ToCamelCase() != "set" {
							t.Errorf("Expected tuple element %d to be Set, got %s", i, fqn.LocalName().ToCamelCase())
						}
					} else {
						t.Errorf("Tuple element %d should be a TypeReference", i)
					}
				}
			} else {
				t.Error("Output should be a TypeTuple")
			}

			return
		}
	}

	t.Error("'partition' function not found in Set module")
}
