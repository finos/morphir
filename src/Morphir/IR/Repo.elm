module Morphir.IR.Repo exposing (..)

import Dict exposing (Dict)
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Morphir.Elm.ModuleName exposing (toIRModuleName)
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.File.FileChanges exposing (FileChanges)
import Morphir.IR.Distribution exposing (Distribution(..))
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
    , nativeFunctions : Dict FQName Native.Function
    , moduleDependencies : DAG ModuleName
    }


type alias SourceCode =
    String


type alias Errors =
    List Error


type Error
    = ModuleNotFound ModuleName
    | ModuleHasDependents ModuleName (Set ModuleName)
    | ModuleAlreadyExist ModuleName
    | CycleDetected -- ModuleName ModuleName


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


{-| Apply all file changes to the repo in one step.
-}
applyFileChanges : FileChanges -> Repo -> Result Errors Repo
applyFileChanges fileChanges repo =
    parseNewElmModules fileChanges
        |> Result.andThen (orderElmModulesByDependency repo)
        |> Result.andThen
            (\parsedModules ->
                parsedModules
                    |> List.foldl
                        (\parsedModule repoResultForModule ->
                            let
                                moduleName : ModuleName
                                moduleName =
                                    ParsedModule.moduleName parsedModule
                                        |> toIRModuleName repo.packageName

                                typeNames : List Name
                                typeNames =
                                    extractTypeNames parsedModule
                            in
                            extractTypes parsedModule typeNames
                                |> Result.map orderTypesByDependency
                                |> Result.andThen
                                    (\types ->
                                        types
                                            |> List.foldl
                                                (\( typeName, typeDef ) repoResultForType ->
                                                    repoResultForType
                                                        |> Result.andThen (insertType moduleName typeName typeDef)
                                                )
                                                repoResultForModule
                                    )
                        )
                        (Ok repo)
            )


parseNewElmModules : FileChanges -> Result Errors (List ParsedModule)
parseNewElmModules fileChanges =
    Debug.todo "implement"


orderElmModulesByDependency : Repo -> List ParsedModule -> Result Error (List ParsedModule)
orderElmModulesByDependency repo parsedModules =
    {- let
          finalModuleGraph: DAG ModuleName
          finalModuleGraph = DAG.empty

          foldLeftInitialFunction: ParsedModule -> DAG ModuleName -> Result Error (DAG ModuleName)
          foldLeftInitialFunction parsedModule =
             let
                  -- extract IR moduleName from ParsedModule
                  fromModuleNameParam = parsedModule |> ParsedModule.moduleName |> toIRModuleName repo.packageName

                  -- extract parsedMod Dependencies + format each moduleName to type ModuleName
                  moduleDependencies: List ModuleName
                  moduleDependencies =
                      ParsedModule.importedModules parsedModule
                           |> List.map (toIRModuleName repo.packageName)

                  -- insert function to DAG Graph

              in
              moduleDependencies
                   |> List.foldl (foldLeftInnerFunction)
       in
       parsedModules
           |> List.foldl (foldLeftInitialFunction) finalGraph
           |> Result.andThen (\functionAResult ->
               case functionAResult of
                   Err err ->
                       case  err of
                           _ ->
                               CycleDetected
                   Ok _ ->
                       parsedModules
           )
    -}
    let
        moduleGraph : DAG ModuleName
        moduleGraph =
            DAG.empty

        foldFunction : ParsedModule -> Result Error (DAG ModuleName) -> Result Error (DAG ModuleName)
        foldFunction parsedModule graph =
            let
                moduleName : ModuleName
                moduleName =
                    ParsedModule.moduleName parsedModule
                        |> toIRModuleName repo.packageName

                moduleDependencies : List ModuleName
                moduleDependencies =
                    ParsedModule.importedModules parsedModule
                        |> List.map (\modName -> toIRModuleName repo.packageName modName)

                insertEdge : ModuleName -> Result Error (DAG ModuleName) -> Result Error (DAG ModuleName)
                insertEdge toModule dag =
                    dag
                        |> Result.andThen
                            (\graphValue ->
                                graphValue
                                    |> DAG.insertEdge moduleName toModule
                                    |> Result.mapError
                                        (\err ->
                                            case err of
                                                _ ->
                                                    CycleDetected moduleName toModule
                                        )
                            )
            in
            moduleDependencies
                |> List.foldl insertEdge graph
    in
    parsedModules
        |> List.foldl foldFunction (Ok moduleGraph)
        |> Result.andThen
            (\finalGraph ->
                finalGraph
                    |> DAG.forwardTopologicalOrdering
                    |> List.concat
                    |> List.map2
            )



--Debug.todo "implement"


extractTypeNames : ParsedModule -> List Name
extractTypeNames parsedModule =
    Debug.todo "implement"


extractTypes : ParsedModule -> List Name -> Result Errors (List ( Name, Type.Definition () ))
extractTypes parsedModule typeNames =
    Debug.todo "implement"


orderTypesByDependency : List ( Name, Type.Definition () ) -> List ( Name, Type.Definition () )
orderTypesByDependency =
    Debug.todo "implement"


extractValueSignatures : ParsedModule -> List ( Name, Type () )
extractValueSignatures parsedModule =
    Debug.todo "implement"


{-| Insert or update a single module in the repo passing the source code in.
-}
mergeModuleSource : ModuleName -> SourceCode -> Repo -> Result Errors Repo
mergeModuleSource moduleName sourceCode repo =
    Debug.todo "implement"


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
    Debug.todo "implement"
