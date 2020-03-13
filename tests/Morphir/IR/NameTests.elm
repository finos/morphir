module Morphir.IR.NameTests exposing (..)

import Expect
import Morphir.IR.Name as Name
import Test exposing (..)
import Json.Encode exposing(encode)


fromStringTests : Test
fromStringTests =
    let
        assert inString outList =
            test ("From string " ++ inString) <|
                \_ ->
                    Name.fromString inString
                        |> Expect.equal (Name.fromList outList)
    in
    describe "fromString"
        [ assert "fooBar_baz 123" [ "foo", "bar", "baz", "123" ]
        , assert "valueInUSD" [ "value", "in", "u", "s", "d" ]
        , assert "ValueInUSD" [ "value", "in", "u", "s", "d" ]
        , assert "value_in_USD" [ "value", "in", "u", "s", "d" ]
        , assert "_-% " []
        ]


toTitleCaseTests : Test
toTitleCaseTests =
    let
        assert inList outString =
            test ("Title case " ++ outString) <|
                \_ ->
                    Name.fromList inList
                        |> Name.toTitleCase
                        |> Expect.equal outString
    in
    describe "toTitleCase"
        [ assert [ "foo", "bar", "baz", "123" ] "FooBarBaz123"
        , assert [ "value", "in", "u", "s", "d" ] "ValueInUSD"
        ]


toCamelCaseTests : Test
toCamelCaseTests =
    let
        assert inList outString =
            test ("Camel case " ++ outString) <|
                \_ ->
                    Name.fromList inList
                        |> Name.toCamelCase
                        |> Expect.equal outString
    in
    describe "toCamelCase"
        [ assert [ "foo", "bar", "baz", "123" ] "fooBarBaz123"
        , assert [ "value", "in", "u", "s", "d" ] "valueInUSD"
        ]


toSnakeCaseTests : Test
toSnakeCaseTests =
    let
        assert inList outString =
            test ("Snake case " ++ outString) <|
                \_ ->
                    Name.fromList inList
                        |> Name.toSnakeCase
                        |> Expect.equal outString
    in
    describe "toSnakeCase"
        [ assert [ "foo", "bar", "baz", "123" ] "foo_bar_baz_123"
        , assert [ "value", "in", "u", "s", "d" ] "value_in_USD"
        ]


toHumanWordsTests : Test
toHumanWordsTests =
    let
        assert inList outList =
            test ("Human words " ++ (outList |> String.join " ")) <|
                \_ ->
                    Name.fromList inList
                        |> Name.toHumanWords
                        |> Expect.equal outList
    in
    describe "toHumanWords"
        [ assert [ "foo", "bar", "baz", "123" ] [ "foo", "bar", "baz", "123" ]
        , assert [ "value", "in", "u", "s", "d" ] [ "value", "in", "USD" ]
        ]

encodeTests : Test
encodeTests =
    let
        assert inList expectedText =
            test ("encode " ++ (expectedText ++ " ")) <|
                \_ ->
                    Name.fromList inList
                        |> Name.encodeName
                        |> encode 0
                        |> Expect.equal expectedText
    in
    describe "encodeName"
        [ assert ["delta", "sigma", "theta"] """["delta","sigma","theta"]"""
        , assert ["sigma","gamma","ro"] """["sigma","gamma","ro"]"""
        ]