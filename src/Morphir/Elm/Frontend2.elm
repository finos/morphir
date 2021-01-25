module Morphir.Elm.Frontend2 exposing (ParseAndOrderError(..), ParseResult(..), parseAndOrderModules)

import Dict exposing (Dict)
import Elm.Parser
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Node as Node
import Graph exposing (Graph)
import Morphir.Compiler as Compiler
import Morphir.ListOfResults as ListOfResults
import Parser exposing (DeadEnd)
import Set exposing (Set)


type alias SourceFiles =
    Dict String String


type alias ModuleName =
    List String


type ParseResult
    = MissingModules (List ModuleName) (List ParsedModule)
    | OrderedModules (List ParsedModule)


type alias ParsedModule =
    RawFile


type ParseAndOrderError
    = ParseErrors (Dict String (List ParseError))
    | ModuleDependencyCycles (List (List ModuleName))


type alias ParseError =
    { problem : String
    , location : Compiler.SourceLocation
    }


parseAndOrderModules : SourceFiles -> (ModuleName -> Bool) -> List ParsedModule -> Result ParseAndOrderError ParseResult
parseAndOrderModules sourceFiles isExternalModule parsedModulesSoFar =
    let
        parseSources : SourceFiles -> Result ParseAndOrderError (List RawFile)
        parseSources sources =
            sources
                |> Dict.toList
                |> List.map
                    (\( filePath, source ) ->
                        Elm.Parser.parse source
                            |> Result.mapError
                                (\deadEnds ->
                                    ( filePath, deadEnds |> List.map parserDeadEndToParseError )
                                )
                    )
                |> ListOfResults.liftAllErrors
                |> Result.mapError (Dict.fromList >> ParseErrors)

        importedModuleNames : List RawFile -> Set ModuleName
        importedModuleNames rawFiles =
            rawFiles
                |> List.concatMap
                    (\rawFile ->
                        rawFile
                            |> RawFile.imports
                            |> List.map (.moduleName >> Node.value)
                    )
                |> List.filter (isExternalModule >> not)
                |> Set.fromList

        parsedModuleNames : List RawFile -> Set ModuleName
        parsedModuleNames rawFiles =
            rawFiles
                ++ parsedModulesSoFar
                |> List.map RawFile.moduleName
                |> Set.fromList

        parsedFilesToGraph : List RawFile -> Graph ModuleName ()
        parsedFilesToGraph rawFiles =
            let
                moduleNameToIndex : Dict ModuleName Int
                moduleNameToIndex =
                    rawFiles
                        |> List.indexedMap
                            (\index rawFile ->
                                ( RawFile.moduleName rawFile, index )
                            )
                        |> Dict.fromList
            in
            Graph.fromNodeLabelsAndEdgePairs (rawFiles |> List.map RawFile.moduleName)
                (rawFiles
                    |> List.indexedMap
                        (\index rawFile ->
                            rawFile
                                |> RawFile.imports
                                |> List.map (.moduleName >> Node.value)
                                |> List.filterMap
                                    (\importedModule ->
                                        Dict.get importedModule moduleNameToIndex
                                    )
                                |> List.map (Tuple.pair index)
                        )
                    |> List.concat
                )

        orderRawFiles : List RawFile -> Result ParseAndOrderError ParseResult
        orderRawFiles rawFiles =
            let
                parsedModulesByName : Dict ModuleName ParsedModule
                parsedModulesByName =
                    rawFiles
                        |> List.map (\file -> ( RawFile.moduleName file, file ))
                        |> Dict.fromList

                missingModuleNames : Set ModuleName
                missingModuleNames =
                    Set.diff (importedModuleNames rawFiles) (parsedModuleNames rawFiles)
            in
            if Set.isEmpty missingModuleNames then
                parsedFilesToGraph (rawFiles ++ parsedModulesSoFar)
                    |> Graph.stronglyConnectedComponents
                    |> Result.map
                        (\acyclicGraph ->
                            acyclicGraph
                                |> Graph.topologicalSort
                                |> List.filterMap
                                    (\nodeContext ->
                                        parsedModulesByName
                                            |> Dict.get nodeContext.node.label
                                    )
                                |> OrderedModules
                        )
                    |> Result.mapError
                        (\components ->
                            ModuleDependencyCycles
                                (components
                                    |> List.filterMap
                                        (\component ->
                                            case Graph.checkAcyclic component of
                                                Err _ ->
                                                    Just component

                                                Ok _ ->
                                                    Nothing
                                        )
                                    |> List.map
                                        (\cyclicGraph ->
                                            cyclicGraph
                                                |> Graph.nodes
                                                |> List.map .label
                                        )
                                )
                        )

            else
                Ok (MissingModules (Set.toList missingModuleNames) (parsedModulesSoFar ++ rawFiles))
    in
    parseSources sourceFiles
        |> Result.andThen orderRawFiles


parserDeadEndToParseError : Parser.DeadEnd -> ParseError
parserDeadEndToParseError deadEnd =
    let
        mapParserProblem : Parser.Problem -> String
        mapParserProblem problem =
            case problem of
                Parser.Expecting something ->
                    "Expecting " ++ something

                Parser.ExpectingInt ->
                    "Expecting integer"

                Parser.ExpectingHex ->
                    "Expecting hexadecimal"

                Parser.ExpectingOctal ->
                    "Expecting octal"

                Parser.ExpectingBinary ->
                    "Expecting binary"

                Parser.ExpectingFloat ->
                    "Expecting float"

                Parser.ExpectingNumber ->
                    "Expecting number"

                Parser.ExpectingVariable ->
                    "Expecting variable"

                Parser.ExpectingSymbol symbol ->
                    "Expecting symbol: " ++ symbol

                Parser.ExpectingKeyword keyword ->
                    "Expecting keyword: " ++ keyword

                Parser.ExpectingEnd ->
                    "Expecting end"

                Parser.UnexpectedChar ->
                    "Unexpected character"

                Parser.Problem message ->
                    "Problem: " ++ message

                Parser.BadRepeat ->
                    "Bad repeat"
    in
    { problem = mapParserProblem deadEnd.problem
    , location =
        { row = deadEnd.row
        , column = deadEnd.col
        }
    }
