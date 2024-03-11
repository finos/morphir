module rec Morphir.IR.Distribution

open Morphir.IR.Package
open Morphir.IR.Type
open Morphir.SDK.Dict

/// Type that represents a package distribution. Currently the only distribution type we provide is a `Library`.
type Distribution =
    | Library of
        packageName: PackageName *
        dependencies: Dict<PackageName, Package.Specification<unit>> *
        definition: Package.Definition<unit, Type<unit>>


let library
    (packageName: PackageName)
    (dependencies: Dict<PackageName, Package.Specification<unit>>)
    (definition: Package.Definition<unit, Type<unit>>)
    : Distribution =
    Library(packageName, dependencies, definition)

/// Get the package name of the distribution.
let lookupPackageName (distribution: Distribution) : PackageName =
    match distribution with
    | Library(packageName, _, _) -> packageName

/// Add a package specification as a dependency of this library.
let insertDependency
    (dependencyPackageName: PackageName)
    (dependencyPackageSpec: Package.Specification<unit>)
    (distribution: Distribution)
    : Distribution =
    match distribution with
    | Library(packageName, dependencies, definition) ->
        Library(
            packageName,
            insert dependencyPackageName dependencyPackageSpec dependencies,
            definition
        )
