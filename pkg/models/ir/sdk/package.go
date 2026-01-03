package sdk

import (
	ir "github.com/finos/morphir-go/pkg/models/ir"
)

// PackageName returns the package name for the Morphir SDK
func PackageName() ir.PackageName {
	return ir.PathFromString("Morphir.SDK")
}

// PackageSpec returns the complete package specification for the Morphir SDK.
// This aggregates all individual module specifications into a single package.
func PackageSpec() ir.PackageSpecification[ir.Unit] {
	modules := []ir.PackageSpecificationModule[ir.Unit]{
		// Core types
		ir.PackageSpecificationModuleFromParts(BasicsModuleName(), BasicsModuleSpec()),
		ir.PackageSpecificationModuleFromParts(ListModuleName(), ListModuleSpec()),
		ir.PackageSpecificationModuleFromParts(MaybeModuleName(), MaybeModuleSpec()),
		ir.PackageSpecificationModuleFromParts(ResultModuleName(), ResultModuleSpec()),

		// String and character operations
		ir.PackageSpecificationModuleFromParts(StringModuleName(), StringModuleSpec()),
		ir.PackageSpecificationModuleFromParts(CharModuleName(), CharModuleSpec()),

		// Numeric types
		ir.PackageSpecificationModuleFromParts(IntModuleName(), IntModuleSpec()),
		ir.PackageSpecificationModuleFromParts(DecimalModuleName(), DecimalModuleSpec()),
		ir.PackageSpecificationModuleFromParts(NumberModuleName(), NumberModuleSpec()),

		// Collections
		ir.PackageSpecificationModuleFromParts(TupleModuleName(), TupleModuleSpec()),
		ir.PackageSpecificationModuleFromParts(DictModuleName(), DictModuleSpec()),
		ir.PackageSpecificationModuleFromParts(SetModuleName(), SetModuleSpec()),

		// Date and time
		ir.PackageSpecificationModuleFromParts(LocalDateModuleName(), LocalDateModuleSpec()),
		ir.PackageSpecificationModuleFromParts(LocalTimeModuleName(), LocalTimeModuleSpec()),

		// Advanced patterns
		ir.PackageSpecificationModuleFromParts(ResultListModuleName(), ResultListModuleSpec()),
		ir.PackageSpecificationModuleFromParts(AggregateModuleName(), AggregateModuleSpec()),
		ir.PackageSpecificationModuleFromParts(RuleModuleName(), RuleModuleSpec()),
		ir.PackageSpecificationModuleFromParts(StatefulAppModuleName(), StatefulAppModuleSpec()),

		// Specialized types
		ir.PackageSpecificationModuleFromParts(UUIDModuleName(), UUIDModuleSpec()),
		ir.PackageSpecificationModuleFromParts(KeyModuleName(), KeyModuleSpec()),
		ir.PackageSpecificationModuleFromParts(RegexModuleName(), RegexModuleSpec()),
	}

	return ir.NewPackageSpecification(modules)
}
