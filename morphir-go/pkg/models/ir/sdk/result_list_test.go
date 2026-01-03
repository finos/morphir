package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestResultListModuleName(t *testing.T) {
	name := ResultListModuleName()
	expected := ir.PathFromString("ResultList")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestResultListModuleSpec(t *testing.T) {
	spec := ResultListModuleSpec()

	// Check that we have 1 type (ResultList type alias)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify ResultList type
	if types[0].Name().ToCamelCase() != "resultList" {
		t.Errorf("Expected type 'resultList', got %s", types[0].Name().ToCamelCase())
	}

	// Check that ResultList is a type alias
	typeSpec := types[0].Spec().Value()
	if aliasSpec, ok := typeSpec.(ir.TypeAliasSpecification[ir.Unit]); ok {
		// Should have 2 type parameters (e and a)
		params := aliasSpec.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected ResultList to have 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("ResultList should be a TypeAliasSpecification")
	}

	// Check value specifications (should have 10 functions)
	values := spec.Values()
	if len(values) != 10 {
		t.Errorf("Expected 10 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"fromList", "errors", "successes", "partition",
		"keepAllErrors", "keepFirstError",
		"map", "mapOrFail", "filter", "filterOrFail",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestResultListTypeReference(t *testing.T) {
	// Test ResultListType helper
	rlT := ResultListType(StringType(), intType())

	if ref, ok := rlT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(ResultListModuleName(), "ResultList")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// ResultList should have 2 type parameters
		params := ref.TypeParams()
		if len(params) != 2 {
			t.Errorf("Expected 2 type parameters, got %d", len(params))
		}
	} else {
		t.Error("ResultListType() should return a TypeReference")
	}
}

func TestFromListFunction(t *testing.T) {
	spec := ResultListModuleSpec()
	values := spec.Values()

	// Find the "fromList" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "fromList" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'fromList' to have 1 input, got %d", len(inputs))
			}

			// Input should be List a
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "list" {
						t.Errorf("Expected input type 'List', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be ResultList e a
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "resultList" {
					t.Errorf("Expected output type 'ResultList', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'fromList' function not found in ResultList module")
}

func TestMapOrFailFunction(t *testing.T) {
	spec := ResultListModuleSpec()
	values := spec.Values()

	// Find the "mapOrFail" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "mapOrFail" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'mapOrFail' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be a function a -> Result e b
			if len(inputs) > 0 {
				if funcType, ok := inputs[0].Type().(ir.TypeFunction[ir.Unit]); ok {
					if funcType.Argument() == nil {
						t.Error("Map function should have an argument type")
					}
					// Result should be Result e b
					if funcType.Result() == nil {
						t.Error("Map function should have a result type")
					}
				} else {
					t.Error("First input should be a TypeFunction")
				}
			}

			// Output should be ResultList e b
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "resultList" {
					t.Errorf("Expected output type 'ResultList', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'mapOrFail' function not found in ResultList module")
}

func TestKeepFirstErrorFunction(t *testing.T) {
	spec := ResultListModuleSpec()
	values := spec.Values()

	// Find the "keepFirstError" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "keepFirstError" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'keepFirstError' to have 1 input, got %d", len(inputs))
			}

			// Output should be Result e (List a)
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "result" {
					t.Errorf("Expected output type 'Result', got %s", fqn.LocalName().ToCamelCase())
				}

				// Result should have 2 type parameters
				params := typeRef.TypeParams()
				if len(params) != 2 {
					t.Errorf("Expected Result to have 2 type parameters, got %d", len(params))
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'keepFirstError' function not found in ResultList module")
}
