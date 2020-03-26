module Morphir.Elm.Backend.Dapr.Stateful.ElmGen exposing (..)

import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..))
import Elm.Syntax.Expression exposing (CaseBlock, Expression(..), Function, FunctionImplementation, LetDeclaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module exposing (Module(..))
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node exposing (Node)
import Elm.Syntax.Pattern exposing (Pattern(..))
import Elm.Syntax.Range as Range exposing (emptyRange)
import Elm.Syntax.TypeAnnotation exposing (RecordDefinition, RecordField, TypeAnnotation(..))
import Elm.Writer
import Morphir.Elm.Backend.Codec.DecoderGen as DecoderGen exposing (typeDefToDecoder)
import Morphir.Elm.Backend.Codec.EncoderGen as EncoderGen exposing (typeDefToEncoder)
import Morphir.Elm.Backend.Utils as Utils exposing (emptyRangeNode)
import Morphir.Elm.Frontend as Frontend exposing (ContentLocation, ContentRange, SourceFile, SourceLocation, mapDeclarationsToType)
import Morphir.IR.Advanced.Type exposing (Field, Type(..))
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name, toCamelCase)
import Morphir.IR.Path exposing (Path)


gen : Path -> Name -> Type extra -> Maybe File
gen modPath appName appType =
    case appType of
        Reference (FQName [ [ "morphir" ] ] [ [ "s", "d", "k" ], [ "stateful", "app" ] ] [ "stateful", "app" ]) (keyType :: cmdType :: stateType :: eventType :: []) _ ->
            let
                moduleDef : Module
                moduleDef =
                    PortModule
                        { moduleName = [ "Test" ] |> Utils.emptyRangeNode
                        , exposingList = All Range.emptyRange |> Utils.emptyRangeNode
                        }

                imports : List (Node Import)
                imports =
                    [ makeSimpleImport [ "Json", "Encode" ] (Just [ "E" ]) |> Utils.emptyRangeNode
                    , makeSimpleImport [ "Json", "Decode" ] (Just [ "D" ]) |> Utils.emptyRangeNode
                    , makeSimpleImport (modPath |> List.map Name.toTitleCase) Nothing |> Utils.emptyRangeNode
                    ]

                decls : List (Node Declaration)
                decls =
                    [ incomingPortDecl
                    , outgoingPortDecl
                    , mainDecl
                    , incomingMsgTypeAliasDecl keyType stateType cmdType
                    , outgoingMsgTypeAliasDecl keyType stateType eventType
                    , msgDecoderDecl keyType stateType cmdType
                    , decodeMsgDecl
                    , encodeStateEventDecl keyType stateType eventType
                    , initDecl
                    , updateDecl appName
                    , subscriptions
                    ]
                        |> List.map Utils.emptyRangeNode
            in
            File (moduleDef |> Utils.emptyRangeNode) imports decls [] |> Just

        _ ->
            Nothing


makeSimpleImport : ModuleName -> Maybe ModuleName -> Import
makeSimpleImport moduleName moduleAlias =
    Import
        (moduleName |> Utils.emptyRangeNode)
        (moduleAlias |> Maybe.map Utils.emptyRangeNode)
        (Just (All Range.emptyRange |> Utils.emptyRangeNode))


incomingPortDecl : Declaration
incomingPortDecl =
    PortDeclaration
        { name = "stateCommandPort" |> Utils.emptyRangeNode
        , typeAnnotation =
            FunctionTypeAnnotation
                (FunctionTypeAnnotation
                    (Typed
                        (( [ "D" ], "Value" ) |> Utils.emptyRangeNode)
                        []
                        |> Utils.emptyRangeNode
                    )
                    (Typed
                        (( [], "Msg" ) |> Utils.emptyRangeNode)
                        []
                        |> Utils.emptyRangeNode
                    )
                    |> Utils.emptyRangeNode
                )
                (Typed
                    (( [], "Sub" ) |> Utils.emptyRangeNode)
                    [ GenericType "msg" |> Utils.emptyRangeNode ]
                    |> Utils.emptyRangeNode
                )
                |> Utils.emptyRangeNode
        }


outgoingPortDecl : Declaration
outgoingPortDecl =
    PortDeclaration
        { name = "stateEventPort" |> Utils.emptyRangeNode
        , typeAnnotation =
            FunctionTypeAnnotation
                (Typed
                    (( [ "E" ], "Value" ) |> Utils.emptyRangeNode)
                    []
                    |> Utils.emptyRangeNode
                )
                (Typed
                    (( [], "Cmd" ) |> Utils.emptyRangeNode)
                    [ GenericType "msg" |> Utils.emptyRangeNode ]
                    |> Utils.emptyRangeNode
                )
                |> Utils.emptyRangeNode
        }


mainDecl : Declaration
mainDecl =
    Destructuring
        (VarPattern "main" |> Utils.emptyRangeNode)
        (Application
            [ FunctionOrValue [ "Platform" ] "worker" |> Utils.emptyRangeNode
            , RecordExpr
                ([ ( "init" |> Utils.emptyRangeNode
                   , FunctionOrValue [] "init" |> Utils.emptyRangeNode
                   )
                 , ( "update" |> Utils.emptyRangeNode
                   , FunctionOrValue [] "update" |> Utils.emptyRangeNode
                   )
                 , ( "subscriptions" |> Utils.emptyRangeNode
                   , FunctionOrValue [] "subscriptions" |> Utils.emptyRangeNode
                   )
                 ]
                    |> List.map Utils.emptyRangeNode
                )
                |> Utils.emptyRangeNode
            ]
            |> Utils.emptyRangeNode
        )


incomingMsgTypeAliasDecl : Type extra -> Type extra -> Type extra -> Declaration
incomingMsgTypeAliasDecl keyType stateType cmdType =
    let
        msgField : String -> Type extra -> RecordField
        msgField fieldName tpe =
            ( fieldName |> Utils.emptyRangeNode
            , Typed
                (( [], "Maybe" ) |> Utils.emptyRangeNode)
                [ morphirToElmTypeDef tpe |> Utils.emptyRangeNode ]
                |> Utils.emptyRangeNode
            )

        typeAnn : TypeAnnotation
        typeAnn =
            Elm.Syntax.TypeAnnotation.Record
                [ msgField "state" stateType |> Utils.emptyRangeNode
                , msgField "command" cmdType |> Utils.emptyRangeNode
                , msgField "key" keyType |> Utils.emptyRangeNode
                ]
    in
    AliasDeclaration
        { documentation = Nothing
        , name = "Msg" |> Utils.emptyRangeNode
        , generics = []
        , typeAnnotation = typeAnn |> Utils.emptyRangeNode
        }


outgoingMsgTypeAliasDecl : Type extra -> Type extra -> Type extra -> Declaration
outgoingMsgTypeAliasDecl keyType stateType eventType =
    let
        typeAnn : TypeAnnotation
        typeAnn =
            Elm.Syntax.TypeAnnotation.Record
                [ ( "key" |> Utils.emptyRangeNode
                  , morphirToElmTypeDef keyType |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                , ( "state" |> Utils.emptyRangeNode
                  , Typed
                        (( [], "Maybe" ) |> Utils.emptyRangeNode)
                        [ morphirToElmTypeDef stateType |> Utils.emptyRangeNode ]
                        |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                , ( "event" |> Utils.emptyRangeNode
                  , morphirToElmTypeDef eventType |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                ]
    in
    AliasDeclaration
        { documentation = Nothing
        , name = "StateEvent" |> Utils.emptyRangeNode
        , generics = []
        , typeAnnotation = typeAnn |> Utils.emptyRangeNode
        }



--msgDecoderDecl : Type extra -> Type extra -> Maybe Declaration


msgDecoderDecl : Type extra -> Type extra -> Type extra -> Declaration
msgDecoderDecl keyType stateType cmdType =
    let
        morphirTypeDef =
            Frontend.mapDeclarationsToType
                emptySourceFile
                (All Range.emptyRange)
                [ incomingMsgTypeAliasDecl keyType stateType cmdType ]
    in
    case morphirTypeDef of
        Ok (( typeName, typeDef ) :: []) ->
            DecoderGen.typeDefToDecoder emptySourceLocation typeName typeDef

        _ ->
            emptyDecl


decodeMsgDecl : Declaration
decodeMsgDecl =
    let
        func : Function
        func =
            { documentation = Nothing
            , signature = Nothing
            , declaration = funcImpl |> Utils.emptyRangeNode
            }

        caseExpr : Expression
        caseExpr =
            [ FunctionOrValue [ "D" ] "decodeValue"
            , FunctionOrValue [] "decoderMsg"
            , FunctionOrValue [] "val"
            ]
                |> List.map Utils.emptyRangeNode
                |> Application

        okCase : ( Node Pattern, Node Expression )
        okCase =
            ( NamedPattern
                { moduleName = []
                , name = "Ok"
                }
                [ VarPattern "msg" |> Utils.emptyRangeNode ]
                |> Utils.emptyRangeNode
            , FunctionOrValue [] "msg" |> Utils.emptyRangeNode
            )

        errCase : ( Node Pattern, Node Expression )
        errCase =
            ( NamedPattern
                { moduleName = []
                , name = "Err"
                }
                [ AllPattern |> Utils.emptyRangeNode ]
                |> Utils.emptyRangeNode
            , RecordExpr
                [ ( "state" |> Utils.emptyRangeNode
                  , FunctionOrValue [] "Nothing" |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                , ( "command" |> Utils.emptyRangeNode
                  , FunctionOrValue [] "Nothing" |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                , ( "key" |> Utils.emptyRangeNode
                  , FunctionOrValue [] "Nothing" |> Utils.emptyRangeNode
                  )
                    |> Utils.emptyRangeNode
                ]
                |> Utils.emptyRangeNode
            )

        cases : List ( Node Pattern, Node Expression )
        cases =
            [ okCase, errCase ]

        caseBlock : CaseBlock
        caseBlock =
            { expression = caseExpr |> Utils.emptyRangeNode
            , cases = cases
            }

        funcImpl : FunctionImplementation
        funcImpl =
            { name = "decodeMsg" |> Utils.emptyRangeNode
            , arguments = [ "val" |> VarPattern |> Utils.emptyRangeNode ]
            , expression = CaseExpression caseBlock |> Utils.emptyRangeNode
            }
    in
    FunctionDeclaration func


encodeStateEventDecl : Type extra -> Type extra -> Type extra -> Declaration
encodeStateEventDecl keyType stateType eventType =
    let
        morphirTypeDef =
            Frontend.mapDeclarationsToType
                emptySourceFile
                (All Range.emptyRange)
                [ outgoingMsgTypeAliasDecl keyType stateType eventType ]
    in
    case morphirTypeDef of
        Ok (( typeName, typeDef ) :: []) ->
            EncoderGen.typeDefToEncoder emptySourceLocation typeName typeDef

        _ ->
            emptyDecl


initDecl : Declaration
initDecl =
    let
        func : Function
        func =
            { documentation = Nothing
            , signature = Nothing
            , declaration = funcImpl |> Utils.emptyRangeNode
            }

        funcImpl : FunctionImplementation
        funcImpl =
            { name = "init" |> Utils.emptyRangeNode
            , arguments = [ AllPattern |> Utils.emptyRangeNode ]
            , expression =
                TupledExpression
                    [ UnitExpr |> Utils.emptyRangeNode
                    , FunctionOrValue [ "Cmd" ] "none" |> Utils.emptyRangeNode
                    ]
                    |> Utils.emptyRangeNode
            }
    in
    FunctionDeclaration func


updateDecl : Name -> Declaration
updateDecl appName =
    let
        func : Function
        func =
            { documentation = Nothing
            , signature = Nothing
            , declaration = funcImpl |> Utils.emptyRangeNode
            }

        funcImpl : FunctionImplementation
        funcImpl =
            { name = "update" |> Utils.emptyRangeNode
            , arguments =
                [ "msg" |> VarPattern |> Utils.emptyRangeNode
                , AllPattern |> Utils.emptyRangeNode
                ]
            , expression = CaseExpression caseBlock |> Utils.emptyRangeNode
            }

        caseBlock : CaseBlock
        caseBlock =
            { expression =
                TupledExpression
                    [ RecordAccess
                        (FunctionOrValue [] "msg" |> Utils.emptyRangeNode)
                        ("command" |> Utils.emptyRangeNode)
                        |> Utils.emptyRangeNode
                    , RecordAccess
                        (FunctionOrValue [] "msg" |> Utils.emptyRangeNode)
                        ("key" |> Utils.emptyRangeNode)
                        |> Utils.emptyRangeNode
                    ]
                    |> Utils.emptyRangeNode
            , cases = cases
            }

        cases : List ( Node Pattern, Node Expression )
        cases =
            [ justCase, nothingCase ]

        justCase : ( Node Pattern, Node Expression )
        justCase =
            ( TuplePattern
                [ NamedPattern
                    { moduleName = []
                    , name = "Just"
                    }
                    [ VarPattern "cmd" |> Utils.emptyRangeNode ]
                    |> Utils.emptyRangeNode
                , NamedPattern
                    { moduleName = []
                    , name = "Just"
                    }
                    [ VarPattern "key" |> Utils.emptyRangeNode ]
                    |> Utils.emptyRangeNode
                ]
                |> Utils.emptyRangeNode
            , justCaseExpr |> Utils.emptyRangeNode
            )

        justCaseExpr : Expression
        justCaseExpr =
            LetExpression
                { declarations =
                    [ LetDestructuring
                        (TuplePattern
                            [ VarPattern "nextKey" |> Utils.emptyRangeNode
                            , VarPattern "nextState" |> Utils.emptyRangeNode
                            , VarPattern "event" |> Utils.emptyRangeNode
                            ]
                            |> Utils.emptyRangeNode
                        )
                        (letExpr |> Utils.emptyRangeNode)
                        |> Utils.emptyRangeNode
                    ]
                , expression = inExpr |> Utils.emptyRangeNode
                }

        letExpr : Expression
        letExpr =
            [ RecordAccess
                (FunctionOrValue [] (appName |> Name.toCamelCase) |> Utils.emptyRangeNode)
                ("businessLogic" |> Utils.emptyRangeNode)
            , FunctionOrValue [] "key"
            , RecordAccess
                (FunctionOrValue [] "msg" |> Utils.emptyRangeNode)
                ("state" |> Utils.emptyRangeNode)
            , FunctionOrValue [] "cmd"
            ]
                |> List.map Utils.emptyRangeNode
                |> Application

        inExpr : Expression
        inExpr =
            TupledExpression
                [ UnitExpr |> Utils.emptyRangeNode
                , Application
                    [ FunctionOrValue [] "stateEventPort" |> Utils.emptyRangeNode
                    , Application
                        [ FunctionOrValue [] "encodeStateEvent" |> Utils.emptyRangeNode
                        , RecordExpr
                            [ ( "key" |> Utils.emptyRangeNode
                              , FunctionOrValue [] "nextKey" |> Utils.emptyRangeNode
                              )
                                |> Utils.emptyRangeNode
                            , ( "state" |> Utils.emptyRangeNode
                              , FunctionOrValue [] "nextState" |> Utils.emptyRangeNode
                              )
                                |> Utils.emptyRangeNode
                            , ( "event" |> Utils.emptyRangeNode
                              , FunctionOrValue [] "event" |> Utils.emptyRangeNode
                              )
                                |> Utils.emptyRangeNode
                            ]
                            |> Utils.emptyRangeNode
                        ]
                        |> Utils.emptyRangeNode
                        |> ParenthesizedExpression
                        |> Utils.emptyRangeNode
                    ]
                    |> Utils.emptyRangeNode
                ]

        nothingCase : ( Node Pattern, Node Expression )
        nothingCase =
            ( AllPattern |> Utils.emptyRangeNode
            , TupledExpression
                [ UnitExpr |> Utils.emptyRangeNode
                , FunctionOrValue [ "Cmd" ] "none" |> Utils.emptyRangeNode
                ]
                |> Utils.emptyRangeNode
            )
    in
    FunctionDeclaration func


subscriptions : Declaration
subscriptions =
    let
        func : Function
        func =
            { documentation = Nothing
            , signature = Nothing
            , declaration = funcImpl |> Utils.emptyRangeNode
            }

        funcImpl : FunctionImplementation
        funcImpl =
            { name = "subscriptions" |> Utils.emptyRangeNode
            , arguments = [ AllPattern |> Utils.emptyRangeNode ]
            , expression =
                Application
                    [ FunctionOrValue [] "stateCommandPort" |> Utils.emptyRangeNode
                    , FunctionOrValue [] "decodeMsg" |> Utils.emptyRangeNode
                    ]
                    |> Utils.emptyRangeNode
            }
    in
    FunctionDeclaration func


morphirToElmTypeDef : Type extra -> TypeAnnotation
morphirToElmTypeDef tpe =
    case tpe of
        Variable name _ ->
            name |> Name.toCamelCase |> GenericType

        Reference (FQName _ _ [ "bool" ]) [] _ ->
            Typed (( [], "Bool" ) |> Utils.emptyRangeNode) []

        Reference (FQName _ _ [ "int" ]) [] _ ->
            Typed (( [], "Int" ) |> Utils.emptyRangeNode) []

        Reference (FQName _ _ [ "float" ]) [] _ ->
            Typed (( [], "Float" ) |> Utils.emptyRangeNode) []

        Reference (FQName _ _ [ "string" ]) [] _ ->
            Typed (( [], "String" ) |> Utils.emptyRangeNode) []

        Reference (FQName _ modPath tpeName) types _ ->
            let
                moduleName : ModuleName
                moduleName =
                    modPath |> List.map Name.toTitleCase

                typeName : String
                typeName =
                    Name.toTitleCase tpeName

                innerTypes : List (Node TypeAnnotation)
                innerTypes =
                    types
                        |> List.map morphirToElmTypeDef
                        |> List.map Utils.emptyRangeNode
            in
            Typed
                (( moduleName, typeName ) |> Utils.emptyRangeNode)
                innerTypes

        Morphir.IR.Advanced.Type.Record fields _ ->
            let
                morphirToElmField : Field extra -> ( Node String, Node TypeAnnotation )
                morphirToElmField field =
                    ( Name.toCamelCase field.name |> Utils.emptyRangeNode
                    , field.tpe |> morphirToElmTypeDef |> Utils.emptyRangeNode
                    )

                recordDef : RecordDefinition
                recordDef =
                    fields
                        |> List.map morphirToElmField
                        |> List.map Utils.emptyRangeNode
            in
            Elm.Syntax.TypeAnnotation.Record recordDef

        _ ->
            Elm.Syntax.TypeAnnotation.Unit


emptySourceFile : SourceFile
emptySourceFile =
    { path = ""
    , content = ""
    }


emptySourceLocation : SourceLocation
emptySourceLocation =
    { source = emptySourceFile
    , range = emptyContentRange
    }


emptyContentRange : ContentRange
emptyContentRange =
    { start = emptyContentLocation
    , end = emptyContentLocation
    }


emptyContentLocation : ContentLocation
emptyContentLocation =
    { row = 0
    , column = 0
    }



-- TODO: Remove below, just using for testing


emptyDecl : Declaration
emptyDecl =
    FunctionDeclaration
        emptyFuncDecl


emptyFuncDecl : Function
emptyFuncDecl =
    { documentation = Nothing
    , signature = Nothing
    , declaration = emptyFuncImpl |> Utils.emptyRangeNode
    }


emptyFuncImpl : FunctionImplementation
emptyFuncImpl =
    { name = "placeholder" |> Utils.emptyRangeNode
    , arguments = []
    , expression = UnitExpr |> Utils.emptyRangeNode
    }


test : Type ()
test =
    Reference
        (FQName [ [ "morphir" ] ] [ [ "s", "d", "k" ], [ "stateful", "app" ] ] [ "stateful", "app" ])
        [ Reference
            (FQName [] [ [ "morphir" ], [ "sdk" ] ] [ "Int" ])
            []
            ()
        , Reference
            (FQName [] [ [ "morphir" ], [ "sdk" ] ] [ "Int" ])
            []
            ()
        , Reference
            (FQName [] [ [ "morphir" ], [ "sdk" ] ] [ "Int" ])
            []
            ()
        , Reference
            (FQName [] [ [ "morphir" ], [ "sdk" ] ] [ "Int" ])
            []
            ()
        ]
        ()


testRun : Maybe String
testRun =
    gen [ [ "morphir" ], [ "elm" ], [ "backend" ], [ "codec" ], [ "dapr", "example" ] ] (Name.fromString "app") test
        |> Maybe.map Elm.Writer.writeFile
        |> Maybe.map Elm.Writer.write
