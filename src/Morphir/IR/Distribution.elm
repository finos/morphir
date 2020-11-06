module Morphir.IR.Distribution exposing
    ( Distribution(..)
    , lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName
    )

{-| A distribution contains all the necessary information to consume a package.

@docs Distribution


# Lookups

@docs lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification, lookupBaseTypeName

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value


{-| Type that represents a package distribution.
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
