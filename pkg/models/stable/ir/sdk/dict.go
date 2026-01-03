package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// DictModuleName returns the module name for Morphir.SDK.Dict
func DictModuleName() ir.ModuleName {
	return ir.PathFromString("Dict")
}

// DictModuleSpec returns the module specification for Morphir.SDK.Dict
func DictModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		dictTypes(),
		dictValues(),
		nil,
	)
}

// dictTypes returns the type specifications for the Dict module
func dictTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// Dict type
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("Dict"),
			ir.NewDocumented(
				"Type that represents a dictionary of key-value pairs.",
				ir.NewOpaqueTypeSpecification[ir.Unit]([]ir.Name{
					ir.NameFromString("k"),
					ir.NameFromString("v"),
				}),
			),
		),
	}
}

// dictValues returns the value specifications for the Dict module
func dictValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("empty", []VSpecInput{},
			DictType(TVar("k"), TVar("v")),
			"Create an empty dictionary."),

		VSpec("singleton", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "value", Type: TVar("v")},
		}, DictType(TVar("k"), TVar("v")),
			"Create a dictionary with one key-value pair."),

		VSpec("insert", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "value", Type: TVar("v")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Insert a key-value pair into a dictionary. Replaces value when there is a collision."),

		VSpec("update", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{MaybeType(TVar("v"))}, MaybeType(TVar("v")))},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Update the value of a dictionary for a specific key with a given function."),

		VSpec("remove", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Remove a key-value pair from a dictionary. If the key is not found, no changes are made."),

		// Query
		VSpec("isEmpty", []VSpecInput{
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, boolType(),
			"Determine if a dictionary is empty."),

		VSpec("member", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, boolType(),
			"Determine if a key is in a dictionary."),

		VSpec("get", []VSpecInput{
			{Name: "key", Type: TVar("k")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, MaybeType(TVar("v")),
			"Get the value associated with a key."),

		VSpec("size", []VSpecInput{
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, intType(),
			"Determine the number of key-value pairs in the dictionary."),

		// Lists
		VSpec("keys", []VSpecInput{
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, ListType(TVar("k")),
			"Get all of the keys in a dictionary, sorted from lowest to highest."),

		VSpec("values", []VSpecInput{
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, ListType(TVar("v")),
			"Get all of the values in a dictionary, in the order of their keys."),

		VSpec("toList", []VSpecInput{
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, ListType(TupleType(TVar("k"), TVar("v"))),
			"Convert a dictionary into an association list of key-value pairs, sorted by keys."),

		VSpec("fromList", []VSpecInput{
			{Name: "list", Type: ListType(TupleType(TVar("k"), TVar("v")))},
		}, DictType(TVar("k"), TVar("v")),
			"Convert an association list into a dictionary."),

		// Transform
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("a")}, TVar("b"))},
			{Name: "dict", Type: DictType(TVar("k"), TVar("a"))},
		}, DictType(TVar("k"), TVar("b")),
			"Apply a function to all values in a dictionary."),

		VSpec("foldl", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("v"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, TVar("b"),
			"Fold over the key-value pairs in a dictionary from lowest key to highest key."),

		VSpec("foldr", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("v"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, TVar("b"),
			"Fold over the key-value pairs in a dictionary from highest key to lowest key."),

		VSpec("filter", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("v")}, boolType())},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Keep only the key-value pairs that pass the given test."),

		VSpec("partition", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("v")}, boolType())},
			{Name: "dict", Type: DictType(TVar("k"), TVar("v"))},
		}, TupleType(DictType(TVar("k"), TVar("v")), DictType(TVar("k"), TVar("v"))),
			"Partition a dictionary according to some test. The first dictionary contains all key-value pairs which passed the test, and the second contains the pairs that did not."),

		// Combine
		VSpec("union", []VSpecInput{
			{Name: "left", Type: DictType(TVar("k"), TVar("v"))},
			{Name: "right", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Combine two dictionaries. If there is a collision, preference is given to the first dictionary."),

		VSpec("intersect", []VSpecInput{
			{Name: "left", Type: DictType(TVar("k"), TVar("v"))},
			{Name: "right", Type: DictType(TVar("k"), TVar("v"))},
		}, DictType(TVar("k"), TVar("v")),
			"Keep a key-value pair when its key appears in the second dictionary. Preference is given to values in the first dictionary."),

		VSpec("diff", []VSpecInput{
			{Name: "left", Type: DictType(TVar("k"), TVar("a"))},
			{Name: "right", Type: DictType(TVar("k"), TVar("b"))},
		}, DictType(TVar("k"), TVar("a")),
			"Keep a key-value pair when its key does not appear in the second dictionary."),

		VSpec("merge", []VSpecInput{
			{Name: "leftOnly", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("a"), TVar("result")}, TVar("result"))},
			{Name: "both", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("a"), TVar("b"), TVar("result")}, TVar("result"))},
			{Name: "rightOnly", Type: TFun([]ir.Type[ir.Unit]{TVar("k"), TVar("b"), TVar("result")}, TVar("result"))},
			{Name: "leftDict", Type: DictType(TVar("k"), TVar("a"))},
			{Name: "rightDict", Type: DictType(TVar("k"), TVar("b"))},
			{Name: "initialResult", Type: TVar("result")},
		}, TVar("result"),
			"The most general way of combining two dictionaries. You provide three accumulators for when a given key appears in the left dict, in both, or in the right dict."),
	}
}

// DictType creates a Dict type reference
func DictType(keyType ir.Type[ir.Unit], valueType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(DictModuleName(), "Dict"),
		[]ir.Type[ir.Unit]{keyType, valueType},
	)
}
