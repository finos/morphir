module Morphir.IR.Distribution exposing
    ( Distribution(..)
    , lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification
    )

{-| A distribution contains all the necessary information to consume a package.

@docs Distribution


# Lookups

@docs lookupModuleSpecification, lookupTypeSpecification, lookupValueSpecification

-}

import Dict exposing (Dict)
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


{-| Look up a value specification by package, module and local name in a distribution.
-}
lookupValueSpecification : PackageName -> ModuleName -> Name -> Distribution -> Maybe (Value.Specification ())
lookupValueSpecification packageName moduleName localName distribution =
    distribution
        |> lookupModuleSpecification packageName moduleName
        |> Maybe.andThen (Module.lookupValueSpecification localName)
