module Morphir.IR.Distribution exposing
    ( Distribution(..)
    , lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName, lookupValueDefinition
    )

{-| A distribution is a complete package of Morphir types and functions with all their dependencies.
`morphir-elm make` produces a JSON that represents a `Distribution`. We are planning to define different types of
distributions in the future but currently the only one is `Library`. A library contains the following pieces of
information:

  - The name of the library. This is the globally unique identifier of the package like the package name in NPM or the
    Group and Artifact ID in Maven.
  - All the library dependencies as a dictionary of package name and package specification. The package specification
    only contains type signatures, no implementations.
  - The package definition which contains all the module definitions included in the library. The package definition
    contains implementations as well, even ones that are not exposed.

@docs Distribution


# Lookups

@docs lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName, lookupValueDefinition

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName, lookupModuleDefinition)
import Morphir.IR.QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value


{-| Type that represents a package distribution. Currently the only distribution type we provide is a `Library`.
-}
type Distribution
    = Library PackageName (Dict PackageName (Package.Specification ())) (Package.Definition () (Type ()))


{-| Look up a module specification by package and module path in a distribution.
-}
lookupModuleSpecification : PackageName -> ModuleName -> Distribution -> Maybe (Module.Specification ())
lookupModuleSpecification packageName modulePath distribution =
    case distribution of
        Library libraryPackageName dependencies packageDef ->
            if packageName == libraryPackageName then
                packageDef
                    |> Package.definitionToSpecification
                    |> Package.lookupModuleSpecification modulePath

            else
                dependencies
                    |> Dict.get packageName
                    |> Maybe.andThen (Package.lookupModuleSpecification modulePath)


{-| Look up a type specification by package, module and local name in a distribution.
-}
lookupTypeSpecification : PackageName -> ModuleName -> Name -> Distribution -> Maybe (Type.Specification ())
lookupTypeSpecification packageName moduleName localName distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupTypeSpecification localName)


{-| Look up the base type name following aliases by package, module and local name in a distribution.
-}
lookupBaseTypeName : FQName -> Distribution -> Maybe FQName
lookupBaseTypeName ((FQName packageName moduleName localName) as fQName) distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupTypeSpecification localName)
        |> Maybe.andThen
            (\typeSpec ->
                case typeSpec of
                    Type.TypeAliasSpecification _ (Type.Reference _ aliasFQName _) ->
                        lookupBaseTypeName aliasFQName distribution

                    _ ->
                        Just fQName
            )


{-| Look up a value specification by package, module and local name in a distribution.
-}
lookupValueSpecification : PackageName -> ModuleName -> Name -> Distribution -> Maybe (Value.Specification ())
lookupValueSpecification packageName moduleName localName distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupValueSpecification localName)


{-| Look up a value definition by qualified name in a distribution. The value will only be searched in the current
package.
-}
lookupValueDefinition : QName -> Distribution -> Maybe (Value.Definition () (Type ()))
lookupValueDefinition (QName moduleName localName) distribution =
    case distribution of
        Library _ _ packageDef ->
            packageDef
                |> lookupModuleDefinition moduleName
                |> Maybe.andThen (Module.lookupValueDefinition localName)
