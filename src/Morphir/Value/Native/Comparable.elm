module Morphir.Value.Native.Comparable exposing (..)

import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue)
import Morphir.Value.Error exposing (Error(..))
import Morphir.SDK.UUID as UUID exposing (UUID)


lessThan : RawValue -> RawValue -> Result Error Bool
lessThan arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    LT ->
                        True

                    _ ->
                        False
            )


lessThanOrEqual : RawValue -> RawValue -> Result Error Bool
lessThanOrEqual arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    GT ->
                        False

                    _ ->
                        True
            )


greaterThan : RawValue -> RawValue -> Result Error Bool
greaterThan arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    GT ->
                        True

                    _ ->
                        False
            )


greaterThanOrEqual : RawValue -> RawValue -> Result Error Bool
greaterThanOrEqual arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    LT ->
                        False

                    _ ->
                        True
            )


max : RawValue -> RawValue -> Result Error RawValue
max arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    LT ->
                        arg2

                    _ ->
                        arg1
            )


min : RawValue -> RawValue -> Result Error RawValue
min arg1 arg2 =
    compareValue arg1 arg2
        |> Result.map
            (\order ->
                case order of
                    GT ->
                        arg2

                    _ ->
                        arg1
            )


compareValue : RawValue -> RawValue -> Result Error Order
compareValue arg1 arg2 =
    case ( arg1, arg2 ) of
        ( Value.Literal () (WholeNumberLiteral val1), Value.Literal () (WholeNumberLiteral val2) ) ->
            compare val1 val2 |> Ok

        ( Value.Literal () (FloatLiteral val1), Value.Literal () (FloatLiteral val2) ) ->
            compare val1 val2 |> Ok

        ( Value.Literal () (CharLiteral val1), Value.Literal () (CharLiteral val2) ) ->
            compare val1 val2 |> Ok

        ( Value.Literal () (StringLiteral val1), Value.Literal () (StringLiteral val2) ) ->
            compare val1 val2 |> Ok

        ( Value.List () list1, Value.List () list2 ) ->
            let
                fun : List RawValue -> List RawValue -> Result Error Order
                fun listA listB =
                    case ( listA, listB ) of
                        ( [], [] ) ->
                            Ok EQ

                        ( [], _ ) ->
                            Ok LT

                        ( _, [] ) ->
                            Ok GT

                        ( head1 :: tail1, head2 :: tail2 ) ->
                            case compareValue head1 head2 of
                                Ok EQ ->
                                    fun tail1 tail2

                                other ->
                                    other
            in
            fun list1 list2

        ( Value.Tuple () tupleList1, Value.Tuple () tupleList2 ) ->
            let
                fun : List RawValue -> List RawValue -> Result Error Order
                fun listA listB =
                    case ( listA, listB ) of
                        ( [], [] ) ->
                            Ok EQ

                        ( [], _ ) ->
                            Err (TupleLengthNotMatchException tupleList1 tupleList2)

                        ( _, [] ) ->
                            Err (TupleLengthNotMatchException tupleList1 tupleList2)

                        ( head1 :: tail1, head2 :: tail2 ) ->
                            case compareValue head1 head2 of
                                Ok EQ ->
                                    fun tail1 tail2

                                other ->
                                    other
            in
            fun tupleList1 tupleList2

        ( a, b ) ->
            Err (UnexpectedArguments [ a, b ])
