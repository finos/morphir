module Morphir.IR.SDK.UUID exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Path as Path
import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.IR.SDK.Common exposing (vSpec)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.SDK.Result exposing (resultType)
import Morphir.IR.SDK.Basics exposing (intType, orderType, boolType)
import Morphir.Value.Native as Native
import Morphir.Value.Native exposing (eval1, eval2)
import Morphir.SDK.UUID as UUID
import Morphir.Value.Native exposing (decodeLiteral, encodeLiteral, stringLiteral, intLiteral, encodeMaybe)
import Morphir.Value.Native exposing (eval0)
import Morphir.Value.Native exposing (encodeUUID, encodeUUID2)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.Value.Native exposing (decodeUUID)
import Morphir.Value.Native.Comparable exposing (compareValue)

moduleName : ModuleName
moduleName =
    Path.fromString "UUID"

moduleSpec : Module.Specification ()
moduleSpec = 
    { types = 
        Dict.fromList
            [ (Name.fromString "UUID", OpaqueTypeSpecification [] |> Documented "Type that represents a UUID v5")
            ]
    , values =
        Dict.fromList
            [ vSpec "parse" [ ("s", stringType () ) ] (resultType () (errorType ()) (uuidType ()))
            , vSpec "fromString" [ ("s", stringType() ) ] (maybeType () (uuidType ()))
            , vSpec "forName" [ ("s", stringType () ), ("uuid", uuidType () ) ] (uuidType ())
            , vSpec "toString" [ ("uuid", uuidType () ) ] (stringType ())
            , vSpec "version" [ ("uuid", uuidType () ) ] (intType ())
            , vSpec "compare" [ ("uuid1", uuidType () ), ("uuid2", uuidType () ) ] (orderType ())
            , vSpec "nilString" [] (stringType ())
            , vSpec "isNilString" [ ("s", stringType () ) ] (boolType())
            , vSpec "dnsNamespace" [] (uuidType ())
            , vSpec "urlNamespace" [] (uuidType ())
            , vSpec "oidNamespace" [] (uuidType ())
            , vSpec "x500Namespace" [] (uuidType ())
            ]
    , doc = Just "The UUID type and associated functions"
    }

uuidType : a -> Type a
uuidType attributes = 
    Reference attributes (toFQName moduleName "UUID") []

errorType: a -> Type a
errorType attributes =
    Reference attributes (toFQName moduleName "Error") []

nativeFunctions : List ( String, Native.Function )
nativeFunctions = 
    [ ( "forName" 
        , eval2 UUID.forName (decodeLiteral stringLiteral) decodeUUID (encodeUUID))
    , ( "parse" 
        , eval1 UUID.parse (decodeLiteral stringLiteral) (encodeUUID2))
    , ( "fromString" 
        , eval1 UUID.fromString (decodeLiteral stringLiteral) (encodeMaybe encodeUUID))
    , ( "toString"
        , eval1 UUID.toString decodeUUID (encodeLiteral StringLiteral))
    , ( "version"
        , eval1 UUID.version decodeUUID (encodeLiteral WholeNumberLiteral))
    , ( "nilString"
        , eval0 UUID.nilString (encodeLiteral StringLiteral))
    , ( "isNilString"
        , eval1 UUID.isNilString (decodeLiteral stringLiteral) (encodeLiteral BoolLiteral))
    , ( "compare"
      , Native.binaryStrict
            (\arg1 arg2 ->
                compareValue arg1 arg2
                    |> Result.map encodeOrder
            )
      )
    , ( "dnsNamespace"
        , eval0 UUID.dnsNamespace (encodeUUID))
    , ( "urlNamespace"
        , eval0 UUID.urlNamespace (encodeUUID))
    , ( "oidNamespace"
        , eval0 UUID.oidNamespace (encodeUUID))
    , ( "x500Namespace"
        , eval0 UUID.x500Namespace (encodeUUID))
    ]

encodeOrder : Order -> Value () ()
encodeOrder =
    \order ->
        let
            val =
                case order of
                    GT ->
                        "GT"

                    LT ->
                        "LT"

                    EQ ->
                        "EQ"
        in
        Value.Constructor () (toFQName moduleName val)