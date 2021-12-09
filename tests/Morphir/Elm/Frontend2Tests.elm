module Morphir.Elm.Frontend2Tests exposing (dependencyCycles, missingModules, overwriteTests, positiveTests)

import Dict
import Expect
import Morphir.Elm.Frontend2 exposing (ParseAndOrderError(..), ParseResult(..), parseAndOrderModules)
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Test exposing (Test, describe, test)


positiveTests : Test
positiveTests =
    let
        assert msg sources expectedOrderedModules =
            test msg
                (\_ ->
                    case parseAndOrderModules (Dict.fromList sources) (always False) [] of
                        Ok (OrderedModules actualOrderedModules) ->
                            Expect.equal
                                expectedOrderedModules
                                (actualOrderedModules |> List.map ParsedModule.moduleName)

                        result ->
                            Expect.fail ("Unexpected result: " ++ Debug.toString result)
                )
    in
    describe "Positive tests"
        [ assert "Parse no sources"
            []
            []
        , assert "Parse one source"
            [ ( "Foo.elm", "module Foo exposing (..)" )
            ]
            [ [ "Foo" ] ]
        , assert "Parse two source"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar" )
            , ( "Bar.elm", "module Bar exposing (..)" )
            ]
            [ [ "Bar" ], [ "Foo" ] ]
        , assert "Parse three source"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar" )
            , ( "Baz.elm", "module Baz exposing (..)" )
            , ( "Bar.elm", "module Bar exposing (..)\n\nimport Baz" )
            ]
            [ [ "Baz" ], [ "Bar" ], [ "Foo" ] ]
        ]


overwriteTests : Test
overwriteTests =
    let
        assert msg previouslyParsedModules sources expectedOrderedModules =
            test msg
                (\_ ->
                    case parseAndOrderModules (Dict.fromList sources) (always False) previouslyParsedModules of
                        Ok (OrderedModules actualOrderedModules) ->
                            Expect.equal
                                expectedOrderedModules
                                (actualOrderedModules |> List.map ParsedModule.moduleName)

                        result ->
                            Expect.fail ("Unexpected result: " ++ Debug.toString result)
                )

        parseSources : List ( String, String ) -> List ParsedModule
        parseSources sources =
            case parseAndOrderModules (Dict.fromList sources) (always False) [] of
                Ok (OrderedModules modules) ->
                    modules

                _ ->
                    []
    in
    describe "Overwrite tests"
        [ assert "Flip module dependency by overwriting sources"
            (parseSources
                [ ( "Foo.elm", "module Foo exposing (..)" )
                , ( "Bar.elm", "module Bar exposing (..)\n\nimport Foo" )
                ]
            )
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar" )
            , ( "Bar.elm", "module Bar exposing (..)" )
            ]
            [ [ "Bar" ], [ "Foo" ] ]
        ]


missingModules : Test
missingModules =
    let
        assert msg sources expectedMissingModules =
            test msg
                (\_ ->
                    case parseAndOrderModules (Dict.fromList sources) (always False) [] of
                        Ok (MissingModules actualMissingModules _) ->
                            Expect.equal
                                (expectedMissingModules |> List.sort)
                                (actualMissingModules |> List.sort)

                        result ->
                            Expect.fail ("Unexpected result: " ++ Debug.toString result)
                )
    in
    describe "Missing modules"
        [ assert "Single missing module"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar\nimport Baz" )
            , ( "Baz.elm", "module Baz exposing (..)" )
            ]
            [ [ "Bar" ] ]
        , assert "Two missing modules"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar\nimport Baz" )
            , ( "Baz.elm", "module Baz exposing (..)\n\nimport Foo\nimport Bat" )
            ]
            [ [ "Bar" ], [ "Bat" ] ]
        ]


dependencyCycles : Test
dependencyCycles =
    let
        assert msg sources expectedCycles =
            test msg
                (\_ ->
                    case parseAndOrderModules (Dict.fromList sources) (always False) [] of
                        Err (ModuleDependencyCycles actualCycles) ->
                            Expect.equal
                                (expectedCycles
                                    |> List.map List.sort
                                    |> List.sort
                                )
                                (actualCycles
                                    |> List.map List.sort
                                    |> List.sort
                                )

                        result ->
                            Expect.fail ("Unexpected result: " ++ Debug.toString result)
                )
    in
    describe "Dependency cycles"
        [ assert "Detect single cycle"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar" )
            , ( "Bar.elm", "module Bar exposing (..)\n\nimport Foo" )
            ]
            [ [ [ "Foo" ], [ "Bar" ] ] ]
        , assert "Detect two cycles"
            [ ( "Foo.elm", "module Foo exposing (..)\n\nimport Bar" )
            , ( "Bar.elm", "module Bar exposing (..)\n\nimport Foo" )
            , ( "Baz.elm", "module Baz exposing (..)\n\nimport Bat" )
            , ( "Bat.elm", "module Bat exposing (..)\n\nimport Baz" )
            ]
            [ [ [ "Foo" ], [ "Bar" ] ], [ [ "Bat" ], [ "Baz" ] ] ]
        ]
