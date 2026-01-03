package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// UUIDModuleName returns the module name for Morphir.SDK.UUID
func UUIDModuleName() ir.ModuleName {
	return ir.PathFromString("UUID")
}

// UUIDModuleSpec returns the module specification for Morphir.SDK.UUID
func UUIDModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		uuidTypes(),
		uuidValues(),
		nil,
	)
}

// uuidTypes returns the type specifications for the UUID module
func uuidTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// UUID type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("UUID"),
			ir.NewDocumented(
				"Type that represents a UUID v5 identifier.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),

		// Error type (custom type with error constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Error"),
			ir.NewDocumented(
				"Type that represents UUID parsing errors.",
				ir.NewCustomTypeSpecification[ir.Unit](
					nil,
					ir.TypeConstructors[ir.Unit]{
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("WrongFormat"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("WrongLength"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("UnsupportedVariant"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("IsNil"), nil),
						ir.TypeConstructorFromParts[ir.Unit](ir.NameFromString("NoVersion"), nil),
					},
				),
			),
		),
	}
}

// uuidValues returns the value specifications for the UUID module
func uuidValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Parsing
		VSpec("parse", []VSpecInput{
			{Name: "str", Type: StringType()},
		}, ResultType(UUIDErrorType(), UUIDType()),
			"Parse a string into a UUID, returning an error on failure."),

		VSpec("fromString", []VSpecInput{
			{Name: "str", Type: StringType()},
		}, MaybeType(UUIDType()),
			"Parse a string into a UUID, returning Nothing on failure."),

		// Generation
		VSpec("forName", []VSpecInput{
			{Name: "name", Type: StringType()},
			{Name: "namespace", Type: UUIDType()},
		}, UUIDType(),
			"Generate a UUID v5 from a name and namespace UUID."),

		// Conversion
		VSpec("toString", []VSpecInput{
			{Name: "uuid", Type: UUIDType()},
		}, StringType(),
			"Convert a UUID to its string representation."),

		// Properties
		VSpec("version", []VSpecInput{
			{Name: "uuid", Type: UUIDType()},
		}, intType(),
			"Extract the version number from a UUID."),

		VSpec("compare", []VSpecInput{
			{Name: "a", Type: UUIDType()},
			{Name: "b", Type: UUIDType()},
		}, OrderType(),
			"Compare two UUIDs."),

		// Nil UUID utilities
		VSpec("nilString", []VSpecInput{},
			StringType(),
			"The string representation of a nil UUID."),

		VSpec("isNilString", []VSpecInput{
			{Name: "str", Type: StringType()},
		}, boolType(),
			"Check if a string represents a nil UUID."),

		// Standard namespaces
		VSpec("dnsNamespace", []VSpecInput{},
			UUIDType(),
			"The DNS namespace UUID."),

		VSpec("urlNamespace", []VSpecInput{},
			UUIDType(),
			"The URL namespace UUID."),

		VSpec("oidNamespace", []VSpecInput{},
			UUIDType(),
			"The OID namespace UUID."),

		VSpec("x500Namespace", []VSpecInput{},
			UUIDType(),
			"The X.500 namespace UUID."),
	}
}

// UUIDType creates a UUID type reference
func UUIDType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(UUIDModuleName(), "UUID"),
		nil,
	)
}

// UUIDErrorType creates a UUID.Error type reference
func UUIDErrorType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(UUIDModuleName(), "Error"),
		nil,
	)
}
