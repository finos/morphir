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


module Morphir.Elm.Backend.Dapr.StatefulApp exposing (..)

import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing(..))
import Elm.Syntax.Expression exposing (CaseBlock, Expression(..), Function, FunctionImplementation, LetDeclaration(..))
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module exposing (Module(..))
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node exposing (Node)
import Elm.Syntax.Pattern exposing (Pattern(..))
import Elm.Syntax.Range as Range
import Elm.Syntax.Signature exposing (Signature)
import Elm.Syntax.TypeAnnotation exposing (RecordDefinition, RecordField, TypeAnnotation(..))
import Elm.Writer
import Morphir.Elm.Backend.Codec.DecoderGen as DecoderGen
import Morphir.Elm.Backend.Codec.EncoderGen as EncoderGen
import Morphir.Elm.Backend.Utils as Utils
import Morphir.Elm.Frontend as Frontend exposing (ContentLocation, ContentRange, SourceFile, SourceLocation)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.FQName exposing (fQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Definition(..), Field, Type(..), eraseAttributes)


gen : Path -> Name -> Type () -> List ( Name, AccessControlled (Documented (Type.Definition ())) ) -> Maybe File
gen fullAppPath appName appType otherTypeDefs =
    case appType of
        Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "stateful", "app" ] ], [ "stateful", "app" ] ) (keyType :: cmdType :: stateType :: eventType :: []) ->
            let
                moduleDef : Module
                moduleDef =
                    PortModule
                        { moduleName = [ "Main" ] |> Utils.emptyRangeNode
                        , exposingList = All Range.emptyRange |> Utils.emptyRangeNode
                        }

                imports : List (Node Import)
                imports =
                    [ makeSimpleImport [ "Json", "Encode" ] (Just [ "E" ]) |> Utils.emptyRangeNode
                    , makeSimpleImport [ "Json", "Decode" ] (Just [ "D" ]) |> Utils.emptyRangeNode
                    , makeSimpleImport (fullAppPath |> List.map Name.toTitleCase) Nothing |> Utils.emptyRangeNode
                    ]

                innerDecoders : List Declaration
                innerDecoders =
                    otherTypeDefs
                        |> List.map (\( tName, tDef ) -> DecoderGen.typeDefToDecoder tName tDef)

                innerEncoders : List Declaration
                innerEncoders =
                    otherTypeDefs
                        |> List.map (\( tName, tDef ) -> EncoderGen.typeDefToEncoder tName tDef)

                decls : List (Node Declaration)
                decls =
                    ([ incomingPortDecl
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
                        ++ innerDecoders
                        ++ innerEncoders
                    )
                        |> List.map Utils.emptyRangeNode
            in
            File
                (moduleDef |> Utils.emptyRangeNode)
                imports
                decls
                []
                |> Just

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
                        (( [], "msg" ) |> Utils.emptyRangeNode)
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


incomingMsgTypeAliasDecl : Type () -> Type () -> Type () -> Declaration
incomingMsgTypeAliasDecl keyType stateType cmdType =
    let
        msgField : String -> Type () -> RecordField
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


outgoingMsgTypeAliasDecl : Type () -> Type () -> Type () -> Declaration
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


msgDecoderDecl : Type () -> Type () -> Type () -> Declaration
msgDecoderDecl keyType stateType cmdType =
    let
        morphirTypeDef : Result Frontend.Errors (List ( Name, AccessControlled (Documented (Definition SourceLocation)) ))
        morphirTypeDef =
            Frontend.mapDeclarationsToType
                emptySourceFile
                (All Range.emptyRange)
                [ incomingMsgTypeAliasDecl keyType stateType cmdType ]
    in
    case morphirTypeDef of
        Ok (( typeName, typeDef ) :: []) ->
            DecoderGen.typeDefToDecoder
                typeName
                (typeDef |> AccessControlled.map (Documented.map eraseAttributes))

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


encodeStateEventDecl : Type () -> Type () -> Type () -> Declaration
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
            EncoderGen.typeDefToEncoder typeName (typeDef |> AccessControlled.map (Documented.map eraseAttributes))

        _ ->
            emptyDecl


initDecl : Declaration
initDecl =
    let
        func : Function
        func =
            { documentation = Nothing
            , signature = funcSignature |> Utils.emptyRangeNode |> Just
            , declaration = funcImpl |> Utils.emptyRangeNode
            }

        funcName : String
        funcName =
            "init"

        funcSignature : Signature
        funcSignature =
            { name = funcName |> Utils.emptyRangeNode
            , typeAnnotation =
                FunctionTypeAnnotation
                    (Elm.Syntax.TypeAnnotation.Unit |> Utils.emptyRangeNode)
                    (Elm.Syntax.TypeAnnotation.Tupled
                        ([ Elm.Syntax.TypeAnnotation.Unit
                         , Elm.Syntax.TypeAnnotation.Typed
                            (( [], "Cmd" ) |> Utils.emptyRangeNode)
                            ([ Elm.Syntax.TypeAnnotation.Typed
                                (( [], "Msg" ) |> Utils.emptyRangeNode)
                                []
                             ]
                                |> List.map Utils.emptyRangeNode
                            )
                         ]
                            |> List.map Utils.emptyRangeNode
                        )
                        |> Utils.emptyRangeNode
                    )
                    |> Utils.emptyRangeNode
            }

        funcImpl : FunctionImplementation
        funcImpl =
            { name = funcName |> Utils.emptyRangeNode
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


morphirToElmTypeDef : Type () -> TypeAnnotation
morphirToElmTypeDef tpe =
    case tpe of
        Variable _ name ->
            name |> Name.toCamelCase |> GenericType

        Reference _ ( _, _, [ "bool" ] ) [] ->
            Typed (( [], "Bool" ) |> Utils.emptyRangeNode) []

        Reference _ ( _, _, [ "int" ] ) [] ->
            Typed (( [], "Int" ) |> Utils.emptyRangeNode) []

        Reference _ ( _, _, [ "float" ] ) [] ->
            Typed (( [], "Float" ) |> Utils.emptyRangeNode) []

        Reference _ ( _, _, [ "string" ] ) [] ->
            Typed (( [], "String" ) |> Utils.emptyRangeNode) []

        Reference _ ( pkgPath, modPath, tpeName ) types ->
            let
                moduleName : ModuleName
                moduleName =
                    pkgPath ++ modPath |> List.map Name.toTitleCase

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

        Type.Record _ fields ->
            let
                morphirToElmField : Field () -> ( Node String, Node TypeAnnotation )
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
    Reference ()
        ( [ [ "morphir" ] ], [ [ "s", "d", "k" ], [ "stateful", "app" ] ], [ "stateful", "app" ] )
        [ Reference ()
            ( [], [ [ "morphir" ], [ "sdk" ] ], [ "Int" ] )
            []
        , Reference ()
            ( [], [ [ "morphir" ], [ "sdk" ] ], [ "Int" ] )
            []
        , Reference ()
            ( [], [ [ "morphir" ], [ "sdk" ] ], [ "Int" ] )
            []
        , Reference ()
            ( [], [ [ "morphir" ], [ "sdk" ] ], [ "Int" ] )
            []
        ]


testRun : Maybe String
testRun =
    gen [ [ "morphir" ], [ "elm" ], [ "backend" ], [ "codec" ], [ "dapr", "example" ] ] (Name.fromString "app") test []
        |> Maybe.map Elm.Writer.writeFile
        |> Maybe.map Elm.Writer.write
