package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// MaybeModuleName returns the module name for Morphir.SDK.Maybe
func MaybeModuleName() ir.ModuleName {
	return ir.PathFromString("Maybe")
}

// MaybeModuleSpec returns the module specification for Morphir.SDK.Maybe
func MaybeModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		maybeTypes(),
		maybeValues(),
		nil,
	)
}

// maybeTypes returns the type specifications for the Maybe module
func maybeTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Maybe type (custom type with Just and Nothing constructors)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Maybe"),
			ir.NewDocumented(
				"Type that represents an optional value.",
				ir.NewCustomTypeSpecification(
					[]ir.Name{ir.NameFromString("a")}, // type parameter
					ir.TypeConstructors[ir.Unit]{
						// Just constructor takes one argument of type 'a'
						ir.TypeConstructorFromParts[ir.Unit](
							ir.NameFromString("Just"),
							ir.TypeConstructorArgs[ir.Unit]{
								ir.TypeConstructorArgFromParts(
									ir.NameFromString("value"),
									TVar("a"),
								),
							},
						),
						// Nothing constructor takes no arguments
						ir.TypeConstructorFromParts[ir.Unit](
							ir.NameFromString("Nothing"),
							nil,
						),
					},
				),
			),
		),
	}
}

// maybeValues returns the value specifications for the Maybe module
func maybeValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Chaining
		VSpec("andThen", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, MaybeType(TVar("b")))},
			{Name: "maybe", Type: MaybeType(TVar("a"))},
		}, MaybeType(TVar("b")), "Chain together many computations that may fail."),

		// Mapping
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "maybe", Type: MaybeType(TVar("a"))},
		}, MaybeType(TVar("b")), "Transform a Maybe value with a given function."),

		VSpec("map2", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("r"))},
			{Name: "maybe1", Type: MaybeType(TVar("a"))},
			{Name: "maybe2", Type: MaybeType(TVar("b"))},
		}, MaybeType(TVar("r")), "Apply a function if all the arguments are present."),

		VSpec("map3", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c")}, TVar("r"))},
			{Name: "maybe1", Type: MaybeType(TVar("a"))},
			{Name: "maybe2", Type: MaybeType(TVar("b"))},
			{Name: "maybe3", Type: MaybeType(TVar("c"))},
		}, MaybeType(TVar("r")), "Apply a function if all the arguments are present."),

		VSpec("map4", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d")}, TVar("r"))},
			{Name: "maybe1", Type: MaybeType(TVar("a"))},
			{Name: "maybe2", Type: MaybeType(TVar("b"))},
			{Name: "maybe3", Type: MaybeType(TVar("c"))},
			{Name: "maybe4", Type: MaybeType(TVar("d"))},
		}, MaybeType(TVar("r")), "Apply a function if all the arguments are present."),

		VSpec("map5", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d"), TVar("e")}, TVar("r"))},
			{Name: "maybe1", Type: MaybeType(TVar("a"))},
			{Name: "maybe2", Type: MaybeType(TVar("b"))},
			{Name: "maybe3", Type: MaybeType(TVar("c"))},
			{Name: "maybe4", Type: MaybeType(TVar("d"))},
			{Name: "maybe5", Type: MaybeType(TVar("e"))},
		}, MaybeType(TVar("r")), "Apply a function if all the arguments are present."),

		// Utilities
		VSpec("withDefault", []VSpecInput{
			{Name: "default", Type: TVar("a")},
			{Name: "maybe", Type: MaybeType(TVar("a"))},
		}, TVar("a"), "Provide a default value, turning an optional value into a normal value."),

		VSpec("hasValue", []VSpecInput{
			{Name: "maybe", Type: MaybeType(TVar("a"))},
		}, boolType(), "Check if a maybe value is a Just."),
	}
}

// Note: MaybeType helper is already defined in list.go
// We keep it there to avoid circular dependencies, and it will work correctly
// once the Maybe module is registered
