package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// NumberModuleName returns the module name for Morphir.SDK.Number
func NumberModuleName() ir.ModuleName {
	return ir.PathFromString("Number")
}

// NumberModuleSpec returns the module specification for Morphir.SDK.Number
func NumberModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		nil, // Types defined elsewhere
		numberValues(),
		nil,
	)
}

// numberValues returns the value specifications for the Number module
func numberValues() []ir.ModuleSpecificationValue[ir.Unit] {
	// Helper for Number type
	numberType := func() ir.Type[ir.Unit] {
		return ir.NewTypeReference(
			ir.Unit{},
			ToFQName(NumberModuleName(), "Number"),
			nil,
		)
	}

	// Helper for DivisionByZero error type
	divisionByZeroType := func() ir.Type[ir.Unit] {
		return ir.NewTypeReference(
			ir.Unit{},
			ToFQName(NumberModuleName(), "DivisionByZero"),
			nil,
		)
	}

	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Constants
		VSpec("zero", []VSpecInput{},
			numberType(),
			"The number zero."),

		VSpec("one", []VSpecInput{},
			numberType(),
			"The number one."),

		// Construction
		VSpec("fromInt", []VSpecInput{
			{Name: "value", Type: intType()},
		}, numberType(),
			"Convert an integer to a number."),

		// Comparison
		VSpec("equal", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if two numbers are equal."),

		VSpec("notEqual", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if two numbers are not equal."),

		VSpec("lessThan", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if one number is less than another."),

		VSpec("lessThanOrEqual", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if one number is less than or equal to another."),

		VSpec("greaterThan", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if one number is greater than another."),

		VSpec("greaterThanOrEqual", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, boolType(),
			"Check if one number is greater than or equal to another."),

		// Arithmetic
		VSpec("add", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, numberType(),
			"Add two numbers."),

		VSpec("subtract", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, numberType(),
			"Subtract two numbers."),

		VSpec("multiply", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, numberType(),
			"Multiply two numbers."),

		VSpec("divide", []VSpecInput{
			{Name: "a", Type: numberType()},
			{Name: "b", Type: numberType()},
		}, ResultType(divisionByZeroType(), numberType()),
			"Divide two numbers, returning an error on division by zero."),

		VSpec("abs", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, numberType(),
			"Get the absolute value of a number."),

		VSpec("negate", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, numberType(),
			"Negate a number."),

		VSpec("reciprocal", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, ResultType(divisionByZeroType(), numberType()),
			"Get the reciprocal (1/x) of a number."),

		// Conversion
		VSpec("toDecimal", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, MaybeType(DecimalType()),
			"Try to convert a number to a decimal."),

		VSpec("coerceToDecimal", []VSpecInput{
			{Name: "default", Type: DecimalType()},
			{Name: "value", Type: numberType()},
		}, DecimalType(),
			"Convert a number to a decimal with a default value."),

		VSpec("toFractionalString", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, StringType(),
			"Convert a number to its fractional string representation."),

		// Simplification
		VSpec("simplify", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, numberType(),
			"Attempt to simplify a number."),

		VSpec("isSimplified", []VSpecInput{
			{Name: "value", Type: numberType()},
		}, boolType(),
			"Check if a number is in simplified form."),
	}
}
