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


module Morphir.Elm.Backend.Codec.DecoderGen exposing (..)

import Dict
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression exposing (Expression(..))
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Pattern exposing (Pattern(..))
import Morphir.Elm.Backend.Utils as Utils
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Definition(..), Field, Type(..))


typeDefToDecoder : Name -> AccessControlled (Documented (Type.Definition ())) -> Declaration
typeDefToDecoder typeName accessCtrlTypeDef =
    let
        decoderVar : Pattern
        decoderVar =
            ("decoder" ++ (typeName |> Name.toTitleCase))
                |> VarPattern

        decoderExpr : Expression
        decoderExpr =
            case accessCtrlTypeDef.access of
                Public ->
                    case accessCtrlTypeDef.value.value of
                        CustomTypeDefinition _ acsCtrlCtors ->
                            case acsCtrlCtors.access of
                                Public ->
                                    case acsCtrlCtors.value |> Dict.toList of
                                        [] ->
                                            Literal "Opaque types are not supported"

                                        ctor :: [] ->
                                            constructorDecoder True ctor

                                        ctors ->
                                            let
                                                oneOfFunc : Expression
                                                oneOfFunc =
                                                    FunctionOrValue decoderModuleName "oneOf"

                                                listOfPossibleDecoders : Expression
                                                listOfPossibleDecoders =
                                                    ctors
                                                        |> List.map (constructorDecoder False)
                                                        |> List.map Utils.emptyRangeNode
                                                        |> ListExpr
                                            in
                                            Application
                                                [ oneOfFunc |> Utils.emptyRangeNode
                                                , listOfPossibleDecoders |> Utils.emptyRangeNode
                                                ]

                                _ ->
                                    Literal "Private constructors are not supported"

                        TypeAliasDefinition _ tpe ->
                            tpe |> typeToDecoder typeName []

                _ ->
                    Literal "Private types are not supported"
    in
    Destructuring
        (decoderVar |> Utils.emptyRangeNode)
        (decoderExpr |> Utils.emptyRangeNode)


constructorDecoder : Bool -> ( Name, List ( Name, Type () ) ) -> Expression
constructorDecoder isSingle ( ctorName, fields ) =
    case fields of
        [] ->
            Application
                [ FunctionOrValue [] "at" |> Utils.emptyRangeNode
                , ListExpr
                    [ Literal "$type" |> Utils.emptyRangeNode
                    , ctorName |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                    ]
                    |> Utils.emptyRangeNode
                , ParenthesizedExpression
                    (Application
                        [ FunctionOrValue [] "succeed" |> Utils.emptyRangeNode
                        , FunctionOrValue [] (ctorName |> Name.toTitleCase) |> Utils.emptyRangeNode
                        ]
                        |> Utils.emptyRangeNode
                    )
                    |> Utils.emptyRangeNode
                ]

        _ ->
            let
                ctorFieldToRecField : ( Name, Type () ) -> Field ()
                ctorFieldToRecField ( name, tpe ) =
                    Field name tpe

                topLevelFieldNames =
                    if isSingle then
                        []

                    else
                        [ "$type" ]
            in
            Record () (fields |> List.map ctorFieldToRecField)
                |> typeToDecoder ctorName topLevelFieldNames


typeToDecoder : Name -> List String -> Type () -> Expression
typeToDecoder typeName topLevelFieldNames tpe =
    case tpe of
        Reference _ fqName typeParams ->
            case fqName of
                ( _, _, [ "string" ] ) ->
                    FunctionOrValue decoderModuleName "string"

                ( _, _, [ "bool" ] ) ->
                    FunctionOrValue decoderModuleName "bool"

                ( _, _, [ "int" ] ) ->
                    FunctionOrValue decoderModuleName "int"

                ( _, _, [ "float" ] ) ->
                    FunctionOrValue decoderModuleName "float"

                ( _, _, [ "maybe" ] ) ->
                    let
                        typeParamEncoder =
                            case typeParams of
                                [] ->
                                    Literal "Maybe should have a type parameter"

                                tParam :: [] ->
                                    tParam
                                        |> typeToDecoder (Name.fromString "") topLevelFieldNames

                                _ ->
                                    Literal "Maybe type can have only a single type parameter"
                    in
                    Application
                        [ FunctionOrValue decoderModuleName "nullable"
                            |> Utils.emptyRangeNode
                        , typeParamEncoder
                            |> Utils.emptyRangeNode
                        ]
                        |> Utils.emptyRangeNode
                        |> ParenthesizedExpression

                ( _, _, name ) ->
                    FunctionOrValue
                        []
                        ("decoder" ++ (name |> Name.toTitleCase))

        Record _ fields ->
            let
                mapFunc : Expression
                mapFunc =
                    fields
                        |> List.length
                        |> mapDecoderMapFunc

                ctorFunc : Expression
                ctorFunc =
                    typeName
                        |> Name.toTitleCase
                        |> FunctionOrValue []

                fieldDecoder : Name -> Field () -> Expression
                fieldDecoder _ field =
                    Application <|
                        [ FunctionOrValue decoderModuleName "at" |> Utils.emptyRangeNode
                        , ListExpr
                            ((topLevelFieldNames
                                |> List.map Literal
                                |> List.map Utils.emptyRangeNode
                             )
                                ++ [ typeName |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                                   , field.name |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                                   ]
                            )
                            |> Utils.emptyRangeNode
                        , field.tpe
                            |> typeToDecoder (Name.fromString "") []
                            |> Utils.emptyRangeNode
                        ]

                fieldDecoders : List Expression
                fieldDecoders =
                    fields
                        |> List.map (fieldDecoder typeName)
                        |> List.map Utils.emptyRangeNode
                        |> List.map ParenthesizedExpression
            in
            Application <|
                [ mapFunc |> Utils.emptyRangeNode
                , ctorFunc |> Utils.emptyRangeNode
                ]
                    ++ (fieldDecoders |> List.map Utils.emptyRangeNode)

        _ ->
            Literal "Only reference and record types are supported"


decoderModuleName : ModuleName
decoderModuleName =
    [ "D" ]


mapDecoderMapFunc : Int -> Expression
mapDecoderMapFunc n =
    let
        mapFuncName =
            case n of
                1 ->
                    "map"

                2 ->
                    "map2"

                3 ->
                    "map3"

                4 ->
                    "map4"

                5 ->
                    "map5"

                6 ->
                    "map6"

                7 ->
                    "map7"

                8 ->
                    "map8"

                _ ->
                    "more than 8 fields cannot be mapped"
    in
    FunctionOrValue decoderModuleName mapFuncName
