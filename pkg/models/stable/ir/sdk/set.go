package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// SetModuleName returns the module name for Morphir.SDK.Set
func SetModuleName() ir.ModuleName {
	return ir.PathFromString("Set")
}

// SetModuleSpec returns the module specification for Morphir.SDK.Set
func SetModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		setTypes(),
		setValues(),
		nil,
	)
}

// setTypes returns the type specifications for the Set module
func setTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Set type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Set"),
			ir.NewDocumented(
				"Type that represents a set of unique values.",
				ir.NewOpaqueTypeSpecification[ir.Unit]([]ir.Name{
					ir.NameFromString("t"),
				}),
			),
		),
	}
}

// setValues returns the value specifications for the Set module
func setValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("empty", []VSpecInput{},
			SetType(TVar("t")),
			"Create an empty set."),

		VSpec("singleton", []VSpecInput{
			{Name: "value", Type: TVar("t")},
		}, SetType(TVar("t")),
			"Create a set with one value."),

		VSpec("insert", []VSpecInput{
			{Name: "value", Type: TVar("t")},
			{Name: "set", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Insert a value into a set."),

		VSpec("remove", []VSpecInput{
			{Name: "value", Type: TVar("t")},
			{Name: "set", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Remove a value from a set. If the value is not found, no changes are made."),

		// Query
		VSpec("isEmpty", []VSpecInput{
			{Name: "set", Type: SetType(TVar("t"))},
		}, boolType(),
			"Determine if a set is empty."),

		VSpec("member", []VSpecInput{
			{Name: "value", Type: TVar("t")},
			{Name: "set", Type: SetType(TVar("t"))},
		}, boolType(),
			"Determine if a value is in a set."),

		VSpec("size", []VSpecInput{
			{Name: "set", Type: SetType(TVar("t"))},
		}, intType(),
			"Determine the number of elements in the set."),

		// Combine
		VSpec("union", []VSpecInput{
			{Name: "left", Type: SetType(TVar("t"))},
			{Name: "right", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Get the union of two sets. Keep all values."),

		VSpec("intersect", []VSpecInput{
			{Name: "left", Type: SetType(TVar("t"))},
			{Name: "right", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Get the intersection of two sets. Keeps values that appear in both sets."),

		VSpec("diff", []VSpecInput{
			{Name: "left", Type: SetType(TVar("t"))},
			{Name: "right", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Get the difference between the first set and the second. Keeps values that do not appear in the second set."),

		// Lists
		VSpec("toList", []VSpecInput{
			{Name: "set", Type: SetType(TVar("t"))},
		}, ListType(TVar("t")),
			"Convert a set into a list, sorted from lowest to highest."),

		VSpec("fromList", []VSpecInput{
			{Name: "list", Type: ListType(TVar("t"))},
		}, SetType(TVar("t")),
			"Convert a list into a set, removing any duplicates."),

		// Transform
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "set", Type: SetType(TVar("a"))},
		}, SetType(TVar("b")),
			"Map a function onto a set, creating a new set with no duplicates."),

		VSpec("foldl", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "set", Type: SetType(TVar("a"))},
		}, TVar("b"),
			"Fold over the values in a set from lowest to highest."),

		VSpec("foldr", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "set", Type: SetType(TVar("a"))},
		}, TVar("b"),
			"Fold over the values in a set from highest to lowest."),

		VSpec("filter", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("t")}, boolType())},
			{Name: "set", Type: SetType(TVar("t"))},
		}, SetType(TVar("t")),
			"Only keep elements that pass the given test."),

		VSpec("partition", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("t")}, boolType())},
			{Name: "set", Type: SetType(TVar("t"))},
		}, TupleType(SetType(TVar("t")), SetType(TVar("t"))),
			"Create two new sets. The first contains all the elements that passed the test, and the second contains all the elements that did not."),
	}
}

// SetType creates a Set type reference
func SetType(elementType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(SetModuleName(), "Set"),
		[]ir.Type[ir.Unit]{elementType},
	)
}
