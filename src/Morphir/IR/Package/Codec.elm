module Morphir.IR.Package.Codec exposing (..)

import Dict
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.IR.AccessControlled.Codec exposing (decodeAccessControlled, encodeAccessControlled)
import Morphir.IR.Module.Codec as ModuleCodec
import Morphir.IR.Package exposing (Definition, Specification)
import Morphir.IR.Path.Codec exposing (decodePath, encodePath)


encodeSpecification : (a -> Encode.Value) -> Specification a -> Encode.Value
encodeSpecification encodeAttributes spec =
    Encode.object
        [ ( "modules"
          , spec.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleSpec ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "spec", ModuleCodec.encodeSpecification encodeAttributes moduleSpec )
                            ]
                    )
          )
        ]


encodeDefinition : (a -> Encode.Value) -> Definition a -> Encode.Value
encodeDefinition encodeAttributes def =
    Encode.object
        [ ( "dependencies"
          , def.dependencies
                |> Dict.toList
                |> Encode.list
                    (\( packageName, packageSpec ) ->
                        Encode.object
                            [ ( "name", encodePath packageName )
                            , ( "spec", encodeSpecification encodeAttributes packageSpec )
                            ]
                    )
          )
        , ( "modules"
          , def.modules
                |> Dict.toList
                |> Encode.list
                    (\( moduleName, moduleDef ) ->
                        Encode.object
                            [ ( "name", encodePath moduleName )
                            , ( "def", encodeAccessControlled (ModuleCodec.encodeDefinition encodeAttributes) moduleDef )
                            ]
                    )
          )
        ]


decodeDefinition : Decode.Decoder a -> Decode.Decoder (Definition a)
decodeDefinition decodeAttributes =
    Decode.map2 Definition
        (Decode.field "dependencies"
            (Decode.succeed Dict.empty)
        )
        (Decode.field "modules"
            (Decode.map Dict.fromList
                (Decode.list
                    (Decode.map2 Tuple.pair
                        (Decode.field "name" decodePath)
                        (Decode.field "def" (decodeAccessControlled (ModuleCodec.decodeDefinition decodeAttributes)))
                    )
                )
            )
        )
