module Morphir.TypeScript.Backend.ImportRefs exposing (getUniqueImportRefs)

import Morphir.IR.Path exposing (Path)
import Morphir.TypeScript.AST as TS


getUniqueImportRefs : Path -> Path -> TS.TypeDef -> List TS.NamespacePath
getUniqueImportRefs currentPackagePath currentModulePath typeDef =
    typeDef
        |> collectRefsFromTypeDef
        |> List.filter
            (\( packagePath, modulePath ) ->
                packagePath /= currentPackagePath || modulePath /= currentModulePath
            )
        |> List.filter
            (\( packagePath, modulePath ) ->
                packagePath /= [] || modulePath /= []
            )
        |> List.sort
        |> filterUnique


filterUnique : List a -> List a
filterUnique inputList =
    let
        incrementalFilterUnique : a -> List a -> List a
        incrementalFilterUnique element shorterList =
            if List.member element shorterList then
                shorterList

            else
                element :: shorterList
    in
    List.foldr incrementalFilterUnique [] inputList


collectRefsFromTypeDef : TS.TypeDef -> List TS.NamespacePath
collectRefsFromTypeDef typeDef =
    case typeDef of
        TS.Namespace namespace ->
            namespace.content |> List.concatMap collectRefsFromTypeDef

        TS.TypeAlias typeAlias ->
            List.concat
                [ typeAlias.variables |> List.concatMap collectRefsFromTypeExpression
                , typeAlias.typeExpression |> collectRefsFromTypeExpression
                ]

        TS.Interface interface ->
            List.concat
                [ interface.variables |> List.concatMap collectRefsFromTypeExpression
                , interface.fields |> List.concatMap (\( _, typeExp ) -> collectRefsFromTypeExpression typeExp)
                ]

        TS.ImportAlias importAlias ->
            [ importAlias.namespacePath ]


collectRefsFromTypeExpression : TS.TypeExp -> List TS.NamespacePath
collectRefsFromTypeExpression typeExp =
    case typeExp of
        TS.List subTypeExp ->
            subTypeExp |> collectRefsFromTypeExpression

        TS.Tuple subTypeExpList ->
            subTypeExpList |> List.concatMap collectRefsFromTypeExpression

        TS.Union subTypeExpList ->
            subTypeExpList |> List.concatMap collectRefsFromTypeExpression

        TS.Object fieldList ->
            fieldList |> List.concatMap (\( _, subTypeExp ) -> collectRefsFromTypeExpression subTypeExp)

        TS.TypeRef ( packagePath, modulePath, _ ) subTypeExpList ->
            List.concat
                [ [ ( packagePath, modulePath ) ]
                , subTypeExpList |> List.concatMap collectRefsFromTypeExpression
                ]

        _ ->
            []
