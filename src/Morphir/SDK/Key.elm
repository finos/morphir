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


module Morphir.SDK.Key exposing
    ( noKey, key0, key2, key3, key4, key5, key6, key7, key8, key9, key10, key11, key12, key13, key14, key15, key16
    , Key0, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, Key10, Key11, Key12, Key13, Key14, Key15, Key16
    )

{-| Helpers to work with composite keys.


# Motivation

It is difficult to work with composite keys in Elm due to various limitations:

  - Keys should be comparable. Record and union types are not comparable in Elm. We can only use Tuples to represent them.
  - Tuples are limited at 3 elements. Real-world composite keys can easily have more elements than that.
  - Unit is not comparable. This makes it impossible to pass in a zero element key where comparable keys are required.

This library resolves those issues by introducing type aliases for keys of various element sizes. All these types are
generic to let developers to create their custom types to be comparable and they all have utility functions to compose them. Here's an example:

    type alias MyEntity =
        { foo : String
        , bar : Int
        , baz : Float
        }

    -- myKey : Key3 Int String Float
    myKey =
        key3 .bar .foo .baz

**Note:** This file was generated using Elm code that is included as a comment at the end of the source code for this
module. You can use that code to extend this module without too much manual work.


# Composing Keys

@docs noKey, key0, key2, key3, key4, key5, key6, key7, key8, key9, key10, key11, key12, key13, key14, key15, key16


# Key Types

@docs Key0, Key2, Key3, Key4, Key5, Key6, Key7, Key8, Key9, Key10, Key11, Key12, Key13, Key14, Key15, Key16

-}


{-| Type that represents a zero element key. The ideal representation would be `()` but `Unit` is not comparable in Elm.
So we use `Int` to retain comparable semantics but only `0` should be used as a value.
`key0` and `noKey` can be used to create a `Key0` value.
-}
type alias Key0 =
    Int


{-| Type that represents a composite key with 2 elements.
-}
type alias Key2 k1 k2 =
    ( k1, k2 )


{-| Type that represents a composite key with 3 elements.
-}
type alias Key3 k1 k2 k3 =
    ( k1, k2, k3 )


{-| Type that represents a composite key with 4 elements.
-}
type alias Key4 k1 k2 k3 k4 =
    ( k1, k2, ( k3, k4 ) )


{-| Type that represents a composite key with 5 elements.
-}
type alias Key5 k1 k2 k3 k4 k5 =
    ( k1, k2, ( k3, k4, k5 ) )


{-| Type that represents a composite key with 6 elements.
-}
type alias Key6 k1 k2 k3 k4 k5 k6 =
    ( k1, k2, ( k3, k4, ( k5, k6 ) ) )


{-| Type that represents a composite key with 7 elements.
-}
type alias Key7 k1 k2 k3 k4 k5 k6 k7 =
    ( k1, k2, ( k3, k4, ( k5, k6, k7 ) ) )


{-| Type that represents a composite key with 8 elements.
-}
type alias Key8 k1 k2 k3 k4 k5 k6 k7 k8 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8 ) ) ) )


{-| Type that represents a composite key with 9 elements.
-}
type alias Key9 k1 k2 k3 k4 k5 k6 k7 k8 k9 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, k9 ) ) ) )


{-| Type that represents a composite key with 10 elements.
-}
type alias Key10 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10 ) ) ) ) )


{-| Type that represents a composite key with 11 elements.
-}
type alias Key11 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, k11 ) ) ) ) )


{-| Type that represents a composite key with 12 elements.
-}
type alias Key12 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, ( k11, k12 ) ) ) ) ) )


{-| Type that represents a composite key with 13 elements.
-}
type alias Key13 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, ( k11, k12, k13 ) ) ) ) ) )


{-| Type that represents a composite key with 14 elements.
-}
type alias Key14 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 k14 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, ( k11, k12, ( k13, k14 ) ) ) ) ) ) )


{-| Type that represents a composite key with 15 elements.
-}
type alias Key15 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, ( k11, k12, ( k13, k14, k15 ) ) ) ) ) ) )


{-| Type that represents a composite key with 16 elements.
-}
type alias Key16 k1 k2 k3 k4 k5 k6 k7 k8 k9 k10 k11 k12 k13 k14 k15 k16 =
    ( k1, k2, ( k3, k4, ( k5, k6, ( k7, k8, ( k9, k10, ( k11, k12, ( k13, k14, ( k15, k16 ) ) ) ) ) ) ) )


{-| Creates a key with zero elements.
-}
noKey : a -> Key0
noKey =
    key0


{-| Creates a key with zero elements.
-}
key0 : a -> Key0
key0 =
    always 0


{-| Create a composite key with 2 elements.
-}
key2 : (a -> b1) -> (a -> b2) -> a -> Key2 b1 b2
key2 getKey1 getKey2 a =
    ( getKey1 a, getKey2 a )


{-| Create a composite key with 3 elements.
-}
key3 : (a -> b1) -> (a -> b2) -> (a -> b3) -> a -> Key3 b1 b2 b3
key3 getKey1 getKey2 getKey3 a =
    ( getKey1 a, getKey2 a, getKey3 a )


{-| Create a composite key with 4 elements.
-}
key4 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> a -> Key4 b1 b2 b3 b4
key4 getKey1 getKey2 getKey3 getKey4 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a ) )


{-| Create a composite key with 5 elements.
-}
key5 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> a -> Key5 b1 b2 b3 b4 b5
key5 getKey1 getKey2 getKey3 getKey4 getKey5 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, getKey5 a ) )


{-| Create a composite key with 6 elements.
-}
key6 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> a -> Key6 b1 b2 b3 b4 b5 b6
key6 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a ) ) )


{-| Create a composite key with 7 elements.
-}
key7 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> a -> Key7 b1 b2 b3 b4 b5 b6 b7
key7 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, getKey7 a ) ) )


{-| Create a composite key with 8 elements.
-}
key8 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> a -> Key8 b1 b2 b3 b4 b5 b6 b7 b8
key8 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a ) ) ) )


{-| Create a composite key with 9 elements.
-}
key9 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> a -> Key9 b1 b2 b3 b4 b5 b6 b7 b8 b9
key9 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, getKey9 a ) ) ) )


{-| Create a composite key with 10 elements.
-}
key10 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> a -> Key10 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10
key10 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a ) ) ) ) )


{-| Create a composite key with 11 elements.
-}
key11 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> a -> Key11 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11
key11 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, getKey11 a ) ) ) ) )


{-| Create a composite key with 12 elements.
-}
key12 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> (a -> b12) -> a -> Key12 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12
key12 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 getKey12 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, ( getKey11 a, getKey12 a ) ) ) ) ) )


{-| Create a composite key with 13 elements.
-}
key13 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> (a -> b12) -> (a -> b13) -> a -> Key13 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13
key13 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 getKey12 getKey13 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, ( getKey11 a, getKey12 a, getKey13 a ) ) ) ) ) )


{-| Create a composite key with 14 elements.
-}
key14 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> (a -> b12) -> (a -> b13) -> (a -> b14) -> a -> Key14 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14
key14 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 getKey12 getKey13 getKey14 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, ( getKey11 a, getKey12 a, ( getKey13 a, getKey14 a ) ) ) ) ) ) )


{-| Create a composite key with 15 elements.
-}
key15 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> (a -> b12) -> (a -> b13) -> (a -> b14) -> (a -> b15) -> a -> Key15 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15
key15 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 getKey12 getKey13 getKey14 getKey15 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, ( getKey11 a, getKey12 a, ( getKey13 a, getKey14 a, getKey15 a ) ) ) ) ) ) )


{-| Create a composite key with 16 elements.
-}
key16 : (a -> b1) -> (a -> b2) -> (a -> b3) -> (a -> b4) -> (a -> b5) -> (a -> b6) -> (a -> b7) -> (a -> b8) -> (a -> b9) -> (a -> b10) -> (a -> b11) -> (a -> b12) -> (a -> b13) -> (a -> b14) -> (a -> b15) -> (a -> b16) -> a -> Key16 b1 b2 b3 b4 b5 b6 b7 b8 b9 b10 b11 b12 b13 b14 b15 b16
key16 getKey1 getKey2 getKey3 getKey4 getKey5 getKey6 getKey7 getKey8 getKey9 getKey10 getKey11 getKey12 getKey13 getKey14 getKey15 getKey16 a =
    ( getKey1 a, getKey2 a, ( getKey3 a, getKey4 a, ( getKey5 a, getKey6 a, ( getKey7 a, getKey8 a, ( getKey9 a, getKey10 a, ( getKey11 a, getKey12 a, ( getKey13 a, getKey14 a, ( getKey15 a, getKey16 a ) ) ) ) ) ) ) )



--# Generating this module
--
--This module was generated by the below snippet. You can use it to generate higher element values or other features
--if needed.
--
--        gen : Int -> String
--        gen maxIndex =
--            let
--                genKeyType : Int -> String
--                genKeyType n =
--                    let
--                        argNames =
--                            List.range 1 n
--                                |> List.map (\i -> "k" ++ String.fromInt i)
--                                |> String.join " "
--
--                        body keys =
--                            case keys of
--                                [] ->
--                                    "()"
--
--                                [ one ] ->
--                                    "k" ++ String.fromInt one
--
--                                [ one, two ] ->
--                                    "( k" ++ String.fromInt one ++ ", k" ++ String.fromInt two ++ " )"
--
--                                one :: two :: rest ->
--                                    "( k" ++ String.fromInt one ++ ", k" ++ String.fromInt two ++ ", " ++ body rest ++ " )"
--                    in
--                    String.join "\n"
--                        [ "{-| Type that represents a composite key with " ++ String.fromInt n ++ " elements."
--                        , "-}"
--                        , "type alias Key" ++ String.fromInt n ++ " " ++ argNames ++ " =\n    " ++ body (List.range 1 n)
--                        ]
--
--                genKeyFun : Int -> String
--                genKeyFun n =
--                    let
--                        funName =
--                            "key" ++ String.fromInt n
--
--                        argTypes =
--                            List.range 1 n
--                                |> List.map (\i -> "(a -> b" ++ String.fromInt i ++ ")")
--                                |> String.join " -> "
--
--                        returnType =
--                            List.range 1 n
--                                |> List.map (\i -> "b" ++ String.fromInt i)
--                                |> String.join " "
--                                |> (++) ("Key" ++ String.fromInt n ++ " ")
--
--                        argNames =
--                            List.range 1 n
--                                |> List.map (\i -> "getKey" ++ String.fromInt i)
--                                |> String.join " "
--
--                        body keys =
--                            case keys of
--                                [] ->
--                                    "()"
--
--                                [ one ] ->
--                                    "getKey" ++ String.fromInt one ++ " a"
--
--                                [ one, two ] ->
--                                    "( getKey" ++ String.fromInt one ++ " a, getKey" ++ String.fromInt two ++ " a )"
--
--                                one :: two :: rest ->
--                                    "( getKey" ++ String.fromInt one ++ " a, getKey" ++ String.fromInt two ++ " a, " ++ body rest ++ " )"
--                    in
--                    String.join "\n"
--                        [ "{-| Create a composite key with " ++ String.fromInt n ++ " elements."
--                        , "-}"
--                        , funName ++ " : " ++ argTypes ++ " -> a -> " ++ returnType
--                        , funName ++ " " ++ argNames ++ " a = "
--                        , "    " ++ body (List.range 1 n)
--                        ]
--
--
--            in
--            String.join "\n\n\n"
--                [ String.join "\n"
--                    [ "module Morphir.SDK.Key exposing"
--                    , "    ( Key0, " ++ (List.range 2 maxIndex |> List.map (\n -> "Key" ++ String.fromInt n) |> String.join ", ")
--                    , "    , noKey, key0, " ++ (List.range 2 maxIndex |> List.map (\n -> "key" ++ String.fromInt n) |> String.join ", ")
--                    , "    )"
--                    , ""
--                    , "{-| Helpers to work with composite keys. Composite keys are represented as tuples to retain comparable semantics."
--                    , "Since Elm 0.19 limits tuples to 3 elements we use nested structures to represent higher element counts. "
--                    , ""
--                    , "# Composing Keys"
--                    , ""
--                    , "@docs noKey, key0, " ++ (List.range 2 maxIndex |> List.map (\n -> "key" ++ String.fromInt n) |> String.join ", ")
--                    , ""
--                    , "# Key Types"
--                    , ""
--                    , "@docs Key0, " ++ (List.range 2 maxIndex |> List.map (\n -> "Key" ++ String.fromInt n) |> String.join ", ")
--                    , ""
--                    , "-}"
--                    , ""
--                    , "{-| Type that represents a zero element key. The ideal representation would be `()` but `Unit` is not comparable in Elm."
--                    , "So we use `Int` to retain comparable semantics but only `0` should be used as a value. "
--                    , "`key0` and `noKey` can be used to create a `Key0` value."
--                    , "-}"
--                    , "type alias Key0 = Int"
--                    ]
--                , List.range 2 maxIndex
--                    |> List.map genKeyType
--                    |> String.join "\n\n\n"
--                , String.join "\n"
--                    [ "{-| Creates a key with zero elements. -}"
--                    , "noKey : Key0"
--                    , "noKey ="
--                    , "    key0"
--                    ]
--                , String.join "\n"
--                    [ "{-| Creates a key with zero elements. -}"
--                    , "key0 : Key0"
--                    , "key0 ="
--                    , "    0"
--                    ]
--                , List.range 2 maxIndex
--                    |> List.map genKeyFun
--                    |> String.join "\n\n\n"
--                ]
