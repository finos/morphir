package ir

// PackageName is a globally unique identifier for a package.
// It is represented by a Path, which is a list of names.
type PackageName = Path

// PackageSpecification represents a package specification.
// A package specification only contains types that are exposed publicly
// and type signatures for values that are exposed publicly.
//
// This matches Morphir.IR.Package.Specification in finos/morphir-elm.
type PackageSpecification[TA any] struct {
	modules []PackageSpecificationModule[TA]
}

// PackageSpecificationModule represents a module in a package specification.
type PackageSpecificationModule[TA any] struct {
	name ModuleName
	spec ModuleSpecification[TA]
}

// PackageSpecificationModuleFromParts creates a package specification module.
func PackageSpecificationModuleFromParts[TA any](name ModuleName, spec ModuleSpecification[TA]) PackageSpecificationModule[TA] {
	return PackageSpecificationModule[TA]{name: name, spec: spec}
}

func (m PackageSpecificationModule[TA]) Name() ModuleName              { return m.name }
func (m PackageSpecificationModule[TA]) Spec() ModuleSpecification[TA] { return m.spec }

// NewPackageSpecification creates a new package specification.
func NewPackageSpecification[TA any](modules []PackageSpecificationModule[TA]) PackageSpecification[TA] {
	var modulesCopy []PackageSpecificationModule[TA]
	if len(modules) > 0 {
		modulesCopy = make([]PackageSpecificationModule[TA], len(modules))
		copy(modulesCopy, modules)
	}
	return PackageSpecification[TA]{modules: modulesCopy}
}

// Modules returns the modules in this package specification.
func (p PackageSpecification[TA]) Modules() []PackageSpecificationModule[TA] {
	if len(p.modules) == 0 {
		return nil
	}
	copied := make([]PackageSpecificationModule[TA], len(p.modules))
	copy(copied, p.modules)
	return copied
}

// EmptyPackageSpecification returns an empty package specification.
func EmptyPackageSpecification[TA any]() PackageSpecification[TA] {
	return PackageSpecification[TA]{}
}

// LookupModuleSpecification looks up a module specification by name in a package specification.
func LookupModuleSpecification[TA any](name ModuleName, spec PackageSpecification[TA]) *ModuleSpecification[TA] {
	for _, m := range spec.modules {
		if m.name.Equal(name) {
			return &m.spec
		}
	}
	return nil
}

// PackageDefinition represents a package definition.
// A package definition contains all the details including implementation
// and private types and values.
//
// This matches Morphir.IR.Package.Definition in finos/morphir-elm.
type PackageDefinition[TA any, VA any] struct {
	modules []PackageDefinitionModule[TA, VA]
}

// PackageDefinitionModule represents a module in a package definition.
type PackageDefinitionModule[TA any, VA any] struct {
	name       ModuleName
	definition AccessControlled[ModuleDefinition[TA, VA]]
}

// PackageDefinitionModuleFromParts creates a package definition module.
func PackageDefinitionModuleFromParts[TA any, VA any](name ModuleName, definition AccessControlled[ModuleDefinition[TA, VA]]) PackageDefinitionModule[TA, VA] {
	return PackageDefinitionModule[TA, VA]{name: name, definition: definition}
}

func (m PackageDefinitionModule[TA, VA]) Name() ModuleName { return m.name }
func (m PackageDefinitionModule[TA, VA]) Definition() AccessControlled[ModuleDefinition[TA, VA]] {
	return m.definition
}

// NewPackageDefinition creates a new package definition.
func NewPackageDefinition[TA any, VA any](modules []PackageDefinitionModule[TA, VA]) PackageDefinition[TA, VA] {
	var modulesCopy []PackageDefinitionModule[TA, VA]
	if len(modules) > 0 {
		modulesCopy = make([]PackageDefinitionModule[TA, VA], len(modules))
		copy(modulesCopy, modules)
	}
	return PackageDefinition[TA, VA]{modules: modulesCopy}
}

// Modules returns the modules in this package definition.
func (p PackageDefinition[TA, VA]) Modules() []PackageDefinitionModule[TA, VA] {
	if len(p.modules) == 0 {
		return nil
	}
	copied := make([]PackageDefinitionModule[TA, VA], len(p.modules))
	copy(copied, p.modules)
	return copied
}

// EmptyPackageDefinition returns an empty package definition.
func EmptyPackageDefinition[TA any, VA any]() PackageDefinition[TA, VA] {
	return PackageDefinition[TA, VA]{}
}

// LookupModuleDefinition looks up a module definition by name in a package definition.
func LookupModuleDefinition[TA any, VA any](name ModuleName, def PackageDefinition[TA, VA]) *AccessControlled[ModuleDefinition[TA, VA]] {
	for _, m := range def.modules {
		if m.name.Equal(name) {
			return &m.definition
		}
	}
	return nil
}
