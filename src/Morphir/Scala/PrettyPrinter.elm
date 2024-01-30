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


module Morphir.Scala.PrettyPrinter exposing (Options, mapCompilationUnit, mapMemberDecl)

{-| Pretty-printer for the Scala AST.

@docs Options, mapCompilationUnit, mapMemberDecl

-}

import Decimal
import Morphir.File.SourceCode exposing (Doc, concat, dot, dotSep, empty, indent, indentLines, newLine, parens, space)
import Morphir.IR.Name as Name
import Morphir.Scala.AST exposing (..)
import Morphir.Scala.Common exposing (prefixKeyword, prefixKeywords)


{-| -}
type alias Options =
    { indentDepth : Int
    , maxWidth : Int
    }


mapDocumented : (a -> Doc) -> Documented a -> Doc
mapDocumented valueToDoc documented =
    case documented.doc of
        Just doc ->
            concat
                [ concat [ "/** ", doc, newLine ]
                , concat [ "*/", newLine ]
                , valueToDoc documented.value
                ]

        Nothing ->
            valueToDoc documented.value


mapAnnotated : (a -> Doc) -> Annotated a -> Doc
mapAnnotated valueToDoc annotated =
    case annotated.annotations of
        [] ->
            valueToDoc annotated.value

        annotations ->
            concat
                [ dotSep annotations
                , newLine
                , valueToDoc annotated.value
                , newLine
                ]


{-| -}
mapCompilationUnit : Options -> CompilationUnit -> Doc
mapCompilationUnit opt cu =
    concat
        [ concat [ "package ", dotSep (prefixKeywords cu.packageDecl), newLine ]
        , newLine
        , mapImports cu.imports
        , cu.typeDecls
            |> List.map (mapDocumented (mapAnnotated (mapTypeDecl opt)))
            |> String.join (newLine ++ newLine)
        ]

mapImports : List ImportDecl -> Doc
mapImports imports =
    case imports of
        [] -> 
            ""
        importsList ->
            (importsList |> List.map mapImport) ++ [ newLine ]
                |> concat
        

mapImport : ImportDecl -> Doc
mapImport importDecl =
    concat
        [ "import "
        , String.join "." (importDecl.packagePrefix)
        , newLine
        ]

mapTypeDecl : Options -> TypeDecl -> Doc
mapTypeDecl opt typeDecl =
    case typeDecl of
        Trait decl ->
            let
                body =
                    " {"
                        ++ newLine
                        ++ newLine
                        ++ (decl.members
                                |> List.map (mapAnnotated (mapMemberDecl opt))
                                |> List.intersperse (newLine ++ newLine)
                                |> concat
                                |> indent opt.indentDepth
                           )
                        ++ newLine
                        ++ newLine
                        ++ "}"
            in
            mapModifiers decl.modifiers ++ "trait " ++ decl.name ++ mapTypeArgs opt decl.typeArgs ++ mapExtends opt decl.extends ++ body

        Class decl ->
            let
                ctorArgsDoc =
                    case decl.ctorArgs of
                        [] ->
                            empty

                        _ ->
                            decl.ctorArgs
                                |> List.map (mapArgDecls opt)
                                |> concat

                members =
                    case decl.members of
                        [] ->
                            empty

                        _ ->
                            newLine
                                ++ newLine
                                ++ (decl.members
                                        |> List.map (mapAnnotated (mapMemberDecl opt))
                                        |> List.intersperse (newLine ++ newLine)
                                        |> concat
                                        |> indent opt.indentDepth
                                   )
                                ++ newLine
                                ++ newLine

                bodyDoc =
                    decl.body
                        |> List.foldl
                            (\value valDocsSoFar ->
                                valDocsSoFar
                                    ++ newLine
                                    ++ indent opt.indentDepth (mapValue opt value)
                            )
                            empty
            in
            mapModifiers decl.modifiers ++ "class " ++ decl.name ++ mapTypeArgs opt decl.typeArgs ++ ctorArgsDoc ++ mapExtends opt decl.extends ++ "{" ++ members ++ bodyDoc ++ "}"

        Object decl ->
            let
                memberDoc =
                    case decl.members of
                        [] ->
                            empty

                        _ ->
                            newLine
                                ++ newLine
                                ++ (decl.members
                                        |> List.map (mapAnnotated (mapMemberDecl opt))
                                        |> List.intersperse (newLine ++ newLine)
                                        |> concat
                                        |> indent opt.indentDepth
                                   )
                                ++ newLine
                                ++ newLine

                bodyDoc =
                    case decl.body of
                        Just ((Block _ _) as value) ->
                            mapValue opt value

                        Just value ->
                            newLine ++ indent opt.indentDepth (mapValue opt value)

                        Nothing ->
                            empty
            in
            mapModifiers decl.modifiers ++ "object " ++ decl.name ++ mapExtends opt decl.extends ++ "{" ++ memberDoc ++ bodyDoc ++ "}"


{-| Map a member declaration to Doc.
-}
mapMemberDecl : Options -> MemberDecl -> Doc
mapMemberDecl opt memberDecl =
    case memberDecl of
        TypeAlias typeAlias ->
            "type " ++ typeAlias.alias ++ mapTypeArgs opt typeAlias.typeArgs ++ " = " ++ mapType opt typeAlias.tpe

        ValueDecl decl ->
            concat
                [ mapModifiers decl.modifiers
                , "val "
                , mapPattern decl.pattern
                , case decl.valueType of
                    Just tpe ->
                        concat [ ": ", mapType opt tpe ]

                    Nothing ->
                        empty
                , " = "
                , mapValue opt decl.value
                ]

        FunctionDecl decl ->
            let
                modifierDoc =
                    mapModifiers decl.modifiers

                argsDoc =
                    case decl.args of
                        [] ->
                            empty

                        _ ->
                            decl.args
                                |> List.map (mapArgDecls opt)
                                |> concat

                returnTypeDoc =
                    case decl.returnType of
                        Just tpe ->
                            ": " ++ mapType opt tpe

                        Nothing ->
                            empty

                bodyDoc =
                    case decl.body of
                        Just ((Block _ _) as value) ->
                            " = " ++ mapValue opt value

                        Just value ->
                            " =" ++ newLine ++ indent opt.indentDepth (mapValue opt value)

                        Nothing ->
                            empty
            in
            modifierDoc ++ "def " ++ decl.name ++ mapTypeArgs opt decl.typeArgs ++ argsDoc ++ returnTypeDoc ++ bodyDoc

        MemberTypeDecl decl ->
            mapTypeDecl opt decl


mapTypeArgs : Options -> List Type -> Doc
mapTypeArgs opt typeArgs =
    case typeArgs of
        [] ->
            empty

        types ->
            "["
                ++ (types
                        |> List.map (mapType opt)
                        |> List.intersperse ", "
                        |> concat
                   )
                ++ "]"


mapModifiers : List Mod -> Doc
mapModifiers mods =
    case mods of
        [] ->
            empty

        _ ->
            (mods
                |> List.map mapModifier
                |> String.join space
            )
                ++ space


mapModifier : Mod -> Doc
mapModifier mod =
    case mod of
        Sealed ->
            "sealed"

        Final ->
            "final"

        Case ->
            "case"

        Val ->
            "val"

        Package ->
            "package"

        Implicit ->
            "implicit"

        Abstract ->
            "abstract"

        Private maybeScope ->
            case maybeScope of
                Just scope ->
                    concat [ "private[", scope, "]" ]

                Nothing ->
                    "private"


mapExtends : Options -> List Type -> Doc
mapExtends opt types =
    case types of
        [] ->
            empty

        _ ->
            " extends "
                ++ (types
                        |> List.map (mapType opt)
                        |> List.intersperse " with "
                        |> concat
                   )


mapArgDecls : Options -> List ArgDecl -> Doc
mapArgDecls opt argDecls =
    "("
        ++ newLine
        ++ indent opt.indentDepth
            (argDecls
                |> List.map (mapArgDecl opt)
                |> List.intersperse ("," ++ newLine)
                |> concat
            )
        ++ newLine
        ++ ")"


mapArgDecl : Options -> ArgDecl -> Doc
mapArgDecl opt argDecl =
    let
        defaultValueDoc =
            case argDecl.defaultValue of
                Just value ->
                    " = " ++ mapValue opt value

                Nothing ->
                    empty
    in
    mapModifiers argDecl.modifiers ++ prefixKeyword argDecl.name ++ ": " ++ mapType opt argDecl.tpe ++ defaultValueDoc


mapType : Options -> Type -> Doc
mapType opt tpe =
    case tpe of
        TypeVar name ->
            name

        TypeRef path name ->
            dotSep (path ++ [ name ])

        TypeOfValue path ->
            dotSep (path ++ [ "type " ])

        TypeApply ctor args ->
            mapType opt ctor
                ++ "["
                ++ (args
                        |> List.map (mapType opt)
                        |> List.intersperse ", "
                        |> concat
                   )
                ++ "]"

        TupleType elemTypes ->
            parens
                (elemTypes
                    |> List.map (mapType opt)
                    |> List.intersperse ", "
                    |> concat
                )

        StructuralType memberDecls ->
            if List.isEmpty memberDecls then
                "{}"

            else
                concat
                    [ "{ "
                    , memberDecls
                        |> List.map (mapMemberDecl opt)
                        |> List.intersperse "; "
                        |> concat
                    , " }"
                    ]

        FunctionType argType returnType ->
            (case argType of
                TupleType _ ->
                    parens (mapType opt argType)

                FunctionType _ _ ->
                    parens (mapType opt argType)

                _ ->
                    mapType opt argType
            )
                ++ " => "
                ++ mapType opt returnType

        TypeParametrized ctor args params ->
            mapType opt ctor
                ++ newLine
                ++ "["
                ++ (args
                        |> List.map (mapType opt)
                        |> List.intersperse (", " ++ newLine)
                        |> concat
                   )
                ++ "]("
                ++ mapType opt params
                ++ ")"

        CommentedType childType message ->
            mapType opt childType ++ " /* " ++ message ++ " */ "


mapValue : Options -> Value -> Doc
mapValue opt value =
    case value of
        Literal lit ->
            mapLit lit

        Variable name ->
            prefixKeyword name

        Ref path name ->
            dotSep <| prefixKeywords (path ++ [ name ])

        Select targetValue name ->
            mapValue opt targetValue ++ dot ++ prefixKeyword name

        Wildcard ->
            "_"

        Apply funValue argValues ->
            mapValue opt funValue ++ argValueBlock opt argValues
        
        New path name argValues ->
            "new" ++ " " ++ (dotSep <| prefixKeywords (path ++ [ name ])) ++ argValueBlock opt argValues

        UnOp op right ->
            op ++ mapValue opt right

        BinOp left op right ->
            parens (mapValue opt left) ++ " " ++ op ++ " " ++ parens (mapValue opt right)

        Lambda args bodyValue ->
            let
                argDoc ( argName, maybeArgType ) =
                    case maybeArgType of
                        Just argType ->
                            concat [ prefixKeyword argName, ": ", mapType opt argType ]

                        Nothing ->
                            prefixKeyword argName

                argsDoc =
                    parens (args |> List.map argDoc |> String.join ", ")
            in
            parens
                (argsDoc
                    ++ " =>"
                    ++ newLine
                    ++ indent opt.indentDepth (mapValue opt bodyValue)
                )

        Block decls returnValue ->
            let
                declDocs =
                    decls
                        |> List.map (mapMemberDecl opt)

                statements =
                    declDocs ++ [ returnValue |> mapValue opt ]
            in
            statements
                |> List.intersperse empty
                |> statementBlock opt

        MatchCases cases ->
            cases
                |> List.map
                    (\( pattern, caseValue ) ->
                        ( pattern |> mapPattern, caseValue |> mapValue opt )
                    )
                |> matchBlock opt

        Match targetValue casesValue ->
            mapValue opt targetValue ++ " match " ++ mapValue opt casesValue

        IfElse condValue trueValue falseValue ->
            concat
                [ "if "
                , parens (mapValue opt condValue)
                , " "
                , case trueValue of
                    Block _ _ ->
                        mapValue opt trueValue

                    _ ->
                        statementBlock opt [ mapValue opt trueValue ]
                , " else "
                , case falseValue of
                    IfElse _ _ _ ->
                        mapValue opt falseValue

                    Block _ _ ->
                        mapValue opt falseValue

                    _ ->
                        statementBlock opt [ mapValue opt falseValue ]
                ]

        Tuple elemValues ->
            parens
                (elemValues
                    |> List.map (mapValue opt)
                    |> List.intersperse ", "
                    |> concat
                )

        StructuralValue fieldValues ->
            if List.isEmpty fieldValues then
                "new {}"

            else
                concat
                    [ "new {"
                    , newLine
                    , fieldValues
                        |> List.map
                            (\( fieldName, fieldValue ) ->
                                concat [ "def ", fieldName, " = ", mapValue opt fieldValue ]
                            )
                        |> indentLines opt.indentDepth
                    , newLine
                    , "}"
                    ]

        Unit ->
            "{}"

        This ->
            "this"

        CommentedValue childValue message ->
            mapValue opt childValue ++ " /* " ++ message ++ " */ "

        ForComp generators yieldValue ->
            concat
                [ "for {"
                , newLine
                , generators
                    |> List.map
                        (\generator ->
                            case generator of
                                Guard expr ->
                                    concat [ "if ", mapValue opt expr ]

                                Extract pattern expr ->
                                    concat [ mapPattern pattern, " <- ", mapValue opt expr ]

                                Bind pattern expr ->
                                    concat [ mapPattern pattern, " <- ", mapValue opt expr ]
                        )
                    |> indentLines opt.indentDepth
                , newLine
                , "}  yield "
                , mapValue opt yieldValue
                ]

        TypeAscripted nestedValue tpe ->
            concat
                [ "("
                , mapValue opt nestedValue
                , " : "
                , mapType opt tpe
                , ")"
                ]
        Throw exceptionExpr ->
            "throw " ++ (mapValue opt exceptionExpr)


mapPattern : Pattern -> Doc
mapPattern pattern =
    case pattern of
        WildcardMatch ->
            "_"

        NamedMatch name ->
            prefixKeyword name

        AliasedMatch name aliasedPattern ->
            concat [ prefixKeyword name, " @ ", mapPattern aliasedPattern ]

        LiteralMatch lit ->
            mapLit lit

        UnapplyMatch path name argPatterns ->
            let
                argsDoc =
                    case argPatterns of
                        [] ->
                            empty

                        _ ->
                            parens
                                (argPatterns
                                    |> List.map mapPattern
                                    |> List.intersperse ", "
                                    |> concat
                                )
            in
            (dotSep <| prefixKeywords (path ++ [ name ])) ++ argsDoc

        TupleMatch elemPatterns ->
            parens
                (elemPatterns
                    |> List.map mapPattern
                    |> List.intersperse ", "
                    |> concat
                )

        EmptyListMatch ->
            "Nil"

        HeadTailMatch headPattern tailPattern ->
            parens (mapPattern headPattern ++ " :: " ++ mapPattern tailPattern)

        CommentedPattern childPattern message ->
            mapPattern childPattern ++ " /* " ++ message ++ " */ "


mapLit : Lit -> Doc
mapLit lit =
    case lit of
        BooleanLit bool ->
            if bool then
                "true"

            else
                "false"

        CharacterLit char ->
            "'" ++ String.fromChar char ++ "'"

        StringLit string ->
            "\"\"\"" ++ string ++ "\"\"\""

        IntegerLit int ->
            String.fromInt int

        FloatLit float ->
            String.fromFloat float

        DecimalLit decimal ->
            Decimal.toString decimal

        NullLit ->
            "null"


statementBlock : Options -> List String -> Doc
statementBlock opt statements =
    concat
        [ "{"
        , newLine
        , indentLines opt.indentDepth statements
        , newLine
        , "}"
        ]


argValueBlock : Options -> List ArgValue -> Doc
argValueBlock opt argValues =
    let
        mapArgValue (ArgValue name value) =
            case name of
                Just argName ->
                    argName ++ " = " ++ mapValue opt value

                Nothing ->
                    mapValue opt value
    in
    case argValues of
        [ singleArgValue ] ->
            parens (mapArgValue singleArgValue)

        _ ->
            concat
                [ "("
                , newLine
                , indentLines opt.indentDepth
                    (argValues
                        |> List.indexedMap
                            (\index argValue ->
                                if (index + 1) == List.length argValues then
                                    mapArgValue argValue

                                else
                                    concat [ mapArgValue argValue, "," ]
                            )
                    )
                , newLine
                , ")"
                ]


matchBlock : Options -> List ( String, String ) -> Doc
matchBlock opt statements =
    concat
        [ "{"
        , newLine
        , indentLines opt.indentDepth
            (statements
                |> List.map
                    (\( pattern, value ) ->
                        concat
                            [ concat [ "case ", pattern, " => ", newLine ]
                            , indent opt.indentDepth value
                            ]
                    )
            )
        , newLine
        , "}"
        ]
