package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// AggregateModuleName returns the module name for Morphir.SDK.Aggregate
func AggregateModuleName() ir.ModuleName {
	return ir.PathFromString("Aggregate")
}

// AggregateModuleSpec returns the module specification for Morphir.SDK.Aggregate
func AggregateModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		aggregateTypes(),
		aggregateValues(),
		nil,
	)
}

// aggregateTypes returns the type specifications for the Aggregate module
func aggregateTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Aggregation type (opaque with 2 type parameters: element and key)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Aggregation"),
			ir.NewDocumented(
				"Type that represents an aggregation over elements with an optional grouping key.",
				ir.NewOpaqueTypeSpecification[ir.Unit]([]ir.Name{
					ir.NameFromString("a"),
					ir.NameFromString("key"),
				}),
			),
		),
	}
}

// aggregateValues returns the value specifications for the Aggregate module
func aggregateValues() []ir.ModuleSpecificationValue[ir.Unit] {
	// Aggregator type alias: Aggregation a key -> Float
	aggregatorType := func() ir.Type[ir.Unit] {
		return TFun(
			[]ir.Type[ir.Unit]{AggregationType(TVar("a"), TVar("key"))},
			floatType(),
		)
	}

	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Basic aggregators
		VSpec("count", []VSpecInput{},
			aggregatorType(),
			"Count the number of elements."),

		VSpec("sumOf", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, floatType())},
		}, aggregatorType(),
			"Sum the values extracted by a function."),

		VSpec("averageOf", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, floatType())},
		}, aggregatorType(),
			"Calculate the average of values extracted by a function."),

		VSpec("minimumOf", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("comparable"))},
		}, TFun(
			[]ir.Type[ir.Unit]{AggregationType(TVar("a"), TVar("key"))},
			MaybeType(TVar("comparable")),
		),
			"Find the minimum value extracted by a function."),

		VSpec("maximumOf", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("comparable"))},
		}, TFun(
			[]ir.Type[ir.Unit]{AggregationType(TVar("a"), TVar("key"))},
			MaybeType(TVar("comparable")),
		),
			"Find the maximum value extracted by a function."),

		VSpec("weightedAverageOf", []VSpecInput{
			{Name: "weightFn", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, floatType())},
			{Name: "valueFn", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, floatType())},
		}, aggregatorType(),
			"Calculate a weighted average using weight and value extraction functions."),

		// Aggregation modifiers
		VSpec("byKey", []VSpecInput{
			{Name: "keyFn", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("comparableKey"))},
			{Name: "aggregation", Type: AggregationType(TVar("a"), TVar("key"))},
		}, AggregationType(TVar("a"), TVar("comparableKey")),
			"Group an aggregation by a key function."),

		VSpec("withFilter", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "aggregation", Type: AggregationType(TVar("a"), TVar("key"))},
		}, AggregationType(TVar("a"), TVar("key")),
			"Filter elements before aggregating."),

		// Aggregate mapping functions
		VSpec("aggregateMap", []VSpecInput{
			{Name: "aggregator", Type: aggregatorType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, floatType(),
			"Apply an aggregator to a list."),

		VSpec("aggregateMap2", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{floatType(), floatType()}, TVar("b"))},
			{Name: "agg1", Type: aggregatorType()},
			{Name: "agg2", Type: aggregatorType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, TVar("b"),
			"Apply two aggregators and combine their results."),

		VSpec("aggregateMap3", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{floatType(), floatType(), floatType()}, TVar("b"))},
			{Name: "agg1", Type: aggregatorType()},
			{Name: "agg2", Type: aggregatorType()},
			{Name: "agg3", Type: aggregatorType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, TVar("b"),
			"Apply three aggregators and combine their results."),

		VSpec("aggregateMap4", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{floatType(), floatType(), floatType(), floatType()}, TVar("b"))},
			{Name: "agg1", Type: aggregatorType()},
			{Name: "agg2", Type: aggregatorType()},
			{Name: "agg3", Type: aggregatorType()},
			{Name: "agg4", Type: aggregatorType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, TVar("b"),
			"Apply four aggregators and combine their results."),

		// Grouping functions
		VSpec("groupBy", []VSpecInput{
			{Name: "keyFn", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("comparableKey"))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, DictType(TVar("comparableKey"), ListType(TVar("a"))),
			"Group a list into a dictionary by key."),

		VSpec("aggregate", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("groupKey"), ListType(TVar("a"))}, TVar("b"))},
			{Name: "aggregator", Type: TFun(
				[]ir.Type[ir.Unit]{AggregationType(TVar("a"), TVar("groupKey"))},
				TVar("result"),
			)},
			{Name: "list", Type: ListType(TVar("a"))},
		}, DictType(TVar("groupKey"), TVar("result")),
			"Apply an aggregator to grouped data."),
	}
}

// AggregationType creates an Aggregation type reference
func AggregationType(elementType ir.Type[ir.Unit], keyType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(AggregateModuleName(), "Aggregation"),
		[]ir.Type[ir.Unit]{elementType, keyType},
	)
}
