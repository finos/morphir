package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// IntModuleName returns the module name for Morphir.SDK.Int
func IntModuleName() ir.ModuleName {
	return ir.PathFromString("Int")
}

// IntModuleSpec returns the module specification for Morphir.SDK.Int
func IntModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		intTypes(),
		intValues(),
		nil,
	)
}

// intTypes returns the type specifications for the Int module
func intTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Int8 type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Int8"),
			ir.NewDocumented(
				"Type that represents an 8-bit integer.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Int16 type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Int16"),
			ir.NewDocumented(
				"Type that represents a 16-bit integer.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Int32 type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Int32"),
			ir.NewDocumented(
				"Type that represents a 32-bit integer.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
		// Int64 type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Int64"),
			ir.NewDocumented(
				"Type that represents a 64-bit integer.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// intValues returns the value specifications for the Int module
func intValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Int8 conversions
		VSpec("fromInt8", []VSpecInput{
			{Name: "value", Type: Int8Type()},
		}, intType(), "Convert an 8-bit integer to an Int."),

		VSpec("toInt8", []VSpecInput{
			{Name: "value", Type: intType()},
		}, MaybeType(Int8Type()), "Try to convert an Int to an 8-bit integer."),

		// Int16 conversions
		VSpec("fromInt16", []VSpecInput{
			{Name: "value", Type: Int16Type()},
		}, intType(), "Convert a 16-bit integer to an Int."),

		VSpec("toInt16", []VSpecInput{
			{Name: "value", Type: intType()},
		}, MaybeType(Int16Type()), "Try to convert an Int to a 16-bit integer."),

		// Int32 conversions
		VSpec("fromInt32", []VSpecInput{
			{Name: "value", Type: Int32Type()},
		}, intType(), "Convert a 32-bit integer to an Int."),

		VSpec("toInt32", []VSpecInput{
			{Name: "value", Type: intType()},
		}, MaybeType(Int32Type()), "Try to convert an Int to a 32-bit integer."),

		// Int64 conversions
		VSpec("fromInt64", []VSpecInput{
			{Name: "value", Type: Int64Type()},
		}, intType(), "Convert a 64-bit integer to an Int."),

		VSpec("toInt64", []VSpecInput{
			{Name: "value", Type: intType()},
		}, MaybeType(Int64Type()), "Try to convert an Int to a 64-bit integer."),
	}
}

// Int8Type creates an Int8 type reference
func Int8Type() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(IntModuleName(), "Int8"),
		nil,
	)
}

// Int16Type creates an Int16 type reference
func Int16Type() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(IntModuleName(), "Int16"),
		nil,
	)
}

// Int32Type creates an Int32 type reference
func Int32Type() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(IntModuleName(), "Int32"),
		nil,
	)
}

// Int64Type creates an Int64 type reference
func Int64Type() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(IntModuleName(), "Int64"),
		nil,
	)
}
