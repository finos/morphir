module Morphir.Elm.IncrementalFrontend exposing (..)

{-| Apply all file changes to the repo in one step.
-}

import Dict exposing (Dict)
import Elm.Parser
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing as Exposing
import Elm.Syntax.Expression exposing (Expression(..))
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.TypeAnnotation as TypeAnnotation
import List.Extra as List
import Morphir.Dependency.DAG as DAG exposing (CycleDetected(..), DAG)
import Morphir.Elm.IncrementalFrontend.Mapper as Mapper
import Morphir.Elm.IncrementalResolve as IncrementalResolve
import Morphir.Elm.ModuleName as ElmModuleName exposing (toIRModuleName)
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.File.FileChanges as FileChanges exposing (Change(..), FileChanges)
import Morphir.File.Path as FilePath
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.KindOfName exposing (KindOfName(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Repo as Repo exposing (Repo, SourceCode)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.SDK.ResultList as ResultList
import Parser
import Set exposing (Set)


{-| Options that modify the behavior of the frontend:

    - `typesOnly` - only include type information in the IR, no values

-}
type alias Options =
    { typesOnly : Bool
    }


type alias Errors =
    List Error


type Error
    = ModuleCycleDetected ModuleName ModuleName
    | TypeCycleDetected Name Name
    | TypeNotFound FQName
    | ValueCycleDetected FQName FQName
    | InvalidModuleName ElmModuleName.ModuleName
    | ParseError FilePath.Path (List Parser.DeadEnd)
    | RepoError String Repo.Errors
    | MappingError Mapper.Errors
    | ResolveError ModuleName IncrementalResolve.Error
    | InvalidSourceFilePath FilePath.Path String


type alias OrderedFileChanges =
    { insertsAndUpdates : List ( ModuleName, ParsedModule )
    , deletes : Set ModuleName
    }


type ModuleChange
    = ModuleInsert ModuleName ParsedModule
    | ModuleUpdate ModuleName ParsedModule
    | ModuleDelete ModuleName


type alias SignatureAndValue =
    ( Maybe (Type ()), Value () () )


orderFileChanges : PackageName -> Repo -> FileChanges -> Result Errors (List ModuleChange)
orderFileChanges packageName repo fileChanges =
    let
        fileChangesByType : FileChanges.FileChangesByType
        fileChangesByType =
            fileChanges
                |> FileChanges.partitionByType

        parseSources : Dict FilePath.Path String -> Result Errors (List ParsedModule)
        parseSources sources =
            sources
                |> Dict.toList
                |> List.map (\( path, source ) -> parseSource ( path, source ))
                |> ResultList.keepAllErrors

        parsedInsertsAndUpdates : Result Errors (List ParsedModule)
        parsedInsertsAndUpdates =
            Result.map2 (++)
                (parseSources fileChangesByType.inserts)
                (parseSources fileChangesByType.updates)

        filePathsToModuleNames : Set FilePath.Path -> Result Errors (Set ModuleName)
        filePathsToModuleNames paths =
            paths
                |> Set.toList
                |> List.map (filePathToModuleName packageName)
                |> ResultList.keepAllErrors
                |> Result.map Set.fromList

        orderedFileChanges : Result Errors OrderedFileChanges
        orderedFileChanges =
            Result.map2 OrderedFileChanges
                (parsedInsertsAndUpdates
                    |> Result.andThen (orderElmModulesByDependency packageName)
                )
                (fileChangesByType.deletes
                    |> filePathsToModuleNames
                )
    in
    orderedFileChanges
        |> Result.map (reOrderChanges repo)


filePathToModuleName : PackageName -> FilePath.Path -> Result Error ModuleName
filePathToModuleName packageName filePath =
    let
        filePathParts : List String
        filePathParts =
            filePath
                -- Split by Linux path separator
                |> String.split "/"
                -- Split by Windows path separator
                |> List.concatMap (String.split "\\")

        packageNameReversed : List Name
        packageNameReversed =
            packageName |> List.reverse

        -- Try to find the package name going recursively backwards in the path, if it's found return the path that we
        -- skipped through as the module name
        findModuleName : Name -> List Name -> List Name -> Result String (List Name)
        findModuleName lastPartOfModuleName modulePathReversed remainingDirectoryPathReversed =
            if List.length remainingDirectoryPathReversed < List.length packageNameReversed then
                Err "Could not find package name in path."

            else if packageNameReversed |> Path.isPrefixOf remainingDirectoryPathReversed then
                Ok (lastPartOfModuleName :: modulePathReversed |> List.reverse)

            else
                case remainingDirectoryPathReversed of
                    lastDirectoryName :: nextRemainingDirectoryPathReversed ->
                        findModuleName lastPartOfModuleName (lastDirectoryName :: modulePathReversed) nextRemainingDirectoryPathReversed

                    _ ->
                        Err "Could not find package name in path."
    in
    case filePathParts |> List.reverse of
        filePart :: directoryPartReversed ->
            case filePart |> String.split "." of
                [ fileName, "elm" ] ->
                    findModuleName (Name.fromString fileName) [] (directoryPartReversed |> List.map Name.fromString)
                        |> Result.mapError (InvalidSourceFilePath filePath)

                _ ->
                    Err (InvalidSourceFilePath filePath "A valid file path must end with a file name with '.elm' extension.")

        _ ->
            Err (InvalidSourceFilePath filePath "A valid file path must have at least one directory and one file.")


applyFileChanges : PackageName -> List ModuleChange -> Options -> Maybe (Set Path) -> Repo -> Result Errors Repo
applyFileChanges packageName fileChanges opts maybeExposedModules repo =
    case maybeExposedModules of
        Just exposedModules ->
            if Set.isEmpty exposedModules then
                -- an effect of an empty exposedModules set
                -- is that all the modules would private and removed during tree shaking
                -- so we just return the repo here
                Ok repo

            else
                let
                    updateRepoModDep : ( ModuleName, Set ModuleName ) -> Result Errors (DAG ModuleName) -> Result Errors (DAG ModuleName)
                    updateRepoModDep ( modName, modDeps ) moduleDepDAGRes =
                        moduleDepDAGRes
                            |> Result.andThen
                                (DAG.insertNode modName modDeps >> Result.mapError (\(DAG.CycleDetected from to) -> [ ModuleCycleDetected from to ]))

                    insertsAndUpdates =
                        fileChanges
                            |> List.filterMap
                                (\change ->
                                    case change of
                                        ModuleInsert modName parsedMod ->
                                            Just ( modName, parsedMod )

                                        ModuleUpdate modName parsedMod ->
                                            Just ( modName, parsedMod )

                                        _ ->
                                            Nothing
                                )

                    updatedModuleDep : Result Errors (DAG ModuleName)
                    updatedModuleDep =
                        insertsAndUpdates
                            |> List.map
                                (\( modName, parsedModule ) ->
                                    ParsedModule.imports parsedModule
                                        |> List.filterMap
                                            (\imp ->
                                                let
                                                    importedModuleName =
                                                        imp.moduleName |> Node.value
                                                in
                                                importedModuleName |> toIRModuleName packageName
                                            )
                                        |> Set.fromList
                                        |> Tuple.pair modName
                                )
                            |> List.foldl updateRepoModDep (Repo.moduleDependencies repo |> Ok)

                    usedModules : DAG ModuleName -> Set ModuleName
                    usedModules modulesDeps =
                        exposedModules
                            |> Set.foldl
                                (\exposedModule usedModulesSoFar ->
                                    DAG.collectForwardReachableNodes exposedModule modulesDeps
                                        |> Debug.log "DAG.collectForwardReachableNodes exposedModule"
                                        |> Set.union usedModulesSoFar
                                )
                                exposedModules

                    modulesToProcess : Set ModuleName -> List ModuleChange
                    modulesToProcess usedModuleSet =
                        let
                            _ =
                                Debug.log "Used Modules:" usedModuleSet
                        in
                        fileChanges
                            |> List.filter
                                (\fileChange ->
                                    case fileChange of
                                        ModuleInsert moduleName _ ->
                                            Set.member moduleName usedModuleSet

                                        ModuleUpdate moduleName _ ->
                                            Set.member moduleName usedModuleSet

                                        ModuleDelete moduleName ->
                                            Set.member moduleName usedModuleSet
                                )
                in
                updatedModuleDep
                    |> Result.map (usedModules >> modulesToProcess)
                    |> Result.andThen (\filteredFileChanges -> applyChangesByOrder filteredFileChanges opts exposedModules repo)

        Nothing ->
            -- make everything public when exposedModules not defined
            -- create the list of exposedModules from insertsAndUpdates and the modules already in the repo
            let
                insertsAndUpdateChanges =
                    fileChanges
                        |> List.filterMap
                            (\modChange ->
                                case modChange of
                                    ModuleInsert modName _ ->
                                        Just modName

                                    ModuleUpdate modName _ ->
                                        Just modName

                                    ModuleDelete _ ->
                                        Nothing
                            )
            in
            Repo.modules repo
                |> Dict.keys
                |> List.append insertsAndUpdateChanges
                |> Set.fromList
                |> (\exposedMods -> applyChangesByOrder fileChanges opts exposedMods repo)


reOrderChanges : Repo -> OrderedFileChanges -> List ModuleChange
reOrderChanges repo orderedFileChanges =
    let
        updateAndInsertsAsDict : Dict ModuleName ParsedModule
        updateAndInsertsAsDict =
            Dict.fromList orderedFileChanges.insertsAndUpdates

        -- updates and deletes ordered by the existing moduleDependency
        updatesAndDeletesChanges : List ModuleChange
        updatesAndDeletesChanges =
            Repo.moduleDependencies repo
                |> (DAG.forwardTopologicalOrdering >> List.concat)
                |> List.filterMap
                    (\modName ->
                        case Dict.get modName updateAndInsertsAsDict of
                            Just parsedModule ->
                                ModuleUpdate modName parsedModule
                                    |> Just

                            Nothing ->
                                if Set.member modName orderedFileChanges.deletes then
                                    ModuleDelete modName |> Just

                                else
                                    Nothing
                    )

        insertsAndUpdatesChanges : List ModuleChange
        insertsAndUpdatesChanges =
            orderedFileChanges.insertsAndUpdates
                |> List.map
                    (\( modName, parsedModule ) ->
                        Repo.modules repo
                            |> (\existingMods ->
                                    if Dict.member modName existingMods then
                                        ModuleUpdate modName parsedModule

                                    else
                                        ModuleInsert modName parsedModule
                               )
                    )

        insertAfterOrBefore : Maybe ModuleChange -> Maybe ModuleChange -> ModuleChange -> List ModuleChange -> List ModuleChange
        insertAfterOrBefore after before item list =
            let
                insertAt index =
                    case List.splitAt index list of
                        ( firstPart, secondPart ) ->
                            List.concat [ firstPart, [ item ], secondPart ]

                tryInsertAfter =
                    case after of
                        Just afterValue ->
                            case List.elemIndex afterValue list of
                                Just index ->
                                    insertAt (index + 1)

                                Nothing ->
                                    tryInsertBefore

                        Nothing ->
                            tryInsertBefore

                tryInsertBefore =
                    case before of
                        Just beforeValue ->
                            case List.elemIndex beforeValue list of
                                Just index ->
                                    insertAt index

                                Nothing ->
                                    list

                        Nothing ->
                            list
            in
            tryInsertAfter

        allChangesMerged : List ModuleChange
        allChangesMerged =
            updatesAndDeletesChanges
                |> List.indexedMap (\idx change -> ( change, idx ))
                |> List.foldl
                    (\( change, idx ) mergeSoFar ->
                        case change of
                            ModuleInsert _ _ ->
                                -- no inserts will show up, continue.
                                mergeSoFar

                            ModuleUpdate _ _ ->
                                insertAfterOrBefore
                                    (List.getAt (idx - 1) updatesAndDeletesChanges)
                                    (List.getAt (idx + 1) updatesAndDeletesChanges)
                                    change
                                    mergeSoFar

                            ModuleDelete _ ->
                                insertAfterOrBefore
                                    (List.getAt (idx - 1) updatesAndDeletesChanges)
                                    (List.getAt (idx + 1) updatesAndDeletesChanges)
                                    change
                                    mergeSoFar
                    )
                    insertsAndUpdatesChanges
    in
    allChangesMerged


applyChangesByOrder : List ModuleChange -> Options -> Set Path -> Repo -> Result Errors Repo
applyChangesByOrder orderedChanges opts exposedModules repo =
    orderedChanges
        |> List.foldl
            (\modChange repoResultSoFar ->
                case modChange of
                    ModuleInsert modName parsedModule ->
                        repoResultSoFar
                            |> Result.andThen (applyInsert modName parsedModule opts exposedModules)

                    ModuleUpdate modName parsedModule ->
                        repoResultSoFar
                            |> Result.andThen (applyUpdate modName parsedModule opts exposedModules)

                    ModuleDelete _ ->
                        repoResultSoFar
            )
            (Ok repo)
        |> Result.andThen
            (\updatedRepo ->
                orderedChanges
                    |> List.reverse
                    |> List.foldl
                        (\modChange repoResultSoFar ->
                            case modChange of
                                ModuleInsert _ _ ->
                                    repoResultSoFar

                                ModuleUpdate modName parsedModule ->
                                    repoResultSoFar
                                        |> Result.andThen (applyUpdateCleanup modName parsedModule repo)

                                ModuleDelete modName ->
                                    repoResultSoFar |> Result.andThen (applyDelete modName)
                        )
                        (Ok updatedRepo)
            )
        |> Result.andThen
            (Repo.removeUnusedModules exposedModules
                >> Result.mapError (RepoError "" >> List.singleton)
            )
        |> Result.map
            (\r ->
                -- make implicitly exposed modules public
                exposedModules
                    |> collectImplicitlyExposedModules (Repo.getPackageName r)
                        (Repo.modules r
                            |> Dict.map
                                (\_ accessControlledModuleDef ->
                                    accessControlledModuleDef.value
                                )
                        )
                    |> Set.foldl (Repo.updateModuleAccess AccessControlled.Public) r
            )


applyInsert : ModuleName -> ParsedModule -> Options -> Set Path -> Repo -> Result Errors Repo
applyInsert moduleName parsedModule opts exposedModules repo =
    processModule moduleName parsedModule opts exposedModules repo


applyUpdate : ModuleName -> ParsedModule -> Options -> Set Path -> Repo -> Result Errors Repo
applyUpdate moduleName parsedModule opts exposedModules repo =
    processModule moduleName parsedModule opts exposedModules repo


applyUpdateCleanup : ModuleName -> ParsedModule -> Repo -> Repo -> Result Errors Repo
applyUpdateCleanup moduleName parsedModule oldRepoState newRepoState =
    let
        currentTypes : Set Name
        currentTypes =
            extractTypeNames parsedModule
                |> Set.fromList

        currentValues : Set Name
        currentValues =
            extractValueNames parsedModule
                |> Set.fromList

        previousTypes : Set Name
        previousTypes =
            Repo.modules oldRepoState
                |> Dict.get moduleName
                |> Maybe.map (.value >> .types >> Dict.keys >> Set.fromList)
                |> Maybe.withDefault Set.empty

        previousValues : Set Name
        previousValues =
            Repo.modules oldRepoState
                |> Dict.get moduleName
                |> Maybe.map (.value >> .values >> Dict.keys >> Set.fromList)
                |> Maybe.withDefault Set.empty

        deletedTypes : Set Name
        deletedTypes =
            Set.diff previousTypes currentTypes

        deletedValues : Set Name
        deletedValues =
            Set.diff previousValues currentValues

        deletedTypesOrderedByDeps : List Name
        deletedTypesOrderedByDeps =
            Repo.typeDependencies oldRepoState
                |> (DAG.forwardTopologicalOrdering >> List.concat)
                |> List.filterMap
                    (\( _, mn, name ) ->
                        if mn == moduleName && Set.member name deletedTypes then
                            Just name

                        else
                            Nothing
                    )

        deletedValuesOrderedByDeps : List Name
        deletedValuesOrderedByDeps =
            Repo.valueDependencies oldRepoState
                |> (DAG.forwardTopologicalOrdering >> List.concat)
                |> List.filterMap
                    (\( _, mn, name ) ->
                        if mn == moduleName && Set.member name deletedValues then
                            Just name

                        else
                            Nothing
                    )
    in
    deletedValuesOrderedByDeps
        |> List.foldl
            (\valueName repoResultSoFar ->
                repoResultSoFar
                    |> Result.andThen
                        (Repo.deleteValue moduleName valueName
                            >> Result.mapError (RepoError "could not delete value" >> List.singleton)
                        )
            )
            (Ok newRepoState)
        |> (\repoResultWithValueDeleted ->
                deletedTypesOrderedByDeps
                    |> List.foldl
                        (\typeName repoResultSoFar ->
                            repoResultSoFar
                                |> Result.andThen
                                    (Repo.deleteType moduleName typeName
                                        >> Result.mapError (RepoError "could not delete type" >> List.singleton)
                                    )
                        )
                        repoResultWithValueDeleted
           )


applyDelete : ModuleName -> Repo -> Result Errors Repo
applyDelete moduleName repo =
    Repo.deleteModule moduleName repo
        |> Result.mapError (RepoError "Cannot delete module" >> List.singleton)


processModule : ModuleName -> ParsedModule -> Options -> Set Path -> Repo -> Result (List Error) Repo
processModule moduleName parsedModule opts exposedModules repo =
    let
        accessOf : KindOfName -> Name -> Access
        accessOf kindOfName localName =
            case parsedModule |> ParsedModule.exposingList of
                Exposing.All _ ->
                    Public

                Exposing.Explicit topLevelExposesNodes ->
                    let
                        isExposed : Bool
                        isExposed =
                            topLevelExposesNodes
                                |> List.map Node.value
                                |> List.any
                                    (\topLevelExpose ->
                                        case ( kindOfName, topLevelExpose ) of
                                            ( Value, Exposing.FunctionExpose functionName ) ->
                                                Name.fromString functionName == localName

                                            ( Type, Exposing.TypeOrAliasExpose typeName ) ->
                                                Name.fromString typeName == localName

                                            ( Type, Exposing.TypeExpose typeExpose ) ->
                                                Name.fromString typeExpose.name == localName

                                            ( Constructor, Exposing.TypeExpose te ) ->
                                                case te.open of
                                                    Just _ ->
                                                        Name.fromString te.name == localName

                                                    Nothing ->
                                                        False

                                            _ ->
                                                False
                                    )
                    in
                    if isExposed then
                        Public

                    else
                        Private

        -- if a moduleName is not in repo insert it because it's probably a module insert
        repoWithModuleInserted : Repo
        repoWithModuleInserted =
            let
                moduleAccess =
                    if Set.member moduleName exposedModules then
                        Public

                    else
                        Private

                documentedModule : Module.Definition () (Type ())
                documentedModule =
                    { types = Dict.empty
                    , values = Dict.empty
                    , doc = ParsedModule.documentation parsedModule
                    }
            in
            repo
                |> Repo.insertModule moduleName documentedModule moduleAccess
                |> Result.withDefault repo

        typeNames : List Name
        typeNames =
            extractTypeNames parsedModule

        constructorNames : List Name
        constructorNames =
            extractConstructorNames parsedModule

        valueNames : List Name
        valueNames =
            extractValueNames parsedModule

        localNames : IncrementalResolve.VisibleNames
        localNames =
            { types = Set.fromList typeNames
            , constructors = Set.fromList constructorNames
            , values = Set.fromList valueNames
            }
    in
    parsedModule
        |> ParsedModule.imports
        |> IncrementalResolve.resolveImports repoWithModuleInserted
        |> Result.mapError (ResolveError moduleName >> List.singleton)
        |> Result.andThen
            (\resolvedImports ->
                let
                    resolveName : List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName
                    resolveName modName localName kindOfName =
                        IncrementalResolve.resolveLocalName
                            repoWithModuleInserted
                            moduleName
                            localNames
                            resolvedImports
                            modName
                            kindOfName
                            localName
                in
                extractTypes resolveName accessOf parsedModule
                    |> Result.andThen (orderTypesByDependency (Repo.getPackageName repoWithModuleInserted) moduleName)
                    |> Result.andThen
                        (List.foldl
                            (\( typeName, typeDoc, typeDef ) repoResultForType ->
                                repoResultForType
                                    |> Result.andThen (processType moduleName typeName typeDef (accessOf Type typeName) typeDoc)
                            )
                            (Ok repoWithModuleInserted)
                        )
                    |> Result.andThen
                        (\repoWithTypesInserted ->
                            if opts.typesOnly then
                                Ok repoWithTypesInserted

                            else
                                extractValues resolveName parsedModule
                                    |> Result.andThen
                                        (List.foldl
                                            (\( valueName, valueDoc, valueDef ) repoResultSoFar ->
                                                repoResultSoFar
                                                    |> Result.andThen (processValue (accessOf Value valueName) moduleName valueName valueDef valueDoc)
                                            )
                                            (Ok repoWithTypesInserted)
                                        )
                        )
            )



-- TODO track noChanges. not tracking no changes


processType : ModuleName -> Name -> Type.Definition () -> Access -> String -> Repo -> Result (List Error) Repo
processType moduleName typeName typeDef access doc repo =
    case repo |> Repo.modules |> Dict.get moduleName of
        Just existingModDef ->
            case Dict.member typeName existingModDef.value.types of
                True ->
                    -- TODO update a type using an update function
                    repo
                        |> Repo.updateType moduleName typeName typeDef access doc
                        |> Result.mapError (RepoError "Cannot process type" >> List.singleton)

                False ->
                    repo
                        |> Repo.insertType moduleName typeName typeDef access doc
                        |> Result.mapError (RepoError "Cannot process type" >> List.singleton)

        Nothing ->
            -- module does not exist, do nothing
            -- TODO : module should already exist, but error out if it doesn't
            Ok repo


processValue : Access -> ModuleName -> Name -> SignatureAndValue -> String -> Repo -> Result (List Error) Repo
processValue access moduleName valueName ( maybeValueType, body ) valueDoc repo =
    let
        _ =
            Debug.log "processing value" (String.concat [ Path.toString Name.toTitleCase "." moduleName, ".", Name.toCamelCase valueName ])
    in
    case repo |> Repo.modules |> Dict.get moduleName of
        Just existingModDef ->
            case Dict.member valueName existingModDef.value.values of
                True ->
                    repo
                        |> Repo.updateValue moduleName valueName maybeValueType body access valueDoc
                        |> Result.mapError (RepoError "Cannot process value" >> List.singleton)

                False ->
                    repo
                        |> Repo.insertValue moduleName valueName maybeValueType body access valueDoc
                        |> Result.mapError (RepoError "Cannot process value" >> List.singleton)

        Nothing ->
            -- module does not exist, do nothing
            -- TODO : module should already exist, but error out if it doesn't
            Ok repo


{-| convert New or Updated Elm modules into ParsedModules for further processing
-}
parseElmModules : FileChanges -> Result Errors (List ParsedModule)
parseElmModules fileChanges =
    fileChanges
        |> Dict.toList
        |> List.filterMap
            (\( path, content ) ->
                case content of
                    Insert source ->
                        Just ( path, source )

                    Update source ->
                        Just ( path, source )

                    Delete ->
                        Nothing
            )
        |> List.map parseSource
        |> ResultList.keepAllErrors


{-| Converts an elm source into a ParsedModule.
-}
parseSource : ( FilePath.Path, String ) -> Result Error ParsedModule
parseSource ( path, content ) =
    Elm.Parser.parse content
        |> Result.mapError (ParseError path)
        |> Result.map ParsedModule.parsedModule


orderElmModulesByDependency : PackageName -> List ParsedModule -> Result Errors (List ( ModuleName, ParsedModule ))
orderElmModulesByDependency packageName parsedModules =
    let
        parsedModuleByName : Dict ModuleName ParsedModule
        parsedModuleByName =
            parsedModules
                |> List.filterMap
                    (\parsedModule ->
                        ParsedModule.moduleName parsedModule
                            |> ElmModuleName.toIRModuleName packageName
                            |> Maybe.map
                                (\moduleName ->
                                    ( moduleName
                                    , parsedModule
                                    )
                                )
                    )
                |> Dict.fromList

        foldFunction : ParsedModule -> Result Errors (DAG ModuleName) -> Result Errors (DAG ModuleName)
        foldFunction parsedModule graph =
            let
                moduleDependencies : Set ModuleName
                moduleDependencies =
                    ParsedModule.importedModules parsedModule
                        |> List.filterMap
                            (\modName ->
                                ElmModuleName.toIRModuleName packageName modName
                            )
                        |> Set.fromList

                elmModuleName : ElmModuleName.ModuleName
                elmModuleName =
                    ParsedModule.moduleName parsedModule
            in
            case elmModuleName |> ElmModuleName.toIRModuleName packageName of
                Nothing ->
                    graph

                Just fromModuleName ->
                    graph
                        |> Result.andThen
                            (DAG.insertNode fromModuleName moduleDependencies
                                >> Result.mapError (\(DAG.CycleDetected from to) -> [ ModuleCycleDetected from to ])
                            )
    in
    parsedModules
        |> List.foldl foldFunction (Ok DAG.empty)
        |> Result.map
            (\graph ->
                graph
                    |> DAG.backwardTopologicalOrdering
                    |> List.concat
                    |> List.filterMap
                        (\moduleName ->
                            parsedModuleByName
                                |> Dict.get moduleName
                                |> Maybe.map (Tuple.pair moduleName)
                        )
            )


extractTypeNames : ParsedModule -> List Name
extractTypeNames parsedModule =
    let
        extractTypeNamesFromFile : List (Node Declaration) -> List Name
        extractTypeNamesFromFile declarations =
            declarations
                |> List.filterMap
                    (\node ->
                        case Node.value node of
                            CustomTypeDeclaration typ ->
                                typ.name |> Node.value |> Just

                            AliasDeclaration typeAlias ->
                                typeAlias.name |> Node.value |> Just

                            _ ->
                                Nothing
                    )
                |> List.map Name.fromString
    in
    parsedModule
        |> ParsedModule.declarations
        |> extractTypeNamesFromFile


extractConstructorNames : ParsedModule -> List Name
extractConstructorNames parsedModule =
    let
        extractConstructorNamesFromFile : List (Node Declaration) -> List Name
        extractConstructorNamesFromFile declarations =
            declarations
                |> List.concatMap
                    (\node ->
                        case Node.value node of
                            CustomTypeDeclaration typ ->
                                typ.constructors |> List.map (Node.value >> .name >> Node.value)

                            AliasDeclaration typeAlias ->
                                case typeAlias.typeAnnotation |> Node.value of
                                    TypeAnnotation.Record _ ->
                                        -- Record type aliases have an implicit type constructor
                                        [ typeAlias.name |> Node.value ]

                                    _ ->
                                        []

                            _ ->
                                []
                    )
                |> List.map Name.fromString
    in
    parsedModule
        |> ParsedModule.declarations
        |> extractConstructorNamesFromFile


extractTypes : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> (KindOfName -> Name -> Access) -> ParsedModule -> Result Errors (List ( Name, String, Type.Definition () ))
extractTypes resolveTypeName accessOf parsedModule =
    let
        declarationsInParsedModule : List Declaration
        declarationsInParsedModule =
            parsedModule
                |> ParsedModule.declarations
                |> List.map Node.value

        typeNameWithDefinition : Result Errors (List ( Name, String, Type.Definition () ))
        typeNameWithDefinition =
            declarationsInParsedModule
                |> List.filterMap typeDeclarationToDefinition
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat

        typeDeclarationToDefinition : Declaration -> Maybe (Result Errors ( Name, String, Type.Definition () ))
        typeDeclarationToDefinition declaration =
            case declaration of
                CustomTypeDeclaration customType ->
                    let
                        typeParams : List Name
                        typeParams =
                            customType.generics
                                |> List.map (Node.value >> Name.fromString)

                        typeDoc : String
                        typeDoc =
                            customType.documentation
                                |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                |> Maybe.withDefault ""

                        constructorsResult : Result Errors (Type.Constructors ())
                        constructorsResult =
                            customType.constructors
                                |> List.map
                                    (\(Node _ constructor) ->
                                        let
                                            constructorName : Name
                                            constructorName =
                                                constructor.name
                                                    |> Node.value
                                                    |> Name.fromString

                                            constructorArgsResult : Result Errors (List ( Name, Type () ))
                                            constructorArgsResult =
                                                constructor.arguments
                                                    |> List.indexedMap
                                                        (\index arg ->
                                                            Mapper.mapTypeAnnotation resolveTypeName arg
                                                                |> Result.mapError MappingError
                                                                |> Result.map
                                                                    (\argType ->
                                                                        ( [ "arg", String.fromInt (index + 1) ]
                                                                        , argType |> Type.mapTypeAttributes (always ())
                                                                        )
                                                                    )
                                                        )
                                                    |> ResultList.keepAllErrors
                                        in
                                        Result.map (Tuple.pair constructorName) constructorArgsResult
                                    )
                                |> ResultList.keepAllErrors
                                |> Result.mapError List.concat
                                |> Result.map Dict.fromList

                        typeName : Name
                        typeName =
                            customType.name |> Node.value |> Name.fromString
                    in
                    constructorsResult
                        |> Result.map
                            (\constructors ->
                                ( typeName
                                , typeDoc
                                , Type.customTypeDefinition typeParams
                                    (AccessControlled.AccessControlled (accessOf Constructor typeName) constructors)
                                )
                            )
                        |> Just

                AliasDeclaration typeAlias ->
                    let
                        typeDoc : String
                        typeDoc =
                            typeAlias.documentation
                                |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                |> Maybe.withDefault ""

                        typeParams : List Name
                        typeParams =
                            typeAlias.generics
                                |> List.map (Node.value >> Name.fromString)
                    in
                    typeAlias.typeAnnotation
                        |> Mapper.mapTypeAnnotation resolveTypeName
                        |> Result.mapError (MappingError >> List.singleton)
                        |> Result.map
                            (\tpe ->
                                ( typeAlias.name
                                    |> Node.value
                                    |> Name.fromString
                                , typeDoc
                                , Type.TypeAliasDefinition typeParams (tpe |> Type.mapTypeAttributes (always ()))
                                )
                            )
                        |> Just

                _ ->
                    Nothing
    in
    typeNameWithDefinition


{-| Order types topologically by their dependencies. The purpose of this function is to allow us to insert the types
into the repo in the right order without causing dependency errors.
-}
orderTypesByDependency : PackageName -> ModuleName -> List ( Name, String, Type.Definition () ) -> Result Errors (List ( Name, String, Type.Definition () ))
orderTypesByDependency thisPackageName thisModuleName unorderedTypeDefinitions =
    let
        -- This dictionary will allow us to correlate back each type definition to their names after we ordered the names
        typeDefinitionsByName : Dict Name ( Type.Definition (), String )
        typeDefinitionsByName =
            unorderedTypeDefinitions
                |> List.map (\( name, doc, def ) -> ( name, ( def, doc ) ))
                |> Dict.fromList

        -- Helper function to collect all references of a type definition
        collectReferences : Type.Definition () -> Set FQName
        collectReferences typeDef =
            case typeDef of
                Type.TypeAliasDefinition _ typeExp ->
                    Type.collectReferences typeExp

                Type.CustomTypeDefinition _ accessControlledConstructors ->
                    accessControlledConstructors.value
                        |> Dict.values
                        |> List.concat
                        |> List.map (Tuple.second >> Type.collectReferences)
                        |> List.foldl Set.union Set.empty

        -- We only need to take into account local type references when ordering them
        keepLocalTypesOnly : Set FQName -> Set Name
        keepLocalTypesOnly allTypeNames =
            allTypeNames
                |> Set.filter
                    (\( packageName, moduleName, _ ) ->
                        packageName == thisPackageName && moduleName == thisModuleName
                    )
                |> Set.map (\( _, _, typeName ) -> typeName)

        -- Build the dependency graph of type names
        buildDependencyGraph : Result (CycleDetected Name) (DAG Name)
        buildDependencyGraph =
            unorderedTypeDefinitions
                |> List.foldl
                    (\( nextTypeName, _, typeDef ) dagResultSoFar ->
                        dagResultSoFar
                            |> Result.andThen
                                (\dagSoFar ->
                                    dagSoFar
                                        |> DAG.insertNode nextTypeName
                                            (typeDef
                                                |> collectReferences
                                                |> keepLocalTypesOnly
                                            )
                                )
                    )
                    (Ok DAG.empty)
    in
    buildDependencyGraph
        |> Result.mapError (\(CycleDetected from to) -> [ TypeCycleDetected from to ])
        |> Result.map
            (\typeDependencies ->
                typeDependencies
                    |> DAG.backwardTopologicalOrdering
                    |> List.concat
                    |> List.filterMap
                        (\typeName ->
                            typeDefinitionsByName
                                |> Dict.get typeName
                                |> Maybe.map (\( def, doc ) -> ( typeName, doc, def ))
                        )
            )


extractValueNames : ParsedModule -> List Name
extractValueNames parsedModule =
    let
        extractValueNamesFromFile : List (Node Declaration) -> List Name
        extractValueNamesFromFile declarations =
            declarations
                |> List.filterMap
                    (\node ->
                        case Node.value node of
                            FunctionDeclaration func ->
                                func.declaration |> Node.value |> .name |> Node.value |> Just

                            _ ->
                                Nothing
                    )
                |> List.map Name.fromString
    in
    parsedModule
        |> ParsedModule.declarations
        |> extractValueNamesFromFile


{-| Extract value definitions
-}
extractValues : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> ParsedModule -> Result Errors (List ( Name, String, SignatureAndValue ))
extractValues resolveValueName parsedModule =
    let
        -- get function name
        -- get function implementation
        -- get function expression
        declarationsAsDefintionsResult : Result Errors (Dict FQName ( SignatureAndValue, String ))
        declarationsAsDefintionsResult =
            ParsedModule.declarations parsedModule
                |> Mapper.mapDeclarationsToValue resolveValueName parsedModule
                |> Result.mapError (MappingError >> List.singleton)
                |> Result.map Dict.fromList

        -- create ordered value names
        orderedValueNameResult : Result Errors (List FQName)
        orderedValueNameResult =
            declarationsAsDefintionsResult
                |> Result.andThen
                    (Dict.toList
                        >> List.foldl
                            (\( fQName, ( ( _, body ), _ ) ) dagResultSoFar ->
                                let
                                    refs =
                                        Value.collectReferences body
                                in
                                dagResultSoFar
                                    |> Result.andThen (DAG.insertNode fQName refs)
                            )
                            (Ok DAG.empty)
                        >> Result.mapError
                            (\(DAG.CycleDetected fNode tNode) ->
                                [ ValueCycleDetected fNode tNode ]
                            )
                        >> Result.map DAG.backwardTopologicalOrdering
                        >> Result.map List.concat
                    )

        orderedDeclarationAsDefinitions : Result Errors (List ( Name, String, SignatureAndValue ))
        orderedDeclarationAsDefinitions =
            orderedValueNameResult
                |> Result.andThen
                    (\fqNames ->
                        declarationsAsDefintionsResult
                            |> Result.map (Tuple.pair fqNames)
                    )
                |> Result.map
                    (\( fqNames, defs ) ->
                        List.foldl
                            (\fqName listSoFar ->
                                case Dict.get fqName defs of
                                    Just ( def, doc ) ->
                                        let
                                            ( _, _, name ) =
                                                fqName
                                        in
                                        List.append listSoFar [ ( name, doc, def ) ]

                                    Nothing ->
                                        listSoFar
                            )
                            []
                            fqNames
                    )
    in
    orderedDeclarationAsDefinitions


{-| Returns a Set of implicitly exposed modules.
A module `ModA` is implicitly exposed if an explicitly exposed module `ModB` uses one of it's type in a public interface.
This could be as a result of a public type in `ModB` dependending on a type in `ModA` or a public function defined in
`ModB` that takes, as an input, a type defined in `ModA`.

The parameters are

  - packageName - Name of the package
  - moduleDefs - All the modules
  - exposedModules - A set of exposed module-names

-}
collectImplicitlyExposedModules : PackageName -> Dict Path (Module.Definition ta va) -> Set Path -> Set Path
collectImplicitlyExposedModules packageName moduleDefs exposedModules =
    let
        exposedTypesRef : Set FQName
        exposedTypesRef =
            let
                inputTypes : List ( a, b, Type ta ) -> List (Type ta)
                inputTypes =
                    List.map (\( _, _, tpe ) -> tpe)

                getPubliclyExposedTypeRefs : Module.Definition ta va -> Set FQName
                getPubliclyExposedTypeRefs modDef =
                    Set.union
                        (modDef.types
                            |> Dict.foldl
                                (\_ accessControlledTpe publicExposedTypeRefSoFar ->
                                    collectImplicitlyExposedReferencesFromDef accessControlledTpe
                                        |> Set.union publicExposedTypeRefSoFar
                                )
                                Set.empty
                        )
                        (modDef.values
                            |> Dict.foldl
                                (\_ accessControlledVal publicExposedTypeRefsSoFar ->
                                    if accessControlledVal.access == AccessControlled.Public then
                                        accessControlledVal.value.value.outputType
                                            :: inputTypes accessControlledVal.value.value.inputTypes
                                            |> List.map Type.collectReferences
                                            |> List.foldl Set.union publicExposedTypeRefsSoFar

                                    else
                                        publicExposedTypeRefsSoFar
                                )
                                Set.empty
                        )
            in
            exposedModules
                |> Set.foldl
                    (\modName exposedTypeRefsSoFar ->
                        moduleDefs
                            |> Dict.get modName
                            |> Maybe.map getPubliclyExposedTypeRefs
                            |> Maybe.withDefault Set.empty
                            |> Set.union exposedTypeRefsSoFar
                    )
                    Set.empty

        lookupTypeDef : FQName -> Maybe (AccessControlled (Documented (Type.Definition ta)))
        lookupTypeDef fqn =
            case fqn of
                ( _, modPath, tpeName ) ->
                    Dict.get modPath moduleDefs
                        |> Maybe.andThen
                            (Dict.get tpeName << .types)

        collectImplicitlyExposedReferencesFromDef : AccessControlled (Documented (Type.Definition ta)) -> Set FQName
        collectImplicitlyExposedReferencesFromDef accessControlledTpeDef =
            if accessControlledTpeDef.access == AccessControlled.Public then
                case accessControlledTpeDef.value.value of
                    Type.TypeAliasDefinition _ tpe ->
                        Type.collectReferences tpe

                    Type.CustomTypeDefinition _ accessControlledCtors ->
                        if accessControlledCtors.access == AccessControlled.Public then
                            Dict.toList accessControlledCtors.value
                                |> List.concatMap Tuple.second
                                |> List.map
                                    (Tuple.second
                                        >> Type.collectReferences
                                    )
                                |> List.foldl Set.union Set.empty

                        else
                            Set.empty

            else
                Set.empty

        extractImplicitDependencies : Set FQName -> Set Path -> Set Path
        extractImplicitDependencies publiclyExposedTypes implicitlyExposedModules =
            case Set.toList publiclyExposedTypes of
                [] ->
                    implicitlyExposedModules

                tpeFQN :: otherExposedTypes ->
                    case tpeFQN of
                        ( pkgName, modName, _ ) ->
                            if pkgName /= packageName then
                                -- ignore refs from other packages
                                extractImplicitDependencies (Set.fromList otherExposedTypes) implicitlyExposedModules

                            else if Set.member modName exposedModules then
                                -- ignore explicitly exposed modules
                                extractImplicitDependencies (Set.fromList otherExposedTypes) implicitlyExposedModules

                            else if Set.member modName implicitlyExposedModules then
                                -- ignore already collected implicitly exposed
                                extractImplicitDependencies (Set.fromList otherExposedTypes) implicitlyExposedModules

                            else
                                let
                                    withNewRefs : Set FQName
                                    withNewRefs =
                                        lookupTypeDef tpeFQN
                                            |> Maybe.map collectImplicitlyExposedReferencesFromDef
                                            |> Maybe.withDefault Set.empty
                                            |> Set.union (Set.fromList otherExposedTypes)
                                in
                                extractImplicitDependencies
                                    withNewRefs
                                    (Set.insert modName implicitlyExposedModules)
    in
    extractImplicitDependencies exposedTypesRef Set.empty
