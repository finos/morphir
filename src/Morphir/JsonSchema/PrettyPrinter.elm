module Morphir.JsonSchema.PrettyPrinter exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.JsonSchema.AST exposing (ArrayType(..), Derivative(..), Schema, SchemaType(..), TypeName)


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

                TupleType schemaTypes numberOfItems ->
                    Encode.object
                        [ ( "type", Encode.string "array" )
                        , ( "items", Encode.bool False )
                        , ( "prefixItems", Encode.list encodeSchemaType schemaTypes )
                        , ( "minItems", Encode.int numberOfItems )
                        , ( "maxItems", Encode.int numberOfItems )
                        ]

        String derivative ->
            case derivative of
                BasicString ->
                    Encode.object
                        [ ( "type", Encode.string "string" ) ]

                CharString ->
                    Encode.object
                        [ ( "type", Encode.string "string" ) ]

                DecimalString ->
                    Encode.object
                        [ ( "type", Encode.string "string" )
                        ]

                DateString ->
                    Encode.object
                        [ ( "type", Encode.string "string" )
                        , ( "format", Encode.string "date" )
                        ]

                TimeString ->
                    Encode.object
                        [ ( "type", Encode.string "string" )
                        , ( "format", Encode.string "time" )
                        ]

                MonthString ->
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
            Encode.object
                [ ( "type", Encode.string "null" ) ]

        OneOf schemaTypes ->
            Encode.object
                [ ( "oneOf", Encode.list encodeSchemaType schemaTypes )
                ]
