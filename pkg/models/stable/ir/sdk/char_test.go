package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

func TestCharModuleName(t *testing.T) {
	name := CharModuleName()
	expected := ir.PathFromString("Char")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestCharModuleSpec(t *testing.T) {
	spec := CharModuleSpec()

	// Check that we have the Char type
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify Char type
	if types[0].Name().ToCamelCase() != "char" {
		t.Errorf("Expected type 'char', got %s", types[0].Name().ToCamelCase())
	}

	// Check value specifications
	values := spec.Values()
	if len(values) != 13 {
		t.Errorf("Expected 13 value specifications, got %d", len(values))
	}

	// Verify all functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		// Classification
		"isUpper", "isLower", "isAlpha", "isAlphaNum",
		"isDigit", "isOctDigit", "isHexDigit",
		// Case conversion
		"toUpper", "toLower", "toLocaleUpper", "toLocaleLower",
		// Code point conversion
		"toCode", "fromCode",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestCharPredicateFunctions(t *testing.T) {
	spec := CharModuleSpec()
	values := spec.Values()

	// Test isUpper function
	for _, val := range values {
		if val.Name().ToCamelCase() == "isUpper" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'isUpper' to have 1 input, got %d", len(inputs))
			}

			// Input should be Char
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "char" {
						t.Errorf("Expected input type 'Char', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be Bool
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "bool" {
					t.Errorf("Expected output type 'Bool', got %s", fqn.LocalName().ToCamelCase())
				}
			}
			break
		}
	}
}

func TestCharConversionFunctions(t *testing.T) {
	spec := CharModuleSpec()
	values := spec.Values()

	// Test toCode function (Char -> Int)
	for _, val := range values {
		if val.Name().ToCamelCase() == "toCode" {
			valueSpec := val.Spec().Value()

			// Output should be Int
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "int" {
					t.Errorf("Expected output type 'Int', got %s", fqn.LocalName().ToCamelCase())
				}
			}
			break
		}
	}

	// Test fromCode function (Int -> Char)
	for _, val := range values {
		if val.Name().ToCamelCase() == "fromCode" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'fromCode' to have 1 input, got %d", len(inputs))
			}

			// Input should be Int
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "int" {
						t.Errorf("Expected input type 'Int', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be Char
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "char" {
					t.Errorf("Expected output type 'Char', got %s", fqn.LocalName().ToCamelCase())
				}
			}
			return
		}
	}
}
