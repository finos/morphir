module Morphir.JsonSchema.PrettyPrinter exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.JsonSchema.AST exposing (ArrayType(..), Schema, SchemaType(..), TypeName)


encodeSchema : Schema -> String
encodeSchema schema =
    Encode.object
        [ ( "$id", Encode.string schema.id )
        , ( "$schema", Encode.string schema.schemaVersion )
        , ( "$defs", encodeDefinitions schema.definitions )
        ]
        |> Encode.encode 4


encodeDefinitions : Dict TypeName SchemaType -> Encode.Value
encodeDefinitions schemaTypeByTypeName =
    Encode.dict identity encodeSchemaType schemaTypeByTypeName


encodeSchemaType : SchemaType -> Encode.Value
encodeSchemaType schemaType =
    case schemaType of
        Integer ->
            Encode.object
                [ ( "type", Encode.string "integer" ) ]

        Array arrayType isUnique ->
            case arrayType of
                ListType itemSchemaType ->
                    Encode.object
                        (List.concat
                            [ [ ( "type", Encode.string "array" )
                              , ( "items", encodeSchemaType itemSchemaType )
                              ]
                            , if isUnique then
                                [ ( "uniqueItems", Encode.bool True ) ]

                              else
                                []
                            ]
                        )

                TupleType schemaTypes ->
                    Encode.object
                        [ ( "type", Encode.string "array" )
                        , ( "items", Encode.bool False )
                        , ( "prefixItems", Encode.list encodeSchemaType schemaTypes )
                        ]

        String stringConstraint ->
            case stringConstraint.format of
                Just format ->
                    Encode.object
                        [ ( "type", Encode.string "string" )
                        , ( "format", Encode.string format )
                        ]

                Nothing ->
                    Encode.object
                        [ ( "type", Encode.string "string" ) ]

        Number ->
            Encode.object
                [ ( "type", Encode.string "number" ) ]

        Boolean ->
            Encode.object
                [ ( "type", Encode.string "boolean" ) ]

        Object st requiredFields ->
            Encode.object
                (List.concat
                    [ [ ( "type", Encode.string "object" )
                      , ( "properties", Encode.dict identity encodeSchemaType st )
                      ]
                    , if List.isEmpty requiredFields then
                        []

                      else
                        [ ( "required", Encode.list Encode.string requiredFields ) ]
                    ]
                )

        Const value ->
            Encode.object
                [ ( "const", Encode.string value ) ]

        Ref string ->
            Encode.object
                [ ( "$ref", Encode.string string ) ]

        Null ->
            Encode.object
                [ ( "type", Encode.string "null" ) ]

        OneOf schemaTypes ->
            Encode.object
                [ ( "oneOf", Encode.list encodeSchemaType schemaTypes )
                ]
