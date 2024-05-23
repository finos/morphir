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
import Morphir.Value.Error as ValueError
import Morphir.Value.Native exposing (decodeLiteral, encodeLiteral, stringLiteral, intLiteral, encodeMaybe)
import Morphir.Value.Native exposing (eval0)
import Morphir.Value.Native exposing (encodeUUID)
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
            , (Name.fromString "Error"
                , CustomTypeSpecification []
                    (Dict.fromList
                        [ (Name.fromString "WrongFormat", [])
                        , (Name.fromString "WrongLength", [])
                        , (Name.fromString "UnsupportedVariant", [])
                        , (Name.fromString "IsNil", [])
                        , (Name.fromString "NoVersion", [])
                        ]
                    )
                    |> Documented "Type that represents an UUID parsing error")
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

wrongFormat: va -> Value ta va
wrongFormat attributes =
    Value.Constructor attributes (toFQName moduleName "WrongFormat")

wrongLength: va -> Value ta va
wrongLength attributes =
    Value.Constructor attributes (toFQName moduleName "WrongLength")

unsupportedVariant: va -> Value ta va
unsupportedVariant attributes =
    Value.Constructor attributes (toFQName moduleName "UnsupportedVariant")

isNil: va -> Value ta va
isNil attributes =
    Value.Constructor attributes (toFQName moduleName "IsNil")

noVersion: va -> Value ta va
noVersion attributes =
    Value.Constructor attributes (toFQName moduleName "NoVersion")


nativeFunctions : List ( String, Native.Function )
nativeFunctions = 
    [ ( "forName" 
        , eval2 UUID.forName (decodeLiteral stringLiteral) decodeUUID (encodeUUID))
    , ( "parse" 
        , eval1 UUID.parse (decodeLiteral stringLiteral) (encodeUUIDParseResult))
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

{-| -}
encodeUUIDParseResult : (Result UUID.Error UUID.UUID) -> Result ValueError.Error Value.RawValue
encodeUUIDParseResult result =
    case result of
        Ok uuid ->
            UUID.toString uuid
                |> StringLiteral
                |> Value.Literal ()
                |> Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "uuid" ] ], [ "from", "string" ] ))
                |> Ok
        Err UUID.WrongFormat -> wrongFormat () |> Ok
        Err UUID.WrongLength -> wrongLength () |> Ok
        Err UUID.UnsupportedVariant -> unsupportedVariant () |> Ok
        Err UUID.IsNil -> isNil () |> Ok
        Err UUID.NoVersion -> noVersion () |> Ok


