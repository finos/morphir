module Morphir.Elm.Backend.Codec.DecoderGen exposing (..)

import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression exposing (Expression(..))
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Pattern exposing (Pattern(..))
import Morphir.Elm.Backend.Codec.Utils as Utils exposing (emptyRangeNode)
import Morphir.IR.AccessControlled exposing (AccessControlled(..))
import Morphir.IR.Advanced.Type as Type exposing (Constructor, Definition(..), Field(..), Type(..))
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)


typeDefToDecoder : extra -> Name -> AccessControlled (Type.Definition extra) -> Declaration
typeDefToDecoder e typeName accessCtrlTypeDef =
    let
        decoderVar : Pattern
        decoderVar =
            ("decoder" ++ (typeName |> Name.toTitleCase))
                |> VarPattern

        decoderExpr : Expression
        decoderExpr =
            case accessCtrlTypeDef of
                Public (CustomTypeDefinition _ (Public constructors)) ->
                    case constructors of
                        [] ->
                            Literal "Opaque types are not supported"

                        ctor :: [] ->
                            constructorDecoder e True ctor

                        ctors ->
                            let
                                oneOfFunc : Expression
                                oneOfFunc =
                                    FunctionOrValue decoderModuleName "oneOf"

                                listOfPossibleDecoders : Expression
                                listOfPossibleDecoders =
                                    ctors
                                        |> List.map (constructorDecoder e False)
                                        |> List.map Utils.emptyRangeNode
                                        |> ListExpr
                            in
                            Application
                                [ oneOfFunc |> Utils.emptyRangeNode
                                , listOfPossibleDecoders |> Utils.emptyRangeNode
                                ]

                Public (TypeAliasDefinition _ tpe) ->
                    tpe |> typeToDecoder typeName []

                _ ->
                    Literal "Private types are not supported"
    in
    Destructuring
        (decoderVar |> Utils.emptyRangeNode)
        (decoderExpr |> Utils.emptyRangeNode)


constructorDecoder : extra -> Bool -> Constructor extra -> Expression
constructorDecoder e isSingle ( ctorName, fields ) =
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
                ctorFieldToRecField : ( Name, Type extra ) -> Field extra
                ctorFieldToRecField ( name, tpe ) =
                    Field name tpe

                topLevelFieldNames =
                    if isSingle then
                        []

                    else
                        [ "$type" ]
            in
            Record (fields |> List.map ctorFieldToRecField) e
                |> typeToDecoder ctorName topLevelFieldNames


typeToDecoder : Name -> List String -> Type extra -> Expression
typeToDecoder typeName topLevelFieldNames tpe =
    case tpe of
        Reference fqName typeParams _ ->
            case fqName of
                FQName [] [] [ "string" ] ->
                    FunctionOrValue decoderModuleName "string"

                FQName [] [] [ "bool" ] ->
                    FunctionOrValue decoderModuleName "bool"

                FQName [] [] [ "int" ] ->
                    FunctionOrValue decoderModuleName "int"

                FQName [] [] [ "float" ] ->
                    FunctionOrValue decoderModuleName "float"

                FQName [] [] [ "maybe" ] ->
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

                FQName [] [] name ->
                    FunctionOrValue
                        []
                        ("decoder" ++ (name |> Name.toTitleCase))

                _ ->
                    Literal """Only string bool float
                    and int primitives are supported"""

        Record fields _ ->
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

                fieldDecoder : Name -> Field extra -> Expression
                fieldDecoder _ (Field fieldName fieldType) =
                    Application <|
                        [ FunctionOrValue decoderModuleName "at" |> Utils.emptyRangeNode
                        , ListExpr
                            ((topLevelFieldNames
                                |> List.map Literal
                                |> List.map Utils.emptyRangeNode
                             )
                                ++ [ typeName |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                                   , fieldName |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                                   ]
                            )
                            |> Utils.emptyRangeNode
                        , fieldType
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
