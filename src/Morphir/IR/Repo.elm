module Morphir.IR.Repo exposing
    ( Repo, Error(..)
    , empty, fromDistribution, insertDependencySpecification
    , mergeNativeFunctions, insertModule, deleteModule
    , insertType, insertValue, insertTypedValue
    , getPackageName, modules, dependsOnPackages, lookupModuleSpecification, typeDependencies, valueDependencies, lookupValue, moduleDependencies, findModuleEntryPoints
    , toDistribution, updateModuleAccess
    , Errors, SourceCode, deleteType, deleteValue, removeUnusedModules, updateType, updateValue
    )

{-| This module contains a data structure that represents a Repo with useful API that allows querying and modification.
The Repo is intended to maintain validity at all times, and as a result, it provides a safe way to build, modify, and
query a Repo without breaking the validity of the Repo.

@docs Repo, Error


# Build

@docs empty, fromDistribution, insertDependencySpecification
@docs mergeNativeFunctions, insertModule, deleteModule
@docs insertType, insertValue, insertTypedValue


# Query

@docs getPackageName, modules, dependsOnPackages, lookupModuleSpecification, typeDependencies, valueDependencies, lookupValue, moduleDependencies, findModuleEntryPoints


# Transform

@docs toDistribution, updateModuleAccess

-}

import Dict exposing (Dict)
import List.Extra
import Morphir.Dependency.DAG as DAG exposing (CycleDetected, DAG)
import Morphir.IR.AccessControlled as AccessControlled exposing (Access, AccessControlled, public, withAccess)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path exposing (Path, isPrefixOf)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Type.Infer as Infer
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
    | IllegalTypeUpdate String
    | DependencyAlreadyExists PackageName
    | ValueAlreadyExist Name
    | ValueNotFound FQName
    | TypeCycleDetected (DAG.CycleDetected FQName)
    | ValueCycleDetected (DAG.CycleDetected FQName)
    | ModuleCycleDetected (DAG.CycleDetected ModuleName)
    | TypeCheckError ModuleName Name Infer.TypeError
    | CannotInsertType ModuleName Name Error


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
        Library packageName dependencies packageDef ->
            let
                repoWithDependencies : Result Errors Repo
                repoWithDependencies =
                    -- TODO: sort dependencies topologically
                    dependencies
                        |> Dict.toList
                        |> List.foldl
                            (\( dependencyPackageName, dependencyPackageSpec ) repoResultSoFar ->
                                repoResultSoFar
                                    |> Result.andThen (insertDependencySpecification dependencyPackageName dependencyPackageSpec)
                            )
                            (Ok (empty packageName))
            in
            packageDef
                |> Package.modulesOrderedByDependency packageName
                |> Result.mapError (ModuleCycleDetected >> List.singleton)
                |> Result.andThen
                    (List.foldl
                        (\( moduleName, accessControlledModuleDef ) repoResultSoFar ->
                            repoResultSoFar
                                |> Result.andThen
                                    (\repoSoFar ->
                                        repoSoFar
                                            |> insertModule moduleName accessControlledModuleDef.value accessControlledModuleDef.access
                                    )
                        )
                        repoWithDependencies
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
insertModule : ModuleName -> Module.Definition () (Type ()) -> Access -> Repo -> Result Errors Repo
insertModule moduleName moduleDef access (Repo repo) =
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
                                    >> Result.mapError (TypeCycleDetected >> List.singleton)
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
                                    >> Result.mapError (ValueCycleDetected >> List.singleton)
                                )
                    )
                    (Ok r.valueDependencies)
                |> Result.map (\valueDag -> Repo { r | valueDependencies = valueDag })

        dependenciesCollectedFromTypesAndValues : Set ModuleName
        dependenciesCollectedFromTypesAndValues =
            let
                filter ( _, modName, _ ) =
                    if moduleName == modName then
                        Nothing

                    else
                        Just modName

                depsFrom target =
                    target
                        |> List.map (Tuple.second >> Set.toList)
                        |> List.concat
                        |> List.filterMap filter
            in
            depsFrom allValuesInModule |> List.append (depsFrom allTypesInModule) |> Set.fromList
    in
    validationErrors
        |> Maybe.map Err
        |> Maybe.withDefault (Ok (Repo repo))
        |> Result.andThen updateRepoTypeDependencies
        |> Result.andThen updateRepoValueDependencies
        |> Result.andThen (updateModuleDependencies moduleName dependenciesCollectedFromTypesAndValues)
        |> Result.map
            (\(Repo r) ->
                Repo
                    { r
                        | modules =
                            r.modules
                                |> Dict.insert moduleName (AccessControlled access moduleDef)
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
insertType : ModuleName -> Name -> Type.Definition () -> Access -> String -> Repo -> Result Errors Repo
insertType moduleName typeName typeDef access typeDoc (Repo repo) =
    let
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
                |> Result.mapError (TypeCycleDetected >> List.singleton)
                |> Result.map (\updatedTypeDep -> Repo { r | typeDependencies = updatedTypeDep })

        updateModuleDefWithType : Repo -> AccessControlled (Module.Definition () (Type ())) -> Repo
        updateModuleDefWithType (Repo r) accessControlledModDef =
            accessControlledModDef
                |> AccessControlled.map
                    (\modDef ->
                        Dict.insert typeName (AccessControlled access (typeDef |> Documented.Documented typeDoc)) modDef.types
                            |> (\updatedTypes -> { modDef | types = updatedTypes })
                    )
                |> (\updatedAccessControlledModDef ->
                        modules (Repo r)
                            |> Dict.insert moduleName updatedAccessControlledModDef
                   )
                |> (\updatedModules -> Repo { r | modules = updatedModules })
    in
    case repo.modules |> Dict.get moduleName of
        Just accessControlledModuleDef ->
            validateTypeExistsResult accessControlledModuleDef
                |> Result.map (updateModuleDefWithType (Repo repo))
                |> Result.andThen updateTypeDependency
                |> Result.andThen (updateModuleDependencies moduleName moduleDepsFromType)

        Nothing ->
            updateModuleDefWithType (Repo repo) (public Module.emptyDefinition)
                |> updateTypeDependency
                |> Result.andThen (updateModuleDependencies moduleName moduleDepsFromType)


{-| Update and existing type in the repo modules and update the type dependency graph of the repo.
The update could fail with an Error if type access is changed in such a way that breaks the repo
or the type update causes a cyclic dependency
-}
updateType : ModuleName -> Name -> Type.Definition () -> Access -> String -> Repo -> Result Errors Repo
updateType moduleName typeName typeDef typeAccess typeDoc repo =
    let
        -- extract new moduleDependencies from type for updateModuleDependency
        moduleDepsFromType : Type.Definition () -> Set ModuleName
        moduleDepsFromType def =
            Type.collectReferencesFromDefintion def
                |> Set.toList
                |> List.filterMap
                    (\( _, modName, _ ) ->
                        if modName == moduleName then
                            Nothing

                        else
                            Just modName
                    )
                |> Set.fromList

        updateTypeDependency : Type.Definition () -> Repo -> Result Errors Repo
        updateTypeDependency def (Repo r) =
            r.typeDependencies
                |> DAG.insertNode
                    (FQName.fQName r.packageName moduleName typeName)
                    (Type.collectReferencesFromDefintion def)
                |> Result.mapError (TypeCycleDetected >> List.singleton)
                |> Result.map (\updatedTypeDep -> Repo { r | typeDependencies = updatedTypeDep })

        updateTypeInDef : Access -> String -> Type.Definition () -> Repo -> Result Errors Repo
        updateTypeInDef access doc def (Repo r) =
            let
                hasExternallyDependentTypes =
                    typeDependencies (Repo r)
                        |> DAG.incomingEdges ( getPackageName (Repo r), moduleName, typeName )
                        |> Set.filter (\( _, modName, _ ) -> moduleName /= modName)
                        |> Set.isEmpty
                        >> not
            in
            if hasExternallyDependentTypes && access == AccessControlled.Private then
                Err [ IllegalTypeUpdate "Change type Access while other types depend on it" ]

            else
                AccessControlled access (Documented doc def)
                    |> (\updatedDef ->
                            modules (Repo r)
                                |> Dict.get moduleName
                                |> Maybe.map
                                    (AccessControlled.map
                                        (\modDef ->
                                            Dict.insert typeName updatedDef modDef.types
                                                |> (\updatedTypes -> { modDef | types = updatedTypes })
                                        )
                                        >> (\updatedAccessControlledModDef ->
                                                modules (Repo r)
                                                    |> Dict.insert moduleName updatedAccessControlledModDef
                                           )
                                        >> (\updatedModules -> Repo { r | modules = updatedModules })
                                    )
                                |> Result.fromMaybe [ ModuleNotFound moduleName ]
                       )
    in
    updateTypeInDef typeAccess typeDoc typeDef repo
        |> Result.andThen (updateTypeDependency typeDef)
        |> Result.andThen (updateModuleDependencies moduleName (moduleDepsFromType typeDef))


deleteType : ModuleName -> Name -> Repo -> Result Errors Repo
deleteType moduleName typeName (Repo repo) =
    case Dict.get moduleName repo.modules of
        Just accessControlModDef ->
            accessControlModDef
                |> AccessControlled.map
                    (\modDef ->
                        modDef.types
                            |> Dict.remove typeName
                            |> (\updatedTypes -> { modDef | types = updatedTypes })
                    )
                |> (\updatedModDef ->
                        Repo { repo | modules = Dict.insert moduleName updatedModDef repo.modules }
                   )
                |> (\(Repo updatedRepo) ->
                        DAG.removeNode ( repo.packageName, moduleName, typeName ) updatedRepo.typeDependencies
                            |> (\updatedTypeDeps -> Repo { updatedRepo | typeDependencies = updatedTypeDeps })
                   )
                |> Ok

        Nothing ->
            Err [ ModuleNotFound moduleName ]


{-| Insert a new value into the repo without type information on each node. The repo will infer the types of each node
and store it. This function might fail if the inferred type is not compatible with the declared type that's passed in.
-}
insertValue : ModuleName -> Name -> Maybe (Type ()) -> Value () () -> Access -> String -> Repo -> Result Errors Repo
insertValue moduleName valueName maybeValueType value access valueDoc repo =
    let
        ir : Distribution
        ir =
            repo
                |> toDistribution
    in
    case maybeValueType of
        -- If the modeler defined a value type
        Just valueType ->
            let
                valueDef : Value.Definition () ()
                valueDef =
                    Value.typeAndValueToDefinition valueType value
            in
            Infer.inferValueDefinition ir valueDef
                |> Result.map (Value.mapDefinitionAttributes identity Tuple.second)
                |> Result.mapError (TypeCheckError moduleName valueName >> List.singleton)
                |> Result.andThen (\typedValueDef -> insertTypedValue moduleName valueName typedValueDef access valueDoc repo)

        Nothing ->
            Infer.inferValue ir value
                |> Result.map (Value.mapValueAttributes identity Tuple.second)
                |> Result.mapError (TypeCheckError moduleName valueName >> List.singleton)
                |> Result.andThen
                    (\typedValue ->
                        let
                            typedValueDef : Value.Definition () (Type ())
                            typedValueDef =
                                Value.typeAndValueToDefinition (typedValue |> Value.valueAttribute) typedValue
                        in
                        insertTypedValue moduleName valueName typedValueDef access valueDoc repo
                    )


{-| Update an existing value in the repo without type information. The repo will infer the types of each node
and store it. This function might fail if the inferred type is not compatible with the declared type that's passed in.
-}
updateValue : ModuleName -> Name -> Maybe (Type ()) -> Value () () -> Access -> String -> Repo -> Result Errors Repo
updateValue moduleName valueName maybeValueType value access doc repo =
    let
        ir : Distribution
        ir =
            repo
                |> toDistribution

        -- remove the existing value from the repo and
        -- cleanup existing dependency edges for the value as it will be recalculated
        removeValue : Repo -> Result Errors Repo
        removeValue (Repo r) =
            let
                valueFQN =
                    ( getPackageName repo, moduleName, valueName )
            in
            modules repo
                |> Dict.get moduleName
                |> Maybe.map
                    (AccessControlled.map
                        (\modDef -> { modDef | values = Dict.remove valueName modDef.values })
                    )
                |> Maybe.map (\accessModDef -> Repo { r | modules = Dict.insert moduleName accessModDef r.modules })
                |> Result.fromMaybe [ ModuleNotFound moduleName ]
                |> Result.map
                    (\updatedRepo ->
                        valueDependencies updatedRepo
                            |> DAG.outgoingEdges valueFQN
                            |> Set.foldl (DAG.removeEdge valueFQN) (valueDependencies updatedRepo)
                            |> Tuple.pair updatedRepo
                    )
                |> Result.map
                    (\( Repo updatedRepoValue, updatedValueDependencies ) ->
                        Repo { updatedRepoValue | valueDependencies = updatedValueDependencies }
                    )
    in
    case maybeValueType of
        -- If the modeler defined a value type
        Just valueType ->
            let
                valueDef : Value.Definition () ()
                valueDef =
                    Value.typeAndValueToDefinition valueType value
            in
            Infer.inferValueDefinition ir valueDef
                |> Result.map (Value.mapDefinitionAttributes identity Tuple.second)
                |> Result.mapError (TypeCheckError moduleName valueName >> List.singleton)
                |> Result.andThen
                    (\typedValueDef ->
                        removeValue repo
                            |> Result.andThen (insertTypedValue moduleName valueName typedValueDef access doc)
                    )

        Nothing ->
            Infer.inferValue ir value
                |> Result.map (Value.mapValueAttributes identity Tuple.second)
                |> Result.mapError (TypeCheckError moduleName valueName >> List.singleton)
                |> Result.andThen
                    (\typedValue ->
                        let
                            typedValueDef : Value.Definition () (Type ())
                            typedValueDef =
                                Value.typeAndValueToDefinition (typedValue |> Value.valueAttribute) typedValue
                        in
                        removeValue repo
                            |> Result.andThen (insertTypedValue moduleName valueName typedValueDef access doc)
                    )


deleteValue : ModuleName -> Name -> Repo -> Result Errors Repo
deleteValue moduleName valueName (Repo repo) =
    case Dict.get moduleName repo.modules of
        Just accessControlModDef ->
            accessControlModDef
                |> AccessControlled.map
                    (\modDef ->
                        modDef.values
                            |> Dict.remove valueName
                            |> (\updatedValues -> { modDef | values = updatedValues })
                    )
                |> (\updatedModDef ->
                        Repo { repo | modules = Dict.insert moduleName updatedModDef repo.modules }
                   )
                |> (\(Repo updatedRepo) ->
                        DAG.removeNode ( repo.packageName, moduleName, valueName ) updatedRepo.valueDependencies
                            |> (\updatedValueDeps -> Repo { updatedRepo | valueDependencies = updatedValueDeps })
                   )
                |> Ok

        Nothing ->
            Err [ ModuleNotFound moduleName ]


{-| Insert typed values into repo modules and update the value dependency graph of the repo
-}
insertTypedValue : ModuleName -> Name -> Value.Definition () (Type ()) -> Access -> String -> Repo -> Result Errors Repo
insertTypedValue moduleName valueName valueDef valueAccess valueDoc repo =
    let
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
                |> Result.mapError (ValueCycleDetected >> List.singleton)
                |> Result.map (\updatedValueDep -> Repo { r | valueDependencies = updatedValueDep })

        updateModuleDefWithValue : Repo -> AccessControlled (Module.Definition () (Type ())) -> Repo
        updateModuleDefWithValue (Repo r) accessControlledModDef =
            accessControlledModDef
                |> AccessControlled.map
                    (\modDef ->
                        Dict.insert valueName (AccessControlled valueAccess (valueDef |> Documented.Documented valueDoc)) modDef.values
                            |> (\updatedValues -> { modDef | values = updatedValues })
                    )
                |> (\updatedAccessControlledModDef ->
                        modules (Repo r)
                            |> Dict.insert moduleName updatedAccessControlledModDef
                   )
                |> (\updatedModules -> Repo { r | modules = updatedModules })
    in
    case repo |> modules |> Dict.get moduleName of
        Just accessControlledModuleDef ->
            validateValueExistsResult accessControlledModuleDef
                |> Result.map (updateModuleDefWithValue repo)
                |> Result.andThen updateValueDependency
                |> Result.andThen (updateModuleDependencies moduleName moduleDepsFromValueDef)

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


{-| get a dependency graph of the modules contained in a Repo
-}
moduleDependencies : Repo -> DAG ModuleName
moduleDependencies (Repo repo) =
    repo.moduleDependencies


{-| Update the module dependency graph of a repo
-}
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


{-| Look up a value from the repo using the access level passed in.
-}
lookupValue : Access -> FQName -> Repo -> Maybe (Value.Definition () (Type ()))
lookupValue access ( packageName, moduleName, localName ) (Repo repo) =
    if packageName == repo.packageName then
        repo.modules
            |> Dict.get moduleName
            |> Maybe.andThen
                (\accessControlledModuleDef ->
                    accessControlledModuleDef
                        |> withAccess access
                        |> Maybe.andThen (.values >> Dict.get localName)
                        |> Maybe.andThen (withAccess access)
                        |> Maybe.map .value
                )

    else
        -- TODO: lookup in dependencies
        Nothing


{-| Remove unused modules from the repo provided a set of exposed or required modules
-}
removeUnusedModules : Set ModuleName -> Repo -> Result Errors Repo
removeUnusedModules exposedModules repo =
    let
        usedModules : Set ModuleName
        usedModules =
            Set.toList exposedModules
                |> List.foldl
                    (\modName usedModulesSoFar ->
                        DAG.collectForwardReachableNodes modName (moduleDependencies repo)
                            |> Set.union usedModulesSoFar
                    )
                    exposedModules

        unusedModules : List ModuleName
        unusedModules =
            Dict.keys (modules repo)
                |> List.filter (\modName -> Set.member modName usedModules |> not)
    in
    List.foldl
        (\modName repoResultSoFar ->
            repoResultSoFar |> Result.andThen (deleteModule modName)
        )
        (Ok repo)
        unusedModules


{-| Update the Access level of a module.
-}
updateModuleAccess : AccessControlled.Access -> ModuleName -> Repo -> Repo
updateModuleAccess access moduleName (Repo repo) =
    Repo <|
        { repo
            | modules =
                repo.modules
                    |> Dict.update moduleName
                        (Maybe.map
                            (\{ value } ->
                                AccessControlled access value
                            )
                        )
        }


findModuleEntryPoints : Repo -> Path -> List FQName
findModuleEntryPoints (Repo repo) moduleName =
    let
        fullFQNameList : List FQName
        fullFQNameList =
            repo.valueDependencies |> DAG.toList |> List.map Tuple.first

        valuesUnderModule : List FQName
        valuesUnderModule =
            fullFQNameList
                |> List.filter
                    (\( _, m, _ ) ->
                        isPrefixOf m moduleName
                    )

        valuesNotUnderModule : List FQName
        valuesNotUnderModule =
            List.foldl List.Extra.remove fullFQNameList valuesUnderModule

        filteredValueDepsDag : DAG FQName
        filteredValueDepsDag =
            valuesNotUnderModule |> List.foldl DAG.removeNode repo.valueDependencies

        dependsOnNothing : FQName -> Bool
        dependsOnNothing f =
            Set.isEmpty <| DAG.incomingEdges f filteredValueDepsDag

        callsOthers : FQName -> Bool
        callsOthers f =
            not <| Set.isEmpty <| DAG.outgoingEdges f filteredValueDepsDag
    in
    valuesUnderModule |> List.filter dependsOnNothing |> List.filter callsOthers
