package sdk

import (
	"testing"

	ir "github.com/finos/morphir/pkg/models/ir"
)

func TestLocalDateModuleName(t *testing.T) {
	name := LocalDateModuleName()
	expected := ir.PathFromString("LocalDate")
	if !name.Equal(expected) {
		t.Errorf("Expected module name %v, got %v", expected, name)
	}
}

func TestLocalDateModuleSpec(t *testing.T) {
	spec := LocalDateModuleSpec()

	// Check that we have 3 types (LocalDate, Month, DayOfWeek)
	types := spec.Types()
	if len(types) != 3 {
		t.Errorf("Expected 3 types, got %d", len(types))
	}

	// Verify all types exist
	typeNames := make(map[string]bool)
	for _, typ := range types {
		typeNames[typ.Name().ToCamelCase()] = true
	}

	expectedTypes := []string{"localDate", "month", "dayOfWeek"}
	for _, expected := range expectedTypes {
		if !typeNames[expected] {
			t.Errorf("Expected type %s not found", expected)
		}
	}

	// Check value specifications (should have 21 functions)
	values := spec.Values()
	if len(values) != 21 {
		t.Errorf("Expected 21 value specifications, got %d", len(values))
	}

	// Verify key functions exist
	valueNames := make(map[string]bool)
	for _, val := range values {
		valueNames[val.Name().ToCamelCase()] = true
	}

	expectedFunctions := []string{
		// Construction
		"fromCalendarDate", "fromOrdinalDate", "fromParts", "fromISO",
		// Conversion
		"toISOString",
		// Accessors
		"year", "month", "monthNumber", "day", "dayOfWeek",
		// Month utilities
		"monthToInt",
		// Predicates
		"isWeekend", "isWeekday",
		// Addition
		"addDays", "addWeeks", "addMonths", "addYears",
		// Difference
		"diffInDays", "diffInWeeks", "diffInMonths", "diffInYears",
	}

	for _, expected := range expectedFunctions {
		if !valueNames[expected] {
			t.Errorf("Expected function %s not found", expected)
		}
	}
}

func TestLocalDateTypeReference(t *testing.T) {
	// Test LocalDateType helper
	dateT := LocalDateType()

	if ref, ok := dateT.(ir.TypeReference[ir.Unit]); ok {
		fqn := ref.FullyQualifiedName()
		expectedFQN := ToFQName(LocalDateModuleName(), "LocalDate")
		if !fqn.Equal(expectedFQN) {
			t.Errorf("Expected FQName %v, got %v", expectedFQN, fqn)
		}

		// LocalDate should have no type parameters
		params := ref.TypeParams()
		if len(params) != 0 {
			t.Errorf("Expected 0 type parameters, got %d", len(params))
		}
	} else {
		t.Error("LocalDateType() should return a TypeReference")
	}
}

func TestMonthType(t *testing.T) {
	spec := LocalDateModuleSpec()
	types := spec.Types()

	// Find the Month type
	for _, typ := range types {
		if typ.Name().ToCamelCase() == "month" {
			typeSpec := typ.Spec().Value()
			if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
				constructors := customSpec.Constructors()
				if len(constructors) != 12 {
					t.Errorf("Expected Month to have 12 constructors, got %d", len(constructors))
				}

				// Verify all month names
				expectedMonths := []string{
					"january", "february", "march", "april", "may", "june",
					"july", "august", "september", "october", "november", "december",
				}

				for i, expected := range expectedMonths {
					if i >= len(constructors) {
						break
					}
					actualName := constructors[i].Name().ToCamelCase()
					if actualName != expected {
						t.Errorf("Expected month %s at position %d, got %s", expected, i, actualName)
					}

					// Each constructor should have no arguments
					args := constructors[i].Args()
					if len(args) != 0 {
						t.Errorf("Expected %s constructor to have 0 arguments, got %d", expected, len(args))
					}
				}
			} else {
				t.Error("Month type should be a CustomTypeSpecification")
			}
			return
		}
	}

	t.Error("Month type not found in LocalDate module")
}

func TestDayOfWeekType(t *testing.T) {
	spec := LocalDateModuleSpec()
	types := spec.Types()

	// Find the DayOfWeek type
	for _, typ := range types {
		if typ.Name().ToCamelCase() == "dayOfWeek" {
			typeSpec := typ.Spec().Value()
			if customSpec, ok := typeSpec.(ir.CustomTypeSpecification[ir.Unit]); ok {
				constructors := customSpec.Constructors()
				if len(constructors) != 7 {
					t.Errorf("Expected DayOfWeek to have 7 constructors, got %d", len(constructors))
				}

				// Verify all day names
				expectedDays := []string{
					"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
				}

				for i, expected := range expectedDays {
					if i >= len(constructors) {
						break
					}
					actualName := constructors[i].Name().ToCamelCase()
					if actualName != expected {
						t.Errorf("Expected day %s at position %d, got %s", expected, i, actualName)
					}

					// Each constructor should have no arguments
					args := constructors[i].Args()
					if len(args) != 0 {
						t.Errorf("Expected %s constructor to have 0 arguments, got %d", expected, len(args))
					}
				}
			} else {
				t.Error("DayOfWeek type should be a CustomTypeSpecification")
			}
			return
		}
	}

	t.Error("DayOfWeek type not found in LocalDate module")
}

func TestFromCalendarDateFunction(t *testing.T) {
	spec := LocalDateModuleSpec()
	values := spec.Values()

	// Find the "fromCalendarDate" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "fromCalendarDate" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 3 {
				t.Errorf("Expected 'fromCalendarDate' to have 3 inputs, got %d", len(inputs))
			}

			// First input should be Int (year)
			if len(inputs) > 0 {
				if typeRef, ok := inputs[0].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "int" {
						t.Errorf("Expected first input type 'Int', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Second input should be Month
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "month" {
						t.Errorf("Expected second input type 'Month', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Third input should be Int (day)
			if len(inputs) > 2 {
				if typeRef, ok := inputs[2].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "int" {
						t.Errorf("Expected third input type 'Int', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be LocalDate
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "localDate" {
					t.Errorf("Expected output type 'LocalDate', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'fromCalendarDate' function not found in LocalDate module")
}

func TestAddDaysFunction(t *testing.T) {
	spec := LocalDateModuleSpec()
	values := spec.Values()

	// Find the "addDays" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "addDays" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'addDays' to have 2 inputs, got %d", len(inputs))
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

			// Second input should be LocalDate
			if len(inputs) > 1 {
				if typeRef, ok := inputs[1].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "localDate" {
						t.Errorf("Expected second input type 'LocalDate', got %s", fqn.LocalName().ToCamelCase())
					}
				}
			}

			// Output should be LocalDate
			output := valueSpec.Output()
			if typeRef, ok := output.(ir.TypeReference[ir.Unit]); ok {
				fqn := typeRef.FullyQualifiedName()
				if fqn.LocalName().ToCamelCase() != "localDate" {
					t.Errorf("Expected output type 'LocalDate', got %s", fqn.LocalName().ToCamelCase())
				}
			} else {
				t.Error("Output should be a TypeReference")
			}

			return
		}
	}

	t.Error("'addDays' function not found in LocalDate module")
}

func TestDiffInDaysFunction(t *testing.T) {
	spec := LocalDateModuleSpec()
	values := spec.Values()

	// Find the "diffInDays" function
	for _, val := range values {
		if val.Name().ToCamelCase() == "diffInDays" {
			valueSpec := val.Spec().Value()
			inputs := valueSpec.Inputs()

			if len(inputs) != 2 {
				t.Errorf("Expected 'diffInDays' to have 2 inputs, got %d", len(inputs))
			}

			// Both inputs should be LocalDate
			for i := 0; i < 2; i++ {
				if i >= len(inputs) {
					break
				}
				if typeRef, ok := inputs[i].Type().(ir.TypeReference[ir.Unit]); ok {
					fqn := typeRef.FullyQualifiedName()
					if fqn.LocalName().ToCamelCase() != "localDate" {
						t.Errorf("Expected input %d type 'LocalDate', got %s", i, fqn.LocalName().ToCamelCase())
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

	t.Error("'diffInDays' function not found in LocalDate module")
}
