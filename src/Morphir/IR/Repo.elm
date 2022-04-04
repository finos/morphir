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

@docs getPackageName, modules, dependsOnPackages, lookupModuleSpecification, typeDependencies, valueDependencies


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
import Morphir.IR.Name as Name exposing (Name)
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
                |> List.foldl
                    (\( moduleName, accessControlledModuleDef ) repoResultSoFar ->
                        let
                            -- extracting types from module and updating typeDependencies in repo
                            typeDefToType : Type.Definition () -> List (Type.Type ())
                            typeDefToType definition =
                                case definition of
                                    Type.TypeAliasDefinition _ tpe ->
                                        [ tpe ]

                                    Type.CustomTypeDefinition _ accessControlledType ->
                                        accessControlledType.value
                                            |> Dict.toList
                                            |> List.map Tuple.second
                                            |> List.concat
                                            |> List.map Tuple.second

                            allTypesInModule : List ( FQName, List (Type ()) )
                            allTypesInModule =
                                accessControlledModuleDef.value.types
                                    |> Dict.toList
                                    |> List.map
                                        (\( name, accessControlledTypeDef ) ->
                                            ( FQName.fQName packageName moduleName name
                                            , typeDefToType accessControlledTypeDef.value.value
                                            )
                                        )

                            collectRefsForTypes : List (Type ()) -> Set FQName
                            collectRefsForTypes tpe =
                                tpe
                                    |> List.map Type.collectReferences
                                    |> List.foldl Set.union Set.empty

                            updateRepoTypeDependencies : Repo -> Result Errors Repo
                            updateRepoTypeDependencies (Repo repo) =
                                allTypesInModule
                                    |> List.foldl
                                        (\( typeFQName, typeList ) dagResultSoFar ->
                                            dagResultSoFar
                                                |> Result.andThen
                                                    (DAG.insertNode typeFQName (collectRefsForTypes typeList)
                                                        >> Result.mapError (\(DAG.CycleDetected ( _, _, n ) _) -> [ TypeCycleDetected n ])
                                                    )
                                        )
                                        (Ok repo.typeDependencies)
                                    |> Result.map (\typeDAG -> Repo { repo | typeDependencies = typeDAG })

                            -- extracting values from module and update valueDependencies in repo
                            allValuesInModule : List ( FQName, Set FQName )
                            allValuesInModule =
                                accessControlledModuleDef.value.values
                                    |> Dict.toList
                                    |> List.map
                                        (\( name, accessControlledValueDef ) ->
                                            ( FQName.fQName packageName moduleName name
                                            , Value.collectReferences accessControlledValueDef.value.value.body
                                            )
                                        )

                            updateRepoValueDependencies : Repo -> Result Errors Repo
                            updateRepoValueDependencies (Repo repo) =
                                allValuesInModule
                                    |> List.foldl
                                        (\( valueFQN, valueDeps ) dagResultSoFar ->
                                            dagResultSoFar
                                                |> Result.andThen
                                                    (DAG.insertNode valueFQN valueDeps
                                                        >> Result.mapError (\(DAG.CycleDetected ( _, _, n ) _) -> [ ValueCycleDetected n ])
                                                    )
                                        )
                                        (Ok repo.valueDependencies)
                                    |> Result.map (\valueDag -> Repo { repo | valueDependencies = valueDag })
                        in
                        repoResultSoFar
                            |> Result.andThen
                                (\repoSoFar ->
                                    repoSoFar
                                        -- TODO extract values and insert into the the repo before inserting the module int the repo
                                        |> insertModule moduleName accessControlledModuleDef.value
                                        |> Result.andThen updateRepoTypeDependencies
                                        |> Result.andThen updateRepoValueDependencies
                                )
                    )
                    (Ok (empty packageName))


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
-}
insertModule : ModuleName -> Module.Definition () (Type ()) -> Repo -> Result Errors Repo
insertModule moduleName moduleDef (Repo repo) =
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
            (Repo
                { repo
                    | modules =
                        repo.modules
                            |> Dict.insert moduleName (AccessControlled.private moduleDef)
                }
                |> Ok
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
                -- TODO extract references for type and use as toNodes
                |> DAG.insertNode (FQName.fQName repo.packageName moduleName typeName) Set.empty
                |> Result.mapError (always [ TypeCycleDetected typeName ])
                |> Result.map
                    (\updatedTypeDependency ->
                        Repo
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


{-| Insert values into repo modules and update the value dependency graph of the repo
-}
insertValue : ModuleName -> Name -> Value.Definition () (Type ()) -> Repo -> Result Errors Repo
insertValue moduleName valueName valueDef (Repo repo) =
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
                                Repo
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
