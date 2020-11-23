module Morphir.Value.Native exposing (..)

import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))


type alias Function =
    Eval -> List (Value () ()) -> Result Error (Value () ())


type alias Eval =
    Value () () -> Result Error (Value () ())


unaryLazy : (Eval -> Value () () -> Result Error (Value () ())) -> Function
unaryLazy f =
    \eval args ->
        case args of
            [ arg ] ->
                f eval arg

            _ ->
                Err (UnexpectedArguments args)


unaryStrict : (Value () () -> Result Error (Value () ())) -> Function
unaryStrict f =
    unaryLazy (\eval arg -> eval arg |> Result.andThen f)


binaryLazy : (Eval -> Value () () -> Value () () -> Result Error (Value () ())) -> Function
binaryLazy f =
    \eval args ->
        case args of
            [ arg1, arg2 ] ->
                f eval arg1 arg2

            _ ->
                Err (UnexpectedArguments args)


binaryStrict : (Value () () -> Value () () -> Result Error (Value () ())) -> Function
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


mapLiteral : (Literal -> Result Error Literal) -> Value () () -> Result Error (Value () ())
mapLiteral f value =
    case value of
        Value.Literal a lit ->
            f lit
                |> Result.map (Value.Literal a)

        _ ->
            Err (ExpectedLiteral value)
