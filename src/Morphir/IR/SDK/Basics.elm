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
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : ModulePath
moduleName =
    Path.fromString "Basics"


moduleSpec : Module.Specification () ()
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
                [ "add"
                , "subtract"
                , "multiply"
                , "divide"
                , "integerDivide"
                , "power"
                , "toFloat"
                , "round"
                , "floor"
                , "ceiling"
                , "truncate"
                , "equal"
                , "notEqual"
                , "lessThan"
                , "greaterThan"
                , "lessThanOrEqual"
                , "greaterThanOrEqual"
                , "max"
                , "min"
                , "compare"
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
                , "identity"
                , "always"
                , "composeLeft"
                , "composeRight"
                , "never"
                ]
        in
        valueNames
            |> List.map
                (\valueName ->
                    ( Name.fromString valueName, dummyValueSpec )
                )
            |> Dict.fromList
    }


numberClass : a -> Type a
numberClass attributes =
    Variable attributes [ "number" ]


equal : a -> Value a
equal a =
    Value.Reference a (toFQName moduleName "equal")


notEqual : a -> Value a
notEqual a =
    Value.Reference a (toFQName moduleName "notEqual")


boolType : a -> Type a
boolType attributes =
    Reference attributes (toFQName moduleName "Bool") []


and : a -> Value a
and a =
    Value.Reference a (toFQName moduleName "and")


or : a -> Value a
or a =
    Value.Reference a (toFQName moduleName "or")


negate : a -> a -> Value a -> Value a
negate refAttributes valueAttributes arg =
    Value.Apply valueAttributes (Value.Reference refAttributes (toFQName moduleName "negate")) arg


add : a -> Value a
add a =
    Value.Reference a (toFQName moduleName "add")


subtract : a -> Value a
subtract a =
    Value.Reference a (toFQName moduleName "subtract")


multiply : a -> Value a
multiply a =
    Value.Reference a (toFQName moduleName "multiply")


power : a -> Value a
power a =
    Value.Reference a (toFQName moduleName "power")


intType : a -> Type a
intType attributes =
    Reference attributes (toFQName moduleName "Int") []


integerDivide : a -> Value a
integerDivide a =
    Value.Reference a (toFQName moduleName "integerDivide")


floatType : a -> Type a
floatType attributes =
    Reference attributes (toFQName moduleName "Float") []


divide : a -> Value a
divide a =
    Value.Reference a (toFQName moduleName "divide")


lessThan : a -> Value a
lessThan a =
    Value.Reference a (toFQName moduleName "lessThan")


lessThanOrEqual : a -> Value a
lessThanOrEqual a =
    Value.Reference a (toFQName moduleName "lessThanOrEqual")


greaterThan : a -> Value a
greaterThan a =
    Value.Reference a (toFQName moduleName "greaterThan")


greaterThanOrEqual : a -> Value a
greaterThanOrEqual a =
    Value.Reference a (toFQName moduleName "greaterThanOrEqual")


composeLeft : a -> Value a
composeLeft a =
    Value.Reference a (toFQName moduleName "composeLeft")


composeRight : a -> Value a
composeRight a =
    Value.Reference a (toFQName moduleName "composeRight")
