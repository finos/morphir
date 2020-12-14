module Morphir.Value.Native exposing
    ( Function
    , Eval
    , unaryLazy, unaryStrict, binaryLazy, binaryStrict, mapLiteral
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

@docs unaryLazy, unaryStrict, binaryLazy, binaryStrict, mapLiteral

-}

import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))


{-| Type that represents a native function. It's a function that takes two arguments:

  - A function to evaluate values. See the section on [Lazy evaluation](#Lazy_evaluation) for details.
  - The list of arguments.

-}
type alias Function =
    Eval -> List (Value () ()) -> Result Error (Value () ())


{-| Type that captures a function used for evaluation. This will usually backed by the interpreter.
-}
type alias Eval =
    Value () () -> Result Error (Value () ())


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
unaryLazy : (Eval -> Value () () -> Result Error (Value () ())) -> Function
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
unaryStrict : (Eval -> Value () () -> Result Error (Value () ())) -> Function
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
binaryLazy : (Eval -> Value () () -> Value () () -> Result Error (Value () ())) -> Function
binaryLazy f =
    \eval args ->
        case args of
            [ arg1, arg2 ] ->
                f eval arg1 arg2

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


{-| Create a native function that maps one literal value to another literal value.
-}
mapLiteral : (Literal -> Result Error Literal) -> Eval -> Value () () -> Result Error (Value () ())
mapLiteral f eval value =
    case value of
        Value.Literal a lit ->
            f lit
                |> Result.map (Value.Literal a)

        _ ->
            Err (ExpectedLiteral value)
