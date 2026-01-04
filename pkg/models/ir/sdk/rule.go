package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// RuleModuleName returns the module name for Morphir.SDK.Rule
func RuleModuleName() ir.ModuleName {
	return ir.PathFromString("Rule")
}

// RuleModuleSpec returns the module specification for Morphir.SDK.Rule
func RuleModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		nil, // No types defined
		ruleValues(),
		nil,
	)
}

// ruleValues returns the value specifications for the Rule module
func ruleValues() []ir.ModuleSpecificationValue[ir.Unit] {
	// Rule type alias: a -> Maybe b
	ruleType := func(inputType ir.Type[ir.Unit], outputType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
		return TFun([]ir.Type[ir.Unit]{inputType}, MaybeType(outputType))
	}

	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Combinators
		VSpec("chain", []VSpecInput{
			{Name: "rules", Type: ListType(ruleType(TVar("a"), TVar("b")))},
		}, ruleType(TVar("a"), TVar("b")),
			"Chain a list of rules together, returning the first successful match."),

		// Predicates
		VSpec("any", []VSpecInput{
			{Name: "value", Type: TVar("a")},
		}, boolType(),
			"A rule that always returns true for any value."),

		VSpec("is", []VSpecInput{
			{Name: "referenceValue", Type: TVar("a")},
			{Name: "value", Type: TVar("a")},
		}, boolType(),
			"Check if a value equals a reference value."),

		VSpec("anyOf", []VSpecInput{
			{Name: "referenceValues", Type: ListType(TVar("a"))},
			{Name: "value", Type: TVar("a")},
		}, boolType(),
			"Check if a value matches any item in a list."),

		VSpec("noneOf", []VSpecInput{
			{Name: "referenceValues", Type: ListType(TVar("a"))},
			{Name: "value", Type: TVar("a")},
		}, boolType(),
			"Check if a value matches none of the items in a list."),
	}
}
