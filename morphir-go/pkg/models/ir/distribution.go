package ir

// Unit represents the Morphir unit type ().
// It is used as the default type/value attribute in distributions.
type Unit struct{}

// Distribution represents a Morphir IR distribution.
// This is the output format of `morphir-elm make` and contains everything
// needed to represent a complete package with its dependencies.
//
// Currently only the Library variant is supported.
//
// This matches Morphir.IR.Distribution in finos/morphir-elm.
type Distribution interface {
	isDistribution()
	PackageName() PackageName
}

// Library represents a library distribution.
// It contains the package name, dependencies (as specifications),
// and the complete package definition.
type Library struct {
	packageName  PackageName
	dependencies []LibraryDependency
	definition   PackageDefinition[Unit, Type[Unit]]
}

// LibraryDependency represents a dependency in a library distribution.
type LibraryDependency struct {
	name PackageName
	spec PackageSpecification[Unit]
}

// LibraryDependencyFromParts creates a library dependency.
func LibraryDependencyFromParts(name PackageName, spec PackageSpecification[Unit]) LibraryDependency {
	return LibraryDependency{name: name, spec: spec}
}

func (d LibraryDependency) Name() PackageName                { return d.name }
func (d LibraryDependency) Spec() PackageSpecification[Unit] { return d.spec }

// NewLibrary creates a new library distribution.
func NewLibrary(
	packageName PackageName,
	dependencies []LibraryDependency,
	definition PackageDefinition[Unit, Type[Unit]],
) Library {
	var depsCopy []LibraryDependency
	if len(dependencies) > 0 {
		depsCopy = make([]LibraryDependency, len(dependencies))
		copy(depsCopy, dependencies)
	}
	return Library{
		packageName:  packageName,
		dependencies: depsCopy,
		definition:   definition,
	}
}

func (Library) isDistribution() {}

// PackageName returns the package name of this library.
func (l Library) PackageName() PackageName { return l.packageName }

// Dependencies returns the dependencies of this library.
func (l Library) Dependencies() []LibraryDependency {
	if len(l.dependencies) == 0 {
		return nil
	}
	copied := make([]LibraryDependency, len(l.dependencies))
	copy(copied, l.dependencies)
	return copied
}

// Definition returns the package definition of this library.
func (l Library) Definition() PackageDefinition[Unit, Type[Unit]] {
	return l.definition
}

// LookupPackageSpecification looks up a dependency package specification by name.
func LookupPackageSpecification(name PackageName, lib Library) *PackageSpecification[Unit] {
	for _, dep := range lib.dependencies {
		if dep.name.Equal(name) {
			return &dep.spec
		}
	}
	return nil
}
