package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// ResultListModuleName returns the module name for Morphir.SDK.ResultList
func ResultListModuleName() ir.ModuleName {
	return ir.PathFromString("ResultList")
}

// ResultListModuleSpec returns the module specification for Morphir.SDK.ResultList
func ResultListModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		resultListTypes(),
		resultListValues(),
		nil,
	)
}

// resultListTypes returns the type specifications for the ResultList module
func resultListTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// ResultList is a type alias for List (Result e a)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("ResultList"),
			ir.NewDocumented(
				"Type alias that represents a list of results.",
				ir.NewTypeAliasSpecification[ir.Unit](
					[]ir.Name{
						ir.NameFromString("e"),
						ir.NameFromString("a"),
					},
					ListType(ResultType(TVar("e"), TVar("a"))),
				),
			),
		),
	}
}

// resultListValues returns the value specifications for the ResultList module
func resultListValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("fromList", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, ResultListType(TVar("e"), TVar("a")),
			"Convert a list into a ResultList by wrapping each element in Ok."),

		// Extraction
		VSpec("errors", []VSpecInput{
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ListType(TVar("e")),
			"Extract all error values from a ResultList."),

		VSpec("successes", []VSpecInput{
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ListType(TVar("a")),
			"Extract all success values from a ResultList."),

		VSpec("partition", []VSpecInput{
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, TupleType(ListType(TVar("e")), ListType(TVar("a"))),
			"Partition a ResultList into errors and successes."),

		// Error handling
		VSpec("keepAllErrors", []VSpecInput{
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultType(ListType(TVar("e")), ListType(TVar("a"))),
			"Return all errors if any exist, otherwise return all successes."),

		VSpec("keepFirstError", []VSpecInput{
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultType(TVar("e"), ListType(TVar("a"))),
			"Return the first error encountered, or all successes if none exist."),

		// Transform
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultListType(TVar("e"), TVar("b")),
			"Map a function over all success values in a ResultList."),

		VSpec("mapOrFail", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, ResultType(TVar("e"), TVar("b")))},
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultListType(TVar("e"), TVar("b")),
			"Map a function that can fail over all success values in a ResultList."),

		// Filter
		VSpec("filter", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultListType(TVar("e"), TVar("a")),
			"Filter a ResultList keeping only success values that pass the predicate."),

		VSpec("filterOrFail", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, ResultType(TVar("e"), boolType()))},
			{Name: "resultList", Type: ResultListType(TVar("e"), TVar("a"))},
		}, ResultListType(TVar("e"), TVar("a")),
			"Filter a ResultList using a predicate that can produce errors."),
	}
}

// ResultListType creates a ResultList type reference (List (Result e a))
func ResultListType(errorType ir.Type[ir.Unit], valueType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(ResultListModuleName(), "ResultList"),
		[]ir.Type[ir.Unit]{errorType, valueType},
	)
}
