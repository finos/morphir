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


module Morphir.IR.SDK.Basics exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tVar, toFQName, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModuleName
moduleName =
    Path.fromString "Basics"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Int", OpaqueTypeSpecification [] |> Documented "Type that represents an integer value." )
            , ( Name.fromString "Float", OpaqueTypeSpecification [] |> Documented "Type that represents a floating-point number." )
            , ( Name.fromString "Bool", OpaqueTypeSpecification [] |> Documented "Type that represents a boolean value." )
            , ( Name.fromString "Never", OpaqueTypeSpecification [] |> Documented "A value that can never happen!" )
            ]
    , values =
        let
            -- Used temporarily as a placeholder for function values until we can generate them based on the SDK.
            dummyValueSpec : Value.Specification ()
            dummyValueSpec =
                Value.Specification [] (Type.Unit ())

            valueNames : List String
            valueNames =
                [ "compare"
                , "not"
                , "and"
                , "or"
                , "xor"
                , "modBy"
                , "remainderBy"
                , "negate"
                , "abs"
                , "clamp"
                , "sqrt"
                , "logBase"
                , "e"
                , "pi"
                , "cos"
                , "sin"
                , "tan"
                , "acos"
                , "asin"
                , "atan"
                , "atan2"
                , "degrees"
                , "radians"
                , "turns"
                , "toPolar"
                , "fromPolar"
                , "isNaN"
                , "isInfinite"
                , "composeLeft"
                , "composeRight"
                , "never"
                ]

            realValues : List ( Name, Value.Specification () )
            realValues =
                [ vSpec "add" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
                , vSpec "subtract" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
                , vSpec "multiply" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
                , vSpec "divide" [ ( "a", floatType () ), ( "b", floatType () ) ] (floatType ())
                , vSpec "integerDivide" [ ( "a", intType () ), ( "b", intType () ) ] (intType ())
                , vSpec "power" [ ( "a", tVar "number" ), ( "b", tVar "number" ) ] (tVar "number")
                , vSpec "toFloat" [ ( "a", intType () ) ] (floatType ())
                , vSpec "round" [ ( "a", floatType () ) ] (intType ())
                , vSpec "floor" [ ( "a", floatType () ) ] (intType ())
                , vSpec "ceiling" [ ( "a", floatType () ) ] (intType ())
                , vSpec "truncate" [ ( "a", floatType () ) ] (intType ())
                , vSpec "equal" [ ( "a", tVar "eq" ), ( "b", tVar "eq" ) ] (boolType ())
                , vSpec "notEqual" [ ( "a", tVar "eq" ), ( "b", tVar "eq" ) ] (boolType ())
                , vSpec "lessThan" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
                , vSpec "greaterThan" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
                , vSpec "lessThanOrEqual" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
                , vSpec "greaterThanOrEqual" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (boolType ())
                , vSpec "max" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (tVar "comparable")
                , vSpec "min" [ ( "a", tVar "comparable" ), ( "b", tVar "comparable" ) ] (tVar "comparable")

                -- break
                , vSpec "identity" [ ( "a", tVar "a" ) ] (tVar "a")
                , vSpec "always" [ ( "a", tVar "a" ), ( "b", tVar "b" ) ] (tVar "a")
                ]
        in
        valueNames
            |> List.map
                (\valueName ->
                    ( Name.fromString valueName, dummyValueSpec )
                )
            |> List.append realValues
            |> Dict.fromList
    }


equal : a -> Value ta a
equal a =
    Value.Reference a (toFQName moduleName "equal")


notEqual : a -> Value ta a
notEqual a =
    Value.Reference a (toFQName moduleName "notEqual")


boolType : a -> Type a
boolType attributes =
    Reference attributes (toFQName moduleName "Bool") []


and : a -> Value ta a
and a =
    Value.Reference a (toFQName moduleName "and")


or : a -> Value ta a
or a =
    Value.Reference a (toFQName moduleName "or")


negate : a -> a -> Value ta a -> Value ta a
negate refAttributes valueAttributes arg =
    Value.Apply valueAttributes (Value.Reference refAttributes (toFQName moduleName "negate")) arg


add : a -> Value ta a
add a =
    Value.Reference a (toFQName moduleName "add")


subtract : a -> Value ta a
subtract a =
    Value.Reference a (toFQName moduleName "subtract")


multiply : a -> Value ta a
multiply a =
    Value.Reference a (toFQName moduleName "multiply")


power : a -> Value ta a
power a =
    Value.Reference a (toFQName moduleName "power")


intType : a -> Type a
intType attributes =
    Reference attributes (toFQName moduleName "Int") []


integerDivide : a -> Value ta a
integerDivide a =
    Value.Reference a (toFQName moduleName "integerDivide")


floatType : a -> Type a
floatType attributes =
    Reference attributes (toFQName moduleName "Float") []


divide : a -> Value ta a
divide a =
    Value.Reference a (toFQName moduleName "divide")


lessThan : a -> Value ta a
lessThan a =
    Value.Reference a (toFQName moduleName "lessThan")


lessThanOrEqual : a -> Value ta a
lessThanOrEqual a =
    Value.Reference a (toFQName moduleName "lessThanOrEqual")


greaterThan : a -> Value ta a
greaterThan a =
    Value.Reference a (toFQName moduleName "greaterThan")


greaterThanOrEqual : a -> Value ta a
greaterThanOrEqual a =
    Value.Reference a (toFQName moduleName "greaterThanOrEqual")


composeLeft : a -> Value ta a
composeLeft a =
    Value.Reference a (toFQName moduleName "composeLeft")


composeRight : a -> Value ta a
composeRight a =
    Value.Reference a (toFQName moduleName "composeRight")
