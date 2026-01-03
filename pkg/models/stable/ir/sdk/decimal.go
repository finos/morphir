package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// DecimalModuleName returns the module name for Morphir.SDK.Decimal
func DecimalModuleName() ir.ModuleName {
	return ir.PathFromString("Decimal")
}

// DecimalModuleSpec returns the module specification for Morphir.SDK.Decimal
func DecimalModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		decimalTypes(),
		decimalValues(),
		nil,
	)
}

// decimalTypes returns the type specifications for the Decimal module
func decimalTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Decimal type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Decimal"),
			ir.NewDocumented(
				"Type that represents a decimal number.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// decimalValues returns the value specifications for the Decimal module
func decimalValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Constants
		VSpec("zero", []VSpecInput{},
			DecimalType(),
			"The decimal value zero."),

		VSpec("one", []VSpecInput{},
			DecimalType(),
			"The decimal value one."),

		VSpec("minusOne", []VSpecInput{},
			DecimalType(),
			"The decimal value minus one."),

		// Constructors
		VSpec("fromInt", []VSpecInput{
			{Name: "value", Type: intType()},
		}, DecimalType(),
			"Convert an integer to a decimal."),

		VSpec("fromFloat", []VSpecInput{
			{Name: "value", Type: floatType()},
		}, DecimalType(),
			"Convert a float to a decimal."),

		VSpec("fromString", []VSpecInput{
			{Name: "str", Type: StringType()},
		}, MaybeType(DecimalType()),
			"Parse a string into a decimal."),

		// Scale helpers
		VSpec("hundred", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Multiply by 100."),

		VSpec("thousand", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Multiply by 1,000."),

		VSpec("million", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Multiply by 1,000,000."),

		VSpec("tenth", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Divide by 10."),

		VSpec("hundredth", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Divide by 100."),

		VSpec("thousandth", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Divide by 1,000."),

		VSpec("millionth", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Divide by 1,000,000."),

		VSpec("bps", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Convert basis points (1/10000)."),

		// Conversions
		VSpec("toString", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, StringType(),
			"Convert a decimal to a string."),

		VSpec("toFloat", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, floatType(),
			"Convert a decimal to a float."),

		// Arithmetic
		VSpec("add", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, DecimalType(),
			"Add two decimals."),

		VSpec("sub", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, DecimalType(),
			"Subtract two decimals."),

		VSpec("mul", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, DecimalType(),
			"Multiply two decimals."),

		VSpec("div", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, MaybeType(DecimalType()),
			"Divide two decimals, returning Nothing on division by zero."),

		VSpec("divWithDefault", []VSpecInput{
			{Name: "default", Type: DecimalType()},
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, DecimalType(),
			"Divide two decimals with a default value for division by zero."),

		VSpec("negate", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Negate a decimal."),

		VSpec("abs", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Get the absolute value of a decimal."),

		// Rounding
		VSpec("truncate", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, intType(),
			"Truncate a decimal to an integer."),

		VSpec("round", []VSpecInput{
			{Name: "value", Type: DecimalType()},
		}, intType(),
			"Round a decimal to the nearest integer."),

		// Comparison
		VSpec("gt", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Greater than comparison."),

		VSpec("gte", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Greater than or equal comparison."),

		VSpec("eq", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Equality comparison."),

		VSpec("neq", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Inequality comparison."),

		VSpec("lt", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Less than comparison."),

		VSpec("lte", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, boolType(),
			"Less than or equal comparison."),

		VSpec("compare", []VSpecInput{
			{Name: "a", Type: DecimalType()},
			{Name: "b", Type: DecimalType()},
		}, OrderType(),
			"Compare two decimals, returning Order."),

		// Manipulation
		VSpec("shiftDecimalLeft", []VSpecInput{
			{Name: "positions", Type: intType()},
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Shift the decimal point left by the given number of positions."),

		VSpec("shiftDecimalRight", []VSpecInput{
			{Name: "positions", Type: intType()},
			{Name: "value", Type: DecimalType()},
		}, DecimalType(),
			"Shift the decimal point right by the given number of positions."),
	}
}

// DecimalType creates a Decimal type reference
func DecimalType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(DecimalModuleName(), "Decimal"),
		nil,
	)
}
