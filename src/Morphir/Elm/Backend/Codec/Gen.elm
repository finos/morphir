module Morphir.Elm.Backend.Codec.Gen exposing (..)

import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression exposing (Case, Expression(..), Function, FunctionImplementation)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Pattern exposing (Pattern(..), QualifiedNameRef)
import Elm.Syntax.Range exposing (emptyRange)
import Morphir.IR.AccessControlled exposing (AccessControlled(..))
import Morphir.IR.Advanced.Type exposing (Constructor, Definition(..), Field(..), Type(..), field, record)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name, fromString, toCamelCase, toTitleCase)
import Morphir.IR.Path as Path exposing (toString)


typeDefToEncoder : extra -> Name -> AccessControlled (Definition extra) -> Declaration
typeDefToEncoder e typeName typeDef =
    let
        function : Function
        function =
            { documentation = Nothing
            , signature = Nothing
            , declaration = emptyRangeNode functionImpl
            }

        functionImpl : FunctionImplementation
        functionImpl =
            { name = emptyRangeNode functionName
            , arguments = args
            , expression = emptyRangeNode funcExpr
            }

        functionName : String
        functionName =
            [ "encode" ] ++ typeName |> Name.toCamelCase

        args : List (Node Pattern)
        args =
            case typeDef of
                Public (CustomTypeDefinition _ (Public constructors)) ->
                    case constructors of
                        [] ->
                            []

                        ( ctorName, fields ) :: [] ->
                            [ deconsPattern ctorName fields
                                |> emptyRangeNode
                                |> ParenthesizedPattern
                                |> emptyRangeNode
                            ]

                        _ ->
                            [ typeName |> Name.toCamelCase |> VarPattern |> emptyRangeNode ]

                Public (TypeAliasDefinition _ _) ->
                    [ typeName |> Name.toCamelCase |> VarPattern |> emptyRangeNode ]

                _ ->
                    []

        funcExpr : Expression
        funcExpr =
            case typeDef of
                Public (CustomTypeDefinition _ (Public constructors)) ->
                    case constructors of
                        [] ->
                            Literal "Types without constructors are not supported"

                        ctor :: [] ->
                            ctor
                                |> constructorToRecord e
                                |> typeToEncoder False [ Tuple.first ctor ]

                        ctors ->
                            let
                                caseValExpr : Node Expression
                                caseValExpr =
                                    typeName
                                        |> Name.toCamelCase
                                        |> FunctionOrValue []
                                        |> emptyRangeNode

                                cases : List ( Node Pattern, Node Expression )
                                cases =
                                    let
                                        ctorToPatternExpr : Constructor extra -> ( Node Pattern, Node Expression )
                                        ctorToPatternExpr ctor =
                                            let
                                                pattern : Pattern
                                                pattern =
                                                    deconsPattern (Tuple.first ctor) (Tuple.second ctor)

                                                expr : Expression
                                                expr =
                                                    ctor
                                                        |> constructorToRecord e
                                                        |> typeToEncoder True [ Tuple.first ctor ]
                                                        |> customTypeTopExpr
                                            in
                                            ( emptyRangeNode pattern, emptyRangeNode expr )
                                    in
                                    ctors |> List.map ctorToPatternExpr
                            in
                            CaseExpression { expression = caseValExpr, cases = cases }

                Public (TypeAliasDefinition _ tpe) ->
                    typeToEncoder True [ typeName ] tpe

                _ ->
                    Literal "Private types are not supported"
    in
    FunctionDeclaration function


{-|

    TODO: Capture Elm's primitive types in the SDK

-}
typeToEncoder : Bool -> List Name -> Type extra -> Expression
typeToEncoder fwdNames varName tpe =
    case tpe of
        Reference fqName typeArgs _ ->
            case fqName of
                FQName _ _ [ "int" ] ->
                    elmJsonEncoderApplication
                        (elmJsonEncoderFunction "int")
                        (varPathToExpr varName)

                FQName _ _ [ "string" ] ->
                    elmJsonEncoderApplication
                        (elmJsonEncoderFunction "string")
                        (varPathToExpr varName)

                FQName _ _ [ "maybe" ] ->
                    case typeArgs of
                        typeArg :: [] ->
                            let
                                caseValExpr : Node Expression
                                caseValExpr =
                                    varName
                                        |> varPathToExpr
                                        |> emptyRangeNode

                                justPattern : Pattern
                                justPattern =
                                    NamedPattern
                                        (QualifiedNameRef [] "Just")
                                        [ "a" |> VarPattern |> emptyRangeNode ]

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
                                    [ ( justPattern |> emptyRangeNode
                                      , justExpression |> emptyRangeNode
                                      )
                                    , ( nothingPattern |> emptyRangeNode
                                      , nothingExpression |> emptyRangeNode
                                      )
                                    ]
                            in
                            CaseExpression { expression = caseValExpr, cases = cases }

                        _ ->
                            Literal
                                """Generic types with a single type argument are supported"""

                FQName _ _ names ->
                    elmJsonEncoderApplication
                        ([ "encode" ] ++ names |> Name.toCamelCase |> FunctionOrValue [])
                        (varPathToExpr varName)

        Record fields _ ->
            let
                namesToFwd name =
                    if fwdNames then
                        varName ++ [ name ]

                    else
                        [ name ]

                fieldEncoder : Field extra -> Expression
                fieldEncoder (Field name fieldType) =
                    TupledExpression
                        [ name |> Name.toCamelCase |> Literal |> emptyRangeNode
                        , typeToEncoder fwdNames (namesToFwd name) fieldType |> emptyRangeNode
                        ]
            in
            elmJsonEncoderApplication
                (elmJsonEncoderFunction "object")
                (ListExpr <|
                    [ TupledExpression
                        [ Path.toString Name.toCamelCase "." varName |> Literal |> emptyRangeNode
                        , elmJsonEncoderApplication
                            (elmJsonEncoderFunction "object")
                            (ListExpr
                                (fields |> List.map fieldEncoder |> List.map emptyRangeNode)
                            )
                            |> emptyRangeNode
                        ]
                        |> emptyRangeNode
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
    Application [ emptyRangeNode func, emptyRangeNode arg ]


elmJsonEncoderFunction : String -> Expression
elmJsonEncoderFunction funcName =
    FunctionOrValue elmJsonEncoderModuleName funcName


elmJsonEncoderModuleName : ModuleName
elmJsonEncoderModuleName =
    [ "E" ]


emptyRangeNode : a -> Node a
emptyRangeNode a =
    Node emptyRange a


deconsPattern : Name -> List ( Name, Type extra ) -> Pattern
deconsPattern ctorName fields =
    let
        consVars : List (Node Pattern)
        consVars =
            fields
                |> List.map Tuple.first
                |> List.map Name.toCamelCase
                |> List.map VarPattern
                |> List.map emptyRangeNode
    in
    NamedPattern
        { moduleName = [], name = Name.toTitleCase ctorName }
        consVars


constructorToRecord : extra -> Constructor extra -> Type extra
constructorToRecord e ( _, types ) =
    let
        fields : List (Morphir.IR.Advanced.Type.Field extra)
        fields =
            types
                |> List.map (\t -> field (Tuple.first t) (Tuple.second t))
    in
    record fields e


customTypeTopExpr : Expression -> Expression
customTypeTopExpr expr =
    elmJsonEncoderApplication
        (elmJsonEncoderFunction "object")
        (ListExpr
            [ TupledExpression
                [ Literal "$type" |> emptyRangeNode
                , expr |> emptyRangeNode
                ]
                |> emptyRangeNode
            ]
        )
