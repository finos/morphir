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


module SlateX.DevBot.Java.ToDoc exposing (..)


import SlateX.DevBot.Source exposing (..)
import SlateX.DevBot.Java.Ast exposing (..)
import SlateX.DevBot.Java.Options exposing (Options)



compilationUnitToDoc : Options -> CompilationUnit -> String
compilationUnitToDoc opt cu =
    String.join newLine
        [ cu.packageDecl
            |> Maybe.map
                (\pd ->
                    ("package " ++ dotSep pd.qualifiedName ++ semi)
                )
            |> Maybe.withDefault empty
        , empty
        , cu.imports
            |> List.map
                (\importDecl ->
                    case importDecl of
                        Import name False ->
                            "import " ++ dotSep name ++ semi

                        Import name True ->
                            "import " ++ dotSep name ++ ".*" ++ semi

                        StaticImport name False ->
                            "import static " ++ dotSep name ++ semi

                        StaticImport name True ->
                            "import static " ++ dotSep name ++ ".*" ++ semi
                )
            |> String.join newLine
        , empty
        , cu.typeDecls
            |> List.map (typeDeclarationToDoc opt)
            |> String.join (newLine ++ newLine)
        ]


typeDeclarationToDoc : Options -> TypeDeclaration -> String
typeDeclarationToDoc opt typeDecl =
    case typeDecl of
        Class decl ->
            let
                implements =
                    case decl.implements of
                        [] ->
                            empty

                        typeList ->
                            "implements " ++
                                (typeList
                                    |> List.map (typeToDoc opt)
                                    |> String.join ", "
                                ) ++ space    

                members = 
                    decl.members
                        |> List.map (\member -> memberDeclToDoc opt decl.name member ++ newLine)
                        |> statementBlock opt
            in
            modifiersToDoc opt decl.modifiers ++ "class " ++ decl.name ++ space ++ implements ++ members

        Interface decl ->
            let
                members = 
                    decl.members
                        |> List.map (\member -> memberDeclToDoc opt decl.name member ++ newLine)
                        |> statementBlock opt

                extends =
                    case decl.extends of
                        [] ->
                            empty
                        typeList ->
                            " extends " ++
                                (typeList
                                    |> List.map (typeToDoc opt)
                                    |> String.join ", "
                                ) ++ space

            in
            modifiersToDoc opt decl.modifiers ++ "interface " ++ decl.name ++ extends ++ members

        Enum decl ->
            let
                values = 
                    decl.values
                        |> String.join ", "
                        |> List.singleton
                        |> statementBlock opt
            in            
            modifiersToDoc opt decl.modifiers ++ "enum " ++ decl.name ++ values


memberDeclToDoc : Options -> Identifier -> MemberDecl -> String
memberDeclToDoc opt typeName member =
    case member of
        Field decl ->
            modifiersToDoc opt decl.modifiers ++ typeToDoc opt decl.tpe ++ space ++ decl.name ++ semi

        Constructor decl ->
            let 
                body =
                    decl.body
                        |> Maybe.map (statementsToDoc opt)
                        |> Maybe.withDefault empty
            in
            modifiersToDoc opt decl.modifiers ++ typeName ++ argsToDoc opt decl.args ++ space ++ body

        Method decl ->
            if List.isEmpty decl.body then
                modifiersToDoc opt decl.modifiers ++ typeParamsToDoc opt decl.typeParams ++ typeToDoc opt decl.returnType ++ space ++ decl.name ++ argsToDoc opt decl.args ++ semi
            else        
                modifiersToDoc opt decl.modifiers ++ typeParamsToDoc opt decl.typeParams ++ typeToDoc opt decl.returnType ++ space ++ decl.name ++ argsToDoc opt decl.args ++ space ++ statementsToDoc opt decl.body


typeParamsToDoc : Options -> List Identifier -> String
typeParamsToDoc opt params =
    if List.isEmpty params then
        empty
    else
        "<" ++ (params |> String.join ", ") ++ "> "


argsToDoc : Options -> List ( Identifier, Type ) -> String
argsToDoc opt args =
    args
        |> List.map
              (\( name, tpe ) ->
                  typeToDoc opt tpe ++ space ++ name
              )
        |> argumentBlock opt


statementsToDoc : Options -> List Exp -> String
statementsToDoc opt statements =
    statements
        |> List.map
            (\exp ->
                case exp of
                    IfElse _ _ _ ->
                        expToDoc opt exp

                    _ ->       
                        expToDoc opt exp ++ semi
            )
        |> statementBlock opt


expToDoc : Options -> Exp -> String
expToDoc opt topExp =
    case topExp of
        VariableDecl modifiers tpe name maybeInitialValue ->
            let
                initValue =
                    case maybeInitialValue of
                        Just initialValue ->
                            " = " ++ expToDoc opt initialValue

                        Nothing ->
                            empty
            in    
            modifiersToDoc opt modifiers ++ typeToDoc opt tpe ++ space ++ name ++ initValue

        Assign lhs rhs ->
            expToDoc opt lhs ++ " = " ++ expToDoc opt rhs

        Return exp ->
            "return " ++ expToDoc opt exp

        Throw exp ->
            "throw " ++ expToDoc opt exp

        Statements exps ->
            exps
                |> List.map (expToDoc opt)
                |> String.join newLine

        BooleanLit bool ->
            if bool then
                "true"
            else 
                "false"

        StringLit string ->
            "\"" ++ string ++ "\""

        IntLit int ->
            String.fromInt int

        Variable name ->
            name

        This ->
            "this"

        Select on name ->
            expToDoc opt on ++ "." ++ name

        BinOp left op right ->
            let
                maybeParens exp isLeft =
                    case exp of
                        BinOp nestedLeft nestedOp nestedRight ->
                            if nestedOp == op && isAssociative op then
                                expToDoc opt exp
                            else if precedence nestedOp > precedence op then
                                expToDoc opt exp
                            else
                                expToDoc opt exp |> parens    

                        _ ->
                            expToDoc opt exp
            in
            maybeParens left True ++ space ++ op ++ space ++ maybeParens right False

        ValueRef qualifiedName ->
            dotSep qualifiedName

        Apply exp args ->
            expToDoc opt exp ++ 
                (args
                    |> List.map (expToDoc opt)
                    |> argumentBlock opt
                )

        Lambda args body ->
            (args |> argumentBlock opt) ++ " -> " ++ expToDoc opt body

        Ternary cond whenTrue whenFalse ->
            (expToDoc opt cond |> parens) ++ " ? " ++ (expToDoc opt whenTrue |> parens) ++ " : " ++ (expToDoc opt whenFalse |> parens)

        IfElse cond whenTrue whenFalse ->
            let
                flatten exp soFar =
                    case exp of
                        [ IfElse c wTrue wFalse ] ->
                            flatten wFalse (soFar ++ [ ( c, wTrue ) ])

                        other ->
                            ( soFar, other )

                ( cases, defaultCase ) =
                    flatten [ topExp ] []

                caseSection =
                    cases
                        |> List.map
                            (\( c, wTrue ) ->
                                "if (" ++ expToDoc opt c ++ ") " ++ statementsToDoc opt wTrue
                            )
                        |> String.join " else "
            in
            caseSection ++ " else " ++ statementsToDoc opt defaultCase

        ConstructorRef typeRef ->
            "new " ++ dotSep typeRef

        UnaryOp op exp ->
            op ++ expToDoc opt exp |> parens

        Cast tpe exp ->
            (typeToDoc opt tpe |> parens) ++ expToDoc opt exp

        Null ->
            "null"                


modifiersToDoc : Options -> List Modifier -> String
modifiersToDoc opt modifiers =
    modifiers
        |> List.map (modifierToDoc opt)
        |> List.map (\m -> m ++ space)
        |> String.concat


modifierToDoc : Options -> Modifier -> String
modifierToDoc opt modifier =
    case modifier of
        Public -> "public"
        Private -> "private"
        Static -> "static"
        Abstract -> "abstract"
        Final -> "final"


typeToDoc : Options -> Type -> String
typeToDoc opt tpe =
    case tpe of
        Void ->
            "void"

        TypeVar name ->
            name    

        TypeRef qualifiedName ->
            dotSep qualifiedName

        TypeConst qualifiedName [] ->
            dotSep qualifiedName

        TypeConst qualifiedName args ->
            dotSep qualifiedName ++ "<" ++ (args |> List.map (typeToDoc opt) |> String.join ", ") ++ ">"

        Predicate arg ->
            "java.util.function.Predicate<" ++ typeToDoc opt arg ++ ">"

        Function argType returnType ->
            "java.util.function.Function<" ++ typeToDoc opt argType ++ ", " ++ typeToDoc opt returnType ++ ">"
                

argumentBlock : Options -> List String -> String
argumentBlock opt args =
    if List.isEmpty args then
        "()"
    else
        "(" ++ (args |> String.join ", ") ++ ")"


statementBlock : Options -> List String -> String
statementBlock opt statements =
    "{\n" ++ indentLines opt.indent statements ++ "\n}"


precedence : String -> Int
precedence op =
    if List.member op [ "*", "/", "%" ] then
        12
    else if List.member op [ "+", "-" ] then
        11
    else if List.member op [ "<", "<=", ">", ">=" ] then
        9
    else if List.member op [ "==", "!=" ] then
        8
    else if List.member op [ "&&" ] then
        4
    else if List.member op [ "||" ] then
        3
    else
        0


isAssociative : String -> Bool
isAssociative op =
    not (List.member op [ "<", "<=", ">", ">=" ])
