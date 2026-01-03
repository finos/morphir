package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/stable/ir"
)

// TupleModuleName returns the module name for Morphir.SDK.Tuple
func TupleModuleName() ir.ModuleName {
	return ir.PathFromString("Tuple")
}

// TupleModuleSpec returns the module specification for Morphir.SDK.Tuple
func TupleModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		nil, // No types defined in Tuple module
		tupleValues(),
		nil,
	)
}

// tupleValues returns the value specifications for the Tuple module
func tupleValues() []ir.ModuleSpecificationValue[ir.Unit] {
	return []ir.ModuleSpecificationValue[ir.Unit]{
		// Construction
		VSpec("pair", []VSpecInput{
			{Name: "first", Type: TVar("a")},
			{Name: "second", Type: TVar("b")},
		}, TupleType(TVar("a"), TVar("b")), "Create a 2-tuple."),

		// Accessors
		VSpec("first", []VSpecInput{
			{Name: "tuple", Type: TupleType(TVar("a"), TVar("b"))},
		}, TVar("a"), "Extract the first value from a tuple."),

		VSpec("second", []VSpecInput{
			{Name: "tuple", Type: TupleType(TVar("a"), TVar("b"))},
		}, TVar("b"), "Extract the second value from a tuple."),

		// Mapping
		VSpec("mapFirst", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("x"))},
			{Name: "tuple", Type: TupleType(TVar("a"), TVar("b"))},
		}, TupleType(TVar("x"), TVar("b")), "Transform the first value in a tuple."),

		VSpec("mapSecond", []VSpecInput{
			{Name: "f", Type: TFun([]ir.Type[ir.Unit]{TVar("b")}, TVar("y"))},
			{Name: "tuple", Type: TupleType(TVar("a"), TVar("b"))},
		}, TupleType(TVar("a"), TVar("y")), "Transform the second value in a tuple."),

		VSpec("mapBoth", []VSpecInput{
			{Name: "f1", Type: TFun([]ir.Type[ir.Unit]{TVar("a")}, TVar("x"))},
			{Name: "f2", Type: TFun([]ir.Type[ir.Unit]{TVar("b")}, TVar("y"))},
			{Name: "tuple", Type: TupleType(TVar("a"), TVar("b"))},
		}, TupleType(TVar("x"), TVar("y")), "Transform both values in a tuple."),
	}
}

// TupleType creates a 2-tuple type
func TupleType(firstType ir.Type[ir.Unit], secondType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeTuple(ir.Unit{}, []ir.Type[ir.Unit]{firstType, secondType})
}
