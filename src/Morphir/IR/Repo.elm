module Morphir.IR.Repo exposing (..)

import Dict exposing (Dict)
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented as Documented
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Value.Native as Native
import Set exposing (Set)


type alias Repo =
    { packageName : PackageName
    , dependencies : Dict PackageName (Package.Definition () (Type ()))
    , modules : Dict ModuleName (Module.Definition () (Type ()))
    , moduleDependencies : DAG ModuleName
    , nativeFunctions : Dict FQName Native.Function
    }


type alias SourceCode =
    String


type alias Errors =
    List Error


type Error
    = ModuleNotFound ModuleName
    | ModuleHasDependents ModuleName (Set ModuleName)
    | ModuleAlreadyExist ModuleName
    | TypeAlreadyExist Name


{-| Creates a repo from scratch when there is no existing IR.
-}
empty : PackageName -> Repo
empty packageName =
    { packageName = packageName
    , dependencies = Dict.empty
    , modules = Dict.empty
    , nativeFunctions = Dict.empty
    , moduleDependencies = DAG.empty
    }


{-| Creates a repo from an existing IR.
-}
fromDistribution : Distribution -> Result Errors Repo
fromDistribution distro =
    case distro of
        Library packageName _ packageDef ->
            packageDef.modules
                |> Dict.toList
                |> List.foldl
                    (\( moduleName, accessControlledModuleDef ) repoResultSoFar ->
                        repoResultSoFar
                            |> Result.andThen
                                (\repoSoFar ->
                                    repoSoFar
                                        |> insertModule moduleName accessControlledModuleDef.value
                                )
                    )
                    (Ok (empty packageName))


{-| Creates a distribution from an existing repo
-}
toDistribution : Repo -> Distribution
toDistribution repo =
    Library repo.packageName
        (repo.dependencies
            |> Dict.map (always Package.definitionToSpecification)
        )
        { modules =
            repo.modules
                |> Dict.map (always public)
        }


{-| Adds native functions to the repo. For now this will be mainly used to add `SDK.nativeFunctions`.
-}
mergeNativeFunctions : Dict FQName Native.Function -> Repo -> Result Errors Repo
mergeNativeFunctions newNativeFunction repo =
    Ok
        { repo
            | nativeFunctions =
                repo.nativeFunctions
                    |> Dict.union newNativeFunction
        }


{-| Insert a module if it's not in the repo yet.
-}
insertModule : ModuleName -> Module.Definition () (Type ()) -> Repo -> Result Errors Repo
insertModule moduleName moduleDef repo =
    let
        validationErrors : Maybe Errors
        validationErrors =
            case repo.modules |> Dict.get moduleName of
                Just _ ->
                    Just [ ModuleAlreadyExist moduleName ]

                Nothing ->
                    Nothing
    in
    validationErrors
        |> Maybe.map Err
        |> Maybe.withDefault
            (Ok
                { repo
                    | modules =
                        repo.modules
                            |> Dict.insert moduleName moduleDef
                }
            )


deleteModule : ModuleName -> Repo -> Result Errors Repo
deleteModule moduleName repo =
    let
        validationErrors : Maybe Errors
        validationErrors =
            case repo.modules |> Dict.get moduleName of
                Nothing ->
                    Just [ ModuleNotFound moduleName ]

                Just _ ->
                    let
                        dependentModules =
                            repo.moduleDependencies |> DAG.incomingEdges moduleName
                    in
                    if Set.isEmpty dependentModules then
                        Nothing

                    else
                        Just [ ModuleHasDependents moduleName dependentModules ]
    in
    validationErrors
        |> Maybe.map Err
        |> Maybe.withDefault
            (Ok
                { repo
                    | modules =
                        repo.modules
                            |> Dict.remove moduleName
                    , moduleDependencies =
                        repo.moduleDependencies
                            |> Dict.remove moduleName
                }
            )


insertType : ModuleName -> Name -> Type.Definition () -> Repo -> Result Errors Repo
insertType moduleName typeName typeDef repo =
    case repo.modules |> Dict.get moduleName of
        Just modDefinition ->
            case modDefinition.types |> Dict.get typeName of
                Just _ ->
                    Err [ TypeAlreadyExist typeName ]

                Nothing ->
                    let
                        alteredModule : Maybe (Module.Definition () (Type ())) -> Maybe (Module.Definition () (Type ()))
                        alteredModule maybeModuleDefinition =
                            maybeModuleDefinition
                                |> Maybe.map
                                    (\modDef ->
                                        { modDef
                                            | types =
                                                modDefinition.types
                                                    |> Dict.insert typeName (public (typeDef |> Documented.Documented ""))
                                        }
                                    )
                    in
                    Ok
                        { repo
                            | modules =
                                repo.modules
                                    |> Dict.update moduleName alteredModule
                        }

        Nothing ->
            Err [ ModuleNotFound moduleName ]


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed value =
    if isExposed then
        AccessControlled.public value

    else
        AccessControlled.private value
