module Morphir.IR.Repo exposing (..)

import Dict exposing (Dict)
import Morphir.Dependency.DAG as DAG exposing (CycleDetected, DAG)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented as Documented
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Value.Native as Native
import Set exposing (Set)


type alias Repo =
    { packageName : PackageName
    , dependencies : Dict PackageName (Package.Specification ())
    , modules : Dict ModuleName (AccessControlled (Module.Definition () (Type ())))
    , moduleDependencies : DAG ModuleName
    , nativeFunctions : Dict FQName Native.Function
    , typeDependencies : DAG FQName
    , valueDependencies : DAG FQName
    }


type alias SourceCode =
    String


type alias Errors =
    List Error


type Error
    = ModuleNotFound ModuleName
    | ModuleHasDependents ModuleName (Set ModuleName)
    | ModuleAlreadyExist ModuleName
    | TypeAlreadyExist FQName
    | DependencyAlreadyExists PackageName
    | ValueAlreadyExist Name
    | TypeCycleDetected Name
    | ValueCycleDetected Name


{-| Creates a repo from scratch when there is no existing IR.
-}
empty : PackageName -> Repo
empty packageName =
    { packageName = packageName
    , dependencies = Dict.empty
    , modules = Dict.empty
    , nativeFunctions = Dict.empty
    , moduleDependencies = DAG.empty
    , typeDependencies = DAG.empty
    , valueDependencies = DAG.empty
    }


{-| Creates a repo from an existing IR.
-}
fromDistribution : Distribution -> Result Errors Repo
fromDistribution distro =
    case distro of
        Library packageName _ packageDef ->
            Package.modulesOrderedByDependency packageName packageDef
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
        repo.dependencies
        { modules =
            repo.modules
        }


insertDependencySpecification : PackageName -> Package.Specification () -> Repo -> Result Errors Repo
insertDependencySpecification packageName packageSpec repo =
    case repo.dependencies |> Dict.get packageName of
        Just _ ->
            Err [ DependencyAlreadyExists packageName ]

        Nothing ->
            Ok
                { repo
                    | dependencies =
                        repo.dependencies
                            |> Dict.insert packageName packageSpec
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
                            |> Dict.insert moduleName (AccessControlled.private moduleDef)
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
                            |> DAG.removeNode moduleName
                }
            )


{-| Insert types into repo modules and update the type dependency graph of the repo |
-}
insertType : ModuleName -> Name -> Type.Definition () -> Repo -> Result Errors Repo
insertType moduleName typeName typeDef repo =
    let
        accessControlledModuleDef : AccessControlled (Module.Definition () (Type ()))
        accessControlledModuleDef =
            case repo.modules |> Dict.get moduleName of
                Just modDefinition ->
                    modDefinition

                Nothing ->
                    public Module.emptyDefinition
    in
    case accessControlledModuleDef.value.types |> Dict.get typeName of
        Just _ ->
            Err [ TypeAlreadyExist ( repo.packageName, moduleName, typeName ) ]

        Nothing ->
            repo.typeDependencies
                |> DAG.insertNode (FQName.fQName repo.packageName moduleName typeName) Set.empty
                |> Result.mapError (always [ TypeCycleDetected typeName ])
                |> Result.map
                    (\updatedTypeDependency ->
                        { repo
                            | modules =
                                repo.modules
                                    |> Dict.insert moduleName
                                        (accessControlledModuleDef
                                            |> AccessControlled.map
                                                (\moduleDef ->
                                                    { moduleDef
                                                        | types =
                                                            moduleDef.types
                                                                |> Dict.insert typeName (public (typeDef |> Documented.Documented ""))
                                                    }
                                                )
                                        )
                            , typeDependencies =
                                updatedTypeDependency
                        }
                    )


{-| Insert values into repo modules and update the value dependency graph of the repo |
-}
insertValue : ModuleName -> Name -> Value.Definition () (Type ()) -> Repo -> Result Errors Repo
insertValue moduleName valueName valueDef repo =
    case repo.modules |> Dict.get moduleName of
        Just modDefinition ->
            case modDefinition.value.values |> Dict.get valueName of
                Just _ ->
                    Err [ ValueAlreadyExist valueName ]

                Nothing ->
                    let
                        updateModule : Maybe (AccessControlled (Module.Definition () (Type ()))) -> Maybe (AccessControlled (Module.Definition () (Type ())))
                        updateModule maybeModuleDefinition =
                            maybeModuleDefinition
                                |> Maybe.map
                                    (\accessControlledModuleDef ->
                                        accessControlledModuleDef
                                            |> AccessControlled.map
                                                (\moduleDef ->
                                                    { moduleDef
                                                        | values =
                                                            modDefinition.value.values
                                                                |> Dict.insert valueName (public (valueDef |> Documented.Documented ""))
                                                    }
                                                )
                                    )
                    in
                    repo.typeDependencies
                        |> DAG.insertNode (FQName.fQName repo.packageName moduleName valueName) Set.empty
                        |> Result.mapError (always [ ValueCycleDetected valueName ])
                        |> Result.map
                            (\updatedValueDependency ->
                                { repo
                                    | modules =
                                        repo.modules
                                            |> Dict.update moduleName updateModule
                                    , valueDependencies =
                                        updatedValueDependency
                                }
                            )

        Nothing ->
            Err [ ModuleNotFound moduleName ]


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed value =
    if isExposed then
        AccessControlled.public value

    else
        AccessControlled.private value


getPackageName : Repo -> PackageName
getPackageName repo =
    repo.packageName


dependsOnPackages : Repo -> Set PackageName
dependsOnPackages repo =
    repo.dependencies
        |> Dict.keys
        |> Set.fromList


lookupModuleSpecification : PackageName -> ModuleName -> Repo -> Maybe (Module.Specification ())
lookupModuleSpecification packageName moduleName repo =
    if packageName == repo.packageName then
        repo.modules
            |> Dict.get moduleName
            -- Private modules are visible within the same package
            |> Maybe.map AccessControlled.withPrivateAccess
            |> Maybe.map Module.definitionToSpecification

    else
        repo.dependencies
            |> Dict.get packageName
            |> Maybe.andThen (.modules >> Dict.get moduleName)
