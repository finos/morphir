package sdk

import (
	ir "github.com/finos/morphir/pkg/models/ir"
)

// StatefulAppModuleName returns the module name for Morphir.SDK.StatefulApp
func StatefulAppModuleName() ir.ModuleName {
	return ir.PathFromString("StatefulApp")
}

// StatefulAppModuleSpec returns the module specification for Morphir.SDK.StatefulApp
func StatefulAppModuleSpec() ir.ModuleSpecification[ir.Unit] {
	return ir.NewModuleSpecification(
		statefulAppTypes(),
		nil, // No functions defined in this module
		nil,
	)
}

// statefulAppTypes returns the type specifications for the StatefulApp module
func statefulAppTypes() []ir.ModuleSpecificationType[ir.Unit] {
	return []ir.ModuleSpecificationType[ir.Unit]{
		// StatefulApp type (custom type with one constructor)
		ir.ModuleSpecificationTypeFromParts[ir.Unit](
			ir.NameFromString("StatefulApp"),
			ir.NewDocumented(
				"Type that represents a stateful application.",
				ir.NewCustomTypeSpecification[ir.Unit](
					[]ir.Name{
						ir.NameFromString("k"),
						ir.NameFromString("c"),
						ir.NameFromString("s"),
						ir.NameFromString("e"),
					},
					ir.TypeConstructors[ir.Unit]{
						ir.TypeConstructorFromParts[ir.Unit](
							ir.NameFromString("StatefulApp"),
							ir.TypeConstructorArgs[ir.Unit]{
								ir.TypeConstructorArgFromParts(
									ir.NameFromString("logic"),
									// logic : Maybe s -> c -> (Maybe s, e)
									TFun(
										[]ir.Type[ir.Unit]{
											MaybeType(TVar("s")),
											TVar("c"),
										},
										TupleType(MaybeType(TVar("s")), TVar("e")),
									),
								),
							},
						),
					},
				),
			),
		),
	}
}

// StatefulAppType creates a StatefulApp type reference
func StatefulAppType(kType, cType, sType, eType ir.Type[ir.Unit]) ir.Type[ir.Unit] {
	return ir.NewTypeReference(
		ir.Unit{},
		ToFQName(StatefulAppModuleName(), "StatefulApp"),
		[]ir.Type[ir.Unit]{kType, cType, sType, eType},
	)
}
