package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestRuleModuleName(t *testing.T) {
	name := RuleModuleName()
	expected := ir.PathFromString("Rule")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestRuleModuleSpec(t *testing.T) {
	spec := RuleModuleSpec()

	// Check that we have no types
	types := spec.Types()
	if len(types) != 0 {
		t.Errorf("Expected 0 types, got %d", len(types))
	}

	// Check value specifications (should have 5 functions)
	values := spec.Values()
	if len(values) != 5 {
		t.Errorf("Expected 5 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"chain", "any", "is", "anyOf", "noneOf",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestChainFunction(t *testing.T) {
	spec := RuleModuleSpec()
	values := spec.Values()

	// Find the "chain" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "chain" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'chain' to have 1 input, got %d", len(inputs))
			}

			// Input should be List (a -> Maybe b)
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "list" {
						t.Errorf("Expected input type 'List', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be a function (Rule type: a -> Maybe b)
			output := valueSpec.Output()
			if _, ok := output.(ir.TypeFunction[ir.Unit]); !ok {
				t.Error("chain output should be a TypeFunction (Rule)")
			}

			return
		}
	}

	t.Error("'chain' function not found in Rule module")
}

func TestAnyFunction(t *testing.T) {
	spec := RuleModuleSpec()
	values := spec.Values()

	// Find the "any" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "any" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'any' to have 1 input, got %d", len(inputs))
			}

			// Input should be type variable 'a'
			if len(inputs) > 0 {
				if typeVar, ok := inputs[0].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "a" {
						t.Errorf("Expected input to be type variable 'a', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("Input should be a TypeVariable")
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

	t.Error("'any' function not found in Rule module")
}

func TestIsFunction(t *testing.T) {
	spec := RuleModuleSpec()
	values := spec.Values()

	// Find the "is" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "is" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'is' to have 2 inputs, got %d", len(inputs))
			}

			// Both inputs should be type variable 'a'
			for i := 0; i < 2; i++ {
				if i >= len(inputs) {
					break
				}
				if typeVar, ok := inputs[i].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "a" {
						t.Errorf("Expected input %d to be type variable 'a', got %s", i, typeVar.Name().ToCamelCase())
					}
				} else {
					t.Errorf("Input %d should be a TypeVariable", i)
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

	t.Error("'is' function not found in Rule module")
}

func TestAnyOfFunction(t *testing.T) {
	spec := RuleModuleSpec()
	values := spec.Values()

	// Find the "anyOf" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "anyOf" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'anyOf' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be List a
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "list" {
						t.Errorf("Expected first input type 'List', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Second input should be type variable 'a'
			if len(inputs) > 1 {
				if typeVar, ok := inputs[1].Type().(ir.TypeVariable[ir.Unit]); ok {
					if typeVar.Name().ToCamelCase() != "a" {
						t.Errorf("Expected second input to be type variable 'a', got %s", typeVar.Name().ToCamelCase())
					}
				} else {
					t.Error("Second input should be a TypeVariable")
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

	t.Error("'anyOf' function not found in Rule module")
}
