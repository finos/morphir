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


module Morphir.Elm.Backend.Codec.EncoderGen exposing (..)

import Dict
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression exposing (Case, Expression(..), Function, FunctionImplementation)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Pattern exposing (Pattern(..), QualifiedNameRef)
import Morphir.Elm.Backend.Utils as Utils
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type exposing (Definition(..), Field, Type(..), record)


typeDefToEncoder : Name -> AccessControlled (Documented (Definition ())) -> Declaration
typeDefToEncoder typeName typeDef =
    let
        function : Function
        function =
            { documentation = Nothing
            , signature = Nothing
            , declaration = Utils.emptyRangeNode functionImpl
            }

        functionImpl : FunctionImplementation
        functionImpl =
            { name = Utils.emptyRangeNode functionName
            , arguments = args
            , expression = Utils.emptyRangeNode funcExpr
            }

        functionName : String
        functionName =
            [ "encode" ] ++ typeName |> Name.toCamelCase

        args : List (Node Pattern)
        args =
            case typeDef.access of
                Public ->
                    case typeDef.value.value of
                        CustomTypeDefinition _ constructors ->
                            case constructors.access of
                                Public ->
                                    case constructors.value |> Dict.toList of
                                        [] ->
                                            []

                                        ( ctorName, fields ) :: [] ->
                                            [ deconsPattern ctorName fields
                                                |> Utils.emptyRangeNode
                                                |> ParenthesizedPattern
                                                |> Utils.emptyRangeNode
                                            ]

                                        _ ->
                                            [ typeName |> Name.toCamelCase |> VarPattern |> Utils.emptyRangeNode ]

                                Private ->
                                    []

                        TypeAliasDefinition _ _ ->
                            [ typeName |> Name.toCamelCase |> VarPattern |> Utils.emptyRangeNode ]

                Private ->
                    []

        funcExpr : Expression
        funcExpr =
            case typeDef.access of
                Public ->
                    case typeDef.value.value of
                        CustomTypeDefinition _ constructors ->
                            case constructors.access of
                                Public ->
                                    case constructors.value |> Dict.toList of
                                        [] ->
                                            Literal "Types without constructors are not supported"

                                        (( ctorName, _ ) as ctor) :: [] ->
                                            ctor
                                                |> constructorToRecord
                                                |> typeToEncoder False [ ctorName ]

                                        ctors ->
                                            let
                                                caseValExpr : Node Expression
                                                caseValExpr =
                                                    typeName
                                                        |> Name.toCamelCase
                                                        |> FunctionOrValue []
                                                        |> Utils.emptyRangeNode

                                                cases : List ( Node Pattern, Node Expression )
                                                cases =
                                                    let
                                                        ctorToPatternExpr : ( Name, List ( Name, Type () ) ) -> ( Node Pattern, Node Expression )
                                                        ctorToPatternExpr (( ctorName, ctorArgs ) as ctor) =
                                                            let
                                                                pattern : Pattern
                                                                pattern =
                                                                    deconsPattern ctorName ctorArgs

                                                                expr : Expression
                                                                expr =
                                                                    ctor
                                                                        |> constructorToRecord
                                                                        |> typeToEncoder False [ ctorName ]
                                                                        |> customTypeTopExpr
                                                            in
                                                            ( Utils.emptyRangeNode pattern, Utils.emptyRangeNode expr )
                                                    in
                                                    ctors |> List.map ctorToPatternExpr
                                            in
                                            CaseExpression { expression = caseValExpr, cases = cases }

                                Private ->
                                    Literal "Private constructors are not supported"

                        TypeAliasDefinition _ tpe ->
                            typeToEncoder True [ typeName ] tpe

                Private ->
                    Literal "Private types are not supported"
    in
    FunctionDeclaration function


{-|

    TODO: Capture Elm's primitive types in the SDK

-}
typeToEncoder : Bool -> List Name -> Type () -> Expression
typeToEncoder fwdNames varName tpe =
    case tpe of
        Reference _ fqName typeArgs ->
            case fqName of
                ( _, _, [ "int" ] ) ->
                    elmJsonEncoderApplication
                        (elmJsonEncoderFunction "int")
                        (varPathToExpr varName)

                ( _, _, [ "float" ] ) ->
                    elmJsonEncoderApplication
                        (elmJsonEncoderFunction "float")
                        (varPathToExpr varName)

                ( _, _, [ "string" ] ) ->
                    elmJsonEncoderApplication
                        (elmJsonEncoderFunction "string")
                        (varPathToExpr varName)

                ( _, _, [ "maybe" ] ) ->
                    case typeArgs of
                        typeArg :: [] ->
                            let
                                caseValExpr : Node Expression
                                caseValExpr =
                                    varName
                                        |> varPathToExpr
                                        |> Utils.emptyRangeNode

                                justPattern : Pattern
                                justPattern =
                                    NamedPattern
                                        (QualifiedNameRef [] "Just")
                                        [ "a" |> VarPattern |> Utils.emptyRangeNode ]

                                justExpression : Expression
                                justExpression =
                                    typeToEncoder True [ Name.fromString "a" ] typeArg

                                nothingPattern : Pattern
                                nothingPattern =
                                    NamedPattern
                                        (QualifiedNameRef [] "Nothing")
                                        []

                                nothingExpression : Expression
                                nothingExpression =
                                    elmJsonEncoderFunction "null"

                                cases : List ( Node Pattern, Node Expression )
                                cases =
                                    [ ( justPattern |> Utils.emptyRangeNode
                                      , justExpression |> Utils.emptyRangeNode
                                      )
                                    , ( nothingPattern |> Utils.emptyRangeNode
                                      , nothingExpression |> Utils.emptyRangeNode
                                      )
                                    ]
                            in
                            CaseExpression { expression = caseValExpr, cases = cases }

                        _ ->
                            Literal
                                """Generic types with a single type argument are supported"""

                ( _, _, names ) ->
                    elmJsonEncoderApplication
                        ([ "encode" ] ++ names |> Name.toCamelCase |> FunctionOrValue [])
                        (varPathToExpr varName)

        Record _ fields ->
            let
                namesToFwd name =
                    if fwdNames then
                        varName ++ [ name ]

                    else
                        [ name ]

                fieldEncoder : Field () -> Expression
                fieldEncoder field =
                    TupledExpression
                        [ field.name |> Name.toCamelCase |> Literal |> Utils.emptyRangeNode
                        , typeToEncoder fwdNames (namesToFwd field.name) field.tpe |> Utils.emptyRangeNode
                        ]
            in
            elmJsonEncoderApplication
                (elmJsonEncoderFunction "object")
                (ListExpr <|
                    [ TupledExpression
                        [ Path.toString Name.toCamelCase "." varName |> Literal |> Utils.emptyRangeNode
                        , elmJsonEncoderApplication
                            (elmJsonEncoderFunction "object")
                            (ListExpr
                                (fields |> List.map fieldEncoder |> List.map Utils.emptyRangeNode)
                            )
                            |> Utils.emptyRangeNode
                        ]
                        |> Utils.emptyRangeNode
                    ]
                )

        _ ->
            Literal
                """Only reference with single type argument
                and record types are supported"""


varPathToExpr : List Name -> Expression
varPathToExpr names =
    Path.toString Name.toCamelCase "." names |> FunctionOrValue []


elmJsonEncoderApplication : Expression -> Expression -> Expression
elmJsonEncoderApplication func arg =
    Application [ Utils.emptyRangeNode func, Utils.emptyRangeNode arg ]


elmJsonEncoderFunction : String -> Expression
elmJsonEncoderFunction funcName =
    FunctionOrValue elmJsonEncoderModuleName funcName


elmJsonEncoderModuleName : ModuleName
elmJsonEncoderModuleName =
    [ "E" ]


deconsPattern : Name -> List ( Name, Type () ) -> Pattern
deconsPattern ctorName fields =
    let
        consVars : List (Node Pattern)
        consVars =
            fields
                |> List.map Tuple.first
                |> List.map Name.toCamelCase
                |> List.map VarPattern
                |> List.map Utils.emptyRangeNode
    in
    NamedPattern
        { moduleName = [], name = Name.toTitleCase ctorName }
        consVars


constructorToRecord : ( Name, List ( Name, Type () ) ) -> Type ()
constructorToRecord ( _, types ) =
    let
        fields : List (Morphir.IR.Type.Field ())
        fields =
            types
                |> List.map (\t -> Field (Tuple.first t) (Tuple.second t))
    in
    record () fields


customTypeTopExpr : Expression -> Expression
customTypeTopExpr expr =
    elmJsonEncoderApplication
        (elmJsonEncoderFunction "object")
        (ListExpr
            [ TupledExpression
                [ Literal "$type" |> Utils.emptyRangeNode
                , expr |> Utils.emptyRangeNode
                ]
                |> Utils.emptyRangeNode
            ]
        )
