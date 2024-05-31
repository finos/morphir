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


module SlateX.DevBot.Java.Ast.Rewrite exposing (..)


import SlateX.DevBot.Java.Ast exposing (..)


type alias Rewrite =
    { exp : Exp -> Maybe Exp
    , memberDecl : MemberDecl -> Maybe MemberDecl
    , typeExp : Type -> Maybe Type
    , typeDeclaration : TypeDeclaration -> Maybe TypeDeclaration
    }


rewriter : Rewrite
rewriter =
    { exp = \_ -> Nothing
    , memberDecl = \_ -> Nothing
    , typeExp = \_ -> Nothing
    , typeDeclaration = \_ -> Nothing
    }


rewriteTypeDeclaration : Rewrite -> TypeDeclaration -> TypeDeclaration
rewriteTypeDeclaration rewrite typeDeclaration =
    case rewrite.typeDeclaration typeDeclaration of
        Nothing ->
            case typeDeclaration of
                Class decl ->
                    Class
                        { decl
                            | extends = decl.extends
                                |> Maybe.map (rewriteType rewrite)
                            , implements = decl.implements
                                |> List.map (rewriteType rewrite)
                            , members = decl.members
                                |> List.map (rewriteMemberDecl rewrite)
                        }

                Interface decl ->
                    Interface
                    { decl
                        | extends = decl.extends
                            |> List.map (rewriteType rewrite)
                        , members = decl.members
                            |> List.map (rewriteMemberDecl rewrite)
                    }

                Enum decl ->
                    Enum
                        { decl
                            | implements = decl.implements
                                |> List.map (rewriteType rewrite)
                        }

        Just result ->
            result


rewriteMemberDecl : Rewrite -> MemberDecl -> MemberDecl
rewriteMemberDecl rewrite memberDecl =
    case rewrite.memberDecl memberDecl of
        Nothing ->
            case memberDecl of
                Constructor decl ->
                    Constructor
                        { decl
                            | args = decl.args
                                |> List.map
                                    (\( name, tpe ) ->
                                        ( name, rewriteType rewrite tpe )
                                    )
                            , body = 
                                decl.body
                                    |> Maybe.map (List.map (rewriteExp rewrite))
                        }

                Method decl ->
                    Method
                        { decl
                            | returnType = decl.returnType
                                |> rewriteType rewrite
                            , args = decl.args
                                |> List.map
                                    (\( name, tpe ) ->
                                        ( name, rewriteType rewrite tpe )
                                    )
                            , body = decl.body
                                |> List.map (rewriteExp rewrite)
                        }

                _ ->
                    memberDecl

        Just result ->
            result


rewriteType : Rewrite -> Type -> Type
rewriteType rewrite typeExp =
    case rewrite.typeExp typeExp of
        Nothing ->
            case typeExp of
                TypeConst qualifiedIdentifier args ->
                    TypeConst
                        qualifiedIdentifier
                        (args |> List.map (rewriteType rewrite))

                _ ->
                    typeExp

        Just result ->
            result


rewriteExp : Rewrite -> Exp -> Exp
rewriteExp rewrite topExp =
    case rewrite.exp topExp of
        Nothing ->
            case topExp of
                Assign to from ->
                    Assign
                        (rewriteExp rewrite to)
                        (rewriteExp rewrite from)

                Return exp ->
                    Return (rewriteExp rewrite exp)

                Throw exp ->
                    Throw (rewriteExp rewrite exp)

                Select exp id ->
                    Select (rewriteExp rewrite exp) id

                BinOp left op right ->
                    BinOp (rewriteExp rewrite left) op (rewriteExp rewrite right)

                Apply fun args ->
                    Apply
                        (rewriteExp rewrite fun)
                        (args |> List.map (rewriteExp rewrite))

                Lambda argNames body ->
                    Lambda argNames (rewriteExp rewrite body)

                IfElse cond whenTrue whenFalse ->
                    IfElse
                        (rewriteExp rewrite cond)
                        (whenTrue |> List.map (rewriteExp rewrite))
                        (whenFalse |> List.map (rewriteExp rewrite))

                _ ->
                    topExp

        Just result ->
            result


