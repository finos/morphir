module Morphir.Value.Native.Comparable exposing (..)

import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native.Eq as Eq


lessThan : RawValue -> RawValue -> Result Error Bool
lessThan a b =
    let
        pairwiseLess : List ( RawValue, RawValue ) -> Bool
        pairwiseLess list =
            case list of
                [] ->
                    False

                ( aValue, bValue ) :: rest ->
                    case lessThan aValue bValue of
                        Ok True ->
                            True

                        Ok False ->
                            case lessThan bValue aValue of
                                Ok True ->
                                    False

                                Ok False ->
                                    pairwiseLess rest

                                Err _ ->
                                    False

                        Err _ ->
                            False
    in
    case ( a, b ) of
        ( Value.Literal _ (IntLiteral aInt), Value.Literal _ (IntLiteral bInt) ) ->
            Ok (aInt < bInt)

        ( Value.Literal _ (FloatLiteral aFloat), Value.Literal _ (FloatLiteral bFloat) ) ->
            Ok (aFloat < bFloat)

        ( Value.Literal _ (CharLiteral aChar), Value.Literal _ (CharLiteral bChar) ) ->
            Ok (aChar < bChar)

        ( Value.Literal _ (StringLiteral aString), Value.Literal _ (StringLiteral bString) ) ->
            Ok (aString < bString)

        ( Value.List _ aItems, Value.List _ bItems ) ->
            if List.length aItems == List.length bItems then
                List.map2 Tuple.pair aItems bItems
                    |> pairwiseLess
                    |> Ok

            else
                Ok False

        ( Value.Tuple _ aElems, Value.Tuple _ bElems ) ->
            if List.length aElems == List.length bElems then
                List.map2 Tuple.pair aElems bElems
                    |> pairwiseLess
                    |> Ok

            else
                Err (UnexpectedArguments [ a, b ])

        _ ->
            Err (UnexpectedArguments [ a, b ])


lessThanOrEqual : RawValue -> RawValue -> Result Error Bool
lessThanOrEqual a b =
    Result.map2 (||) (lessThan a b) (Eq.equal a b)


greaterThan : RawValue -> RawValue -> Result Error Bool
greaterThan a b =
    Result.map not (lessThanOrEqual a b)


greaterThanOrEqual : RawValue -> RawValue -> Result Error Bool
greaterThanOrEqual a b =
    Result.map not (lessThan a b)


max : RawValue -> RawValue -> Result Error RawValue
max a b =
    lessThan a b
        |> Result.map
            (\aIsLess ->
                if aIsLess then
                    b

                else
                    a
            )


min : RawValue -> RawValue -> Result Error RawValue
min a b =
    lessThan a b
        |> Result.map
            (\aIsLess ->
                if aIsLess then
                    a

                else
                    b
            )


compare : RawValue -> RawValue -> Result Error Order
compare a b =
    lessThan a b
        |> Result.andThen
            (\aIsLess ->
                if aIsLess then
                    Ok LT

                else
                    Eq.equal a b
                        |> Result.map
                            (\isEqual ->
                                if isEqual then
                                    EQ

                                else
                                    GT
                            )
            )
