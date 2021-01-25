module Morphir.Frontend2Tests exposing (dependencyCycles, missingModules)

import Dict
import Expect
import Morphir.Elm.Frontend2 exposing (ParseAndOrderError(..), ParseResult(..), parseAndOrderModules)
import Test exposing (Test, describe, test)


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

                        _ ->
                            Expect.fail "Unexpected result"
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

                        _ ->
                            Expect.fail "Expected cycles"
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
