package sdk

import (
	"testing"

	ir "github.com/finos/morphir-go/pkg/models/ir"
)

func TestLocalTimeModuleName(t *testing.T) {
	name := LocalTimeModuleName()
	expected := ir.PathFromString("LocalTime")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestLocalTimeModuleSpec(t *testing.T) {
	spec := LocalTimeModuleSpec()

	// Check that we have 1 type (LocalTime)
	types := spec.Types()
	if len(types) != 1 {
		t.Errorf("Expected 1 type, got %d", len(types))
	}

	// Verify LocalTime type
	if types[0].Name().ToCamelCase() != "localTime" {
		t.Errorf("Expected type 'localTime', got %s", types[0].Name().ToCamelCase())
	}

	// Check that LocalTime type is opaque
	typeSpec := types[0].Spec().Value()
	if _, ok := typeSpec.(ir.OpaqueTypeSpecification[ir.Unit]); !ok {
		t.Error("LocalTime type should be an OpaqueTypeSpecification")
	}

	// Check value specifications (should have 8 functions)
	values := spec.Values()
	if len(values) != 8 {
		t.Errorf("Expected 8 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		"fromMilliseconds", "fromISO",
		"addSeconds", "addMinutes", "addHours",
		"diffInSeconds", "diffInMinutes", "diffInHours",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestLocalTimeTypeReference(t *testing.T) {
	// Test LocalTimeType helper
	timeT := LocalTimeType()

	if ref, ok := timeT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(LocalTimeModuleName(), "LocalTime")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// LocalTime should have no type parameters
		params := ref.TypeParams()
		if len(params) != 0 {
			t.Errorf("Expected 0 type parameters, got %d", len(params))
		}
	} else {
		t.Error("LocalTimeType() should return a TypeReference")
	}
}

func TestFromMillisecondsFunction(t *testing.T) {
	spec := LocalTimeModuleSpec()
	values := spec.Values()

	// Find the "fromMilliseconds" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "fromMilliseconds" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 1 {
				t.Errorf("Expected 'fromMilliseconds' to have 1 input, got %d", len(inputs))
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

			// Output should be LocalTime
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "localTime" {
					t.Errorf("Expected output type 'LocalTime', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'fromMilliseconds' function not found in LocalTime module")
}

func TestAddMinutesFunction(t *testing.T) {
	spec := LocalTimeModuleSpec()
	values := spec.Values()

	// Find the "addMinutes" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "addMinutes" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'addMinutes' to have 2 inputs, got %d", len(inputs))
			}

			// First input should be Int (offset)
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "int" {
						t.Errorf("Expected first input type 'Int', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Second input should be LocalTime
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "localTime" {
						t.Errorf("Expected second input type 'LocalTime', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be LocalTime
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "localTime" {
					t.Errorf("Expected output type 'LocalTime', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'addMinutes' function not found in LocalTime module")
}

func TestDiffInHoursFunction(t *testing.T) {
	spec := LocalTimeModuleSpec()
	values := spec.Values()

	// Find the "diffInHours" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "diffInHours" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'diffInHours' to have 2 inputs, got %d", len(inputs))
			}

			// Both inputs should be LocalTime
			for i := 0; i < 2; i++ {
				if i >= len(inputs) {
					break
				}
				if typeRef, ok := inputs[i].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "localTime" {
						t.Errorf("Expected input %d type 'LocalTime', got %s", i, fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be Int
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "int" {
					t.Errorf("Expected output type 'Int', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'diffInHours' function not found in LocalTime module")
}
