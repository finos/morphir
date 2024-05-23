module Morphir.IR.SDK.Int exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (intType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Int"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Int8", OpaqueTypeSpecification [] |> Documented "Type that represents a 8-bit integer." )
            , ( Name.fromString "Int16", OpaqueTypeSpecification [] |> Documented "Type that represents a 16-bit integer." )
            , ( Name.fromString "Int32", OpaqueTypeSpecification [] |> Documented "Type that represents a 32-bit integer." )
            , ( Name.fromString "Int64", OpaqueTypeSpecification [] |> Documented "Type that represents a 64-bit integer." )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromInt8" [ ( "n", int8Type () ) ] (intType ())
            , vSpec "toInt8" [ ( "n", intType () ) ] (maybeType () (int8Type ()))
            , vSpec "fromInt16" [ ( "n", int16Type () ) ] (intType ())
            , vSpec "toInt16" [ ( "n", intType () ) ] (maybeType () (int16Type ()))
            , vSpec "fromInt32" [ ( "n", int32Type () ) ] (intType ())
            , vSpec "toInt32" [ ( "n", intType () ) ] (maybeType () (int32Type ()))
            , vSpec "fromInt64" [ ( "n", int64Type () ) ] (intType ())
            , vSpec "toInt64" [ ( "n", intType () ) ] (maybeType () (int64Type ()))
            ]
    , doc = Just "Contains types that represent 8, 16, 32, or 64 bit integers, and functions tha convert between these and the general Int type."
    }


int8Type : a -> Type a
int8Type attributes =
    Reference attributes (toFQName moduleName "Int8") []


int16Type : a -> Type a
int16Type attributes =
    Reference attributes (toFQName moduleName "Int16") []


int32Type : a -> Type a
int32Type attributes =
    Reference attributes (toFQName moduleName "Int32") []


int64Type : a -> Type a
int64Type attributes =
    Reference attributes (toFQName moduleName "Int64") []
