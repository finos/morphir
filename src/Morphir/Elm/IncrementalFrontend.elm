module Morphir.Elm.IncrementalFrontend exposing (..)

{-| Apply all file changes to the repo in one step.
-}

import Dict exposing (Dict)
import Elm.Parser
import Elm.Processing as Processing exposing (ProcessContext)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Morphir.Dependency.DAG as DAG exposing (DAG)
import Morphir.Elm.ModuleName as ElmModuleName
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.Elm.WellKnownOperators as WellKnownOperators
import Morphir.File.FileChanges as FileChanges exposing (Change(..), FileChanges)
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Repo as Repo exposing (Repo, SourceCode, withAccessControl)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.SDK.ResultList as ResultList
import Parser


type alias Errors =
    List Error


type Error
    = CycleDetected ModuleName ModuleName
    | InvalidModuleName ElmModuleName.ModuleName
    | ParseError FileChanges.Path (List Parser.DeadEnd)
    | RepoError Repo.Errors


applyFileChanges : FileChanges -> Repo -> Result Errors Repo
applyFileChanges fileChanges repo =
    parseElmModules fileChanges
        |> Result.andThen (orderElmModulesByDependency repo)
        |> Result.andThen
            (\parsedModules ->
                parsedModules
                    |> List.foldl
                        (\( moduleName, parsedModule ) repoResultForModule ->
                            let
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
                                                        |> Result.andThen
                                                            (\repoForType ->
                                                                repoForType
                                                                    |> Repo.insertType moduleName typeName typeDef
                                                                    |> Result.mapError (RepoError >> List.singleton)
                                                            )
                                                )
                                                repoResultForModule
                                    )
                        )
                        (Ok repo)
            )


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
parseSource : ( FileChanges.Path, String ) -> Result Error ParsedModule
parseSource ( path, content ) =
    Elm.Parser.parse content
        |> Result.mapError (ParseError path)


orderElmModulesByDependency : Repo -> List ParsedModule -> Result Errors (List ( ModuleName, ParsedModule ))
orderElmModulesByDependency repo parsedModules =
    let
        parsedModuleByName : Dict ModuleName ParsedModule
        parsedModuleByName =
            parsedModules
                |> List.filterMap
                    (\parsedModule ->
                        ParsedModule.moduleName parsedModule
                            |> ElmModuleName.toIRModuleName repo.packageName
                            |> Maybe.map
                                (\moduleName ->
                                    ( moduleName
                                    , parsedModule
                                    )
                                )
                    )
                |> Dict.fromList

        moduleGraph : DAG ModuleName
        moduleGraph =
            DAG.empty

        foldFunction : ParsedModule -> Result Errors (DAG ModuleName) -> Result Errors (DAG ModuleName)
        foldFunction parsedModule graph =
            let
                validateIfModuleExistInPackage : ModuleName -> Bool
                validateIfModuleExistInPackage modName =
                    Path.isPrefixOf repo.packageName modName

                moduleDependencies : List ModuleName
                moduleDependencies =
                    ParsedModule.importedModules parsedModule
                        |> List.filterMap
                            (\modName ->
                                ElmModuleName.toIRModuleName repo.packageName modName
                            )

                insertEdge : ModuleName -> ModuleName -> Result Errors (DAG ModuleName) -> Result Errors (DAG ModuleName)
                insertEdge fromModuleName toModule dag =
                    dag
                        |> Result.andThen
                            (\graphValue ->
                                graphValue
                                    |> DAG.insertEdge fromModuleName toModule
                                    |> Result.mapError
                                        (\err ->
                                            case err of
                                                _ ->
                                                    [ CycleDetected fromModuleName toModule ]
                                        )
                            )

                elmModuleName =
                    ParsedModule.moduleName parsedModule
            in
            elmModuleName
                |> ElmModuleName.toIRModuleName repo.packageName
                |> Result.fromMaybe [ InvalidModuleName elmModuleName ]
                |> Result.andThen
                    (\fromModuleName ->
                        moduleDependencies
                            |> List.foldl (insertEdge fromModuleName) graph
                    )
    in
    parsedModules
        |> List.foldl foldFunction (Ok moduleGraph)
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
        withWellKnownOperators : ProcessContext -> ProcessContext
        withWellKnownOperators context =
            List.foldl Processing.addDependency context WellKnownOperators.wellKnownOperators

        initialContext : ProcessContext
        initialContext =
            Processing.init |> withWellKnownOperators

        extractTypeNamesFromFile : File -> List Name
        extractTypeNamesFromFile file =
            file.declarations
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
        |> Processing.process initialContext
        |> extractTypeNamesFromFile


extractTypes : ParsedModule -> List Name -> Result Errors (List ( Name, Type.Definition () ))
extractTypes parsedModule typeNames =
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
                                                            mapAnnotationToMorphirType arg
                                                                |> Result.map
                                                                    (\argType ->
                                                                        ( [ "arg", String.fromInt (index + 1) ]
                                                                        , argType
                                                                        )
                                                                    )
                                                        )
                                                    |> ResultList.keepAllErrors
                                                    |> Result.mapError List.concat
                                        in
                                        constructorArgsResult
                                            |> Result.map
                                                (\constructorArgs ->
                                                    ( constructorName, constructorArgs )
                                                )
                                    )
                                |> ResultList.keepAllErrors
                                |> Result.map Dict.fromList
                                |> Result.mapError List.concat
                    in
                    constructorsResult
                        |> Result.map
                            (\constructors ->
                                ( customType.name |> Node.value |> Name.fromString
                                , Type.customTypeDefinition typeParams (withAccessControl True constructors)
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
                        |> mapAnnotationToMorphirType
                        |> Result.map
                            (\tpe ->
                                ( typeAlias.name
                                    |> Node.value
                                    |> Name.fromString
                                , Type.TypeAliasDefinition typeParams tpe
                                )
                            )
                        |> Just

                _ ->
                    Nothing
    in
    typeNameToDefinition


mapAnnotationToMorphirType : Node TypeAnnotation -> Result Errors (Type ())
mapAnnotationToMorphirType (Node range typeAnnotation) =
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.Variable () (varName |> Name.fromString))

        Typed (Node _ ( moduleName, localName )) argNodes ->
            Result.map
                (Type.Reference ()
                    (fQName
                        []
                        (List.map Name.fromString moduleName)
                        (Name.fromString localName)
                    )
                )
                (argNodes
                    |> List.map mapAnnotationToMorphirType
                    |> ResultList.keepAllErrors
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.Unit ())

        Tupled typeAnnotationNodes ->
            typeAnnotationNodes
                |> List.map mapAnnotationToMorphirType
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Type.Tuple ())

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ argName, fieldTypeNode ) ->
                        mapAnnotationToMorphirType fieldTypeNode
                            |> Result.map (Type.Field (Name.fromString argName))
                    )
                |> ResultList.keepAllErrors
                |> Result.map (Type.Record ())
                |> Result.mapError List.concat

        GenericRecord (Node _ argName) (Node _ fieldNodes) ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ ags, fieldTypeNode ) ->
                        mapAnnotationToMorphirType fieldTypeNode
                            |> Result.map (Type.Field (Name.fromString ags))
                    )
                |> ResultList.keepAllErrors
                |> Result.map (Type.ExtensibleRecord () (Name.fromString argName))
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2
                (Type.Function ())
                (mapAnnotationToMorphirType argTypeNode)
                (mapAnnotationToMorphirType returnTypeNode)


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
