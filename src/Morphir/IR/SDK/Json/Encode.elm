module Morphir.IR.SDK.Json.Encode exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, floatType, intType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.Dict exposing (dictType)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.LocalTime exposing (localTimeType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.Set exposing (setType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Encode"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Encode", OpaqueTypeSpecification [] |> Documented "Type that represents a JSON Encoder" )
            ]
    , values =
        Dict.fromList
            [ vSpec "encode" [ ( "i", intType () ), ( "v", valueType () ) ] (stringType ())
            , vSpec "string" [ ( "s", stringType () ) ] (valueType ())
            , vSpec "int" [ ( "i", intType () ) ] (valueType ())
            , vSpec "float" [ ( "f", floatType () ) ] (valueType ())
            , vSpec "bool" [ ( "f", boolType () ) ] (valueType ())
            , vSpec "null" [] (valueType ())
            , vSpec "list"
                [ ( "f", tFun [ tVar "a" ] (tVar "Value") )
                , ( "list", listType () (tVar "a") )
                ]
                (valueType ())
            , vSpec "set"
                [ ( "f", tFun [ tVar "a" ] (tVar "Value") )
                , ( "set", setType () (tVar "a") )
                ]
                (valueType ())
            , vSpec "object" [ ( "list", listType () (Tuple () [ tVar "a", tVar "b" ]) ) ] (valueType ())
            , vSpec "dict"
                [ ( "f", tFun [ tVar "k" ] (stringType ()) )
                , ( "f", tFun [ tVar "v" ] (valueType ()) )
                , ( "dict", dictType () (tVar "k") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "localTime" [ ( "t", localTimeType () ) ] (valueType ())
            , vSpec "maybe"
                [ ( "f", tFun [ tVar "a" ] (tVar "Value") )
                , ( "maybe", maybeType () (tVar "a") )
                ]
                (valueType ())
            ]
    , doc = Just "The Encode type and associated functions"
    }


valueType : a -> Type a
valueType attributes =
    Reference attributes (toFQName moduleName "Encode") []
