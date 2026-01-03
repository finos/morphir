package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// RegexModuleName returns the module name for Morphir.SDK.Regex
func RegexModuleName() ir.ModuleName {
	return ir.PathFromString("Regex")
}

// RegexModuleSpec returns the module specification for Morphir.SDK.Regex
func RegexModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		nil, // Types defined elsewhere or as records
		regexValues(),
		nil,
	)
}

// regexValues returns the value specifications for the Regex module
func regexValues() []ir.ModuleSpecificationValue[ir.Unit] {
	// Helper type constructors
	regexType := func() ir.Type[ir.Unit] {
		return ir.NewTypeReference(
			ir.Unit{},
			ToFQName(RegexModuleName(), "Regex"),
			nil,
		)
	}

	optionsType := func() ir.Type[ir.Unit] {
		return ir.NewTypeReference(
			ir.Unit{},
			ToFQName(RegexModuleName(), "Options"),
			nil,
		)
	}

	matchType := func() ir.Type[ir.Unit] {
		return ir.NewTypeReference(
			ir.Unit{},
			ToFQName(RegexModuleName(), "Match"),
			nil,
		)
	}

	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("fromString", []VSpecInput{
			{Name: "pattern", Type: StringType()},
		}, MaybeType(regexType()),
			"Create a regex from a string pattern."),

		VSpec("fromStringWith", []VSpecInput{
			{Name: "options", Type: optionsType()},
			{Name: "pattern", Type: StringType()},
		}, MaybeType(regexType()),
			"Create a regex from a string pattern with options."),

		VSpec("never", []VSpecInput{},
			regexType(),
			"A regex that never matches."),

		// Matching
		VSpec("contains", []VSpecInput{
			{Name: "regex", Type: regexType()},
			{Name: "str", Type: StringType()},
		}, boolType(),
			"Check if a string contains a match."),

		VSpec("find", []VSpecInput{
			{Name: "regex", Type: regexType()},
			{Name: "str", Type: StringType()},
		}, ListType(matchType()),
			"Find all matches in a string."),

		VSpec("findAtMost", []VSpecInput{
			{Name: "limit", Type: intType()},
			{Name: "regex", Type: regexType()},
			{Name: "str", Type: StringType()},
		}, ListType(matchType()),
			"Find at most N matches in a string."),

		// Replacement
		VSpec("replace", []VSpecInput{
			{Name: "regex", Type: regexType()},
			{Name: "replacer", Type: TFun([]ir.Type[ir.Unit]{matchType()}, StringType())},
			{Name: "str", Type: StringType()},
		}, StringType(),
			"Replace all matches using a function."),

		VSpec("replaceAtMost", []VSpecInput{
			{Name: "limit", Type: intType()},
			{Name: "regex", Type: regexType()},
			{Name: "replacer", Type: TFun([]ir.Type[ir.Unit]{matchType()}, StringType())},
			{Name: "str", Type: StringType()},
		}, StringType(),
			"Replace at most N matches using a function."),

		// Splitting
		VSpec("split", []VSpecInput{
			{Name: "regex", Type: regexType()},
			{Name: "str", Type: StringType()},
		}, ListType(StringType()),
			"Split a string by regex matches."),

		VSpec("splitAtMost", []VSpecInput{
			{Name: "limit", Type: intType()},
			{Name: "regex", Type: regexType()},
			{Name: "str", Type: StringType()},
		}, ListType(StringType()),
			"Split a string by at most N regex matches."),
	}
}
