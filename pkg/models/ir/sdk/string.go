package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// StringModuleName returns the module name for Morphir.SDK.String
func StringModuleName() ir.ModuleName {
	return ir.PathFromString("String")
}

// StringModuleSpec returns the module specification for Morphir.SDK.String
func StringModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		stringTypes(),
		stringValues(),
		nil,
	)
}

// stringTypes returns the type specifications for the String module
func stringTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// String type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("String"),
			ir.NewDocumented(
				"Type that represents a string of characters.",
				ir.NewOpaqueTypeSpecification[ir.Unit](nil),
			),
		),
	}
}

// stringValues returns the value specifications for the String module
func stringValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Basic operations
		VSpec("isEmpty", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, boolType(), "Determine if a string is empty."),

		VSpec("length", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, intType(), "Get the length of a string."),

		VSpec("reverse", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Reverse a string."),

		VSpec("repeat", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Repeat a string n times."),

		VSpec("replace", []VSpecInput{
			{Name: "match", Type: StringType()},
			{Name: "replacement", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Replace all occurrences of a substring."),

		// Combining
		VSpec("append", []VSpecInput{
			{Name: "s1", Type: StringType()},
			{Name: "s2", Type: StringType()},
		}, StringType(), "Append two strings."),

		VSpec("concat", []VSpecInput{
			{Name: "list", Type: ListType(StringType())},
		}, StringType(), "Concatenate many strings into one."),

		VSpec("split", []VSpecInput{
			{Name: "sep", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, ListType(StringType()), "Split a string using a given separator."),

		VSpec("join", []VSpecInput{
			{Name: "sep", Type: StringType()},
			{Name: "list", Type: ListType(StringType())},
		}, StringType(), "Put many strings together with a given separator."),

		VSpec("words", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, ListType(StringType()), "Break a string into words, splitting on whitespace."),

		VSpec("lines", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, ListType(StringType()), "Break a string into lines, splitting on newlines."),

		// Substrings
		VSpec("slice", []VSpecInput{
			{Name: "start", Type: intType()},
			{Name: "end", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Take a substring given a start and end index."),

		VSpec("left", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Take n characters from the left side of a string."),

		VSpec("right", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Take n characters from the right side of a string."),

		VSpec("dropLeft", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Drop n characters from the left side of a string."),

		VSpec("dropRight", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Drop n characters from the right side of a string."),

		// Search/Match
		VSpec("contains", []VSpecInput{
			{Name: "ref", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, boolType(), "Check if a string contains another string."),

		VSpec("startsWith", []VSpecInput{
			{Name: "ref", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, boolType(), "Check if a string starts with another string."),

		VSpec("endsWith", []VSpecInput{
			{Name: "ref", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, boolType(), "Check if a string ends with another string."),

		VSpec("indexes", []VSpecInput{
			{Name: "ref", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, ListType(intType()), "Get all of the indexes for a substring in a string."),

		VSpec("indices", []VSpecInput{
			{Name: "ref", Type: StringType()},
			{Name: "s", Type: StringType()},
		}, ListType(intType()), "Alias for indexes."),

		// Conversions
		VSpec("toInt", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, MaybeType(intType()), "Try to convert a string into an int."),

		VSpec("fromInt", []VSpecInput{
			{Name: "a", Type: intType()},
		}, StringType(), "Convert an int to a string."),

		VSpec("toFloat", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, MaybeType(floatType()), "Try to convert a string into a float."),

		VSpec("fromFloat", []VSpecInput{
			{Name: "a", Type: floatType()},
		}, StringType(), "Convert a float to a string."),

		VSpec("fromChar", []VSpecInput{
			{Name: "ch", Type: CharType()},
		}, StringType(), "Create a string from a given character."),

		VSpec("cons", []VSpecInput{
			{Name: "ch", Type: CharType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Add a character to the beginning of a string."),

		VSpec("uncons", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, MaybeType(ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
			CharType(),
			StringType(),
		})), "Split a non-empty string into its head and tail."),

		VSpec("toList", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, ListType(CharType()), "Convert a string to a list of characters."),

		VSpec("fromList", []VSpecInput{
			{Name: "a", Type: ListType(CharType())},
		}, StringType(), "Convert a list of characters into a string."),

		// Case conversion
		VSpec("toUpper", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Convert a string to all upper case."),

		VSpec("toLower", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Convert a string to all lower case."),

		// Padding/Trimming
		VSpec("pad", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "ch", Type: CharType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Pad a string on both sides until it has a given length."),

		VSpec("padLeft", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "ch", Type: CharType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Pad a string on the left until it has a given length."),

		VSpec("padRight", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "ch", Type: CharType()},
			{Name: "s", Type: StringType()},
		}, StringType(), "Pad a string on the right until it has a given length."),

		VSpec("trim", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Get rid of whitespace on both sides of a string."),

		VSpec("trimLeft", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Get rid of whitespace on the left of a string."),

		VSpec("trimRight", []VSpecInput{
			{Name: "s", Type: StringType()},
		}, StringType(), "Get rid of whitespace on the right of a string."),

		// Higher-order functions
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType()}, CharType())},
			{Name: "s", Type: StringType()},
		}, StringType(), "Transform every character in a string."),

		VSpec("filter", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType()}, boolType())},
			{Name: "s", Type: StringType()},
		}, StringType(), "Keep only the characters that satisfy the predicate."),

		VSpec("foldl", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType(), TVar("b")}, TVar("b"))},
			{Name: "z", Type: TVar("b")},
			{Name: "s", Type: StringType()},
		}, TVar("b"), "Reduce a string from the left."),

		VSpec("foldr", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType(), TVar("b")}, TVar("b"))},
			{Name: "z", Type: TVar("b")},
			{Name: "s", Type: StringType()},
		}, TVar("b"), "Reduce a string from the right."),

		VSpec("any", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType()}, boolType())},
			{Name: "s", Type: StringType()},
		}, boolType(), "Determine whether any characters satisfy a predicate."),

		VSpec("all", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{CharType()}, boolType())},
			{Name: "s", Type: StringType()},
		}, boolType(), "Determine whether all characters satisfy a predicate."),
	}
}

// StringType creates a String type reference
func StringType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(StringModuleName(), "String"),
		nil,
	)
}

// CharType creates a Char type reference (forward reference for now)
// This will be properly defined in the Char module
func CharType() ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(ir.PathFromString("Char"), "Char"),
		nil,
	)
}
