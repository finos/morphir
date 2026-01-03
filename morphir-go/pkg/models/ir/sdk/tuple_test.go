package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestTupleModuleName(t *testing.T) {
	name := TupleModuleName()
	expected := ir.PathFromString("Tuple")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestTupleModuleSpec(t *testing.T) {
	spec := TupleModuleSpec()

	// Check that we have no types (Tuple uses built-in tuple type)
	types := spec.Types()
	if len(types) != 0 {
		t.Errorf("Expected 0 types, got %d", len(types))
	}

	// Check value specifications (should have 6 functions)
	values := spec.Values()
	if len(values) != 6 {
		t.Errorf("Expected 6 value specifications, got %d", len(values))
	}

	// Verify all functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"pair", "first", "second",
		"mapFirst", "mapSecond", "mapBoth",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestTupleTypeHelper(t *testing.T) {
	// Test TupleType helper with Int and String
	tupleT := TupleType(intType(), StringType())

	if tuple, ok := tupleT.(ir.TypeTuple[ir.Unit]); ok {
		elements := tuple.Elements()
		if len(elements) != 2 {
			t.Errorf("Expected 2 tuple elements, got %d", len(elements))
		}

		// First element should be Int
		if ref, ok := elements[0].(ir.TypeReference[ir.Unit]); ok {
			fqn := ref.FullyQualifiedName()
			if fqn.LocalName().ToCamelCase() != "int" {
				t.Errorf("Expected first element type 'Int', got %s", fqn.LocalName().ToCamelCase())
			}
		} else {
			t.Error("First element should be a TypeReference")
		}

		// Second element should be String
		if ref, ok := elements[1].(ir.TypeReference[ir.Unit]); ok {
			fqn := ref.FullyQualifiedName()
			if fqn.LocalName().ToCamelCase() != "string" {
				t.Errorf("Expected second element type 'String', got %s", fqn.LocalName().ToCamelCase())
			}
		} else {
			t.Error("Second element should be a TypeReference")
		}
	} else {
		t.Error("TupleType() should return a TypeTuple")
	}
}

func TestTuplePairFunction(t *testing.T) {
	spec := TupleModuleSpec()
	values := spec.Values()

	// Find the "pair" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "pair" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'pair' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be type variable 'a'
			if len(inputs) > 0 {
				if typeVar, ok := inputs[0].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "a" {
						t.Errorf("Expected first input to be type variable 'a', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("First input should be a TypeVariable")
				}
			}

			// Second input should be type variable 'b'
			if len(inputs) > 1 {
				if typeVar, ok := inputs[1].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "b" {
						t.Errorf("Expected second input to be type variable 'b', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeVariable")
				}
			}

			// Output should be a tuple of (a, b)
			output := valueSpec.Output()
			if tuple, ok := output.(ir.TypeTuple[ir.Unit]); ok {
				elements := tuple.Elements()
				if len(elements) != 2 {
					t.Errorf("Expected output to be a 2-tuple, got %d elements", len(elements))
				}
			} else {
				t.Error("Output should be a TypeTuple")
			}

			return
		}
	}

	t.Error("'pair' function not found in Tuple module")
}

func TestTupleFirstFunction(t *testing.T) {
	spec := TupleModuleSpec()
	values := spec.Values()

	// Find the "first" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "first" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'first' to have 1 input, got %d", len(inputs))
			}

			// Input should be a tuple of (a, b)
			if len(inputs) > 0 {
				if tuple, ok := inputs[0].Type().(ir.TypeTuple[ir.Unit]); ok {
					elements := tuple.Elements()
					if len(elements) != 2 {
						t.Errorf("Expected input to be a 2-tuple, got %d elements", len(elements))
					}
				} else {
					t.Error("Input should be a TypeTuple")
				}
			}

			// Output should be type variable 'a'
			output := valueSpec.Output()
			if typeVar, ok := output.(ir.TypeVariable[ir.Unit]); ok {
				if typeVar.Name().ToCamelCase() != "a" {
					t.Errorf("Expected output to be type variable 'a', got %s", typeVar.Name().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeVariable")
			}

			return
		}
	}

	t.Error("'first' function not found in Tuple module")
}

func TestTupleMapBothFunction(t *testing.T) {
	spec := TupleModuleSpec()
	values := spec.Values()

	// Find the "mapBoth" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "mapBoth" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 3 {
				t.Errorf("Expected 'mapBoth' to have 3 inputs, got %d", len(inputs))
			}

			// First input should be function from 'a' to 'x'
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					// Verify it has argument and result
					if funcType.Argument() == nil {
						t.Error("First input function should have an argument type")
					}
					if funcType.Result() == nil {
						t.Error("First input function should have a result type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Second input should be function from 'b' to 'y'
			if len(inputs) > 1 {
				if funcType, ok := inputs[1].Type().(ir.TypeFunction[ir.Unit]); ok {
					// Verify it has argument and result
					if funcType.Argument() == nil {
						t.Error("Second input function should have an argument type")
					}
					if funcType.Result() == nil {
						t.Error("Second input function should have a result type")
					}
				} else {
					t.Error("Second input should be a TypeFunction")
				}
			}

			// Third input should be a tuple of (a, b)
			if len(inputs) > 2 {
				if tuple, ok := inputs[2].Type().(ir.TypeTuple[ir.Unit]); ok {
					elements := tuple.Elements()
					if len(elements) != 2 {
						t.Errorf("Expected third input to be a 2-tuple, got %d elements", len(elements))
					}
				} else {
					t.Error("Third input should be a TypeTuple")
				}
			}

			// Output should be a tuple of (x, y)
			output := valueSpec.Output()
			if tuple, ok := output.(ir.TypeTuple[ir.Unit]); ok {
				elements := tuple.Elements()
				if len(elements) != 2 {
					t.Errorf("Expected output to be a 2-tuple, got %d elements", len(elements))
				}
			} else {
				t.Error("Output should be a TypeTuple")
			}

			return
		}
	}

	t.Error("'mapBoth' function not found in Tuple module")
}
