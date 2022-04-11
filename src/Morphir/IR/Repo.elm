module Morphir.IR.Repo exposing
    ( Repo, Error(..)
    , empty, fromDistribution, insertDependencySpecification
    , mergeNativeFunctions, insertModule, deleteModule
    , insertType, insertValue
    , getPackageName, modules, dependsOnPackages, lookupModuleSpecification, typeDependencies, valueDependencies
    , toDistribution
    , Errors, SourceCode
    )

{-| This module contains a data structure that represents a Repo with useful API that allows querying and modification.
The Repo is intended to maintain validity at all times, and as a result, it provides a safe way to build, modify, and
query a Repo without breaking the validity of the Repo.

@docs Repo, Error


# Build

@docs empty, fromDistribution, insertDependencySpecification
@docs mergeNativeFunctions, insertModule, deleteModule
@docs insertType, insertValue


# Query

@docs getPackageName, modules, dependsOnPackages, lookupModuleSpecification, typeDependencies, valueDependencies, moduleDependencies


# Transform

@docs toDistribution

-}

import Dict exposing (Dict)
import Morphir.Dependency.DAG as DAG exposing (CycleDetected, DAG)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented as Documented
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.Value.Native as Native
import Set exposing (Set)


{-| A Repo is an internal representation of a Morphir project, that could contain external dependencies, modules, type,
values, e.t.c, which makes it a format that enable Morphir capture all of the information regarding this project.

The following parts of the Repo is

  - **packageName**
    The name of the package (or project name)
  - **dependencies**
    External dependencies (which are also Morphir projects),
    stored as a dictionary of the package name and the package specification. The specification of each package,
    contains definitions required within the current package
  - **modules**
    Modules defined within this package stored as a dictionary of the module name and the module definition
  - **moduleDependencies**
    A dependency graph showing dependencies between modules defined within this package
  - **nativeFunctions**
    A collection of native functions used within a Repo. Native functions are not implemented within Morphir and as a
    result they need to map to native functions in a Morphir backend. example of a native function withing elm is
    `String.length`
  - **typeDependencies**
    A dependency graph showing Types defined within this package and the dependencies between them
  - **valueDependencies**
    A dependency graph showing values and functions defined within this package and the dependencies between them

-}
type Repo
    = Repo
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


{-| Error state of a repo.

    - **ModuleNotFound ModuleName**
        A module was not found within the Repo
    - **ModuleHasDependents ModuleName (Set ModuleName)**
        A module has other module that depends on it
    - **ModuleAlreadyExist ModuleName**
        A module already exists within a Repo
    - **TypeAlreadyExist FQName**
        A type already exists within a Repo
    - **DependencyAlreadyExists PackageName**
        A dependency to a package already exists
    - **ValueAlreadyExist Name**
        A value already exists within a Repo
    - **TypeCycleDetected Name**
        Circular dependency detected within types
    - **ValueCycleDetected Name**
        Circular dependency detected within values

-}
type Error
    = ModuleNotFound ModuleName
    | ModuleHasDependents ModuleName (Set ModuleName)
    | ModuleAlreadyExist ModuleName
    | TypeAlreadyExist FQName
    | DependencyAlreadyExists PackageName
    | ValueAlreadyExist Name
    | TypeCycleDetected Name
    | ValueCycleDetected Name
    | ModuleCycleDetected (DAG.CycleDetected ModuleName)


{-| Creates a repo from scratch when there is no existing IR.
-}
empty : PackageName -> Repo
empty packageName =
    Repo
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
            packageDef
                |> Package.modulesOrderedByDependency packageName
                |> Result.mapError (\err -> [ ModuleCycleDetected err ])
                |> Result.andThen
                    (List.foldl
                        (\( moduleName, accessControlledModuleDef ) repoResultSoFar ->
                            repoResultSoFar
                                |> Result.andThen
                                    (\repoSoFar ->
                                        repoSoFar
                                            |> insertModule moduleName accessControlledModuleDef.value
                                    )
                        )
                        (Ok (empty packageName))
                    )


{-| Creates a distribution from an existing repo
-}
toDistribution : Repo -> Distribution
toDistribution (Repo repo) =
    Library repo.packageName
        repo.dependencies
        { modules =
            repo.modules
        }


{-| Adds an external package as a dependency to the current Repo
-}
insertDependencySpecification : PackageName -> Package.Specification () -> Repo -> Result Errors Repo
insertDependencySpecification packageName packageSpec (Repo repo) =
    case repo.dependencies |> Dict.get packageName of
        Just _ ->
            Err [ DependencyAlreadyExists packageName ]

        Nothing ->
            Repo
                { repo
                    | dependencies =
                        repo.dependencies
                            |> Dict.insert packageName packageSpec
                }
                |> Ok


{-| Adds native functions to the repo. For now this will be mainly used to add `SDK.nativeFunctions`.
-}
mergeNativeFunctions : Dict FQName Native.Function -> Repo -> Result Errors Repo
mergeNativeFunctions newNativeFunction (Repo repo) =
    Repo
        { repo
            | nativeFunctions =
                repo.nativeFunctions
                    |> Dict.union newNativeFunction
        }
        |> Ok


{-| Insert a module if it's not in the repo yet.
This also updates the types and values dependency graph contained within the Repo
-}
insertModule : ModuleName -> Module.Definition () (Type ()) -> Repo -> Result Errors Repo
insertModule moduleName moduleDef (Repo repo) =
    let
        -- check if the module already exists
        validationErrors : Maybe Errors
        validationErrors =
            case repo.modules |> Dict.get moduleName of
                Just _ ->
                    Just [ ModuleAlreadyExist moduleName ]

                Nothing ->
                    Nothing

        -- extracting types from module and updating typeDependencies in repo
        allTypesInModule : List ( FQName, Set FQName )
        allTypesInModule =
            moduleDef.types
                |> Dict.toList
                |> List.map
                    (\( name, accessControlledTypeDef ) ->
                        ( FQName.fQName (getPackageName (Repo repo)) moduleName name
                        , Type.collectReferencesFromDefintion accessControlledTypeDef.value.value
                        )
                    )

        updateRepoTypeDependencies : Repo -> Result Errors Repo
        updateRepoTypeDependencies (Repo r) =
            allTypesInModule
                |> List.foldl
                    (\( typeFQName, typeList ) dagResultSoFar ->
                        dagResultSoFar
                            |> Result.andThen
                                (DAG.insertNode typeFQName typeList
                                    >> Result.mapError (\(DAG.CycleDetected ( _, _, n ) _) -> [ TypeCycleDetected n ])
                                )
                    )
                    (Ok r.typeDependencies)
                |> Result.map (\typeDAG -> Repo { r | typeDependencies = typeDAG })

        -- extracting values from module and update valueDependencies in repo
        allValuesInModule : List ( FQName, Set FQName )
        allValuesInModule =
            moduleDef.values
                |> Dict.toList
                |> List.map
                    (\( name, accessControlledValueDef ) ->
                        ( FQName.fQName (getPackageName (Repo repo)) moduleName name
                        , Value.collectReferences accessControlledValueDef.value.value.body
                        )
                    )

        updateRepoValueDependencies : Repo -> Result Errors Repo
        updateRepoValueDependencies (Repo r) =
            allValuesInModule
                |> List.foldl
                    (\( valueFQN, valueDeps ) dagResultSoFar ->
                        dagResultSoFar
                            |> Result.andThen
                                (DAG.insertNode valueFQN valueDeps
                                    >> Result.mapError (\(DAG.CycleDetected ( _, _, n ) _) -> [ ValueCycleDetected n ])
                                )
                    )
                    (Ok r.valueDependencies)
                |> Result.map (\valueDag -> Repo { r | valueDependencies = valueDag })

        updateRepoModulesDependencies : Repo -> Result Errors Repo
        updateRepoModulesDependencies (Repo r) =
            List.map2
                (\( _, modName, _ ) ( _, modName2, _ ) ->
                    [ modName, modName2 ]
                )
                (allTypesInModule |> List.map (Tuple.second >> Set.toList) |> List.concat)
                (allValuesInModule |> List.map (Tuple.second >> Set.toList) |> List.concat)
                |> List.concat
                |> Set.fromList
                |> Set.filter (\modName -> modName == moduleName |> not)
                |> (\dependencies -> DAG.insertNode moduleName dependencies r.moduleDependencies)
                |> Result.mapError (ModuleCycleDetected >> List.singleton)
                |> Result.map (\updatedModuleDependencies -> Repo { r | moduleDependencies = updatedModuleDependencies })
    in
    validationErrors
        |> Maybe.map Err
        |> Maybe.withDefault (Ok (Repo repo))
        |> Result.andThen updateRepoTypeDependencies
        |> Result.andThen updateRepoValueDependencies
        |> Result.andThen updateRepoModulesDependencies
        |> Result.map
            (\(Repo r) ->
                Repo
                    { r
                        | modules =
                            r.modules
                                |> Dict.insert moduleName (AccessControlled.private moduleDef)
                    }
            )


{-| delete a module from the Repo if the module can be safely removed.
If the module does not exist within the Repo or if the module has other modules that are dependent on it, the operation
fails with an Error.
-}
deleteModule : ModuleName -> Repo -> Result Errors Repo
deleteModule moduleName (Repo repo) =
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
            (Repo
                { repo
                    | modules =
                        repo.modules
                            |> Dict.remove moduleName
                    , moduleDependencies =
                        repo.moduleDependencies
                            |> DAG.removeNode moduleName
                }
                |> Ok
            )


{-| Insert types into repo modules and update the type dependency graph of the repo
-}
insertType : ModuleName -> Name -> Type.Definition () -> Repo -> Result Errors Repo
insertType moduleName typeName typeDef (Repo repo) =
    let
        accessControlledModuleDefResult : Result Errors (AccessControlled (Module.Definition () (Type ())))
        accessControlledModuleDefResult =
            Result.fromMaybe
                [ ModuleNotFound moduleName ]
                (repo |> Repo |> modules |> Dict.get moduleName)

        validateTypeExistsResult : AccessControlled (Module.Definition () (Type ())) -> Result Errors (AccessControlled (Module.Definition () (Type ())))
        validateTypeExistsResult accessControlledModuleDef =
            case accessControlledModuleDef.value.types |> Dict.get typeName of
                Just _ ->
                    Err [ TypeAlreadyExist ( repo.packageName, moduleName, typeName ) ]

                Nothing ->
                    Ok accessControlledModuleDef

        -- extract new moduleDependencies from type and updateModuleDependency
        moduleDepsFromType : Set ModuleName
        moduleDepsFromType =
            Type.collectReferencesFromDefintion typeDef
                |> Set.toList
                |> List.filterMap
                    (\( _, modName, _ ) ->
                        if modName == moduleName then
                            Nothing

                        else
                            Just modName
                    )
                |> Set.fromList

        updateTypeDependency : Repo -> Result Errors Repo
        updateTypeDependency (Repo r) =
            r.typeDependencies
                |> DAG.insertNode
                    (FQName.fQName repo.packageName moduleName typeName)
                    (Type.collectReferencesFromDefintion typeDef)
                |> Result.mapError (always [ TypeCycleDetected typeName ])
                |> Result.map (\updatedTypeDep -> Repo { r | typeDependencies = updatedTypeDep })

        updateModuleDefWithType : Repo -> AccessControlled (Module.Definition () (Type ())) -> Repo
        updateModuleDefWithType (Repo r) accessControlledModDef =
            accessControlledModDef
                |> AccessControlled.map
                    (\modDef ->
                        Dict.insert typeName (public (typeDef |> Documented.Documented "")) modDef.types
                            |> (\updatedTypes -> { modDef | types = updatedTypes })
                    )
                |> (\updatedAccessControlledModDef ->
                        modules (Repo r)
                            |> Dict.insert moduleName updatedAccessControlledModDef
                   )
                |> (\updatedModules -> Repo { r | modules = updatedModules })
    in
    accessControlledModuleDefResult
        |> Result.andThen validateTypeExistsResult
        |> Result.map (updateModuleDefWithType (Repo repo))
        |> Result.andThen updateTypeDependency
        |> Result.andThen (updateModuleDependencies moduleName moduleDepsFromType)


{-| Insert values into repo modules and update the value dependency graph of the repo
-}
insertValue : ModuleName -> Name -> Value.Definition () (Type ()) -> Repo -> Result Errors Repo
insertValue moduleName valueName valueDef repo =
    let
        accessControlledModuleDefinitionResult : Result Errors (AccessControlled (Module.Definition () (Type ())))
        accessControlledModuleDefinitionResult =
            Result.fromMaybe
                [ ModuleNotFound moduleName ]
                (repo |> modules |> Dict.get moduleName)

        validateValueExistsResult : AccessControlled (Module.Definition () (Type ())) -> Result Errors (AccessControlled (Module.Definition () (Type ())))
        validateValueExistsResult accessControlledModuleDef =
            case accessControlledModuleDef.value.values |> Dict.get valueName of
                Just _ ->
                    Err [ ValueAlreadyExist valueName ]

                Nothing ->
                    Ok accessControlledModuleDef

        -- extract new moduleDependencies from value definition and updateModuleDependency
        moduleDepsFromValueDef : Set ModuleName
        moduleDepsFromValueDef =
            Value.collectReferences valueDef.body
                |> Set.toList
                |> List.filterMap
                    (\( _, modName, _ ) ->
                        if modName == moduleName then
                            Nothing

                        else
                            Just modName
                    )
                |> Set.fromList

        updateValueDependency : Repo -> Result Errors Repo
        updateValueDependency (Repo r) =
            r.valueDependencies
                |> DAG.insertNode
                    (FQName.fQName r.packageName moduleName valueName)
                    (Value.collectReferences valueDef.body)
                |> Result.mapError (always [ ValueCycleDetected valueName ])
                |> Result.map (\updatedValueDep -> Repo { r | valueDependencies = updatedValueDep })

        updateModuleDefWithValue : Repo -> AccessControlled (Module.Definition () (Type ())) -> Repo
        updateModuleDefWithValue (Repo r) accessControlledModDef =
            accessControlledModDef
                |> AccessControlled.map
                    (\modDef ->
                        Dict.insert valueName (public (valueDef |> Documented.Documented "")) modDef.values
                            |> (\updatedValues -> { modDef | values = updatedValues })
                    )
                |> (\updatedAccessControlledModDef ->
                        modules (Repo r)
                            |> Dict.insert moduleName updatedAccessControlledModDef
                   )
                |> (\updatedModules -> Repo { r | modules = updatedModules })
    in
    accessControlledModuleDefinitionResult
        |> Result.andThen validateValueExistsResult
        |> Result.map (updateModuleDefWithValue repo)
        |> Result.andThen updateValueDependency
        |> Result.andThen (updateModuleDependencies moduleName moduleDepsFromValueDef)


{-| get the packageName for a Repo
-}
getPackageName : Repo -> PackageName
getPackageName (Repo repo) =
    repo.packageName


{-| return the modules in a Repo as a dictionary
-}
modules : Repo -> Dict ModuleName (AccessControlled (Module.Definition () (Type ())))
modules (Repo repo) =
    repo.modules


{-| get the external dependencies for this Repo, i.e other packages that a Repo depends on.
-}
dependsOnPackages : Repo -> Set PackageName
dependsOnPackages (Repo repo) =
    repo.dependencies
        |> Dict.keys
        |> Set.fromList


{-| get the specification for a module within a Repo if it exists.
-}
lookupModuleSpecification : PackageName -> ModuleName -> Repo -> Maybe (Module.Specification ())
lookupModuleSpecification packageName moduleName (Repo repo) =
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


{-| return a type dependency graph for all the types within a Repo
-}
typeDependencies : Repo -> DAG FQName
typeDependencies (Repo repo) =
    repo.typeDependencies


{-| return the modules in a repo as a dictionary
-}
valueDependencies : Repo -> DAG FQName
valueDependencies (Repo repo) =
    repo.valueDependencies


{-| get a dependency graph of the modules contained in a Repo
-}
moduleDependencies : Repo -> DAG ModuleName
moduleDependencies (Repo repo) =
    repo.moduleDependencies


updateModuleDependencies : ModuleName -> Set ModuleName -> Repo -> Result Errors Repo
updateModuleDependencies moduleName dependencies (Repo repo) =
    DAG.insertNode moduleName dependencies repo.moduleDependencies
        |> Result.mapError (ModuleCycleDetected >> List.singleton)
        |> Result.map
            (\updatedModDependencies ->
                Repo
                    { repo
                        | moduleDependencies = updatedModDependencies
                    }
            )
