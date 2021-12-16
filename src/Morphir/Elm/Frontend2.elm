module Morphir.Elm.Frontend2 exposing (ParseAndOrderError(..), ParseError, ParseResult(..), SourceFiles, parseAndOrderModules)

import Dict exposing (Dict)
import Elm.Parser
import Graph exposing (Graph)
import Morphir.Compiler as Compiler
import Morphir.Elm.ModuleName exposing (ModuleName)
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.ListOfResults as ListOfResults
import Parser exposing (DeadEnd)
import Set exposing (Set)


type alias SourceFiles =
    Dict String String


type ParseResult
    = MissingModules (List ModuleName) (List ParsedModule)
    | OrderedModules (List ParsedModule)


type ParseAndOrderError
    = ParseErrors (Dict String (List ParseError))
    | ModuleDependencyCycles (List (List ModuleName))


type alias ParseError =
    { problem : String
    , location : Compiler.SourceLocation
    }


parseAndOrderModules : SourceFiles -> (ModuleName -> Bool) -> List ParsedModule -> Result ParseAndOrderError ParseResult
parseAndOrderModules sourceFiles isExternalModule previouslyParsedModules =
    let
        parseSources : SourceFiles -> Result ParseAndOrderError (List ParsedModule)
        parseSources sources =
            sources
                |> Dict.toList
                |> List.map
                    (\( filePath, source ) ->
                        Elm.Parser.parse source
                            |> Result.mapError
                                (\deadEnds ->
                                    ( filePath, deadEnds |> parserDeadEndToParseError )
                                )
                    )
                |> ListOfResults.liftAllErrors
                |> Result.mapError (Dict.fromList >> ParseErrors)

        mergeParsedModules : List ParsedModule -> List ParsedModule -> List ParsedModule
        mergeParsedModules modules1 modules2 =
            let
                toDict modules =
                    modules
                        |> List.map
                            (\parsedModule ->
                                ( parsedModule |> ParsedModule.moduleName
                                , parsedModule
                                )
                            )
                        |> Dict.fromList
            in
            Dict.union (toDict modules2) (toDict modules1)
                |> Dict.toList
                |> List.map Tuple.second

        importedModuleNames : List ParsedModule -> Set ModuleName
        importedModuleNames parsedModules =
            parsedModules
                |> List.concatMap ParsedModule.importedModules
                |> List.filter (isExternalModule >> not)
                |> Set.fromList

        parsedModuleNames : List ParsedModule -> Set ModuleName
        parsedModuleNames parsedModules =
            parsedModules
                ++ previouslyParsedModules
                |> List.map ParsedModule.moduleName
                |> Set.fromList

        parsedModulesToGraph : List ParsedModule -> Graph ModuleName ()
        parsedModulesToGraph parsedModules =
            let
                moduleNameToIndex : Dict ModuleName Int
                moduleNameToIndex =
                    parsedModules
                        |> List.indexedMap
                            (\index rawFile ->
                                ( ParsedModule.moduleName rawFile, index )
                            )
                        |> Dict.fromList
            in
            Graph.fromNodeLabelsAndEdgePairs (parsedModules |> List.map ParsedModule.moduleName)
                (parsedModules
                    |> List.indexedMap
                        (\index parsedModule ->
                            parsedModule
                                |> ParsedModule.importedModules
                                |> List.filterMap
                                    (\importedModule ->
                                        Dict.get importedModule moduleNameToIndex
                                    )
                                |> List.map (Tuple.pair index)
                        )
                    |> List.concat
                )

        orderParsedModules : List ParsedModule -> Result ParseAndOrderError ParseResult
        orderParsedModules parsedModules =
            let
                parsedModulesByName : Dict ModuleName ParsedModule
                parsedModulesByName =
                    parsedModules
                        |> List.map (\parsedModule -> ( ParsedModule.moduleName parsedModule, parsedModule ))
                        |> Dict.fromList

                missingModuleNames : Set ModuleName
                missingModuleNames =
                    Set.diff (importedModuleNames parsedModules) (parsedModuleNames parsedModules)
            in
            if Set.isEmpty missingModuleNames then
                parsedModulesToGraph parsedModules
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
                                |> List.reverse
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
                Ok (MissingModules (Set.toList missingModuleNames) (previouslyParsedModules ++ parsedModules))
    in
    parseSources sourceFiles
        |> Result.map (mergeParsedModules previouslyParsedModules)
        |> Result.andThen orderParsedModules


parserDeadEndToParseError : List Parser.DeadEnd -> List ParseError
parserDeadEndToParseError deadEnds =
    let
        mapParserProblem : Parser.Problem -> String
        mapParserProblem problem =
            case problem of
                Parser.Expecting something ->
                    "Expecting '" ++ something ++ "'"

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

        groupDeadEnds : List Parser.DeadEnd -> Dict ( Int, Int ) (List Parser.Problem)
        groupDeadEnds des =
            des
                |> List.foldl
                    (\deadEnd dict ->
                        dict
                            |> Dict.update ( deadEnd.row, deadEnd.col )
                                (\maybeProblemsSoFar ->
                                    case maybeProblemsSoFar of
                                        Just problemsSoFar ->
                                            Just (deadEnd.problem :: problemsSoFar)

                                        Nothing ->
                                            Just [ deadEnd.problem ]
                                )
                    )
                    Dict.empty
    in
    deadEnds
        |> groupDeadEnds
        |> Dict.toList
        |> List.map
            (\( ( row, col ), problems ) ->
                { problem =
                    problems
                        |> List.map mapParserProblem
                        |> String.join " OR "
                , location =
                    { row = row
                    , column = col
                    }
                }
            )
