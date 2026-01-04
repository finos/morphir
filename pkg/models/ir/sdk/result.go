package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// ResultModuleName returns the module name for Morphir.SDK.Result
func ResultModuleName() ir.ModuleName {
	return ir.PathFromString("Result")
}

// ResultModuleSpec returns the module specification for Morphir.SDK.Result
func ResultModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		resultTypes(),
		resultValues(),
		nil,
	)
}

// resultTypes returns the type specifications for the Result module
func resultTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Result type (custom type with Ok and Err constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Result"),
			ir.NewDocumented(
				"Type that represents the result of a computation that may fail.",
				ir.NewCustomTypeSpecification(
					[]ir.Name{
						ir.NameFromString("e"), // error type
						ir.NameFromString("a"), // success type
					},
					ir.TypeConstructors[ir.Unit]{
						// Ok constructor takes one argument of type 'a'
						ir.TypeConstructorFromParts[ir.Unit](
							ir.NameFromString("Ok"),
							ir.TypeConstructorArgs[ir.Unit]{
								ir.TypeConstructorArgFromParts(
									ir.NameFromString("value"),
									TVar("a"),
								),
							},
						),
						// Err constructor takes one argument of type 'e'
						ir.TypeConstructorFromParts[ir.Unit](
							ir.NameFromString("Err"),
							ir.TypeConstructorArgs[ir.Unit]{
								ir.TypeConstructorArgFromParts(
									ir.NameFromString("error"),
									TVar("e"),
								),
							},
						),
					},
				),
			),
		),
	}
}

// resultValues returns the value specifications for the Result module
func resultValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Chaining
		VSpec("andThen", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, ResultType(TVar("x"), TVar("b")))},
			{Name: "result", Type: ResultType(TVar("x"), TVar("a"))},
		}, ResultType(TVar("x"), TVar("b")), "Chain together a sequence of computations that may fail."),

		// Mapping
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "result", Type: ResultType(TVar("x"), TVar("a"))},
		}, ResultType(TVar("x"), TVar("b")), "Apply a function to a result. If the result is Ok, it will be converted."),

		VSpec("map2", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("r"))},
			{Name: "result1", Type: ResultType(TVar("x"), TVar("a"))},
			{Name: "result2", Type: ResultType(TVar("x"), TVar("b"))},
		}, ResultType(TVar("x"), TVar("r")), "Combine two results with a function."),

		VSpec("map3", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c")}, TVar("r"))},
			{Name: "result1", Type: ResultType(TVar("x"), TVar("a"))},
			{Name: "result2", Type: ResultType(TVar("x"), TVar("b"))},
			{Name: "result3", Type: ResultType(TVar("x"), TVar("c"))},
		}, ResultType(TVar("x"), TVar("r")), "Combine three results with a function."),

		VSpec("map4", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d")}, TVar("r"))},
			{Name: "result1", Type: ResultType(TVar("x"), TVar("a"))},
			{Name: "result2", Type: ResultType(TVar("x"), TVar("b"))},
			{Name: "result3", Type: ResultType(TVar("x"), TVar("c"))},
			{Name: "result4", Type: ResultType(TVar("x"), TVar("d"))},
		}, ResultType(TVar("x"), TVar("r")), "Combine four results with a function."),

		VSpec("map5", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d"), TVar("e")}, TVar("r"))},
			{Name: "result1", Type: ResultType(TVar("x"), TVar("a"))},
			{Name: "result2", Type: ResultType(TVar("x"), TVar("b"))},
			{Name: "result3", Type: ResultType(TVar("x"), TVar("c"))},
			{Name: "result4", Type: ResultType(TVar("x"), TVar("d"))},
			{Name: "result5", Type: ResultType(TVar("x"), TVar("e"))},
		}, ResultType(TVar("x"), TVar("r")), "Combine five results with a function."),

		// Error handling
		VSpec("mapError", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("x")}, TVar("y"))},
			{Name: "result", Type: ResultType(TVar("x"), TVar("a"))},
		}, ResultType(TVar("y"), TVar("a")), "Transform an Err value. If the result is Ok, it stays exactly the same."),

		// Conversion
		VSpec("withDefault", []VSpecInput{
			{Name: "default", Type: TVar("a")},
			{Name: "result", Type: ResultType(TVar("x"), TVar("a"))},
		}, TVar("a"), "If the result is Ok return the value, but if the result is an Err then return a given default value."),

		VSpec("toMaybe", []VSpecInput{
			{Name: "result", Type: ResultType(TVar("x"), TVar("a"))},
		}, MaybeType(TVar("a")), "Convert to a Maybe that is Just when the result is Ok and Nothing when it is Err."),

		VSpec("fromMaybe", []VSpecInput{
			{Name: "err", Type: TVar("x")},
			{Name: "maybe", Type: MaybeType(TVar("a"))},
		}, ResultType(TVar("x"), TVar("a")), "Convert from a Maybe. If the value is Just, return Ok. If it is Nothing, return the given error."),
	}
}

// ResultType creates a Result type reference with the given error and value types
func ResultType(errorType ir.Type[ir.Unit], valueType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(ResultModuleName(), "Result"),
		[]ir.Type[ir.Unit]{errorType, valueType},
	)
}
