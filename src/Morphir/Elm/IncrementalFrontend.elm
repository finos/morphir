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
import Morphir.Dependency.DAG as DAG exposing (CycleDetected(..), DAG)
import Morphir.Elm.IncrementalFrontend.Mapper as Mapper
import Morphir.Elm.IncrementalResolve as IncrementalResolve
import Morphir.Elm.ModuleName as ElmModuleName
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.File.FileChanges as FileChanges exposing (Change(..), FileChanges)
import Morphir.File.Path as FilePath
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..))
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.KindOfName exposing (KindOfName(..))
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Repo as Repo exposing (Repo, SourceCode)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.SDK.ResultList as ResultList
import Parser
import Set exposing (Set)


type alias Errors =
    List Error


type Error
    = ModuleCycleDetected ModuleName ModuleName
    | TypeCycleDetected Name Name
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


orderFileChanges : PackageName -> FileChanges -> Result Errors OrderedFileChanges
orderFileChanges packageName fileChanges =
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
    in
    Result.map2 OrderedFileChanges
        (parsedInsertsAndUpdates
            |> Result.andThen (orderElmModulesByDependency packageName)
        )
        (fileChangesByType.deletes
            |> filePathsToModuleNames
        )


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


applyFileChanges : OrderedFileChanges -> Repo -> Result Errors Repo
applyFileChanges fileChanges repo =
    repo
        |> applyInsertsAndUpdates fileChanges.insertsAndUpdates
        |> Result.andThen (applyDeletes fileChanges.deletes)


applyInsertsAndUpdates : List ( ModuleName, ParsedModule ) -> Repo -> Result Errors Repo
applyInsertsAndUpdates insertsAndUpdates repo =
    insertsAndUpdates
        |> List.foldl
            (\( moduleName, parsedModule ) repoResultForModule ->
                repoResultForModule
                    |> Result.andThen (processModule moduleName parsedModule)
            )
            (Ok repo)


applyDeletes : Set ModuleName -> Repo -> Result Errors Repo
applyDeletes deletes repo =
    deletes
        |> Set.foldl
            (\moduleName repoResultForModule ->
                repoResultForModule
                    |> Result.andThen (Repo.deleteModule moduleName)
            )
            (Ok repo)
        |> Result.mapError (RepoError "Cannot delete module" >> List.singleton)


processModule : ModuleName -> ParsedModule -> Repo -> Result (List Error) Repo
processModule moduleName parsedModule repo =
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

                                            ( Type, Exposing.TypeExpose te ) ->
                                                Name.fromString te.name == localName

                                            _ ->
                                                False
                                    )
                    in
                    if isExposed then
                        Public

                    else
                        Private

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

        resolveName : List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName
        resolveName modName localName kindOfName =
            parsedModule
                |> ParsedModule.imports
                |> IncrementalResolve.resolveImports repo
                |> Result.andThen
                    (\resolvedImports ->
                        IncrementalResolve.resolveLocalName
                            repo
                            moduleName
                            localNames
                            resolvedImports
                            modName
                            kindOfName
                            localName
                    )
    in
    extractTypes resolveName parsedModule
        |> Result.andThen (orderTypesByDependency (Repo.getPackageName repo) moduleName)
        |> Result.andThen
            (List.foldl
                (\( typeName, typeDef ) repoResultForType ->
                    repoResultForType
                        |> Result.andThen (processType moduleName typeName typeDef)
                )
                (Ok repo)
            )
        |> Result.andThen
            (\repoWithTypesInserted ->
                extractValues resolveName parsedModule
                    |> Result.andThen
                        (List.foldl
                            (\( name, definition ) repoResultSoFar ->
                                repoResultSoFar
                                    |> Result.andThen (processValue (accessOf Value name) moduleName name definition)
                            )
                            (Ok repoWithTypesInserted)
                        )
            )


processType : ModuleName -> Name -> Type.Definition () -> Repo -> Result (List Error) Repo
processType moduleName typeName typeDef repo =
    repo
        |> Repo.insertType moduleName typeName typeDef
        |> Result.mapError (RepoError "Cannot process type" >> List.singleton)


processValue : Access -> ModuleName -> Name -> Value.Definition Bool () -> Repo -> Result (List Error) Repo
processValue access moduleName valueName valueDefinition repo =
    repo
        -- TODO: implement type inference
        |> Repo.insertTypedValue moduleName valueName (valueDefinition |> Value.mapDefinitionAttributes (always ()) (always (Type.Unit ())))
        |> Result.mapError (RepoError "Cannot process value" >> List.singleton)


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
            elmModuleName
                |> ElmModuleName.toIRModuleName packageName
                |> Result.fromMaybe [ InvalidModuleName elmModuleName ]
                |> Result.andThen
                    (\fromModuleName ->
                        graph
                            |> Result.andThen
                                (DAG.insertNode fromModuleName moduleDependencies
                                    >> Result.mapError (\(DAG.CycleDetected from to) -> [ ModuleCycleDetected from to ])
                                )
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


extractTypes : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> ParsedModule -> Result Errors (List ( Name, Type.Definition () ))
extractTypes resolveTypeName parsedModule =
    let
        declarationsInParsedModule : List Declaration
        declarationsInParsedModule =
            parsedModule
                |> ParsedModule.declarations
                |> List.map Node.value

        typeNameToDefinition : Result Errors (List ( Name, Type.Definition () ))
        typeNameToDefinition =
            declarationsInParsedModule
                |> List.filterMap typeDeclarationToDefinition
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat

        typeDeclarationToDefinition : Declaration -> Maybe (Result Errors ( Name, Type.Definition () ))
        typeDeclarationToDefinition declaration =
            case declaration of
                CustomTypeDeclaration customType ->
                    let
                        typeParams : List Name
                        typeParams =
                            customType.generics
                                |> List.map (Node.value >> Name.fromString)

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
                    in
                    constructorsResult
                        |> Result.map
                            (\constructors ->
                                ( customType.name |> Node.value |> Name.fromString
                                , Type.customTypeDefinition typeParams (AccessControlled.public constructors)
                                )
                            )
                        |> Just

                AliasDeclaration typeAlias ->
                    let
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
                                , Type.TypeAliasDefinition typeParams (tpe |> Type.mapTypeAttributes (always ()))
                                )
                            )
                        |> Just

                _ ->
                    Nothing
    in
    typeNameToDefinition


{-| Order types topologically by their dependencies. The purpose of this function is to allow us to insert the types
into the repo in the right order without causing dependency errors.
-}
orderTypesByDependency : PackageName -> ModuleName -> List ( Name, Type.Definition () ) -> Result Errors (List ( Name, Type.Definition () ))
orderTypesByDependency thisPackageName thisModuleName unorderedTypeDefinitions =
    let
        -- This dictionary will allow us to correlate back each type definition to their names after we ordered the names
        typeDefinitionsByName : Dict Name (Type.Definition ())
        typeDefinitionsByName =
            unorderedTypeDefinitions
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
                    (\( nextTypeName, typeDef ) dagResultSoFar ->
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
                                |> Maybe.map (Tuple.pair typeName)
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
extractValues : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> ParsedModule -> Result Errors (List ( Name, Value.Definition Bool () ))
extractValues resolveValueName parsedModule =
    let
        -- get function name
        -- get function implementation
        -- get function expression
        declarationsAsDefintionsResult : Result Errors (Dict FQName (Value.Definition Bool ()))
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
                            (\( fQName, def ) dagResultSoFar ->
                                let
                                    refs =
                                        Value.collectReferences def.body
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

        orderedDeclarationAsDefinitions : Result Errors (List ( Name, Value.Definition Bool () ))
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
                                    Just def ->
                                        let
                                            ( _, _, name ) =
                                                fqName
                                        in
                                        List.append listSoFar [ ( name, def ) ]

                                    Nothing ->
                                        listSoFar
                            )
                            []
                            fqNames
                    )
    in
    orderedDeclarationAsDefinitions
