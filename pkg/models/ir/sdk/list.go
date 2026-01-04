package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// ListModuleName returns the module name for Morphir.SDK.List
func ListModuleName() ir.ModuleName {
	return ir.PathFromString("List")
}

// ListModuleSpec returns the module specification for Morphir.SDK.List
func ListModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		listTypes(),
		listValues(),
		nil,
	)
}

// listTypes returns the type specifications for the List module
func listTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// List type (parameterized by element type)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("List"),
			ir.NewDocumented(
				"Type that represents a list of values.",
				ir.NewOpaqueTypeSpecification[ir.Unit]([]ir.Name{
					ir.NameFromString("a"),
				}),
			),
		),
	}
}

// listValues returns the value specifications for the List module
func listValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("singleton", []VSpecInput{
			{Name: "value", Type: TVar("a")},
		}, ListType(TVar("a")), "Create a list with only one element."),

		VSpec("repeat", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "value", Type: TVar("a")},
		}, ListType(TVar("a")), "Create a list with n copies of a value."),

		VSpec("range", []VSpecInput{
			{Name: "start", Type: intType()},
			{Name: "end", Type: intType()},
		}, ListType(intType()), "Create a list of numbers, every element increasing by one."),

		VSpec("cons", []VSpecInput{
			{Name: "head", Type: TVar("a")},
			{Name: "tail", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Add an element to the front of a list."),

		// Transformation
		VSpec("map", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("b"))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("b")), "Apply a function to every element of a list."),

		VSpec("indexedMap", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{intType(), TVar("a")}, TVar("b"))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("b")), "Same as map but the function is also applied to the index of each element."),

		VSpec("foldl", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "list", Type: ListType(TVar("a"))},
		}, TVar("b"), "Reduce a list from the left."),

		VSpec("foldr", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("b"))},
			{Name: "acc", Type: TVar("b")},
			{Name: "list", Type: ListType(TVar("a"))},
		}, TVar("b"), "Reduce a list from the right."),

		VSpec("filter", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Keep only elements that satisfy the predicate."),

		VSpec("filterMap", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, MaybeType(TVar("b")))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("b")), "Filter and transform elements of a list."),

		// Utilities
		VSpec("length", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, intType(), "Determine the length of a list."),

		VSpec("reverse", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Reverse a list."),

		VSpec("member", []VSpecInput{
			{Name: "value", Type: TVar("a")},
			{Name: "list", Type: ListType(TVar("a"))},
		}, boolType(), "Figure out whether a list contains a value."),

		VSpec("all", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "list", Type: ListType(TVar("a"))},
		}, boolType(), "Determine if all elements satisfy some test."),

		VSpec("any", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "list", Type: ListType(TVar("a"))},
		}, boolType(), "Determine if any elements satisfy some test."),

		VSpec("maximum", []VSpecInput{
			{Name: "list", Type: ListType(TVar("comparable"))},
		}, MaybeType(TVar("comparable")), "Find the maximum element in a non-empty list."),

		VSpec("minimum", []VSpecInput{
			{Name: "list", Type: ListType(TVar("comparable"))},
		}, MaybeType(TVar("comparable")), "Find the minimum element in a non-empty list."),

		VSpec("sum", []VSpecInput{
			{Name: "list", Type: ListType(TVar("number"))},
		}, TVar("number"), "Get the sum of the list elements."),

		VSpec("product", []VSpecInput{
			{Name: "list", Type: ListType(TVar("number"))},
		}, TVar("number"), "Get the product of the list elements."),

		// Combining
		VSpec("append", []VSpecInput{
			{Name: "list1", Type: ListType(TVar("a"))},
			{Name: "list2", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Put two lists together."),

		VSpec("concat", []VSpecInput{
			{Name: "lists", Type: ListType(ListType(TVar("a")))},
		}, ListType(TVar("a")), "Concatenate a bunch of lists into a single list."),

		VSpec("concatMap", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, ListType(TVar("b")))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("b")), "Map a given function onto a list and flatten the results."),

		VSpec("intersperse", []VSpecInput{
			{Name: "separator", Type: TVar("a")},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Place a value between all members of a list."),

		// map2 through map5
		VSpec("map2", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, TVar("c"))},
			{Name: "list1", Type: ListType(TVar("a"))},
			{Name: "list2", Type: ListType(TVar("b"))},
		}, ListType(TVar("c")), "Combine two lists, combining them with the given function."),

		VSpec("map3", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c")}, TVar("d"))},
			{Name: "list1", Type: ListType(TVar("a"))},
			{Name: "list2", Type: ListType(TVar("b"))},
			{Name: "list3", Type: ListType(TVar("c"))},
		}, ListType(TVar("d")), "Combine three lists with a function."),

		VSpec("map4", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d")}, TVar("e"))},
			{Name: "list1", Type: ListType(TVar("a"))},
			{Name: "list2", Type: ListType(TVar("b"))},
			{Name: "list3", Type: ListType(TVar("c"))},
			{Name: "list4", Type: ListType(TVar("d"))},
		}, ListType(TVar("e")), "Combine four lists with a function."),

		VSpec("map5", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b"), TVar("c"), TVar("d"), TVar("e")}, TVar("f"))},
			{Name: "list1", Type: ListType(TVar("a"))},
			{Name: "list2", Type: ListType(TVar("b"))},
			{Name: "list3", Type: ListType(TVar("c"))},
			{Name: "list4", Type: ListType(TVar("d"))},
			{Name: "list5", Type: ListType(TVar("e"))},
		}, ListType(TVar("f")), "Combine five lists with a function."),

		// Sorting
		VSpec("sort", []VSpecInput{
			{Name: "list", Type: ListType(TVar("comparable"))},
		}, ListType(TVar("comparable")), "Sort values from lowest to highest."),

		VSpec("sortBy", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("comparable"))},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Sort values by a derived property."),

		VSpec("sortWith", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("a")}, orderType())},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Sort values with a custom comparison function."),

		// Deconstruction
		VSpec("isEmpty", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, boolType(), "Determine if a list is empty."),

		VSpec("head", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, MaybeType(TVar("a")), "Extract the first element of a list."),

		VSpec("tail", []VSpecInput{
			{Name: "list", Type: ListType(TVar("a"))},
		}, MaybeType(ListType(TVar("a"))), "Extract the elements after the head of a list."),

		VSpec("take", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Take the first n members of a list."),

		VSpec("drop", []VSpecInput{
			{Name: "n", Type: intType()},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ListType(TVar("a")), "Drop the first n members of a list."),

		VSpec("partition", []VSpecInput{
			{Name: "predicate", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, boolType())},
			{Name: "list", Type: ListType(TVar("a"))},
		}, ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
			ListType(TVar("a")),
			ListType(TVar("a")),
		}), "Partition a list based on some test."),

		VSpec("unzip", []VSpecInput{
			{Name: "list", Type: ListType(ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
				TVar("a"),
				TVar("b"),
			}))},
		}, ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
			ListType(TVar("a")),
			ListType(TVar("b")),
		}), "Decompose a list of tuples into a tuple of lists."),

		// Joins
		VSpec("innerJoin", []VSpecInput{
			{Name: "right", Type: ListType(TVar("b"))},
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, boolType())},
			{Name: "left", Type: ListType(TVar("a"))},
		}, ListType(ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
			TVar("a"),
			TVar("b"),
		})), "Inner join two lists."),

		VSpec("leftJoin", []VSpecInput{
			{Name: "right", Type: ListType(TVar("b"))},
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a"), TVar("b")}, boolType())},
			{Name: "left", Type: ListType(TVar("a"))},
		}, ListType(ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{
			TVar("a"),
			MaybeType(TVar("b")),
		})), "Left join two lists."),
	}
}

// ListType creates a List type reference with the given element type
func ListType(elementType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(ListModuleName(), "List"),
		[]ir.Type[ir.Unit]{elementType},
	)
}

// MaybeType creates a Maybe type reference (forward reference for now)
// This will be properly defined in the Maybe module
func MaybeType(valueType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(ir.PathFromString("Maybe"), "Maybe"),
		[]ir.Type[ir.Unit]{valueType},
	)
}
