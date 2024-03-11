module rec Morphir.IR.Package

open Morphir.IR.AccessControlled
open Morphir.IR.Path
open Morphir.IR.Module
open Morphir.SDK.Dict
open Morphir.SDK.Maybe

/// A package name is a globally unique identifier for a package. It is represented by a path, which
/// is a list of names.
type PackageName = PackageName.PackageName

/// Type that represents a package specification. A package specification only contains types that
/// are exposed publicly and type signatures for values that are exposed publicly.
type Specification<'TA> =
    { Modules: Dict<ModuleName, Module.Specification<'TA>> }

/// Type that represents a package definition. A package definition contains all the details including implementation
/// and private types and values. The modules field is a dictionary keyed by module name that contains access controlled
/// module definitions. The `AccessControlled` adds access classifiers to each module to differentiate public and private
/// modules.
type Definition<'TA, 'VA> =
    { Modules: Dict<ModuleName, AccessControlled<Module.Definition<'TA, 'VA>>> }

/// Get an empty package specification with no modules.
let emptySpecification<'TA> = { Modules = Map.empty }

/// Get an empty package definition with no modules.
let emptyDefinition<'TA, 'VA> = { Modules = Map.empty }

let specification (modules: Dict<ModuleName, Module.Specification<'TA>>) = { Specification.Modules = modules }

let definition (modules: Dict<ModuleName, AccessControlled<Module.Definition<'TA, 'VA>>>) =
    { Definition.Modules = modules }

/// Look up a module specification by its path in a package specification.
let lookupModuleSpecification (modulePath: Path) (packageSpec: Specification<'ta>) : Maybe<Module.Specification<'ta>> =
    packageSpec.Modules |> get modulePath

/// Look up a module definition by its path in a package definition.
let lookupModuleDefinition (modulePath: Path) (packageDef: Definition<'ta, 'va>) : Maybe<Module.Definition<'ta, 'va>> =
    packageDef.Modules |> get modulePath |> map withPrivateAccess
