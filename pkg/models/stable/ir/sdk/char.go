package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// CharModuleName returns the module name for Morphir.SDK.Char
func CharModuleName() ir.ModuleName {
	return ir.PathFromString("Char")
}

// CharModuleSpec returns the module specification for Morphir.SDK.Char
func CharModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		charTypes(),
		charValues(),
		nil,
	)
}

// charTypes returns the type specifications for the Char module
func charTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Char type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Char"),
			ir.NewDocumented(
				"Type that represents a single character.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// charValues returns the value specifications for the Char module
func charValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Character classification predicates
		VSpec("isUpper", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect upper case characters."),

		VSpec("isLower", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect lower case characters."),

		VSpec("isAlpha", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect letters."),

		VSpec("isAlphaNum", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect letters and numbers."),

		VSpec("isDigit", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect decimal digits (0-9)."),

		VSpec("isOctDigit", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect octal digits (0-7)."),

		VSpec("isHexDigit", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, boolType(), "Detect hexadecimal digits (0-9, a-f, A-F)."),

		// Case conversion
		VSpec("toUpper", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, CharType(), "Convert to upper case."),

		VSpec("toLower", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, CharType(), "Convert to lower case."),

		VSpec("toLocaleUpper", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, CharType(), "Convert to upper case, according to any locale-specific case mappings."),

		VSpec("toLocaleLower", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, CharType(), "Convert to lower case, according to any locale-specific case mappings."),

		// Code point conversion
		VSpec("toCode", []VSpecInput{
			{Name: "c", Type: CharType()},
		}, intType(), "Convert a character to its Unicode code point."),

		VSpec("fromCode", []VSpecInput{
			{Name: "code", Type: intType()},
		}, CharType(), "Convert a Unicode code point to a character."),
	}
}

// Note: CharType helper is already defined in string.go
// We keep it there to avoid circular dependencies
