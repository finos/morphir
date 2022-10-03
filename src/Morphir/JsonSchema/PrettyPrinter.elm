module Morphir.JsonSchema.PrettyPrinter exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.JsonSchema.AST exposing (ArrayType(..), Schema, SchemaType(..), TypeName)


encodeSchema : Schema -> String
encodeSchema schema =
    Encode.object
        [ ( "$id", Encode.string (schema.id ++ ".schema.json") )
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

        Array arrayType ->
            case arrayType of
                ListType itemSchemaType ->
                    Encode.object
                        [ ( "type", Encode.string "array" )
                        , ( "items", encodeSchemaType itemSchemaType )
                        ]

                TupleType schemaTypes ->
                    Encode.object
                        [ ( "type", Encode.string "array" )
                        , ( "items", Encode.bool False )
                        , ( "prefixItems", Encode.list encodeSchemaType schemaTypes )
                        ]

        String ->
            Encode.object
                [ ( "type", Encode.string "string" ) ]

        Number ->
            Encode.object
                [ ( "type", Encode.string "number" ) ]

        Boolean ->
            Encode.object
                [ ( "type", Encode.string "boolean" ) ]

        Object st ->
            Encode.object
                [ ( "type", Encode.string "object" )
                , ( "properties", Encode.dict identity encodeSchemaType st )
                ]

        Const value ->
            Encode.object
                [ ( "const", Encode.string value ) ]

        Ref string ->
            Encode.object
                [ ( "$ref", Encode.string string ) ]

        Null ->
            Encode.null

        AnyOf schemaTypes ->
            Encode.object
                [ ( "anyOf", Encode.list encodeSchemaType schemaTypes )
                ]
