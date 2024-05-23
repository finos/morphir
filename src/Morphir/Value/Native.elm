module Morphir.Value.Native exposing
    ( Function
    , Eval
    , unaryLazy, unaryStrict, binaryLazy, binaryStrict, boolLiteral, charLiteral, eval0, eval1, eval2, eval3
    , floatLiteral, intLiteral, oneOf, stringLiteral, decimalLiteral
    , decodeFun1, decodeList, decodeLiteral, decodeMaybe, decodeLocalDate, decodeRaw, decodeTuple2, decodeUUID, encodeList, encodeLiteral, encodeMaybe, encodeLocalDate, encodeMaybeResult, encodeRaw, encodeResultList, encodeTuple2, decodeDict, decodeFun2, encodeDict, encodeUUID
    , trinaryLazy, trinaryStrict
    )

{-| This module contains an API and some tools to implement native functions. Native functions are functions that are
not expressed in terms Morphir expressions either because they cannot be or they are more efficient natively. Native in
this context means evaluating within Elm which in turn translates to JavaScript which either executes in the browser or
on the backend using Node.

Native functions are mainly used in the interpreter for evaluating SDK functions. Think of simple things like adding two
numbers: the IR captures the fact that you want to add them in a reference `Morphir.SDK.Basics.add` and the interpreter
finds the native function that actually adds the two numbers (which would be impossible to express in Morphir since it's
a primitive operation).

@docs Function


## Lazy evaluation

One important thing to understand is that the API allows lazy evaluation. Instead of evaluating arguments before they
are passed to the native function they are passed without evaluation. This allows the native function itself to decide
what order to evaluate arguments in. Think of the boolean `and` and `or` operators, they can often skip evaluation of
the second argument depending on the value of the first argument.

Also, when a lambda is passed as an argument it might need to be evaluated multiple times with different inputs. For
example the predicate in a `filter` will need to be evaluated on each item in the list.

@docs Eval


# Utilities

Various utilities to help with implementing native functions.

@docs unaryLazy, unaryStrict, binaryLazy, binaryStrict, boolLiteral, charLiteral, eval0, eval1, eval2, eval3
@docs floatLiteral, intLiteral, oneOf, stringLiteral, decimalLiteral
@docs decodeFun1, decodeList, decodeLiteral, decodeMaybe, decodeLocalDate, decodeRaw, decodeTuple2, decodeUUID, encodeList, encodeLiteral, encodeMaybe, encodeLocalDate, encodeMaybeResult, encodeRaw, encodeResultList, encodeTuple2, decodeDict, decodeFun2, encodeDict, encodeUUID
@docs trinaryLazy, trinaryStrict

-}

import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.SDK.Decimal exposing (Decimal)
import Morphir.SDK.Dict as Dict exposing (Dict)
import Morphir.SDK.LocalDate as LocalDate exposing (LocalDate)
import Morphir.SDK.UUID as UUID
import Morphir.SDK.ResultList as ListOfResults
import Morphir.Value.Error exposing (Error(..))

{-| Type that represents a native function. It's a function that takes two arguments:

  - A function to evaluate values. See the section on [Lazy evaluation](#Lazy_evaluation) for details.
  - The list of arguments.

-}
type alias Function =
    Eval -> List RawValue -> Result Error RawValue


{-| Type that captures a function used for evaluation. This will usually backed by the interpreter.
-}
type alias Eval =
    RawValue -> Result Error RawValue


{-| Create a native function that takes exactly one argument. Let the implementor decide when to evaluate the argument.

    nativeFunction : Native.Function
    nativeFunction =
        unaryLazy
            (\eval arg ->
                eval arg
                    |> Result.map
                        (\evaluatedArg ->
                            -- do something
                        )
            )

-}
unaryLazy : (Eval -> RawValue -> Result Error RawValue) -> Function
unaryLazy f =
    \eval args ->
        case args of
            [ arg ] ->
                f eval arg

            _ ->
                Err (UnexpectedArguments args)


{-| Create a native function that takes exactly one argument. Evaluate the argument before passing it to the supplied
function.

    nativeFunction : Native.Function
    nativeFunction =
        unaryLazy
            (\eval evaluatedArg ->
                -- do something with evaluatedArg
            )

-}
unaryStrict : (Eval -> RawValue -> Result Error RawValue) -> Function
unaryStrict f =
    unaryLazy (\eval arg -> eval arg |> Result.andThen (f eval))


{-| Create a native function that takes exactly two arguments. Let the implementor decide when to evaluate the arguments.

    nativeFunction : Native.Function
    nativeFunction =
        binaryLazy
            (\eval arg1 arg2 ->
                eval arg1
                    |> Result.andThen
                        (\evaluatedArg1 ->
                            eval arg2
                                |> Result.andThen
                                    (\evaluatedArg2 ->
                                        -- do something with evaluatedArg1 and evaluatedArg2
                                    )
                        )
            )

-}
binaryLazy : (Eval -> RawValue -> RawValue -> Result Error RawValue) -> Function
binaryLazy f =
    \eval args ->
        case args of
            [ arg1, arg2 ] ->
                f eval arg1 arg2

            _ ->
                Err (UnexpectedArguments args)


{-| -}
trinaryLazy : (Eval -> RawValue -> RawValue -> RawValue -> Result Error RawValue) -> Function
trinaryLazy f =
    \eval args ->
        case args of
            [ arg1, arg2, arg3 ] ->
                f eval arg1 arg2 arg3

            _ ->
                Err (UnexpectedArguments args)


{-| Create a native function that takes exactly two arguments. Evaluate both arguments before passing then to the supplied
function.

    nativeFunction : Native.Function
    nativeFunction =
        binaryStrict
            (\eval evaluatedArg1 evaluatedArg2 ->
                -- do something with evaluatedArg1 and evaluatedArg2
            )

-}
binaryStrict : (RawValue -> RawValue -> Result Error RawValue) -> Function
binaryStrict f =
    binaryLazy
        (\eval arg1 arg2 ->
            eval arg1
                |> Result.andThen
                    (\a1 ->
                        eval arg2
                            |> Result.andThen (f a1)
                    )
        )


{-| -}
trinaryStrict : (RawValue -> RawValue -> RawValue -> Result Error RawValue) -> Function
trinaryStrict f =
    trinaryLazy
        (\eval arg1 arg2 arg3 ->
            eval arg1
                |> Result.andThen
                    (\a1 ->
                        eval arg2
                            |> Result.andThen
                                (\a2 ->
                                    eval arg3
                                        |> Result.andThen (f a1 a2)
                                )
                    )
        )


type alias Decoder a =
    Eval -> RawValue -> Result Error a


type alias Encode a =
    a -> Result Error RawValue


{-| -}
decodeRaw : Decoder RawValue
decodeRaw eval value =
    eval value


{-| -}
encodeRaw : Encode RawValue
encodeRaw value =
    Ok value


{-| -}
decodeLiteral : (Literal -> Result Error a) -> Decoder a
decodeLiteral decodeLit eval value =
    case eval value of
        Ok (Value.Literal _ lit) ->
            decodeLit lit

        Ok _ ->
            Err (ExpectedLiteral value)

        Err error ->
            Err error


{-| -}
decodeList : Decoder a -> Decoder (List a)
decodeList decodeItem eval value =
    case eval value of
        Ok (Value.List _ values) ->
            values
                |> List.map (decodeItem eval)
                |> ListOfResults.keepFirstError

        Ok _ ->
            Err (ExpectedList value)

        Err error ->
            Err error


{-| -}
decodeDict : Decoder k -> Decoder v -> Decoder (Dict k v)
decodeDict decodeKey decodeValue eval value =
    case eval value of
        Ok (Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) list) ->
            list
                |> decodeList (decodeTuple2 ( decodeKey, decodeValue )) eval
                |> Result.map Dict.fromList

        Ok _ ->
            Err (ExpectedList value)

        Err error ->
            Err error


{-| -}
encodeDict : Encode k -> Encode v -> Dict k v -> Result Error RawValue
encodeDict encodeKey encodeValue dict =
    Dict.toList dict
        |> encodeList (encodeTuple2 ( encodeKey, encodeValue ))


{-| -}
encodeTuple2 : ( Encode a, Encode b ) -> ( a, b ) -> Result Error RawValue
encodeTuple2 ( encodeA, encodeB ) ( a, b ) =
    encodeB b
        |> Result.map2 (\a1 b1 -> Value.Tuple () [ a1, b1 ]) (encodeA a)


{-| -}
decodeTuple2 : ( Decoder a, Decoder b ) -> Decoder ( a, b )
decodeTuple2 ( decodeA, decodeB ) eval value =
    case eval value of
        Ok (Value.Tuple _ [ val1, val2 ]) ->
            Result.map2 (\a1 b1 -> ( a1, b1 )) (decodeA eval val1) (decodeB eval val2)

        Ok _ ->
            Err (ExpectedTuple value)

        Err error ->
            Err error


{-| -}
decodeFun1 : Encode a -> Decoder r -> Decoder (a -> Result Error r)
decodeFun1 encodeA decodeR eval fun =
    Ok
        (\a ->
            encodeA a
                |> Result.andThen
                    (\arg -> eval (Value.Apply () fun arg))
                |> Result.andThen (decodeR eval)
        )


{-| -}
decodeFun2 : Encode a -> Encode b -> Decoder r -> Decoder (a -> b -> Result Error r)
decodeFun2 encodeA encodeB decodeR eval fun =
    Ok
        (\a b ->
            encodeA a
                |> Result.andThen
                    (\arg1 ->
                        encodeB b
                            |> Result.andThen
                                (\arg2 ->
                                    eval (Value.Apply () (Value.Apply () fun arg1) arg2)
                                        |> Result.andThen (decodeR eval)
                                )
                    )
        )


{-| -}
boolLiteral : Literal -> Result Error Bool
boolLiteral lit =
    case lit of
        BoolLiteral v ->
            Ok v

        _ ->
            Err (ExpectedBoolLiteral (Value.Literal () lit))


{-| -}
intLiteral : Literal -> Result Error Int
intLiteral lit =
    case lit of
        WholeNumberLiteral v ->
            Ok v

        _ ->
            Err (ExpectedIntLiteral (Value.Literal () lit))


{-| -}
floatLiteral : Literal -> Result Error Float
floatLiteral lit =
    case lit of
        FloatLiteral v ->
            Ok v

        _ ->
            Err (ExpectedFloatLiteral (Value.Literal () lit))


{-| -}
charLiteral : Literal -> Result Error Char
charLiteral lit =
    case lit of
        CharLiteral v ->
            Ok v

        _ ->
            Err (ExpectedCharLiteral (Value.Literal () lit))


{-| -}
stringLiteral : Literal -> Result Error String
stringLiteral lit =
    case lit of
        StringLiteral v ->
            Ok v

        _ ->
            Err (ExpectedStringLiteral (Value.Literal () lit))


{-| -}
decimalLiteral : Literal -> Result Error Decimal
decimalLiteral lit =
    case lit of
        DecimalLiteral v ->
            Ok v

        _ ->
            Err (ExpectedDecimalLiteral (Value.Literal () lit))


{-| -}
encodeLiteral : (a -> Literal) -> a -> Result Error RawValue
encodeLiteral toLit a =
    Ok (Value.Literal () (toLit a))


{-| -}
encodeResultList : List (Result Error RawValue) -> Result Error RawValue
encodeResultList listOfValueResults =
    listOfValueResults
        |> ListOfResults.keepFirstError
        |> Result.map (Value.List ())


{-| -}
encodeMaybeResult : Maybe (Result Error RawValue) -> Result Error RawValue
encodeMaybeResult maybeResult =
    case maybeResult of
        Just (Ok value) ->
            Ok (Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) value)

        Just (Err error) ->
            Err error

        Nothing ->
            Ok (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ))


{-| -}
encodeList : Encode a -> List a -> Result Error RawValue
encodeList encodeA list =
    list
        |> List.map encodeA
        |> ListOfResults.keepFirstError
        |> Result.map (Value.List ())


{-| -}
encodeMaybe : Encode a -> Maybe a -> Result Error RawValue
encodeMaybe encodeA maybe =
    case maybe of
        Just a ->
            encodeA a |> Result.map (Value.Apply () (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )))

        Nothing ->
            Ok (Value.Constructor () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ))


{-| -}
decodeMaybe : Decoder a -> Decoder (Maybe a)
decodeMaybe decodeItem eval value =
    case eval value of
        Ok (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] )) ->
            Ok Nothing

        Ok (Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) val) ->
            val
                |> decodeItem eval
                |> Result.map Just

        Ok _ ->
            Err (ExpectedMaybe value)

        Err error ->
            Err error


{-| -}
encodeUUID : UUID.UUID -> Result Error RawValue
encodeUUID uuid =
    UUID.toString uuid
        |> StringLiteral
        |> Value.Literal ()
        |> Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "uuid" ] ], [ "from", "string" ] ))
        |> Ok

    
{-| -}
decodeUUID : Decoder UUID.UUID
decodeUUID e value =
    e value
        |> Result.andThen
            (\v ->
                case v of
                    Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "uuid" ] ], [ "from", "string" ] )) (Value.Literal () (StringLiteral str)) ->
                        case UUID.fromString str of
                            Just uuid ->
                                Ok uuid

                            Nothing ->
                                Err <| ErrorWhileEvaluatingDerivedType ("Invalid UUID format: " ++ str)

                    Value.Literal () (StringLiteral str) ->
                        case UUID.fromString str of
                            Just uuid ->
                                Ok uuid

                            Nothing ->
                                Err <| ErrorWhileEvaluatingDerivedType ("Invalid UUID format: " ++ str)

                    _ ->
                        Err (ExpectedDerivedType ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "uuid" ] ], [ "uuid" ] ) v)
            )

{-| -}
encodeLocalDate : LocalDate -> Result Error RawValue
encodeLocalDate localDate =
    LocalDate.toISOString localDate
        |> StringLiteral
        |> Value.Literal ()
        |> Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] ))
        |> Ok


{-| -}
decodeLocalDate : Decoder LocalDate
decodeLocalDate e value =
    e value
        |> Result.andThen
            (\v ->
                case v of
                    Value.Apply () (Value.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) (Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] )) (Value.Literal () (StringLiteral str))) ->
                        case LocalDate.fromISO str of
                            Just localDate ->
                                Ok localDate

                            Nothing ->
                                Err <| ErrorWhileEvaluatingDerivedType ("Invalid ISO format: " ++ str)

                    Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "from", "i", "s", "o" ] )) (Value.Literal () (StringLiteral str)) ->
                        case LocalDate.fromISO str of
                            Just localDate ->
                                Ok localDate

                            Nothing ->
                                Err <| ErrorWhileEvaluatingDerivedType ("Invalid ISO format: " ++ str)

                    Value.Literal () (StringLiteral str) ->
                        case LocalDate.fromISO str of
                            Just localDate ->
                                Ok localDate

                            Nothing ->
                                Err <| ErrorWhileEvaluatingDerivedType ("Invalid ISO format: " ++ str)

                    _ ->
                        Err (ExpectedDerivedType ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "local", "date" ] ], [ "local", "date" ] ) v)
            )


{-| -}
eval0 : r -> Encode r -> Function
eval0 r encodeR =
    \eval args ->
        case args of
            [] ->
                encodeR r

            _ ->
                Err (UnexpectedArguments args)


{-| -}
eval1 : (a -> r) -> Decoder a -> Encode r -> Function
eval1 f decodeA encodeR eval args =
    case args of
        [ arg1 ] ->
            Result.andThen
                (\a ->
                    encodeR (f a)
                )
                (decodeA eval arg1)

        _ ->
            Err (UnexpectedArguments args)


{-| -}
eval2 : (a -> b -> r) -> Decoder a -> Decoder b -> Encode r -> Function
eval2 f decodeA decodeB encodeR eval args =
    case args of
        [ arg1, arg2 ] ->
            decodeA eval arg1
                |> Result.andThen
                    (\a ->
                        decodeB eval arg2
                            |> Result.andThen
                                (\b -> encodeR (f a b))
                    )

        _ ->
            Err (UnexpectedArguments args)


{-| -}
eval3 : (a -> b -> c -> r) -> Decoder a -> Decoder b -> Decoder c -> Encode r -> Function
eval3 f decodeA decodeB decodeC encodeR eval args =
    case args of
        [ arg1, arg2, arg3 ] ->
            decodeA eval arg1
                |> Result.andThen
                    (\a ->
                        decodeB eval arg2
                            |> Result.andThen
                                (\b ->
                                    decodeC eval arg3
                                        |> Result.andThen (\c -> encodeR (f a b c))
                                )
                    )

        _ ->
            Err (UnexpectedArguments args)


{-| -}
oneOf : List Function -> Function
oneOf funs =
    funs
        |> List.foldl
            (\nextFun funSoFar ->
                \eval args ->
                    case funSoFar eval args of
                        Ok result ->
                            Ok result

                        Err _ ->
                            nextFun eval args
            )
            (\eval args ->
                Err NotImplemented
            )
