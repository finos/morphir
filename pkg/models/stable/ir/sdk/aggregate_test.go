package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestAggregateModuleName(t *testing.T) {
	name := AggregateModuleName()
	expected := ir.PathFromString("Aggregate")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestAggregateModuleSpec(t *testing.T) {
	spec := AggregateModuleSpec()

	// Check that we have 1 type (Aggregation)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Aggregation type
	if types[0].Name().ToCamelCase() != "aggregation" {
		t.Errorf("Expected type 'aggregation', got %s", types[0].Name().ToCamelCase())
	}

	// Check that Aggregation type is opaque with 2 type parameters
	typeSpec := types[0].Spec().Value()
	if opaqueSpec, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); ok {
		params := opaqueSpec.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected Aggregation to have 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("Aggregation type should be an OpaqueTypeSpecification")
	}

	// Check value specifications (should have 14 functions)
	values := spec.Values()
	if len(values) != 14 {
		t.Errorf("Expected 14 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"count", "sumOf", "averageOf", "minimumOf", "maximumOf", "weightedAverageOf",
		"byKey", "withFilter",
		"aggregateMap", "aggregateMap2", "aggregateMap3", "aggregateMap4",
		"groupBy", "aggregate",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestAggregationTypeReference(t *testing.T) {
	// Test AggregationType helper
	aggT := AggregationType(intType(), StringType())

	if ref, ok := aggT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(AggregateModuleName(), "Aggregation")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// Aggregation should have 2 type parameters
		params := ref.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("AggregationType() should return a TypeReference")
	}
}

func TestCountFunction(t *testing.T) {
	spec := AggregateModuleSpec()
	values := spec.Values()

	// Find the "count" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "count" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 0 {
				t.Errorf("Expected 'count' to have 0 inputs, got %d", len(inputs))
			}

			// Output should be a function (Aggregator type)
			output := valueSpec.Output()
			if _, ok := output.(ir.TypeFunction[ir.Unit]); !ok {
				t.Error("count output should be a TypeFunction (Aggregator)")
			}

			return
		}
	}

	t.Error("'count' function not found in Aggregate module")
}

func TestSumOfFunction(t *testing.T) {
	spec := AggregateModuleSpec()
	values := spec.Values()

	// Find the "sumOf" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "sumOf" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'sumOf' to have 1 input, got %d", len(inputs))
			}

			// Input should be a function a -> Float
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("sumOf function argument should have an argument type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Output should be an Aggregator (function)
			output := valueSpec.Output()
			if _, ok := output.(ir.TypeFunction[ir.Unit]); !ok {
				t.Error("sumOf output should be a TypeFunction (Aggregator)")
			}

			return
		}
	}

	t.Error("'sumOf' function not found in Aggregate module")
}

func TestByKeyFunction(t *testing.T) {
	spec := AggregateModuleSpec()
	values := spec.Values()

	// Find the "byKey" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "byKey" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'byKey' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be a key extraction function
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("Key function should have an argument type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Second input should be Aggregation a key
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "aggregation" {
						t.Errorf("Expected second input type 'Aggregation', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be Aggregation a comparableKey
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "aggregation" {
					t.Errorf("Expected output type 'Aggregation', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'byKey' function not found in Aggregate module")
}

func TestGroupByFunction(t *testing.T) {
	spec := AggregateModuleSpec()
	values := spec.Values()

	// Find the "groupBy" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "groupBy" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'groupBy' to have 2 inputs, got %d", len(inputs))
			}

			// Output should be Dict comparableKey (List a)
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "dict" {
					t.Errorf("Expected output type 'Dict', got %s", fqn.LocalName().ToCamelCase())
				}

				// Dict should have 2 type parameters
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

	t.Error("'groupBy' function not found in Aggregate module")
}
