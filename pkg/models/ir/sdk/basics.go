package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// BasicsModuleName returns the module name for Morphir.SDK.Basics
func BasicsModuleName() ir.ModuleName {
	return ir.PathFromString("Basics")
}

// BasicsModuleSpec returns the module specification for Morphir.SDK.Basics
func BasicsModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		basicsTypes(),
		basicsValues(),
		nil,
	)
}

// basicsTypes returns the type specifications for the Basics module
func basicsTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Int type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Int"),
			ir.NewDocumented(
				"Type that represents an integer value.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Float type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Float"),
			ir.NewDocumented(
				"Type that represents a floating-point number.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Bool type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Bool"),
			ir.NewDocumented(
				"Type that represents a boolean value.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Order type (custom type with LT, EQ, GT constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Order"),
			ir.NewDocumented(
				"Represents the relative ordering of two things.",
				ir.NewCustomTypeSpecification(
					nil, // no type parameters
					ir.TypeConstructors[ir.Unit]{
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("LT"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("EQ"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("GT"), nil),
					},
				),
			),
		),
		// Never type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Never"),
			ir.NewDocumented(
				"A value that can never happen!",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// basicsValues returns the value specifications for the Basics module
func basicsValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Arithmetic operations
		binaryOp("add", "number", "number", "number", "Addition."),
		binaryOp("subtract", "number", "number", "number", "Subtraction."),
		binaryOp("multiply", "number", "number", "number", "Multiplication."),
		VSpec("divide", []VSpecInput{
			{Name: "a", Type: floatType()},
			{Name: "b", Type: floatType()},
		}, floatType(), "Floating point division."),
		VSpec("integerDivide", []VSpecInput{
			{Name: "a", Type: intType()},
			{Name: "b", Type: intType()},
		}, intType(), "Integer division."),
		binaryOp("power", "number", "number", "number", "Exponentiation."),
		unaryOp("negate", "number", "number", "Negate a number."),
		unaryOp("abs", "number", "number", "Absolute value."),

		// Comparison operations
		VSpec("equal", []VSpecInput{
			{Name: "a", Type: TVar("eq")},
			{Name: "b", Type: TVar("eq")},
		}, boolType(), "Check if values are equal."),
		VSpec("notEqual", []VSpecInput{
			{Name: "a", Type: TVar("eq")},
			{Name: "b", Type: TVar("eq")},
		}, boolType(), "Check if values are not equal."),
		VSpec("lessThan", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, boolType(), "Check if first value is less than second."),
		VSpec("greaterThan", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, boolType(), "Check if first value is greater than second."),
		VSpec("lessThanOrEqual", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, boolType(), "Check if first value is less than or equal to second."),
		VSpec("greaterThanOrEqual", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, boolType(), "Check if first value is greater than or equal to second."),
		VSpec("compare", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, orderType(), "Compare two values and return their order."),
		VSpec("min", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, TVar("comparable"), "Return the smaller of two values."),
		VSpec("max", []VSpecInput{
			{Name: "a", Type: TVar("comparable")},
			{Name: "b", Type: TVar("comparable")},
		}, TVar("comparable"), "Return the larger of two values."),

		// Boolean logic
		VSpec("and", []VSpecInput{
			{Name: "a", Type: boolType()},
			{Name: "b", Type: boolType()},
		}, boolType(), "Logical AND."),
		VSpec("or", []VSpecInput{
			{Name: "a", Type: boolType()},
			{Name: "b", Type: boolType()},
		}, boolType(), "Logical OR."),
		VSpec("xor", []VSpecInput{
			{Name: "a", Type: boolType()},
			{Name: "b", Type: boolType()},
		}, boolType(), "Logical XOR."),
		VSpec("not", []VSpecInput{
			{Name: "a", Type: boolType()},
		}, boolType(), "Logical NOT."),

		// Type conversions
		VSpec("toFloat", []VSpecInput{
			{Name: "a", Type: intType()},
		}, floatType(), "Convert an integer to a float."),
		VSpec("round", []VSpecInput{
			{Name: "a", Type: floatType()},
		}, intType(), "Round a float to the nearest integer."),
		VSpec("floor", []VSpecInput{
			{Name: "a", Type: floatType()},
		}, intType(), "Round a float down to an integer."),
		VSpec("ceiling", []VSpecInput{
			{Name: "a", Type: floatType()},
		}, intType(), "Round a float up to an integer."),
		VSpec("truncate", []VSpecInput{
			{Name: "a", Type: floatType()},
		}, intType(), "Truncate a float to an integer."),

		// Higher-order functions
		VSpec("composeLeft", []VSpecInput{
			{Name: "g", Type: TFun([]ir.Type[ir.Unit]{TVar("b")}, TVar("c"))},
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
		}, TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("c")), "Compose two functions (left to right)."),
		VSpec("composeRight", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "g", Type: TFun([]ir.Type[ir.Unit]{TVar("b")}, TVar("c"))},
		}, TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("c")), "Compose two functions (right to left)."),
		VSpec("identity", []VSpecInput{
			{Name: "a", Type: TVar("a")},
		}, TVar("a"), "Return the input unchanged."),
		VSpec("always", []VSpecInput{
			{Name: "a", Type: TVar("a")},
			{Name: "b", Type: TVar("b")},
		}, TVar("a"), "Always return the first argument, ignoring the second."),

		// Other operations
		VSpec("clamp", []VSpecInput{
			{Name: "min", Type: TVar("number")},
			{Name: "max", Type: TVar("number")},
			{Name: "value", Type: TVar("number")},
		}, TVar("number"), "Clamp a value between a minimum and maximum."),
		VSpec("append", []VSpecInput{
			{Name: "a", Type: TVar("appendable")},
			{Name: "b", Type: TVar("appendable")},
		}, TVar("appendable"), "Append two appendable values."),

		// Trigonometric functions
		unaryOp("sin", "float", "float", "Sine function."),
		unaryOp("cos", "float", "float", "Cosine function."),
		unaryOp("tan", "float", "float", "Tangent function."),
		unaryOp("asin", "float", "float", "Arcsine function."),
		unaryOp("acos", "float", "float", "Arccosine function."),
		unaryOp("atan", "float", "float", "Arctangent function."),
		VSpec("atan2", []VSpecInput{
			{Name: "y", Type: floatType()},
			{Name: "x", Type: floatType()},
		}, floatType(), "Two-argument arctangent."),

		// Mathematical constants and functions
		unaryOp("sqrt", "float", "float", "Square root."),
		unaryOp("logBase", "float", "float", "Logarithm with custom base."),
		VSpec("e", []VSpecInput{}, floatType(), "Euler's number (e)."),
		VSpec("pi", []VSpecInput{}, floatType(), "Pi constant."),

		// Additional mathematical operations
		VSpec("remainderBy", []VSpecInput{
			{Name: "divisor", Type: intType()},
			{Name: "dividend", Type: intType()},
		}, intType(), "Remainder after division."),
		VSpec("modBy", []VSpecInput{
			{Name: "modulus", Type: intType()},
			{Name: "value", Type: intType()},
		}, intType(), "Modulo operation."),
		VSpec("isNaN", []VSpecInput{
			{Name: "value", Type: floatType()},
		}, boolType(), "Check if a float is NaN."),
		VSpec("isInfinite", []VSpecInput{
			{Name: "value", Type: floatType()},
		}, boolType(), "Check if a float is infinite."),
	}
}

// Helper functions for creating type references

func intType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(ir.Unit{}, ToFQName(BasicsModuleName(), "Int"), nil)
}

func floatType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(ir.Unit{}, ToFQName(BasicsModuleName(), "Float"), nil)
}

func boolType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(ir.Unit{}, ToFQName(BasicsModuleName(), "Bool"), nil)
}

func orderType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(ir.Unit{}, ToFQName(BasicsModuleName(), "Order"), nil)
}

// Helper functions for creating value specifications

func binaryOp(name string, param1Type string, param2Type string, returnType string, doc string) ir.ModuleSpecificationValue[ir.Unit] {
	return VSpec(name, []VSpecInput{
		{Name: "a", Type: typeFromString(param1Type)},
		{Name: "b", Type: typeFromString(param2Type)},
	}, typeFromString(returnType), doc)
}

func unaryOp(name string, paramType string, returnType string, doc string) ir.ModuleSpecificationValue[ir.Unit] {
	return VSpec(name, []VSpecInput{
		{Name: "a", Type: typeFromString(paramType)},
	}, typeFromString(returnType), doc)
}

func typeFromString(typeName string) ir.Type[ir.Unit] {
	switch typeName {
	case "int":
		return intType()
	case "float":
		return floatType()
	case "bool":
		return boolType()
	case "number":
		return TVar("number")
	default:
		return TVar(typeName)
	}
}
