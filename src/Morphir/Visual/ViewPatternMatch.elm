module Morphir.Visual.ViewPatternMatch exposing (..)

import Element exposing (Attribute, Column, Element, fill, row, spacing, table, text, width)
import List exposing (concat)
import Morphir.IR.Literal as Value
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, TypedValue, Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.DecisionTable as DecisionTable exposing (DecisionTable)


view : Config msg -> (Value ta ( Int, Type ta ) -> Element msg) -> Value va ( int, Type ta ) -> List ( Pattern pa, Value va ( int, Type ta ) ) -> Element msg
view config viewValue param patterns =
    table [ spacing 10 ]
        { data = examples
        , columns = generateColumns param patterns
        }



--table [ spacing 10 ]
--    { data = examples
--    , columns =
--        [ { header = text "a"
--          , width = fill
--          , view = \example -> text example.a
--          }
--        , { header = text "b", width = fill, view = \example -> text example.b }
--        , { header = text "c", width = fill, view = \example -> text example.c }
--        , { header = text "d", width = fill, view = \example -> text example.d }
--        , { header = text "e", width = fill, view = \example -> text example.e }
--        , { header = text "Result", width = fill, view = \example -> text example.result }
--        ]
--    }
--decisionTable : DecisionTable
--decisionTable =
--    { decomposeInput = getHeaders param
--    , rules = []
--    }
--
--
--getHeaders : Value ta va -> List TypedValue
--getHeaders =
--    []


type alias Example =
    { a : String
    , b : String
    , c : String
    , d : String
    , e : String
    , result : String
    }


examples : List Example
examples =
    [ { a = "foo", b = "bar", c = "any", d = "any", e = "any", result = "1" }
    , { a = "any", b = "any", c = "bar", d = "any", e = "any", result = "2" }
    , { a = "any", b = "any", c = "any", d = "any", e = "any", result = "3" }
    ]



--flattenTree : Value ta va -> List ( Pattern pa, Value ta va ) -> List (Column record msg)
--flattenTree param patterns =
--    patterns |> List.concatMap (extractNestedPattern param)
--
--
--extractNestedPattern : Value ta va -> ( Pattern pa, Value ta va ) -> List (Column record msg)
--extractNestedPattern param pattern =
--    case pattern of
--        ( _, Value.PatternMatch pa nestedParam nestedPattern ) ->
--            flattenTree nestedParam nestedPattern
--
--        _ ->
--            generateColumn pattern param


generateColumn : List ( Pattern pa, Value ta va ) -> Value ta va -> List (Column record msg)
generateColumn patterns param =
    case param of
        Value.Variable ta name ->
            [ Column (text (nameToText name)) fill (\_ -> text "foo") ]

        Value.Tuple va elems ->
            elems |> List.concatMap (generateColumn patterns)

        _ ->
            []


generateColumns : Value ta va -> List ( Pattern pa, Value ta va ) -> List (Column record msg)
generateColumns param patterns =
    concat [ generateColumn patterns param, [ Column (text "Result") fill (\_ -> text "foo") ] ]



--case param of
--    Value.Variable ta name ->
--        [ Column (text (nameToText name)) fill (\example -> text "foo") ]
--
--    Value.Tuple va elems ->
--        elems |> List.concatMap (generateColumns patterns)
--
--    _ ->
--        []
