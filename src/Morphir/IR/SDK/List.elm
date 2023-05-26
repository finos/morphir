{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.SDK.List exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType, orderType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (just, maybeType, nothing)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.SDK.ResultList as ResultList
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native exposing (Eval, decodeFun1, decodeList, decodeLiteral, decodeRaw, decodeTuple2, encodeList, encodeLiteral, encodeMaybe, encodeRaw, encodeResultList, encodeTuple2, eval1, eval2, floatLiteral, intLiteral, oneOf)
import Morphir.Value.Native.Comparable exposing (compareValue)


moduleName : ModuleName
moduleName =
    Path.fromString "List"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "List", OpaqueTypeSpecification [ [ "a" ] ] |> Documented "Type that represents a list of values." )
            ]
    , values =
        Dict.fromList
            [ vSpec "singleton" [ ( "a", tVar "a" ) ] (listType () (tVar "a"))
            , vSpec "repeat" [ ( "n", intType () ), ( "a", tVar "a" ) ] (listType () (tVar "a"))
            , vSpec "range" [ ( "from", intType () ), ( "to", intType () ) ] (listType () (intType ()))
            , vSpec "cons" [ ( "head", tVar "a" ), ( "tail", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "map" [ ( "f", tFun [ tVar "a" ] (tVar "b") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "indexedMap" [ ( "f", tFun [ intType (), tVar "a" ] (tVar "b") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "foldl" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "list", listType () (tVar "a") ) ] (tVar "b")
            , vSpec "foldr" [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "b") ), ( "z", tVar "b" ), ( "list", listType () (tVar "a") ) ] (tVar "b")
            , vSpec "filter" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "filterMap" [ ( "f", tFun [ tVar "a" ] (maybeType () (tVar "b")) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "length" [ ( "list", listType () (tVar "a") ) ] (intType ())
            , vSpec "reverse" [ ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "member" [ ( "ref", tVar "a" ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "all" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "any" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "maximum" [ ( "list", listType () (tVar "comparable") ) ] (maybeType () (tVar "comparable"))
            , vSpec "minimum" [ ( "list", listType () (tVar "comparable") ) ] (maybeType () (tVar "comparable"))
            , vSpec "sum" [ ( "list", listType () (tVar "number") ) ] (tVar "number")
            , vSpec "product" [ ( "list", listType () (tVar "number") ) ] (tVar "number")
            , vSpec "append" [ ( "l1", listType () (tVar "a") ), ( "l2", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "concat" [ ( "lists", listType () (listType () (tVar "a")) ) ] (listType () (tVar "a"))
            , vSpec "concatMap" [ ( "f", tFun [ tVar "a" ] (listType () (tVar "b")) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "b"))
            , vSpec "intersperse" [ ( "a", tVar "a" ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "map2"
                [ ( "f", tFun [ tVar "a", tVar "b" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                ]
                (listType () (tVar "r"))
            , vSpec "map3"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                ]
                (listType () (tVar "r"))
            , vSpec "map4"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                , ( "list4", listType () (tVar "d") )
                ]
                (listType () (tVar "r"))
            , vSpec "map5"
                [ ( "f", tFun [ tVar "a", tVar "b", tVar "c", tVar "d", tVar "e" ] (tVar "r") )
                , ( "list1", listType () (tVar "a") )
                , ( "list2", listType () (tVar "b") )
                , ( "list3", listType () (tVar "c") )
                , ( "list4", listType () (tVar "d") )
                , ( "list5", listType () (tVar "e") )
                ]
                (listType () (tVar "r"))
            , vSpec "sort" [ ( "list", listType () (tVar "comparable") ) ] (listType () (tVar "comparable"))
            , vSpec "sortBy" [ ( "f", tFun [ tVar "a" ] (tVar "comparable") ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "sortWith" [ ( "f", tFun [ tVar "a", tVar "a" ] (orderType ()) ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "isEmpty" [ ( "list", listType () (tVar "a") ) ] (boolType ())
            , vSpec "head" [ ( "list", listType () (tVar "a") ) ] (maybeType () (tVar "a"))
            , vSpec "tail" [ ( "list", listType () (tVar "a") ) ] (maybeType () (listType () (tVar "a")))
            , vSpec "take" [ ( "n", intType () ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "drop" [ ( "n", intType () ), ( "list", listType () (tVar "a") ) ] (listType () (tVar "a"))
            , vSpec "partition" [ ( "f", tFun [ tVar "a" ] (boolType ()) ), ( "list", listType () (tVar "a") ) ] (Type.Tuple () [ listType () (tVar "a"), listType () (tVar "a") ])
            , vSpec "unzip" [ ( "list", listType () (Type.Tuple () [ tVar "a", tVar "b" ]) ) ] (Type.Tuple () [ listType () (tVar "a"), listType () (tVar "b") ])
            , vSpec "innerJoin"
                [ ( "listB", listType () (tVar "b") )
                , ( "f", tFun [ tVar "a", tVar "b" ] (boolType ()) )
                , ( "listA", listType () (tVar "a") )
                ]
                (listType () (Type.Tuple () [ tVar "a", tVar "b" ]))
            , vSpec "leftJoin"
                [ ( "listB", listType () (tVar "b") )
                , ( "f", tFun [ tVar "a", tVar "b" ] (boolType ()) )
                , ( "listA", listType () (tVar "a") )
                ]
                (listType () (Type.Tuple () [ tVar "a", maybeType () (tVar "b") ]))
            ]
    , doc = Just "Contains the List type (representing a list of values), and it's associated functions."
    }


listType : a -> Type a -> Type a
listType attributes itemType =
    Type.Reference attributes (toFQName moduleName "List") [ itemType ]


construct : a -> Value ta a
construct a =
    Value.Reference a (toFQName moduleName "cons")


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "singleton", eval1 List.singleton decodeRaw (encodeList encodeRaw) )
    , ( "repeat", eval2 List.repeat (decodeLiteral intLiteral) decodeRaw (encodeList encodeRaw) )
    , ( "cons", eval2 (::) decodeRaw (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "map", eval2 List.map (decodeFun1 encodeRaw decodeRaw) (decodeList decodeRaw) encodeResultList )
    , ( "filter"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> List RawValue -> Result Error (List RawValue)
                                            evaluate list items =
                                                case items of
                                                    [] ->
                                                        Ok list

                                                    head :: tail ->
                                                        case eval (Value.Apply () fun head) of
                                                            Ok (Value.Literal _ (BoolLiteral True)) ->
                                                                evaluate (list ++ [ head ]) tail

                                                            Ok (Value.Literal _ (BoolLiteral False)) ->
                                                                evaluate list tail

                                                            Ok other ->
                                                                Err (ExpectedBoolLiteral other)

                                                            Err other ->
                                                                Err other
                                        in
                                        listItems |> evaluate [] |> Result.map (Value.List ())

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "filterMap"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> List RawValue -> Result Error (List RawValue)
                                            evaluate list items =
                                                case items of
                                                    [] ->
                                                        Ok list

                                                    head :: tail ->
                                                        case eval (Value.Apply () fun head) of
                                                            Ok (Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value) ->
                                                                evaluate (list ++ [ value ]) tail

                                                            Ok (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] )) ->
                                                                evaluate list tail

                                                            Ok other ->
                                                                Err (ExpectedBoolLiteral other)

                                                            Err other ->
                                                                Err other
                                        in
                                        listItems |> evaluate [] |> Result.map (Value.List ())

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )

    {- indexedMap -}
    , ( "foldl"
      , \eval args ->
            case args of
                [ fun, arg1, arg2 ] ->
                    eval arg2
                        |> Result.andThen
                            (\evaluatedArg2 ->
                                case evaluatedArg2 of
                                    Value.List () listItems ->
                                        listItems
                                            |> List.foldl
                                                (\next resultSoFar ->
                                                    resultSoFar
                                                        |> Result.andThen
                                                            (\soFar ->
                                                                eval next
                                                                    |> Result.andThen
                                                                        (\evaluatedNext ->
                                                                            eval (Value.Apply () (Value.Apply () fun evaluatedNext) soFar)
                                                                        )
                                                            )
                                                )
                                                (eval arg1)

                                    _ ->
                                        Err (ExpectedList evaluatedArg2)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "foldr"
      , \eval args ->
            case args of
                [ fun, arg1, arg2 ] ->
                    eval arg2
                        |> Result.andThen
                            (\evaluatedArg2 ->
                                case evaluatedArg2 of
                                    Value.List () listItems ->
                                        listItems
                                            |> List.foldr
                                                (\next resultSoFar ->
                                                    resultSoFar
                                                        |> Result.andThen
                                                            (\soFar ->
                                                                eval next
                                                                    |> Result.andThen
                                                                        (\evaluatedNext ->
                                                                            eval (Value.Apply () (Value.Apply () fun evaluatedNext) soFar)
                                                                        )
                                                            )
                                                )
                                                (eval arg1)

                                    _ ->
                                        Err (ExpectedList evaluatedArg2)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "length", eval1 List.length (decodeList decodeRaw) (encodeLiteral WholeNumberLiteral) )
    , ( "reverse", eval1 List.reverse (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "member", eval2 List.member decodeRaw (decodeList decodeRaw) (encodeLiteral BoolLiteral) )
    , ( "all"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> Result Error Bool
                                            evaluate items =
                                                case items of
                                                    [] ->
                                                        Ok True

                                                    head1 :: tail1 ->
                                                        case eval (Value.Apply () fun head1) of
                                                            Ok (Value.Literal _ (BoolLiteral True)) ->
                                                                evaluate tail1

                                                            Ok (Value.Literal _ (BoolLiteral False)) ->
                                                                Ok False

                                                            Ok other ->
                                                                Err (ExpectedBoolLiteral other)

                                                            Err other ->
                                                                Err other
                                        in
                                        evaluate listItems |> Result.map (\val -> Value.Literal () (BoolLiteral val))

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "any"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> Result Error Bool
                                            evaluate items =
                                                case items of
                                                    [] ->
                                                        Ok False

                                                    head1 :: tail1 ->
                                                        case eval (Value.Apply () fun head1) of
                                                            Ok (Value.Literal _ (BoolLiteral False)) ->
                                                                evaluate tail1

                                                            Ok (Value.Literal _ (BoolLiteral True)) ->
                                                                Ok True

                                                            Ok other ->
                                                                Err (ExpectedBoolLiteral other)

                                                            Err other ->
                                                                Err other
                                        in
                                        evaluate listItems |> Result.map (\val -> Value.Literal () (BoolLiteral val))

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "maximum"
      , \eval args ->
            case args of
                [ arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> Result Error RawValue
                                            evaluate items =
                                                case items of
                                                    [] ->
                                                        Ok (nothing ())

                                                    head :: tail ->
                                                        tail
                                                            |> List.foldl
                                                                (\next resultSoFar ->
                                                                    resultSoFar
                                                                        |> Result.andThen
                                                                            (\soFar ->
                                                                                eval next
                                                                                    |> Result.andThen
                                                                                        (\evaluatedNext ->
                                                                                            compareValue evaluatedNext soFar
                                                                                                |> Result.map
                                                                                                    (\order ->
                                                                                                        case order of
                                                                                                            LT ->
                                                                                                                soFar

                                                                                                            _ ->
                                                                                                                evaluatedNext
                                                                                                    )
                                                                                        )
                                                                            )
                                                                )
                                                                (eval head)
                                                            |> Result.map (just ())
                                        in
                                        listItems |> evaluate

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "minimum"
      , \eval args ->
            case args of
                [ arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> Result Error RawValue
                                            evaluate items =
                                                case items of
                                                    [] ->
                                                        Ok (nothing ())

                                                    head :: tail ->
                                                        tail
                                                            |> List.foldl
                                                                (\next resultSoFar ->
                                                                    resultSoFar
                                                                        |> Result.andThen
                                                                            (\soFar ->
                                                                                eval next
                                                                                    |> Result.andThen
                                                                                        (\evaluatedNext ->
                                                                                            compareValue evaluatedNext soFar
                                                                                                |> Result.map
                                                                                                    (\order ->
                                                                                                        case order of
                                                                                                            LT ->
                                                                                                                evaluatedNext

                                                                                                            _ ->
                                                                                                                soFar
                                                                                                    )
                                                                                        )
                                                                            )
                                                                )
                                                                (eval head)
                                                            |> Result.map (just ())
                                        in
                                        listItems |> evaluate

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "sum"
      , oneOf
            [ eval1 List.sum (decodeList (decodeLiteral floatLiteral)) (encodeLiteral FloatLiteral)
            , eval1 List.sum (decodeList (decodeLiteral intLiteral)) (encodeLiteral WholeNumberLiteral)
            ]
      )
    , ( "product"
      , oneOf
            [ eval1 List.product (decodeList (decodeLiteral floatLiteral)) (encodeLiteral FloatLiteral)
            , eval1 List.product (decodeList (decodeLiteral intLiteral)) (encodeLiteral WholeNumberLiteral)
            ]
      )
    , ( "append", eval2 List.append (decodeList decodeRaw) (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "concat", eval1 List.concat (decodeList (decodeList decodeRaw)) (encodeList encodeRaw) )
    , ( "intersperse", eval2 List.intersperse decodeRaw (decodeList decodeRaw) (encodeList encodeRaw) )

    {- sort sortBy sortWith -}
    , ( "indexedMap"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    Result.map
                        (\evaluatedArg1 ->
                            case evaluatedArg1 of
                                Value.List () listItems1 ->
                                    List.indexedMap
                                        (\index item1 ->
                                            eval
                                                (Value.Apply ()
                                                    (Value.Apply ()
                                                        fun
                                                        item1
                                                    )
                                                    (Value.Literal () (WholeNumberLiteral index))
                                                )
                                        )
                                        listItems1
                                        |> ResultList.keepFirstError
                                        |> Result.map (Value.List ())

                                _ ->
                                    Err (UnexpectedArguments args)
                        )
                        (eval arg1)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map2"
      , \eval args ->
            case args of
                [ fun, arg1, arg2 ] ->
                    Result.map2
                        (\evaluatedArg1 evaluatedArg2 ->
                            case ( evaluatedArg1, evaluatedArg2 ) of
                                ( Value.List () listItems1, Value.List () listItems2 ) ->
                                    List.map2
                                        (\item1 item2 ->
                                            eval
                                                (Value.Apply ()
                                                    (Value.Apply ()
                                                        fun
                                                        item1
                                                    )
                                                    item2
                                                )
                                        )
                                        listItems1
                                        listItems2
                                        |> ResultList.keepFirstError
                                        |> Result.map (Value.List ())

                                _ ->
                                    Err (UnexpectedArguments args)
                        )
                        (eval arg1)
                        (eval arg2)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map3"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3 ] ->
                    Result.map3
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 ->
                            case ( evaluatedArg1, evaluatedArg2, evaluatedArg3 ) of
                                ( Value.List () listItems1, Value.List () listItems2, Value.List () listItems3 ) ->
                                    List.map3
                                        (\item1 item2 item3 ->
                                            eval
                                                (Value.Apply ()
                                                    (Value.Apply ()
                                                        (Value.Apply ()
                                                            fun
                                                            item1
                                                        )
                                                        item2
                                                    )
                                                    item3
                                                )
                                        )
                                        listItems1
                                        listItems2
                                        listItems3
                                        |> ResultList.keepFirstError
                                        |> Result.map (Value.List ())

                                _ ->
                                    Err (UnexpectedArguments args)
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map4"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4 ] ->
                    Result.map4
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 evaluatedArg4 ->
                            case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4 ] of
                                [ Value.List () listItems1, Value.List () listItems2, Value.List () listItems3, Value.List () listItems4 ] ->
                                    List.map4
                                        (\item1 item2 item3 item4 ->
                                            eval
                                                (Value.Apply ()
                                                    (Value.Apply ()
                                                        (Value.Apply ()
                                                            (Value.Apply ()
                                                                fun
                                                                item1
                                                            )
                                                            item2
                                                        )
                                                        item3
                                                    )
                                                    item4
                                                )
                                        )
                                        listItems1
                                        listItems2
                                        listItems3
                                        listItems4
                                        |> ResultList.keepFirstError
                                        |> Result.map (Value.List ())

                                _ ->
                                    Err (UnexpectedArguments args)
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        (eval arg4)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "map5"
      , \eval args ->
            case args of
                [ fun, arg1, arg2, arg3, arg4, arg5 ] ->
                    Result.map5
                        (\evaluatedArg1 evaluatedArg2 evaluatedArg3 evaluatedArg4 evaluatedArg5 ->
                            case [ evaluatedArg1, evaluatedArg2, evaluatedArg3, evaluatedArg4, evaluatedArg5 ] of
                                [ Value.List () listItems1, Value.List () listItems2, Value.List () listItems3, Value.List () listItems4, Value.List () listItems5 ] ->
                                    List.map5
                                        (\item1 item2 item3 item4 item5 ->
                                            eval
                                                (Value.Apply ()
                                                    (Value.Apply ()
                                                        (Value.Apply ()
                                                            (Value.Apply ()
                                                                (Value.Apply ()
                                                                    fun
                                                                    item1
                                                                )
                                                                item2
                                                            )
                                                            item3
                                                        )
                                                        item4
                                                    )
                                                    item5
                                                )
                                        )
                                        listItems1
                                        listItems2
                                        listItems3
                                        listItems4
                                        listItems5
                                        |> ResultList.keepFirstError
                                        |> Result.map (Value.List ())

                                _ ->
                                    Err (UnexpectedArguments args)
                        )
                        (eval arg1)
                        (eval arg2)
                        (eval arg3)
                        (eval arg4)
                        (eval arg5)
                        |> Result.andThen identity

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "concatMap"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> List RawValue -> Result Error (List RawValue)
                                            evaluate resultList items =
                                                case items of
                                                    [] ->
                                                        Ok resultList

                                                    head1 :: tail1 ->
                                                        case eval (Value.Apply () fun head1) of
                                                            Ok (Value.List () list) ->
                                                                evaluate (resultList ++ list) tail1

                                                            Ok other ->
                                                                Err (ExpectedList other)

                                                            Err other ->
                                                                Err other
                                        in
                                        listItems
                                            |> evaluate []
                                            |> Result.map (Value.List ())

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "isEmpty", eval1 List.isEmpty (decodeList decodeRaw) (encodeLiteral BoolLiteral) )
    , ( "head", eval1 List.head (decodeList decodeRaw) (encodeMaybe encodeRaw) )
    , ( "tail", eval1 List.tail (decodeList decodeRaw) (encodeMaybe (encodeList encodeRaw)) )
    , ( "take", eval2 List.take (decodeLiteral intLiteral) (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "drop", eval2 List.drop (decodeLiteral intLiteral) (decodeList decodeRaw) (encodeList encodeRaw) )
    , ( "partition"
      , \eval args ->
            case args of
                [ fun, arg1 ] ->
                    eval arg1
                        |> Result.andThen
                            (\evaluatedArg1 ->
                                case evaluatedArg1 of
                                    Value.List () listItems ->
                                        let
                                            evaluate : List RawValue -> List RawValue -> List RawValue -> Result Error ( List RawValue, List RawValue )
                                            evaluate list1 list2 items =
                                                case items of
                                                    [] ->
                                                        Ok ( list1, list2 )

                                                    head1 :: tail1 ->
                                                        case eval (Value.Apply () fun head1) of
                                                            Ok (Value.Literal _ (BoolLiteral True)) ->
                                                                evaluate (list1 ++ [ head1 ]) list2 tail1

                                                            Ok (Value.Literal _ (BoolLiteral False)) ->
                                                                evaluate list1 (list2 ++ [ head1 ]) tail1

                                                            Ok other ->
                                                                Err (ExpectedBoolLiteral other)

                                                            Err other ->
                                                                Err other
                                        in
                                        listItems
                                            |> evaluate [] []
                                            |> Result.map
                                                (\( list1, list2 ) ->
                                                    Value.Tuple () [ Value.List () list1, Value.List () list2 ]
                                                )

                                    _ ->
                                        Err (ExpectedList evaluatedArg1)
                            )

                _ ->
                    Err (UnexpectedArguments args)
      )
    , ( "unzip", eval1 List.unzip (decodeList (decodeTuple2 ( decodeRaw, decodeRaw ))) (encodeTuple2 ( encodeList encodeRaw, encodeList encodeRaw )) )
    , ( "innerJoin"
      , nativeJoin False
      )
    , ( "leftJoin"
      , nativeJoin True
      )
    ]


nativeJoin : Bool -> Eval -> List RawValue -> Result Error RawValue
nativeJoin isOuter eval args =
    case args of
        [ listB, fun, listA ] ->
            eval listA
                |> Result.andThen
                    (\evaluatedListA ->
                        eval listB
                            |> Result.andThen
                                (\evaluatedListB ->
                                    case evaluatedListA of
                                        Value.List () listAItems ->
                                            listAItems
                                                |> List.map
                                                    (\listAItem ->
                                                        let
                                                            filterListB : Value () ()
                                                            filterListB =
                                                                Value.Apply ()
                                                                    (Value.Apply ()
                                                                        (Value.Reference () (toFQName moduleName "filter"))
                                                                        (Value.Apply () fun listAItem)
                                                                    )
                                                                    evaluatedListB
                                                        in
                                                        eval filterListB
                                                            |> Result.andThen
                                                                (\filteredListB ->
                                                                    case filteredListB of
                                                                        Value.List () listBItems ->
                                                                            if isOuter then
                                                                                if List.isEmpty listBItems then
                                                                                    Ok [ Value.Tuple () [ listAItem, nothing () ] ]

                                                                                else
                                                                                    listBItems
                                                                                        |> List.map
                                                                                            (\listBItem ->
                                                                                                Value.Tuple () [ listAItem, just () listBItem ]
                                                                                            )
                                                                                        |> Ok

                                                                            else
                                                                                listBItems
                                                                                    |> List.map
                                                                                        (\listBItem ->
                                                                                            Value.Tuple () [ listAItem, listBItem ]
                                                                                        )
                                                                                    |> Ok

                                                                        _ ->
                                                                            Err (ExpectedList filteredListB)
                                                                )
                                                    )
                                                |> ResultList.keepFirstError
                                                |> Result.map (List.concat >> Value.List ())

                                        _ ->
                                            Err (ExpectedList evaluatedListB)
                                )
                    )

        _ ->
            Err (UnexpectedArguments args)
