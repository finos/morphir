module SlateX.DevBot.Java.Ast.Collect exposing (..)


import SlateX.DevBot.Java.Ast exposing (..)


type alias Collect a =
    { exp : Exp -> List a
    , memberDecl : MemberDecl -> List a
    , typeExp : Type -> List a
    , typeDeclaration : TypeDeclaration -> List a
    }


collector : Collect a
collector =
    { exp = \exp -> []
    , memberDecl = \memberDecl -> []
    , typeExp = \typeExp -> []
    , typeDeclaration = \typeDeclaration -> []
    }


collectTypeDeclaration : Collect a -> TypeDeclaration -> List a
collectTypeDeclaration collect typeDeclaration =
    case collect.typeDeclaration typeDeclaration of
        [] ->
            case typeDeclaration of
                Class decl ->
                    [ decl.extends
                        |> Maybe.map (collectType collect)
                        |> Maybe.withDefault []
                    , decl.implements
                        |> List.concatMap (collectType collect)
                    , decl.members
                        |> List.concatMap (collectMemberDecl collect)
                    ] |> List.concat

                Interface decl ->
                    [ decl.extends
                        |> List.concatMap (collectType collect)
                    , decl.members
                        |> List.concatMap (collectMemberDecl collect)
                    ] |> List.concat

                Enum decl ->
                    decl.implements
                        |> List.concatMap (collectType collect)

        result ->
            result


collectMemberDecl : Collect a -> MemberDecl -> List a
collectMemberDecl collect memberDecl =
    case collect.memberDecl memberDecl of
        [] ->
            case memberDecl of
                Constructor decl ->
                    [ decl.args
                        |> List.concatMap
                            (\( name, tpe ) ->
                                collectType collect tpe
                            )
                    , decl.body
                        |> Maybe.map (List.concatMap (collectExp collect))
                        |> Maybe.withDefault []
                    ] |> List.concat

                Method decl ->
                    [ decl.returnType
                        |> collectType collect
                    , decl.args
                        |> List.concatMap
                            (\( name, tpe ) ->
                                collectType collect tpe
                            )
                    , decl.body
                        |> List.concatMap (collectExp collect)
                    ] |> List.concat

                _ ->
                    []

        result ->
            result


collectType : Collect a -> Type -> List a
collectType collect typeExp =
    case collect.typeExp typeExp of
        [] ->
            case typeExp of
                TypeConst qualifiedIdentifier args ->
                    args
                        |> List.concatMap (collectType collect)

                _ ->
                    []

        result ->
            result


collectExp : Collect a -> Exp -> List a
collectExp collect topExp =
    case collect.exp topExp of
        [] ->
            case topExp of
                Assign to from ->
                    [ collectExp collect to
                    , collectExp collect from
                    ] |> List.concat

                Return exp ->
                    collectExp collect exp

                Throw exp ->
                    collectExp collect exp

                Select exp id ->
                    collectExp collect exp

                BinOp left op right ->
                    [ collectExp collect left
                    , collectExp collect right
                    ] |> List.concat

                Apply fun args ->
                    [ collectExp collect fun
                    , args
                        |> List.concatMap (collectExp collect)
                    ] |> List.concat

                Lambda argNames body ->
                    collectExp collect body

                IfElse cond whenTrue whenFalse ->
                    [ collectExp collect cond
                    , whenTrue |> List.concatMap (collectExp collect)
                    , whenFalse |> List.concatMap (collectExp collect)
                    ] |> List.concat

                _ ->
                    []

        result ->
            result


